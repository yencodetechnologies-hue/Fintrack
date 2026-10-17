const Company = require("../models/company");
const CompanyMember = require("../models/companyMember");
const Expense = require("../models/expense");
const User = require("../models/user");
const { LedgerAccount, LedgerTransaction, LedgerEntry, AuditLog } = require("../models/ledger");
const CompanyLoan = require("../models/companyLoan");
const { ExpenseGroup } = require("../models/expenseGroup");
const { notifyUsers, notifyCompanyAdmins } = require("../services/ledgerNotify");

const fail = (status, message) => Object.assign(new Error(message), { status });

const handle = (fn) => async (req, res) => {
  try {
    await fn(req, res);
  } catch (e) {
    res.status(e.status || 500).json({ success: false, message: e.message });
  }
};

// Categories offered by the app; anything else typed under "Other" is saved per company.
const BASE_EXPENSE_CATEGORIES = ["General", "Travel", "Food & Dining", "Rent", "Software", "Office Supplies", "Utilities", "Other"];

const round = (n) => Math.round(n * 100) / 100;

// ---------- roles ----------
async function roleIn(companyId, userId) {
  if (!userId) return null;
  const user = await User.findById(userId).select("platformRole");
  if (user && user.platformRole === "super_admin") return "super_admin";
  const company = await Company.findById(companyId).select("createdBy external");
  if (!company) throw fail(404, "Company not found");
  if (!company.external && company.createdBy && company.createdBy.toString() === userId.toString()) return "admin";
  const member = await CompanyMember.findOne({ companyId, userId });
  if (!member) return null;
  return member.role === "admin" ? "admin" : "employee";
}

async function requireRole(companyId, userId, allowed) {
  const role = await roleIn(companyId, userId);
  if (!role) throw fail(403, "You are not a member of this company");
  if (!allowed.includes(role)) throw fail(403, "You do not have permission for this action");
  return role;
}

const isAdminRole = (r) => r === "admin" || r === "super_admin";

// ---------- accounts ----------
async function getAccount(companyId, spec) {
  const key = {
    companyId,
    type: spec.type,
    bankAccountId: spec.bankAccountId || null,
    category: spec.category || null,
    userId: spec.userId || null,
    counterpartCompanyId: spec.counterpartCompanyId || null,
  };
  return LedgerAccount.findOneAndUpdate(
    key,
    { $setOnInsert: { ...key, name: spec.name } },
    { upsert: true, new: true }
  );
}

// fundId: "cash" or a Company.bankAccounts subdoc id
async function fundAccount(companyId, fundId) {
  if (!fundId) throw fail(400, "Select the bank account or cash used");
  if (fundId === "cash") return getAccount(companyId, { type: "bank", name: "Cash" });
  const company = await Company.findById(companyId);
  const bank = company && company.bankAccounts.id(fundId);
  if (!bank) throw fail(400, "Selected bank account was not found");
  return getAccount(companyId, { type: "bank", bankAccountId: bank._id, name: bank.bankName });
}

async function applyCompanyFund(companyId, fundId, delta) {
  if (!fundId || fundId === "cash") {
    await Company.updateOne({ _id: companyId }, { $inc: { cashBalance: delta } });
  } else {
    await Company.updateOne(
      { _id: companyId, "bankAccounts._id": fundId },
      { $inc: { "bankAccounts.$.balance": delta } }
    );
  }
}

async function getEffectiveFundBalance(companyId, fundId) {
  const company = await Company.findById(companyId).select("bankAccounts cashBalance");
  if (!fundId || fundId === "cash") {
    return Number(company?.cashBalance || 0);
  }
  const bank = (company?.bankAccounts || []).find((b) => String(b._id) === String(fundId));
  return bank ? Number(bank.balance || 0) : 0;
}

async function payableAccount(companyId, personUserId) {
  const user = await User.findById(personUserId).select("name");
  return getAccount(companyId, { type: "admin_payable", userId: personUserId, name: `Payable to ${user ? user.name : "member"}` });
}

const expenseAccount = (companyId, category) =>
  getAccount(companyId, { type: "expense", category: category || "General", name: `Expense: ${category || "General"}` });

async function accountTotals(accountId) {
  const [r] = await LedgerEntry.aggregate([
    { $match: { accountId } },
    { $group: { _id: null, debit: { $sum: "$debit" }, credit: { $sum: "$credit" } } },
  ]);
  return { debit: r ? r.debit : 0, credit: r ? r.credit : 0 };
}

async function adminOwed(companyId, adminUserId) {
  const acc = await LedgerAccount.findOne({ companyId, type: "admin_payable", userId: adminUserId });
  if (!acc) return 0;
  const t = await accountTotals(acc._id);
  return round(t.credit - t.debit);
}

// ---------- posting ----------
async function post(tx, lines) {
  const debit = round(lines.reduce((s, l) => s + (l.debit || 0), 0));
  const credit = round(lines.reduce((s, l) => s + (l.credit || 0), 0));
  if (!(debit > 0) || debit !== credit) throw fail(400, "Unbalanced transaction");
  const transaction = await LedgerTransaction.create(tx);
  try {
    await LedgerEntry.insertMany(
      lines.map((l) => ({
        transactionId: transaction._id,
        accountId: l.account._id,
        companyId: tx.companyId,
        debit: l.debit || 0,
        credit: l.credit || 0,
      }))
    );
  } catch (e) {
    await LedgerTransaction.deleteOne({ _id: transaction._id });
    throw e;
  }
  return transaction;
}

const audit = (userId, companyId, action, object, objectId, before, after) =>
  AuditLog.create({ userId, companyId, action, object, objectId, before, after });

const snapshot = (doc) => {
  if (!doc) return null;
  const obj = JSON.parse(JSON.stringify(doc.toObject ? doc.toObject() : doc));
  if (obj.attachment) obj.attachment = "[image]";
  if (obj.paymentReceipt) obj.paymentReceipt = "[image]";
  return obj;
};

// FIFO: walk a person's payable credits oldest first; fully reimbursed expenses become "reimbursed".
async function recomputeReimbursed(companyId, adminUserId) {
  const acc = await LedgerAccount.findOne({ companyId, type: "admin_payable", userId: adminUserId });
  if (!acc) return;
  const entries = await LedgerEntry.find({ accountId: acc._id }).sort({ createdAt: 1 });
  let paidBack = round(entries.reduce((s, e) => s + e.debit, 0));
  const txIds = entries.filter((e) => e.credit > 0).map((e) => e.transactionId);
  const txs = await LedgerTransaction.find({ _id: { $in: txIds }, reversedBy: null, type: { $ne: "reversal" } });
  const txMap = new Map(txs.map((t) => [t._id.toString(), t]));

  // reversed credits are cancelled by their reversal debit, so drop both from the walk
  for (const e of entries) {
    if (e.credit > 0 && !txMap.has(e.transactionId.toString())) paidBack = round(paidBack - e.credit);
  }

  for (const e of entries) {
    if (!(e.credit > 0)) continue;
    const tx = txMap.get(e.transactionId.toString());
    if (!tx) continue;
    const covered = paidBack >= e.credit;
    paidBack = round(paidBack - e.credit);
    if (tx.expenseId) {
      const expense = await Expense.findById(tx.expenseId).select("paidByAdminId");
      await Expense.updateOne(
        { _id: tx.expenseId, lifecycle: { $in: ["paid_by_admin", "paid_by_person", "reimbursed"] } },
        { $set: { lifecycle: covered ? "reimbursed" : (expense?.paidByAdminId ? "paid_by_admin" : "paid_by_person") } }
      );
    }
  }
}

// ---------- expenses ----------
async function recordPayerAtPost(expense, userId, choice) {
  const companyId = expense.companyId;
  const kind = choice?.type || "unpaid";
  const method = choice?.method || "";
  const reference = choice?.reference || "";
  if (kind === "unpaid") return;
  if (kind === "person") {
    const personId = choice.userId || userId;
    await requireRole(companyId, personId, ["employee", "admin", "super_admin"]);
    const tx = await post({ companyId, type: "admin_paid", expenseId: expense._id, memo: expense.description, createdBy: userId, method, reference }, [
      { account: await expenseAccount(companyId, expense.category), debit: expense.amount },
      { account: await payableAccount(companyId, personId), credit: expense.amount },
    ]);
    expense.lifecycle = "paid_by_person";
    expense.status = "paid";
    expense.payerType = "person";
    expense.paidByUserId = personId;
    expense.paidByAdminId = (await roleIn(companyId, personId)) === "admin" ? personId : null;
    expense.transactionId = tx._id;
    await expense.save();
    await notifyUsers([personId], { title: "Expense recorded under your name", body: `${expense.description} · ₹${expense.amount} is recorded as payable to you`, data: { expenseId: expense._id, companyId } }, userId);
    return;
  }
  if (kind === "company") {
    const verification = (await needsVerification(companyId, expense.amount)) ? "pending" : null;
    const tx = await post({ companyId, type: "company_paid", expenseId: expense._id, memo: expense.description, createdBy: userId, method, reference, verification }, [
      { account: await expenseAccount(companyId, expense.category), debit: expense.amount },
      { account: await fundAccount(companyId, choice.fundId), credit: expense.amount },
    ]);
    expense.lifecycle = "paid_by_company";
    expense.status = "paid";
    expense.payerType = "company";
    expense.verification = verification;
    expense.transactionId = tx._id;
    await expense.save();
    if (verification) await notifyCompanyAdmins(companyId, { title: "Payment needs verification", body: `${expense.description} · ₹${expense.amount}`, data: { transactionId: tx._id, companyId } }, userId);
    return;
  }
  if (kind === "other_company") {
    const lender = await resolveSourceCompany(userId, companyId, choice.companyId, choice.newCompany);
    expense.payerType = "other_company";
    expense.payerCompanyId = lender._id;
    if (!lender.external) {
      expense.lifecycle = "awaiting_confirmation";
      expense.payerConfirmation = "pending";
      expense.status = "outstanding";
      await expense.save();
      await notifyCompanyAdmins(lender._id, { title: "Payment confirmation requested", body: `${expense.description} · ₹${expense.amount} charged to ${lender.name}`, data: { expenseId: expense._id, companyId: expense.companyId } }, userId);
      return;
    }
    const borrower = await Company.findById(companyId);
    const loan = await CompanyLoan.create({ borrowerCompanyId: borrower._id, lenderCompanyId: lender._id, amount: expense.amount, source: "expense", expenseId: expense._id, createdBy: userId, method, reference });
    const routeId = newRouteId();
    const txs = await postAll([
      [{ companyId, type: "borrowed", expenseId: expense._id, loanId: loan._id, routeId, memo: `${expense.description} (borrowed from ${lender.name})`, createdBy: userId, method, reference }, [{ account: await expenseAccount(companyId, expense.category), debit: expense.amount }, { account: await intercoAccount(companyId, lender), credit: expense.amount }]],
      [{ companyId: lender._id, type: "intercompany", expenseId: expense._id, loanId: loan._id, routeId, memo: `Paid ${borrower.name}: ${expense.description}`, createdBy: userId, method, reference }, [{ account: await intercoAccount(lender._id, borrower), debit: expense.amount }, { account: await fundAccount(lender._id, "cash"), credit: expense.amount }]],
    ]);
    loan.transactionIds = txs.map((tx) => tx._id);
    await loan.save();
    await audit(userId, lender._id, "loan_received", "loan", loan._id, null, { borrowerCompanyId: borrower._id, amount: expense.amount });
    expense.lifecycle = "paid_by_company";
    expense.payerConfirmation = "accepted";
    expense.status = "paid";
    expense.transactionId = txs[0]._id;
    await expense.save();
    return;
  }
  throw fail(400, "Select a valid payer type");
}

exports.createExpense = handle(async (req, res) => {
  const { companyId, userId, amount, description, category, date, attachment, visibleTo, postAs, logAs, fundId, method, reference } = req.body;
  const value = parseFloat(amount);
  if (!companyId || !userId || !(value > 0) || !description || !String(description).trim()) {
    throw fail(400, "Company, amount and description are required");
  }
  const role = await requireRole(companyId, userId, ["employee", "admin", "super_admin"]);
  const members = await CompanyMember.find({ companyId }).distinct("userId");
  const allowedMembers = new Set(members.map(String));
  const company = await Company.findById(companyId).select("createdBy name bankAccounts cashBalance");
  if (company?.createdBy) allowedMembers.add(String(company.createdBy));
  const chosenVisibility = isAdminRole(role)
    ? [...new Set((Array.isArray(visibleTo) ? visibleTo : []).map(String))].filter((id) => allowedMembers.has(id))
    : [...allowedMembers];

  const isCompanyPost = isAdminRole(role) && (postAs === "company" || logAs === "company");

  if (isCompanyPost) {
    const fund = fundId || "cash";
    const available = await getEffectiveFundBalance(companyId, fund);
    if (available < value) {
      throw fail(400, `Insufficient balance in ${fund === "cash" ? "Cash" : "selected bank"} (₹${available.toFixed(2)} available, ₹${value.toFixed(2)} required)`);
    }
  }

  const expense = await Expense.create({
    companyId,
    createdBy: userId,
    isAdminCreated: isAdminRole(role),
    payerType: isCompanyPost ? "company" : "unpaid",
    amount: value,
    description: String(description).trim(),
    category: category || "General",
    date: date ? new Date(date) : new Date(),
    attachment: attachment || "",
    hasAttachment: Boolean(attachment),
    visibleTo: chosenVisibility,
    // an admin posting an expense has effectively approved it; company expense is marked paid by company; staff expenses wait for an admin
    lifecycle: isCompanyPost ? "paid_by_company" : (isAdminRole(role) ? "approved" : "submitted"),
    approvedBy: isAdminRole(role) ? userId : null,
    status: isCompanyPost ? "paid" : "outstanding",
    logAs: isCompanyPost ? "company" : "self",
  });

  if (isCompanyPost) {
    try {
      const fund = fundId || "cash";
      const debit = await expenseAccount(companyId, expense.category);
      const credit = await fundAccount(companyId, fund);
      const verification = (await needsVerification(companyId, expense.amount)) ? "pending" : null;
      const base = { method: method || "Bank", reference: reference || "", expenseId: expense._id, createdBy: userId, verification };
      const txs = await postAll([
        [
          { ...base, companyId, type: "company_paid", memo: expense.description },
          [{ account: debit, debit: expense.amount }, { account: credit, credit: expense.amount }],
        ],
      ]);
      expense.transactionId = txs[0]._id;
      expense.verification = verification;
      await expense.save();
      await applyCompanyFund(companyId, fund, -expense.amount);
    } catch (txErr) {
      console.error("Failed to post company ledger transaction:", txErr);
    }
  }

  await audit(userId, companyId, "create", "expense", expense._id, null, snapshot(expense));
  if (!BASE_EXPENSE_CATEGORIES.includes(expense.category)) {
    await Company.updateOne({ _id: companyId }, { $addToSet: { customCategories: expense.category } });
  }
  const poster = await User.findById(userId).select("name");
  const posterName = isCompanyPost ? (company?.name || "Company") : (poster?.name || "Someone");
  const msg = { title: "Expense posted", body: `${posterName} posted ${expense.category} · ₹${expense.amount}`, data: { expenseId: expense._id, companyId } };
  await notifyCompanyAdmins(companyId, msg, userId);
  if (isAdminRole(role)) notifyUsers(chosenVisibility, msg, userId);
  res.status(201).json({ success: true, expense: await Expense.findById(expense._id).select("-attachment -paymentReceipt").populate("paidByUserId", "name") });
});
exports.listExpenses = handle(async (req, res) => {
  const { companyId } = req.params;
  const { userId, lifecycle, summary } = req.query;
  const role = await requireRole(companyId, userId, ["employee", "admin", "super_admin"]);
  const query = { companyId, lifecycle: { $ne: null } };
  if (lifecycle) query.lifecycle = lifecycle;
  let expenseQuery = Expense.find(query);
  if (summary === "1") {
    expenseQuery = expenseQuery
      .select("companyId createdBy isAdminCreated visibleTo amount description category date lifecycle createdAt approvedBy verification logAs")
      .populate("createdBy", "name")
      .populate("companyId", "name")
      .populate("approvedBy", "name");
  } else {
    expenseQuery = expenseQuery
      // Receipt images are fetched on demand; keeping base64 data out of the list
      // response prevents large expense lists from timing out on mobile networks.
      .select("-attachment -paymentReceipt")
      .populate("createdBy", "name email")
      .populate("companyId", "name")
      .populate("approvedBy", "name")
      .populate("paidByAdminId", "name")
      .populate("paidByUserId", "name")
      .populate("payerCompanyId", "name");
  }
  let expenses = (await expenseQuery.sort({ createdAt: -1 })).map((expense) => expense.toObject());
  if (summary !== "1" && expenses.length) {
    expenses = expenses.map((expense) => ({
      ...expense,
      hasAttachment: Boolean(expense.hasAttachment),
      hasPaymentReceipt: Boolean(expense.hasPaymentReceipt),
    }));
  }
  if (!isAdminRole(role)) {
    const admins = new Set(await adminIds(companyId));
    const company = await Company.findById(companyId).select("createdBy");
    if (company?.createdBy) admins.add(String(company.createdBy));
    expenses = expenses.filter((e) => {
      const creator = String(e.createdBy?._id || e.createdBy);
      const adminCreated = e.isAdminCreated === true || (e.isAdminCreated !== false && admins.has(creator));
      return !adminCreated || (e.visibleTo || []).some((id) => String(id) === String(userId));
    });
  }
  res.json({ success: true, role, expenses });
});

exports.expenseReceipts = handle(async (req, res) => {
  const { userId } = req.query;
  const expense = await Expense.findById(req.params.expenseId)
    .select("companyId createdBy isAdminCreated visibleTo attachment paymentReceipt");
  if (!expense) throw fail(404, "Expense not found");
  const role = await requireRole(expense.companyId, userId, ["employee", "admin", "super_admin"]);
  if (!isAdminRole(role)) {
    const admins = new Set(await adminIds(expense.companyId));
    const company = await Company.findById(expense.companyId).select("createdBy");
    if (company?.createdBy) admins.add(String(company.createdBy));
    const creator = String(expense.createdBy);
    const adminCreated = expense.isAdminCreated === true || (expense.isAdminCreated !== false && admins.has(creator));
    if (adminCreated && !(expense.visibleTo || []).some((id) => String(id) === String(userId))) {
      throw fail(404, "Expense not found");
    }
  }
  res.json({ success: true, attachment: expense.attachment, paymentReceipt: expense.paymentReceipt });
});

async function decide(req, res, target) {
  const { userId } = req.body;
  const expense = await Expense.findById(req.params.expenseId);
  if (!expense) throw fail(404, "Expense not found");
  await requireRole(expense.companyId, userId, ["admin", "super_admin"]);
  const before = snapshot(expense);
  const updated = await Expense.findOneAndUpdate(
    { _id: expense._id, lifecycle: "submitted" },
    { $set: { lifecycle: target, approvedBy: userId } },
    { returnDocument: "after" }
  ).populate("createdBy", "name email").populate("approvedBy", "name email");
  if (!updated) throw fail(400, `Only submitted expenses can be ${target}`);
  await audit(userId, expense.companyId, target === "approved" ? "approve" : "reject", "expense", expense._id, before, snapshot(updated));
  notifyUsers([expense.createdBy], { title: target === "approved" ? "Expense approved" : "Expense rejected", body: `${expense.description} · ₹${expense.amount}`, data: { expenseId: expense._id, companyId: expense.companyId } }, userId);
  res.json({ success: true, expense: updated });
}

exports.approveExpense = handle((req, res) => decide(req, res, "approved"));
exports.rejectExpense = handle((req, res) => decide(req, res, "rejected"));

exports.payExpense = handle(async (req, res) => {
  const { userId, payer, fundId, method, reference, sourceCompanyId, newCompany, sourceFundId, paidByUserId, paymentReceipt } = req.body;
  if (!["admin", "person", "company", "borrow"].includes(payer)) throw fail(400, "Choose a valid payment type");
  if (!method || !String(method).trim() || !paymentReceipt) throw fail(400, "Payment method and receipt are required");
  const expense = await Expense.findById(req.params.expenseId);
  if (!expense) throw fail(404, "Expense not found");
  if (expense.groupId) throw fail(403, "Group expenses are settled only when the group is closed");
  const companyId = expense.companyId;
  const role = await requireRole(companyId, userId, ["employee", "admin", "super_admin"]);
  const isAdmin = isAdminRole(role);
  const staffBorrow = payer === "borrow" && !isAdmin;
  const recordedPayerId = paidByUserId || userId;
  if (paidByUserId && payer !== "person") throw fail(400, "A recorded person payer requires a personal payment");
  if (paidByUserId && String(expense.createdBy) !== String(userId)) throw fail(403, "Only the expense creator can record another member as the payer");
  if (paidByUserId) {
    const payerRole = await roleIn(companyId, paidByUserId);
    if (!payerRole) throw fail(400, "The payer must be a member of this company");
  }
  if (!isAdmin && payer === "admin") throw fail(403, "Only admins can record a payment as an admin");
  if (expense.lifecycle === "awaiting_confirmation") throw fail(409, "This expense is awaiting payer confirmation");
  if (expense.lifecycle !== "approved") throw fail(409, "This expense must be approved before payment can be recorded");
  if (!isAdmin) {
    const adminSet = new Set(await adminIds(companyId));
    if (adminSet.has(String(expense.createdBy)) && !(expense.visibleTo || []).some((id) => String(id) === String(userId))) throw fail(404, "Expense not found");
    if (payer !== "person" && payer !== "borrow" && !(payer === "company" && String(expense.createdBy) === String(userId))) {
      throw fail(403, "Staff may record company-paid expenses only for their own expense");
    }
  }

  const debit = await expenseAccount(companyId, expense.category);
  let source = null;
  let credit;
  if (payer === "admin" || payer === "person") credit = await payableAccount(companyId, payer === "person" ? recordedPayerId : userId);
  else if (payer === "company") {
    credit = await fundAccount(companyId, fundId);
    const available = await getEffectiveFundBalance(companyId, fundId);
    if (available < expense.amount) {
      const company = await Company.findById(companyId).select("bankAccounts");
      const bankDoc = (company?.bankAccounts || []).find((b) => String(b._id) === String(fundId));
      const fundName = fundId === "cash" ? "Cash" : (bankDoc?.bankName || credit.name || "selected fund");
      throw fail(400, `Insufficient balance in ${fundName} (₹${available.toFixed(2)} available, ₹${expense.amount.toFixed(2)} required)`);
    }
  } else {
    source = await resolveSourceCompany(userId, companyId, sourceCompanyId, newCompany);
    credit = await intercoAccount(companyId, source);
  }
  const sourceFund = source
    ? await fundAccount(source._id, source.external || staffBorrow ? "cash" : sourceFundId)
    : null;

  // Staff borrow payments settle immediately, like a group settlement; admin-recorded
  // company payments still require a registered lender's confirmation.
  if (payer === "borrow" && !source.external && !staffBorrow) {
    const requested = await Expense.findOneAndUpdate(
      { _id: expense._id, lifecycle: "approved", status: "outstanding" },
      { $set: { lifecycle: "awaiting_confirmation", status: "outstanding", payerType: "other_company", payerCompanyId: source._id, payerConfirmation: "pending", payerMethod: method || "", payerReference: reference || "", paymentReceipt, hasPaymentReceipt: Boolean(paymentReceipt) } },
      { returnDocument: "after" }
    );
    if (!requested) throw fail(409, "This expense is already paid or another payer has claimed it");
    await audit(userId, companyId, "request_payer_confirmation", "expense", expense._id, snapshot(expense), snapshot(requested));
    await notifyCompanyAdmins(source._id, { title: "Payment confirmation requested", body: `${expense.description} · ₹${expense.amount} charged to ${source.name}`, data: { expenseId: expense._id, companyId } }, userId);
    await notifyCompanyAdmins(companyId, { title: "Awaiting payer confirmation", body: `${expense.description} · ₹${expense.amount} sent to ${source.name}`, data: { expenseId: expense._id, companyId } }, userId);
    res.json({ success: true, expense, awaitingConfirmation: true });
    return;
  }

  const target = payer === "admin" ? "paid_by_admin" : (payer === "person" ? "paid_by_person" : "paid_by_company");
  const verification = (await needsVerification(companyId, expense.amount)) ? "pending" : null;

  // first admin to claim an approved expense locks it
  const before = snapshot(expense);
  const claimed = await Expense.findOneAndUpdate(
    { _id: expense._id, lifecycle: "approved", status: "outstanding" },
    { $set: { lifecycle: target, paidByAdminId: payer === "admin" ? userId : null, paidByUserId: ["admin", "person"].includes(payer) ? recordedPayerId : null, payerType: ["admin", "person"].includes(payer) ? "person" : payer === "company" ? "company" : "other_company", payerMethod: method || "", payerReference: reference || "", ...(paymentReceipt ? { paymentReceipt, hasPaymentReceipt: true } : {}), status: "paid", verification } },
    { returnDocument: "after" }
  );
  if (!claimed) throw fail(409, "This expense is not approved or has already been paid");

  const base = { method: method || "", reference: reference || "", expenseId: expense._id, createdBy: userId, verification };
  let txs;
  try {
    if (payer === "borrow") {
      const routeId = newRouteId();
      const company = await Company.findById(companyId).select("name");
      const loan = await CompanyLoan.create({ borrowerCompanyId: companyId, lenderCompanyId: source._id, amount: expense.amount, source: "expense", expenseId: expense._id, createdBy: userId, method: method || "", reference: reference || "" });
      txs = await postAll([
        [
          { ...base, companyId, type: "borrowed", loanId: loan._id, routeId, memo: `${expense.description} (borrowed from ${source.name})` },
          [{ account: debit, debit: expense.amount }, { account: credit, credit: expense.amount }],
        ],
        [
          { ...base, companyId: source._id, type: "intercompany", loanId: loan._id, routeId, memo: `Paid for ${company.name}: ${expense.description}` },
          [{ account: await intercoAccount(source._id, company), debit: expense.amount }, { account: sourceFund, credit: expense.amount }],
        ],
      ]);
      loan.transactionIds = txs.map((tx) => tx._id);
      await loan.save();
      await audit(userId, source._id, "loan_received", "loan", loan._id, null, { borrowerCompanyId: companyId, amount: expense.amount });
    } else {
      txs = await postAll([
        [
          { ...base, companyId, type: payer === "admin" ? "admin_paid" : "company_paid", memo: expense.description },
          [{ account: debit, debit: expense.amount }, { account: credit, credit: expense.amount }],
        ],
      ]);
    }
  } catch (e) {
    await Expense.updateOne({ _id: expense._id }, { $set: { lifecycle: "approved", paidByAdminId: null, status: "outstanding", verification: null } });
    throw e;
  }
  claimed.transactionId = txs[0]._id;
  await claimed.save();
  if (payer === "company") {
    await applyCompanyFund(companyId, fundId, -expense.amount);
  }
  await audit(userId, companyId, "pay", "expense", expense._id, before, snapshot(claimed));
  const payerName = (await User.findById(userId).select("name"))?.name || "An admin";
  const how = ["admin", "person"].includes(payer) ? "paid it themselves" : payer === "company" ? "paid it from company funds" : `paid it with money borrowed from ${source.name}`;
  await notifyCompanyAdmins(source ? [companyId, source._id] : companyId, {
    title: payer === "borrow" ? "Borrowed from another company" : "Expense paid",
    body: `${payerName} ${how}: ${expense.description} · ₹${expense.amount}`,
    data: { expenseId: expense._id, companyId },
  }, userId);
  if (expense.isAdminCreated) notifyUsers(expense.visibleTo || [], { title: "Expense payment recorded", body: `${expense.description} · ₹${expense.amount}`, data: { expenseId: expense._id, companyId } }, userId);
  const expenseObj = claimed.toObject ? claimed.toObject() : JSON.parse(JSON.stringify(claimed));
  delete expenseObj.paymentReceipt;
  delete expenseObj.attachment;
  res.json({
    success: true,
    expense: {
      ...expenseObj,
      hasAttachment: Boolean(claimed.hasAttachment || claimed.attachment),
      hasPaymentReceipt: Boolean(claimed.hasPaymentReceipt || claimed.paymentReceipt),
    },
    transactions: txs,
  });
});

exports.setExpenseVisibility = handle(async (req, res) => {
  const { userId, visibleTo } = req.body;
  const expense = await Expense.findById(req.params.expenseId);
  if (!expense) throw fail(404, "Expense not found");
  await requireRole(expense.companyId, userId, ["admin", "super_admin"]);
  const creatorRole = await roleIn(expense.companyId, expense.createdBy);
  if (expense.isAdminCreated === false && !isAdminRole(creatorRole)) throw fail(400, "Visibility can only be edited for an admin-created expense");
  const members = await CompanyMember.find({ companyId: expense.companyId }).distinct("userId");
  const company = await Company.findById(expense.companyId).select("createdBy");
  if (company?.createdBy) members.push(company.createdBy);
  const valid = new Set(members.map(String));
  const before = [...(expense.visibleTo || [])];
  expense.visibleTo = [...new Set((Array.isArray(visibleTo) ? visibleTo : []).map(String))].filter((id) => valid.has(id));
  await expense.save();
  await audit(userId, expense.companyId, "visibility", "expense", expense._id, { visibleTo: before }, { visibleTo: expense.visibleTo });
  notifyUsers(expense.visibleTo, { title: "Expense shared with you", body: `${expense.category} · ₹${expense.amount}`, data: { expenseId: expense._id, companyId: expense.companyId } }, userId);
  res.json({ success: true, expense });
});

exports.deleteExpense = handle(async (req, res) => {
  const userId = req.body.userId || req.query.userId;
  const expense = await Expense.findById(req.params.expenseId);
  if (!expense) throw fail(404, "Expense not found");
  if (!userId || expense.createdBy.toString() !== userId.toString()) throw fail(403, "You can only delete your own expenses");
  if (expense.lifecycle !== "submitted") throw fail(400, "Only submitted expenses can be deleted; booked payments must be reversed");
  await audit(userId, expense.companyId, "delete", "expense", expense._id, snapshot(expense), null);
  await Expense.deleteOne({ _id: expense._id });
  res.json({ success: true });
});

// ---------- reimburse & lend ----------
exports.reimburse = handle(async (req, res) => {
  const { companyId, userId, adminUserId, amount, fundId, method, reference } = req.body;
  const value = round(parseFloat(amount));
  if (!(value > 0)) throw fail(400, "Enter a valid amount");
  const role = await requireRole(companyId, userId, ["admin", "super_admin"]);
  const targetRole = await roleIn(companyId, adminUserId);
  if (!targetRole) throw fail(400, "The payee must be a member of this company");
  if (adminUserId.toString() === userId.toString()) throw fail(403, "You cannot reimburse yourself");
  const owed = await adminOwed(companyId, adminUserId);
  if (value > owed) throw fail(400, `Amount exceeds the open balance (₹${owed})`);

  const tx = await post(
    { companyId, type: "reimburse", memo: "Admin reimbursement", method: method || "", reference: reference || "", createdBy: userId, verification: (await needsVerification(companyId, value)) ? "pending" : null },
    [
      { account: await payableAccount(companyId, adminUserId), debit: value },
      { account: await fundAccount(companyId, fundId), credit: value },
    ]
  );
  await recomputeReimbursed(companyId, adminUserId);
  await applyCompanyFund(companyId, fundId, -value);
  await audit(userId, companyId, "reimburse", "transaction", tx._id, null, { adminUserId, amount: value });
  notifyUsers([adminUserId], { title: "You were reimbursed", body: `₹${value} paid back to you`, data: { transactionId: tx._id, companyId } });
  if (tx.verification === "pending") await notifyCompanyAdmins(companyId, { title: "Payment needs verification", body: `Reimbursement of ₹${value}`, data: { transactionId: tx._id, companyId } }, userId);
  res.json({ success: true, transaction: tx, owed: await adminOwed(companyId, adminUserId) });
});

exports.lend = handle(async (req, res) => {
  const { companyId, userId, amount, fundId, method, reference } = req.body;
  const value = round(parseFloat(amount));
  if (!(value > 0)) throw fail(400, "Enter a valid amount");
  await requireRole(companyId, userId, ["admin", "super_admin"]);
  const tx = await post(
    { companyId, type: "lend", memo: "Admin loan to company", method: method || "", reference: reference || "", createdBy: userId },
    [
      { account: await fundAccount(companyId, fundId), debit: value },
      { account: await payableAccount(companyId, userId), credit: value },
    ]
  );
  await audit(userId, companyId, "lend", "transaction", tx._id, null, { amount: value });
  await applyCompanyFund(companyId, fundId, value);
  await notifyCompanyAdmins(companyId, { title: "Admin lent money to the company", body: `₹${value} added; the company owes them this amount`, data: { transactionId: tx._id, companyId } }, userId);
  res.json({ success: true, transaction: tx, owed: await adminOwed(companyId, userId) });
});

// ---------- reversal ----------
exports.reverseTransaction = handle(async (req, res) => {
  const { userId } = req.body;
  const original = await LedgerTransaction.findById(req.params.transactionId);
  if (!original) throw fail(404, "Transaction not found");
  await requireRole(original.companyId, userId, ["super_admin"]);
  if (original.reversedBy) throw fail(400, "This transaction has already been reversed");
  if (original.type === "reversal") throw fail(400, "A reversal cannot be reversed");

  // linked legs (same routeId) are reversed together so both companies stay in step
  const legs = original.routeId ? await LedgerTransaction.find({ routeId: original.routeId, reversedBy: null }) : [original];
  const reversals = [];
  const touched = [];
  for (const leg of legs) {
    const entries = await LedgerEntry.find({ transactionId: leg._id });
    const accounts = await LedgerAccount.find({ _id: { $in: entries.map((e) => e.accountId) } });
    const accMap = new Map(accounts.map((a) => [a._id.toString(), a]));
    const reversal = await post(
      { companyId: leg.companyId, type: "reversal", memo: `Reversal of ${leg.type}`, expenseId: leg.expenseId, routeId: leg.routeId, reverses: leg._id, createdBy: userId },
      entries.map((e) => ({ account: accMap.get(e.accountId.toString()), debit: e.credit, credit: e.debit }))
    );
    leg.reversedBy = reversal._id;
    await leg.save();
    reversals.push(reversal);
    touched.push(...accounts.filter((a) => a.type === "admin_payable"));
  }

  if (original.expenseId && ["admin_paid", "company_paid", "borrowed", "intercompany"].includes(original.type)) {
    await Expense.updateOne(
      { _id: original.expenseId },
      { $set: { lifecycle: "approved", paidByAdminId: null, transactionId: null, status: "outstanding", verification: null } }
    );
  }
  for (const a of touched) await recomputeReimbursed(a.companyId, a.userId);
  for (const leg of legs) {
    await audit(userId, leg.companyId, "reverse", "transaction", leg._id, null, { reversals: reversals.filter((r) => r.companyId.toString() === leg.companyId.toString()).map((r) => r._id) });
  }
  const touchedCompanies = [...new Set(legs.map((leg) => leg.companyId.toString()))];
  await notifyCompanyAdmins(touchedCompanies, { title: "Ledger transaction reversed", body: `A ${original.type} transaction was reversed`, data: { transactionId: original._id, companyId: original.companyId } }, userId);
  res.json({ success: true, reversals });
});

// ---------- reads ----------
exports.balances = handle(async (req, res) => {
  const { companyId } = req.params;
  const { userId } = req.query;
  const role = await requireRole(companyId, userId, ["employee", "admin", "super_admin"]);

  // Ensure Cash and all Company bank accounts exist as LedgerAccount records
  const company = await Company.findById(companyId).select("bankAccounts cashBalance");
  if (company) {
    await fundAccount(companyId, "cash");
    for (const b of (company.bankAccounts || [])) {
      await fundAccount(companyId, b._id);
    }
  }

  const accounts = await LedgerAccount.find({ companyId, type: { $in: ["admin_payable", "bank"] } }).populate("userId", "name");
  const totals = await LedgerEntry.aggregate([
    { $match: { accountId: { $in: accounts.map((a) => a._id) } } },
    { $group: { _id: "$accountId", debit: { $sum: "$debit" }, credit: { $sum: "$credit" } } },
  ]);
  const t = new Map(totals.map((x) => [x._id.toString(), x]));
  const get = (a) => t.get(a._id.toString()) || { debit: 0, credit: 0 };

  const admins = accounts
    .filter((a) => a.type === "admin_payable")
    .map((a) => ({ userId: a.userId?._id, name: a.userId?.name || a.name, owed: round(get(a).credit - get(a).debit) }));
  const myOwed = admins.find((a) => a.userId && a.userId.toString() === userId.toString())?.owed || 0;

  if (!isAdminRole(role)) return res.json({ success: true, role, myOwed });

  const funds = accounts
    .filter((a) => a.type === "bank")
    .map((a) => {
      const bankDoc = (company?.bankAccounts || []).find((b) => String(b._id) === String(a.bankAccountId));
      const bal = bankDoc ? Number(bankDoc.balance || 0) : (a.bankAccountId ? 0 : Number(company?.cashBalance || 0));
      return {
        accountId: a._id,
        fundId: a.bankAccountId ? a.bankAccountId.toString() : "cash",
        name: a.name + (bankDoc?.accountNumber ? ` (…${bankDoc.accountNumber.slice(-4)})` : ""),
        balance: bal,
      };
    });
  res.json({
    success: true,
    role,
    myOwed,
    totalOwedToAdmins: round(admins.reduce((s, a) => s + a.owed, 0)),
    admins,
    funds,
  });
});

exports.listTransactions = handle(async (req, res) => {
  const { companyId } = req.params;
  const { userId } = req.query;
  await requireRole(companyId, userId, ["admin", "super_admin"]);
  const txs = await LedgerTransaction.find({ companyId }).populate("createdBy", "name").sort({ createdAt: -1 }).limit(200).lean();
  const entries = await LedgerEntry.find({ transactionId: { $in: txs.map((t) => t._id) } }).populate("accountId", "name type").lean();
  const byTx = {};
  for (const e of entries) (byTx[e.transactionId.toString()] ||= []).push(e);
  res.json({ success: true, transactions: txs.map((t) => ({ ...t, entries: byTx[t._id.toString()] || [] })) });
});

exports.auditLog = handle(async (req, res) => {
  const { companyId } = req.params;
  const { userId } = req.query;
  await requireRole(companyId, userId, ["admin", "super_admin"]);
  const logs = await AuditLog.find({ companyId })
    .select("-before -after")
    .populate("userId", "name")
    .sort({ at: -1 })
    .limit(300);
  res.json({ success: true, logs });
});

// ---------- Slice 2: verification & inter-company ----------
const crypto = require("crypto");
const newRouteId = () => crypto.randomUUID();

async function adminIds(companyId) {
  const company = await Company.findById(companyId).select("createdBy");
  const ids = new Set((await CompanyMember.find({ companyId, role: "admin" })).map((m) => m.userId.toString()));
  if (company && company.createdBy) ids.add(company.createdBy.toString());
  return [...ids];
}

// Above the threshold a 2nd admin must verify; single-admin companies skip it.
async function needsVerification(companyId, amount) {
  const company = await Company.findById(companyId).select("verificationThreshold");
  if (!company || company.verificationThreshold == null || amount <= company.verificationThreshold) return false;
  return (await adminIds(companyId)).length > 1;
}

// Posts every leg or none of them.
async function postAll(legs) {
  const done = [];
  try {
    for (const [tx, lines] of legs) done.push(await post(tx, lines));
  } catch (e) {
    const ids = done.map((t) => t._id);
    await LedgerEntry.deleteMany({ transactionId: { $in: ids } });
    await LedgerTransaction.deleteMany({ _id: { $in: ids } });
    throw e;
  }
  return done;
}

// In companyId's books: debit = counterpart owes us, credit = we owe counterpart.
const intercoAccount = (companyId, counterpart) =>
  getAccount(companyId, { type: "intercompany", counterpartCompanyId: counterpart._id, name: `Inter-company with ${counterpart.name}` });

async function uniqueJoinCode() {
  for (;;) {
    const code = Math.floor(100000 + Math.random() * 900000).toString();
    if (!(await Company.exists({ joinCode: code }))) return code;
  }
}

// An unregistered source company is saved as an external company with no members.
async function resolveSourceCompany(userId, companyId, sourceCompanyId, newCompany) {
  let source;
  if (sourceCompanyId) {
    source = await Company.findById(sourceCompanyId);
    if (!source) throw fail(404, "Source company not found");
  } else if (newCompany && newCompany.name && String(newCompany.name).trim()) {
    await requireRole(companyId, userId, ["admin", "super_admin"]);
    if (!newCompany.gstin || !String(newCompany.gstin).trim()) throw fail(400, "GSTIN is required for an outside company");
    // reuse an outside company this company's admins already added (guards double taps and repeat entries)
    const name = String(newCompany.name).trim();
    const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    const people = [...new Set([...(await adminIds(companyId)), String(userId)])];
    source = await Company.findOne({ external: true, createdBy: { $in: people }, name: new RegExp(`^${escaped}$`, "i") });
    if (source) return source;
    source = await Company.create({
      name: String(newCompany.name).trim(),
      gstin: newCompany.gstin ? String(newCompany.gstin).trim().toUpperCase() : "",
      joinCode: await uniqueJoinCode(),
      joinCodeCreatedAt: new Date(),
      createdBy: userId,
      external: true,
    });
    await audit(userId, companyId, "create", "company", source._id, null, { name: source.name, gstin: source.gstin, external: true });
  } else {
    throw fail(400, "Select the source company or add a new one");
  }
  if (source._id.toString() === companyId.toString()) throw fail(400, "Source company must be different");
  return source;
}

async function loanBalance(loan) {
  const issue = await LedgerTransaction.find({ _id: { $in: loan.transactionIds }, reversedBy: null, type: { $ne: "reversal" } });
  if (!issue.length) return 0;
  const repayments = await LedgerTransaction.find({ loanId: loan._id, companyId: loan.borrowerCompanyId, type: "loan_repayment", reversedBy: null });
  let repaid = 0;
  for (const tx of repayments) {
    const entries = await LedgerEntry.find({ transactionId: tx._id });
    repaid += entries.reduce((n, e) => n + e.debit, 0);
  }
  return round(Math.max(0, loan.amount - repaid));
}

function loanView(loan, balance) {
  const row = loan.toObject ? loan.toObject() : loan;
  const { repaymentLock, ...publicLoan } = row;
  return { ...publicLoan, balance, repaid: round(row.amount - balance), status: balance <= 0 ? "Completed" : "Outstanding" };
}

exports.listLoans = handle(async (req, res) => {
  const { companyId } = req.params;
  const { userId } = req.query;
  await requireRole(companyId, userId, ["employee", "admin", "super_admin"]);
  const loans = await CompanyLoan.find({ $or: [{ borrowerCompanyId: companyId }, { lenderCompanyId: companyId }] })
    .populate("borrowerCompanyId", "name").populate("lenderCompanyId", "name").sort({ createdAt: -1 });
  const rows = [];
  for (const loan of loans) rows.push(loanView(loan, await loanBalance(loan)));
  res.json({ success: true, loans: rows });
});

exports.createLoan = handle(async (req, res) => {
  const { userId, borrowerCompanyId, lenderCompanyId, amount, fundId, method, reference, note } = req.body;
  const value = round(parseFloat(amount));
  if (!(value > 0) || !borrowerCompanyId || !lenderCompanyId || String(borrowerCompanyId) === String(lenderCompanyId)) throw fail(400, "Choose two companies and a valid amount");
  await requireRole(borrowerCompanyId, userId, ["admin", "super_admin"]);
  const [borrower, lender] = await Promise.all([Company.findById(borrowerCompanyId), Company.findById(lenderCompanyId)]);
  if (!borrower || !lender) throw fail(404, "Company not found");
  const loan = await CompanyLoan.create({ borrowerCompanyId, lenderCompanyId, amount: value, source: "direct", method: method || "", reference: reference || "", note: note || "", createdBy: userId });
  const routeId = newRouteId();
  const txs = await postAll([
    [{ companyId: borrower._id, type: "borrowed", loanId: loan._id, routeId, memo: `Borrowed from ${lender.name}: ${note || "Company loan"}`, method: method || "", reference: reference || "", createdBy: userId }, [{ account: await fundAccount(borrower._id, fundId), debit: value }, { account: await intercoAccount(borrower._id, lender), credit: value }]],
    [{ companyId: lender._id, type: "intercompany", loanId: loan._id, routeId, memo: `Loan to ${borrower.name}: ${note || "Company loan"}`, method: method || "", reference: reference || "", createdBy: userId }, [{ account: await intercoAccount(lender._id, borrower), debit: value }, { account: await fundAccount(lender._id, lender.external ? "cash" : (req.body.lenderFundId || "cash")), credit: value }]],
  ]);
  loan.transactionIds = txs.map((tx) => tx._id);
  await loan.save();
  await audit(userId, borrower._id, "borrow", "loan", loan._id, null, { lenderCompanyId, amount: value });
  await audit(userId, lender._id, "loan_received", "loan", loan._id, null, { borrowerCompanyId, amount: value });
  await notifyCompanyAdmins(borrower._id, { title: "Company loan recorded", body: `Borrowed ₹${value} from ${lender.name}`, data: { loanId: loan._id, companyId: borrower._id } }, userId);
  await notifyCompanyAdmins(lender._id, { title: "Company loan recorded", body: `${borrower.name} recorded a loan from ${lender.name} · ₹${value}`, data: { loanId: loan._id, companyId: lender._id } }, userId);
  res.status(201).json({ success: true, loan: loanView(loan, value) });
});

exports.repayLoan = handle(async (req, res) => {
  const { loanId } = req.params;
  const { userId, amount, fundId, method, reference, note } = req.body;
  const value = round(parseFloat(amount));
  const loan = await CompanyLoan.findById(loanId);
  if (!loan) throw fail(404, "Loan not found");
  await requireRole(loan.borrowerCompanyId, userId, ["admin", "super_admin"]);
  const locked = await CompanyLoan.findOneAndUpdate({ _id: loanId, repaymentLock: false }, { $set: { repaymentLock: true } }, { returnDocument: "after" });
  if (!locked) throw fail(409, "A repayment is already being recorded");
  try {
    const balance = await loanBalance(loan);
    if (!(value > 0) || value > balance) throw fail(400, `Repayment must be positive and no more than the outstanding balance (₹${balance})`);
    const [borrower, lender] = await Promise.all([Company.findById(loan.borrowerCompanyId), Company.findById(loan.lenderCompanyId)]);
    const routeId = newRouteId();
    const txs = await postAll([
      [{ companyId: borrower._id, type: "loan_repayment", loanId: loan._id, routeId, memo: note || `Repayment to ${lender.name}`, method: method || "", reference: reference || "", createdBy: userId }, [{ account: await intercoAccount(borrower._id, lender), debit: value }, { account: await fundAccount(borrower._id, fundId), credit: value }]],
      [{ companyId: lender._id, type: "loan_repayment", loanId: loan._id, routeId, memo: note || `Repayment from ${borrower.name}`, method: method || "", reference: reference || "", createdBy: userId }, [{ account: await fundAccount(lender._id, lender.external ? "cash" : (req.body.lenderFundId || "cash")), debit: value }, { account: await intercoAccount(lender._id, borrower), credit: value }]],
    ]);
    await audit(userId, borrower._id, "repay", "loan", loan._id, { balance }, { amount: value, transactions: txs.map((t) => t._id) });
    await audit(userId, lender._id, "loan_repaid", "loan", loan._id, { balance }, { amount: value, transactions: txs.map((t) => t._id) });
    await notifyCompanyAdmins(borrower._id, { title: "Company loan repayment recorded", body: `Repaid ₹${value} to ${lender.name}`, data: { loanId: loan._id, companyId: borrower._id } }, userId);
    await notifyCompanyAdmins(lender._id, { title: "Company loan repaid", body: `${borrower.name} repaid ₹${value} · ${lender.name}`, data: { loanId: loan._id, companyId: lender._id } }, userId);
    res.json({ success: true, loan: loanView(loan, await loanBalance(loan)), transactions: txs });
  } finally {
    await CompanyLoan.updateOne({ _id: loanId }, { $set: { repaymentLock: false } });
  }
});

exports.settleExpenseGroup = handle(async (req, res) => {
  const { groupId } = req.params;
  const { userId, settlementType, lenderCompanyId } = req.body;
  if (!userId || !["own_company", "other_company"].includes(settlementType)) {
    throw fail(400, "Choose who settled this group");
  }

  const group = await ExpenseGroup.findOneAndUpdate(
    { _id: groupId, createdBy: userId, settlementStatus: { $ne: "settled" }, settlementLock: { $ne: true } },
    { $set: { settlementLock: true } },
    { returnDocument: "after" }
  );
  if (!group) throw fail(403, "Only the group creator can settle an active group");

  let settled = false;
  try {
    const [borrower, rows] = await Promise.all([
      Company.findById(group.companyId),
      Expense.aggregate([
        { $match: { groupId: group._id } },
        { $group: { _id: "$category", amount: { $sum: "$amount" } } },
      ]),
    ]);
    if (!borrower) throw fail(404, "The group company was not found");
    const total = round(rows.reduce((sum, row) => sum + row.amount, 0));
    if (!(total > 0)) throw fail(400, "Add at least one expense before settling this group");

    if (settlementType === "own_company") {
      const before = snapshot(group);
      group.settlementStatus = "settled";
      group.settledAmount = total;
      group.settlementType = "own_company";
      group.settlementCompanyId = borrower._id;
      group.settledBy = userId;
      group.settledAt = new Date();
      group.settlementLock = false;
      await group.save();
      await audit(userId, borrower._id, "settle_group", "expense_group", group._id, before, snapshot(group));
      await notifyCompanyAdmins(borrower._id, {
        title: "Group expenses settled",
        body: `${group.name} · ₹${total} settled by ${borrower.name}`,
        data: { groupId: group._id, companyId: borrower._id },
      }, userId);
      settled = true;
      return res.json({ success: true, group, total });
    }

    if (!lenderCompanyId || String(lenderCompanyId) === String(borrower._id)) {
      throw fail(400, "Choose a different company that paid for the group");
    }
    const lender = await Company.findById(lenderCompanyId);
    if (!lender) throw fail(404, "The paying company was not found");

    const loan = await CompanyLoan.create({
      borrowerCompanyId: borrower._id,
      lenderCompanyId: lender._id,
      amount: total,
      source: "group",
      groupId: group._id,
      createdBy: userId,
      note: `Group settlement: ${group.name}`,
    });
    const routeId = newRouteId();
    let txs;
    try {
      const borrowerLines = [];
      for (const row of rows) {
        borrowerLines.push({ account: await expenseAccount(borrower._id, row._id || "General"), debit: round(row.amount) });
      }
      borrowerLines.push({ account: await intercoAccount(borrower._id, lender), credit: total });
      txs = await postAll([
        [
          { companyId: borrower._id, type: "borrowed", loanId: loan._id, routeId, memo: `Group ${group.name} paid by ${lender.name}`, createdBy: userId },
          borrowerLines,
        ],
        [
          { companyId: lender._id, type: "intercompany", loanId: loan._id, routeId, memo: `Paid group ${group.name} for ${borrower.name}`, createdBy: userId },
          [
            { account: await intercoAccount(lender._id, borrower), debit: total },
            { account: await fundAccount(lender._id, lender.external ? "cash" : "cash"), credit: total },
          ],
        ],
      ]);
      loan.transactionIds = txs.map((tx) => tx._id);
      await loan.save();
    } catch (error) {
      await CompanyLoan.deleteOne({ _id: loan._id });
      throw error;
    }

    const before = snapshot(group);
    group.settlementStatus = "settled";
    group.settledAmount = total;
    group.settlementType = "other_company";
    group.settlementCompanyId = lender._id;
    group.settlementLoanId = loan._id;
    group.settledBy = userId;
    group.settledAt = new Date();
    group.settlementLock = false;
    await group.save();
    await audit(userId, borrower._id, "settle_group_borrowed", "expense_group", group._id, before, { ...snapshot(group), loanId: loan._id, amount: total });
    await audit(userId, lender._id, "group_loan_created", "loan", loan._id, null, { borrowerCompanyId: borrower._id, groupId: group._id, amount: total });
    await notifyCompanyAdmins([borrower._id, lender._id], {
      title: "Group settlement recorded",
      body: `${borrower.name} owes ${lender.name} ₹${total} for ${group.name}`,
      data: { groupId: group._id, loanId: loan._id },
    }, userId);
    settled = true;
    return res.json({ success: true, group, loan: loanView(loan, total), total });
  } finally {
    if (!settled) await ExpenseGroup.updateOne({ _id: groupId }, { $set: { settlementLock: false } });
  }
});

exports.confirmExpensePayer = handle(async (req, res) => {
  const { userId, accept } = req.body;
  let expense = await Expense.findById(req.params.expenseId);
  if (!expense || expense.lifecycle !== "awaiting_confirmation") throw fail(404, "Expense awaiting confirmation not found");
  if (!expense.payerCompanyId) throw fail(400, "No payer company is recorded");
  await requireRole(expense.payerCompanyId, userId, ["admin", "super_admin"]);
  expense = await Expense.findOneAndUpdate(
    { _id: expense._id, lifecycle: "awaiting_confirmation", payerConfirmation: "pending" },
    { $set: { payerConfirmation: "processing" } },
    { returnDocument: "after" }
  );
  if (!expense) throw fail(409, "Another admin is already handling this confirmation");
  if (!accept) {
    expense.lifecycle = expense.isAdminCreated ? "approved" : "submitted";
    expense.status = "outstanding";
    expense.payerConfirmation = "rejected";
    await expense.save();
    await audit(userId, expense.companyId, "reject_payer", "expense", expense._id, null, snapshot(expense));
    notifyUsers([expense.createdBy], { title: "Company payment declined", body: `The payer declined ${expense.description}; it is back to unpaid`, data: { expenseId: expense._id, companyId: expense.companyId } });
    await notifyCompanyAdmins(expense.companyId, { title: "Company payment declined", body: `${expense.description} was returned to unpaid`, data: { expenseId: expense._id, companyId: expense.companyId } });
    res.json({ success: true, expense });
    return;
  }
  const borrower = await Company.findById(expense.companyId);
  const lender = await Company.findById(expense.payerCompanyId);
  const routeId = newRouteId();
  let loan;
  let txs;
  try {
    loan = await CompanyLoan.create({ borrowerCompanyId: borrower._id, lenderCompanyId: lender._id, amount: expense.amount, source: "expense", expenseId: expense._id, createdBy: expense.createdBy, method: expense.payerMethod || "", reference: expense.payerReference || "" });
    txs = await postAll([
      [{ companyId: borrower._id, type: "borrowed", expenseId: expense._id, loanId: loan._id, routeId, memo: `${expense.description} (borrowed from ${lender.name})`, method: expense.payerMethod || "", reference: expense.payerReference || "", createdBy: userId }, [{ account: await expenseAccount(borrower._id, expense.category), debit: expense.amount }, { account: await intercoAccount(borrower._id, lender), credit: expense.amount }]],
      [{ companyId: lender._id, type: "intercompany", expenseId: expense._id, loanId: loan._id, routeId, memo: `Paid ${borrower.name}: ${expense.description}`, method: expense.payerMethod || "", reference: expense.payerReference || "", createdBy: userId }, [{ account: await intercoAccount(lender._id, borrower), debit: expense.amount }, { account: await fundAccount(lender._id, lender.external ? "cash" : (req.body.fundId || "cash")), credit: expense.amount }]],
    ]);
    loan.transactionIds = txs.map((tx) => tx._id);
    await loan.save();
  } catch (error) {
    if (loan) await CompanyLoan.deleteOne({ _id: loan._id });
    await Expense.updateOne({ _id: expense._id, payerConfirmation: "processing" }, { $set: { payerConfirmation: "pending" } });
    throw error;
  }
  expense.lifecycle = "paid_by_company";
  expense.status = "paid";
  expense.payerConfirmation = "accepted";
  expense.transactionId = txs[0]._id;
  await expense.save();
  await audit(userId, expense.companyId, "accept_payer", "expense", expense._id, null, snapshot(expense));
  await audit(userId, lender._id, "accept_payer", "expense", expense._id, null, snapshot(expense));
  await notifyCompanyAdmins(expense.companyId, { title: "Company payment confirmed", body: `${lender.name} confirmed ${expense.description} · ₹${expense.amount}`, data: { expenseId: expense._id, companyId: expense.companyId } }, userId);
  await notifyCompanyAdmins(lender._id, { title: "Company payment confirmed", body: `You paid ${borrower.name} · ${expense.description} · ₹${expense.amount}`, data: { expenseId: expense._id, companyId: lender._id } }, userId);
  res.json({ success: true, expense, loan: loanView(loan, expense.amount) });
});

exports.listPayerConfirmations = handle(async (req, res) => {
  const { companyId } = req.params;
  const { userId } = req.query;
  await requireRole(companyId, userId, ["admin", "super_admin"]);
  const expenses = await Expense.find({ payerCompanyId: companyId, lifecycle: "awaiting_confirmation" })
    .populate("companyId", "name").populate("createdBy", "name").sort({ createdAt: -1 });
  res.json({ success: true, expenses });
});

exports.verifyTransaction = handle(async (req, res) => {
  const { userId } = req.body;
  const tx = await LedgerTransaction.findById(req.params.transactionId);
  if (!tx) throw fail(404, "Transaction not found");
  await requireRole(tx.companyId, userId, ["admin", "super_admin"]);
  if (tx.verification !== "pending") throw fail(400, "This payment is not waiting for verification");
  if (tx.createdBy.toString() === userId.toString()) throw fail(403, "A second admin must verify this payment");
  const filter = tx.routeId ? { routeId: tx.routeId } : { _id: tx._id };
  await LedgerTransaction.updateMany({ ...filter, verification: "pending" }, { $set: { verification: "verified", verifiedBy: userId } });
  if (tx.expenseId) await Expense.updateOne({ _id: tx.expenseId }, { $set: { verification: "verified" } });
  await audit(userId, tx.companyId, "verify", "transaction", tx._id, { verification: "pending" }, { verification: "verified" });
  res.json({ success: true });
});

// Company B sends money to Company A; booked in both companies' books.
exports.intercompanyTransfer = handle(async (req, res) => {
  const { userId, fromCompanyId, toCompanyId, amount, fromFundId, toFundId, method, reference } = req.body;
  const value = round(parseFloat(amount));
  if (!(value > 0)) throw fail(400, "Enter a valid amount");
  if (!fromCompanyId || !toCompanyId || fromCompanyId === toCompanyId) throw fail(400, "Pick two different companies");
  const [from, to] = await Promise.all([Company.findById(fromCompanyId), Company.findById(toCompanyId)]);
  if (!from || !to) throw fail(404, "Company not found");
  const roles = await Promise.all([roleIn(fromCompanyId, userId), roleIn(toCompanyId, userId)]);
  if (!roles.some(isAdminRole)) throw fail(403, "You must be an admin of one of these companies");

  const routeId = newRouteId();
  const base = { method: method || "", reference: reference || "", createdBy: userId, routeId, type: "intercompany" };
  const txs = await postAll([
    [
      { ...base, companyId: to._id, memo: `Received from ${from.name}` },
      [{ account: await fundAccount(to._id, toFundId), debit: value }, { account: await intercoAccount(to._id, from), credit: value }],
    ],
    [
      { ...base, companyId: from._id, memo: `Sent to ${to.name}` },
      [{ account: await intercoAccount(from._id, to), debit: value }, { account: await fundAccount(from._id, from.external ? "cash" : fromFundId), credit: value }],
    ],
  ]);
  await audit(userId, to._id, "intercompany", "transaction", txs[0]._id, null, { from: from._id, to: to._id, amount: value });
  await notifyCompanyAdmins([from._id, to._id], { title: "Inter-company payment", body: `${from.name} → ${to.name} · ₹${value}`, data: { transactionId: txs[0]._id } }, userId);
  res.json({ success: true, transactions: txs });
});

// B → A → admin: settles the admin's open balance in A with money from B. Never B → admin directly.
exports.routedPayment = handle(async (req, res) => {
  const { userId, companyId, adminUserId, amount, sourceCompanyId, newCompany, sourceFundId, method, reference } = req.body;
  const value = round(parseFloat(amount));
  if (!(value > 0)) throw fail(400, "Enter a valid amount");
  if (!companyId || !adminUserId) throw fail(400, "A routed payment must name the company and the admin");
  const role = await requireRole(companyId, userId, ["admin", "super_admin"]);
  if (!isAdminRole(await roleIn(companyId, adminUserId))) throw fail(400, "Payee must be an admin of this company");
  if (adminUserId.toString() === userId.toString()) throw fail(403, "You cannot reimburse yourself");
  const owed = await adminOwed(companyId, adminUserId);
  if (value > owed) throw fail(400, `Amount exceeds the open balance (₹${owed})`);

  const company = await Company.findById(companyId);
  const source = await resolveSourceCompany(userId, companyId, sourceCompanyId, newCompany);
  const loan = await CompanyLoan.create({ borrowerCompanyId: company._id, lenderCompanyId: source._id, amount: value, source: "direct", createdBy: userId, method: method || "", reference: reference || "", note: `Routed payment to ${adminUserId}` });
  const routeId = newRouteId();
  const verification = (await needsVerification(companyId, value)) ? "pending" : null;
  const base = { method: method || "", reference: reference || "", createdBy: userId, routeId, verification };
  const txs = await postAll([
    [
      { ...base, companyId, type: "routed", loanId: loan._id, memo: `Admin paid via ${source.name}` },
      [{ account: await payableAccount(companyId, adminUserId), debit: value }, { account: await intercoAccount(companyId, source), credit: value }],
    ],
    [
      { ...base, companyId: source._id, loanId: loan._id, type: "intercompany", memo: `Paid admin of ${company.name}` },
      [{ account: await intercoAccount(source._id, company), debit: value }, { account: await fundAccount(source._id, source.external ? "cash" : sourceFundId), credit: value }],
    ],
  ]);
  loan.transactionIds = txs.map((tx) => tx._id);
  await loan.save();
  await recomputeReimbursed(companyId, adminUserId);
  await audit(userId, companyId, "routed_payment", "transaction", txs[0]._id, null, { source: source._id, adminUserId, amount: value });
  await audit(userId, source._id, "routed_payment", "loan", loan._id, null, { companyId, adminUserId, amount: value });
  notifyUsers([adminUserId], { title: "You were reimbursed", body: `₹${value} paid to you via ${source.name}`, data: { transactionId: txs[0]._id, companyId } });
  await notifyCompanyAdmins([companyId, source._id], { title: "Borrowed from another company", body: `${source.name} → ${company.name} → admin · ₹${value}`, data: { transactionId: txs[0]._id } }, userId);
  if (verification) await notifyCompanyAdmins(companyId, { title: "Payment needs verification", body: `Routed payment of ₹${value}`, data: { transactionId: txs[0]._id, companyId } }, userId);
  res.json({ success: true, transactions: txs, owed: await adminOwed(companyId, adminUserId) });
});

// Who owes whom, with a mismatch flag when the two mirror accounts disagree.
exports.intercompanyBalances = handle(async (req, res) => {
  const { companyId } = req.params;
  const { userId } = req.query;
  await requireRole(companyId, userId, ["employee", "admin", "super_admin"]);
  const ours = await LedgerAccount.find({ companyId, type: "intercompany" }).populate("counterpartCompanyId", "name external");
  const rows = [];
  for (const acc of ours) {
    const counterpart = acc.counterpartCompanyId;
    if (!counterpart) continue;
    const mine = await accountTotals(acc._id);
    const net = round(mine.debit - mine.credit); // + they owe us, − we owe them
    const mirror = await LedgerAccount.findOne({ companyId: counterpart._id, type: "intercompany", counterpartCompanyId: companyId });
    const theirs = mirror ? await accountTotals(mirror._id) : { debit: 0, credit: 0 };
    const theirNet = round(theirs.debit - theirs.credit);
    rows.push({
      companyId: counterpart._id,
      name: counterpart.name,
      external: counterpart.external,
      net,
      mismatch: round(net + theirNet) !== 0,
    });
  }
  res.json({ success: true, balances: rows, net: round(rows.reduce((s, r) => s + r.net, 0)) });
});

// GSTIN, currency and verification threshold
exports.updateCompanySettings = handle(async (req, res) => {
  const { companyId } = req.params;
  const { userId, gstin, currency, verificationThreshold } = req.body;
  await requireRole(companyId, userId, ["admin", "super_admin"]);
  const company = await Company.findById(companyId);
  const before = { gstin: company.gstin, currency: company.currency, verificationThreshold: company.verificationThreshold };
  if (gstin !== undefined) company.gstin = String(gstin).trim().toUpperCase();
  if (currency !== undefined) company.currency = String(currency).trim().toUpperCase() || "INR";
  if (verificationThreshold !== undefined) {
    const t = verificationThreshold === null || verificationThreshold === "" ? null : parseFloat(verificationThreshold);
    if (t !== null && !(t >= 0)) throw fail(400, "Threshold must be a positive amount");
    company.verificationThreshold = t;
  }
  await company.save();
  const after = { gstin: company.gstin, currency: company.currency, verificationThreshold: company.verificationThreshold };
  await audit(userId, companyId, "update", "company", company._id, before, after);
  res.json({ success: true, company: after });
});

// Companies any admin of this company belongs to, plus companies it already deals with (incl. external ones added inline).
exports.listCompaniesForBorrow = handle(async (req, res) => {
  const { companyId } = req.params;
  const { userId } = req.query;
  await requireRole(companyId, userId, ["employee", "admin", "super_admin"]);
  const companies = await Company.find({ _id: { $ne: companyId } })
    .select("name gstin external")
    .sort({ name: 1 });
  res.json({ success: true, companies });
});

// ---------- Slice 3: reports & export ----------
function periodFilter(from, to) {
  const f = {};
  if (from) f.$gte = new Date(from);
  if (to) {
    const end = new Date(to);
    end.setHours(23, 59, 59, 999);
    f.$lte = end;
  }
  return Object.keys(f).length ? f : null;
}

async function companyReport(companyId, from, to, category) {
  const period = periodFilter(from, to);
  const expQuery = { companyId, lifecycle: { $in: ["paid_by_admin", "paid_by_person", "paid_by_company", "reimbursed"] } };
  if (period) expQuery.date = period;
  if (category && category !== "All") expQuery.category = category;
  const expenses = await Expense.find(expQuery).select("amount lifecycle category");
  const sum = (list) => round(list.reduce((s, e) => s + e.amount, 0));

  const payables = await LedgerAccount.find({ companyId, type: "admin_payable" });
  let owed = 0;
  for (const a of payables) {
    const t = await accountTotals(a._id);
    owed += t.credit - t.debit;
  }
  const intercos = await LedgerAccount.find({ companyId, type: "intercompany" });
  let interco = 0;
  for (const a of intercos) {
    const t = await accountTotals(a._id);
    interco += t.debit - t.credit;
  }
  return {
    expenses: sum(expenses),
    paidByAdmins: sum(expenses.filter((e) => e.lifecycle !== "paid_by_company")),
    owedToAdmins: round(owed),
    intercompanyNet: round(interco),
  };
}

exports.report = handle(async (req, res) => {
  const { companyId } = req.params;
  const { userId, from, to, category } = req.query;
  await requireRole(companyId, userId, ["admin", "super_admin"]);
  res.json({ success: true, report: await companyReport(companyId, from, to, category) });
});

const csvCell = (v) => {
  const s = v == null ? "" : String(v);
  return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
};

// scope=company: one company's ledger; scope=full: every company (super admin only) plus the audit log.
exports.exportCsv = handle(async (req, res) => {
  const { companyId } = req.params;
  const { userId, from, to, scope } = req.query;
  const full = scope === "full";
  await requireRole(companyId, userId, full ? ["super_admin"] : ["admin", "super_admin"]);

  const txQuery = full ? {} : { companyId };
  const period = periodFilter(from, to);
  if (period) txQuery.createdAt = period;
  const txs = await LedgerTransaction.find(txQuery).populate("companyId", "name").populate("createdBy", "name").sort({ createdAt: 1 }).lean();
  const entries = await LedgerEntry.find({ transactionId: { $in: txs.map((t) => t._id) } }).populate("accountId", "name").lean();
  const byTx = {};
  for (const e of entries) (byTx[e.transactionId.toString()] ||= []).push(e);

  const rows = [["Date", "Company", "Type", "Memo", "Account", "Debit", "Credit", "Method", "Reference", "Route", "Verification", "Reversed", "By"]];
  for (const t of txs) {
    for (const e of byTx[t._id.toString()] || []) {
      rows.push([
        new Date(t.createdAt).toISOString().slice(0, 10),
        t.companyId?.name,
        t.type,
        t.memo,
        e.accountId?.name,
        e.debit || "",
        e.credit || "",
        t.method,
        t.reference,
        t.routeId || "",
        t.verification || "",
        t.reversedBy ? "yes" : "",
        t.createdBy?.name,
      ]);
    }
  }
  if (full) {
    const logs = await AuditLog.find(period ? { at: period } : {})
      .select("-before -after")
      .populate("userId", "name")
      .sort({ at: 1 })
      .lean();
    rows.push([], ["Audit log"], ["At", "User", "Action", "Object", "Object ID"]);
    for (const l of logs) rows.push([new Date(l.at).toISOString(), l.userId?.name, l.action, l.object, l.objectId]);
  }

  res.setHeader("Content-Type", "text/csv; charset=utf-8");
  res.setHeader("Content-Disposition", `attachment; filename="${full ? "full-audit" : "company-report"}.csv"`);
  res.send("﻿" + rows.map((r) => r.map(csvCell).join(",")).join("\r\n"));
});

// ---------- Members & roles ----------
const ROLES = ["admin", "member"];

// Promote an existing member to admin, or move an admin back to staff. The company creator always stays admin.
exports.setMemberRole = handle(async (req, res) => {
  const { companyId, memberUserId } = req.params;
  const { userId, role } = req.body;
  if (!ROLES.includes(role)) throw fail(400, "Role must be admin or staff");
  await requireRole(companyId, userId, ["admin", "super_admin"]);
  const company = await Company.findById(companyId).select("createdBy name");
  if (company.createdBy && company.createdBy.toString() === String(memberUserId)) {
    throw fail(400, "The company creator is always an admin");
  }
  const member = await CompanyMember.findOne({ companyId, userId: memberUserId });
  if (!member) throw fail(404, "That person is not in this company");
  const before = { role: member.role };
  member.role = role;
  await member.save();
  await audit(userId, companyId, "change_role", "member", member._id, before, { role, memberUserId });
  notifyUsers([memberUserId], {
    title: role === "admin" ? "You're now an admin" : "Your role changed",
    body: role === "admin" ? `You can now approve and pay expenses in ${company.name}` : `You are now staff in ${company.name}`,
    data: { companyId },
  });
  res.json({ success: true });
});

// Add someone who already has an account, directly as admin or staff (no join code needed).
exports.addMember = handle(async (req, res) => {
  const { companyId } = req.params;
  const { userId, email, role } = req.body;
  if (!ROLES.includes(role)) throw fail(400, "Role must be admin or staff");
  await requireRole(companyId, userId, ["admin", "super_admin"]);
  const company = await Company.findById(companyId).select("name external");
  if (company.external) throw fail(400, "Outside companies can't have members");
  const user = await User.findOne({ email: String(email || "").trim() }).select("name");
  if (!user) throw fail(404, "No account with that email. Ask them to sign up first.");
  const existing = await CompanyMember.findOne({ companyId, userId: user._id });
  if (existing) throw fail(400, `${user.name} is already in this company — change their role instead`);
  const member = await CompanyMember.create({ companyId, userId: user._id, role });
  await audit(userId, companyId, "add_member", "member", member._id, null, { memberUserId: user._id, role });
  notifyUsers([user._id], {
    title: `Added to ${company.name}`,
    body: role === "admin" ? `You were added as an admin of ${company.name}` : `You were added to ${company.name}`,
    data: { companyId },
  });
  res.status(201).json({ success: true, member: { userId: user._id, name: user.name, role } });
});
