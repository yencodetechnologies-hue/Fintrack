const mongoose = require("mongoose");
const Company = require("../models/company");
const CompanyMember = require("../models/companyMember");
const Expense = require("../models/expense");
const User = require("../models/user");
const { LedgerAccount, LedgerTransaction, LedgerEntry, AuditLog } = require("../models/ledger");
const CompanyLoan = require("../models/companyLoan");
const { ExpenseGroup } = require("../models/expenseGroup");
const CompanyInvite = require("../models/companyInvite");
const Voucher = require("../models/voucher");
const AdvanceReturn = require("../models/advanceReturn");
const nodemailer = require("nodemailer");
const { notifyUsers, notifyCompanyAdmins } = require("../services/ledgerNotify");
const { LISTS, resolved, resolvedCustom, roleBase, hasPower, permissionsFor, permissionDenied } = require("../utils/permissions");

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

// a feature switch the primary admin (or a manager, for staff) turned off for this person's role
async function requirePermission(companyId, userId, key) {
  const denied = await permissionDenied(companyId, userId, key);
  if (denied) throw fail(403, denied);
}

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
    { upsert: true, returnDocument: "after" }
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

// Loans only ever move the BORROWER's Cash/Bank (direct loans in, repayments out). A lender's balance is
// never changed by lending — it shows separately as "Lent to other companies". Outside companies have no funds.
async function applyIfTracked(company, fundId, delta) {
  if (!company || company.external) return;
  await applyCompanyFund(company._id, fundId || "cash", delta);
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

// Transaction types whose bank lines were also applied to Company.cashBalance / bankAccounts[].balance.
// Lender-side legs (intercompany) never touched the lender's displayed funds, so they are left alone.
const FUND_TRACKED_TYPES = new Set(["company_paid", "reimburse", "lend", "borrowed", "voucher_issue", "advance_return"]);

async function legMovesCompanyFunds(leg) {
  if (FUND_TRACKED_TYPES.has(leg.type)) return true;
  if (leg.type === "loan_repayment" && leg.loanId) {
    const loan = await CompanyLoan.findById(leg.loanId).select("borrowerCompanyId");
    return Boolean(loan && String(loan.borrowerCompanyId) === String(leg.companyId));
  }
  return false;
}

// Mirrors a transaction's entries, marks it reversed and gives back what it did to the displayed Cash/Bank.
async function postReversal(leg, userId, memo) {
  const entries = await LedgerEntry.find({ transactionId: leg._id });
  const accounts = await LedgerAccount.find({ _id: { $in: entries.map((e) => e.accountId) } });
  const accMap = new Map(accounts.map((a) => [a._id.toString(), a]));
  const reversal = await post(
    { companyId: leg.companyId, type: "reversal", memo: memo || `Reversal of ${leg.type}`, expenseId: leg.expenseId, voucherId: leg.voucherId, advanceReturnId: leg.advanceReturnId, routeId: leg.routeId, reverses: leg._id, createdBy: userId },
    entries.map((e) => ({ account: accMap.get(e.accountId.toString()), debit: e.credit, credit: e.debit }))
  );
  leg.reversedBy = reversal._id;
  await leg.save();
  if (await legMovesCompanyFunds(leg)) {
    const company = await Company.findById(leg.companyId).select("external");
    if (company && !company.external) {
      for (const e of entries) {
        const acc = accMap.get(e.accountId.toString());
        if (!acc || acc.type !== "bank") continue;
        const applied = round(e.debit - e.credit);
        if (applied) await applyCompanyFund(leg.companyId, acc.bankAccountId ? String(acc.bankAccountId) : "cash", -applied);
      }
    }
  }
  return { reversal, accounts };
}

const audit =(userId, companyId, action, object, objectId, before, after) =>
  AuditLog.create({ userId, companyId, action, object, objectId, before, after });

const snapshot = (doc) => {
  if (!doc) return null;
  const obj = JSON.parse(JSON.stringify(doc.toObject ? doc.toObject() : doc));
  if (obj.attachment) obj.attachment = "[image]";
  if (obj.paymentReceipt) obj.paymentReceipt = "[image]";
  return obj;
};

// FIFO: walk a person's payable credits oldest first; fully reimbursed expenses become "reimbursed".
// Walks a person's payable: every bill (credit) oldest first, and how much of it has been paid back.
// Payments go oldest-first, except a payment tied to one bill ("Received" on that expense: a reimburse tx with
// expenseId) which pays that bill first. Shared by recomputeReimbursed and openPayableBills so they never disagree.
async function payableWalk(companyId, personUserId) {
  const acc = await LedgerAccount.findOne({ companyId, type: "admin_payable", userId: personUserId });
  if (!acc) return [];
  const entries = await LedgerEntry.find({ accountId: acc._id }).sort({ createdAt: 1 });
  let paidBack = round(entries.reduce((s, e) => s + e.debit, 0));
  const txIds = entries.filter((e) => e.credit > 0).map((e) => e.transactionId);
  const txs = await LedgerTransaction.find({ _id: { $in: txIds }, reversedBy: null, type: { $ne: "reversal" } });
  const txMap = new Map(txs.map((t) => [t._id.toString(), t]));

  // reversed credits are cancelled by their reversal debit, so drop both from the walk
  for (const e of entries) {
    if (e.credit > 0 && !txMap.has(e.transactionId.toString())) paidBack = round(paidBack - e.credit);
  }

  // payments tied to one bill are kept apart from the oldest-first pool: tied to the bill's own transaction
  // ("Your outstanding" pay) or to its expense ("Received")
  const debitTxIds = entries.filter((e) => e.debit > 0).map((e) => e.transactionId);
  const tied = await LedgerTransaction.find({
    _id: { $in: debitTxIds },
    reversedBy: null,
    type: "reimburse",
    $or: [{ settlesTransactionId: { $ne: null } }, { expenseId: { $ne: null } }],
  }).select("expenseId settlesTransactionId");
  const tiedTx = new Map(tied.map((t) => [t._id.toString(), t.settlesTransactionId ? `tx:${t.settlesTransactionId}` : `exp:${t.expenseId}`]));
  const tiedLeft = new Map();
  for (const e of entries) {
    const key = e.debit > 0 ? tiedTx.get(e.transactionId.toString()) : null;
    if (!key) continue;
    tiedLeft.set(key, round((tiedLeft.get(key) || 0) + e.debit));
    paidBack = round(paidBack - e.debit);
  }

  const bills = [];
  for (const e of entries) {
    if (!(e.credit > 0)) continue;
    const tx = txMap.get(e.transactionId.toString());
    if (!tx) continue;
    let fromTied = 0;
    for (const key of [`tx:${tx._id}`, tx.expenseId ? `exp:${tx.expenseId}` : null]) {
      if (!key || fromTied >= e.credit) continue;
      const take = Math.min(round(e.credit - fromTied), tiedLeft.get(key) || 0);
      if (take > 0) {
        tiedLeft.set(key, round(tiedLeft.get(key) - take));
        fromTied = round(fromTied + take);
      }
    }
    const rest = round(e.credit - fromTied);
    const fromPool = Math.min(rest, Math.max(0, paidBack));
    paidBack = round(paidBack - rest);
    bills.push({ entry: e, tx, credit: e.credit, covered: round(fromTied + fromPool) });
  }
  return bills;
}

async function recomputeReimbursed(companyId, adminUserId) {
  for (const { tx, credit, covered } of await payableWalk(companyId, adminUserId)) {
    if (!tx.expenseId) continue;
    const expense = await Expense.findById(tx.expenseId).select("paidByAdminId");
    await Expense.updateOne(
      { _id: tx.expenseId, lifecycle: { $in: ["paid_by_admin", "paid_by_person", "reimbursed"] } },
      { $set: { lifecycle: covered >= credit ? "reimbursed" : (expense?.paidByAdminId ? "paid_by_admin" : "paid_by_person") } }
    );
  }
}

// Same walk as recomputeReimbursed, read-only: what is still unpaid on each of a person's bills, oldest first.
async function openPayableBills(companyId, personUserId) {
  const bills = [];
  for (const { entry: e, tx, credit, covered } of await payableWalk(companyId, personUserId)) {
    const remaining = round(credit - covered);
    if (remaining > 0) bills.push({ transactionId: tx._id, expenseId: tx.expenseId, memo: tx.memo, amount: credit, remaining, postedAt: e.createdAt });
  }
  const expenses = await Expense.find({ _id: { $in: bills.map((b) => b.expenseId).filter(Boolean) } }).select("description category date");
  const byId = new Map(expenses.map((x) => [x._id.toString(), x]));
  return bills.map((b) => {
    const x = b.expenseId ? byId.get(b.expenseId.toString()) : null;
    return { ...b, description: x?.description || b.memo || "Payable", category: x?.category || "", date: x?.date || b.postedAt };
  });
}

// Approved, still-unpaid expenses a person posted, oldest first: the company owes these to them too.
async function pendingClaims(companyId, personUserId) {
  return Expense.find({ companyId, createdBy: personUserId, lifecycle: "approved", status: "outstanding", groupId: null })
    .select("companyId description category date amount createdAt")
    .sort({ date: 1, createdAt: 1 });
}

// Books a claim as paid by the person who posted it, so it becomes a payable that a reimbursement can close.
async function acknowledgeClaim(expense, personUserId, userId) {
  const personIsAdmin = isAdminRole(await roleIn(expense.companyId, personUserId));
  const claimed = await Expense.findOneAndUpdate(
    { _id: expense._id, lifecycle: "approved", status: "outstanding" },
    { $set: { lifecycle: "paid_by_person", status: "paid", payerType: "person", paidByUserId: personUserId, paidByAdminId: personIsAdmin ? personUserId : null } },
    { returnDocument: "after" }
  );
  if (!claimed) return false;
  try {
    const tx = await post(
      { companyId: expense.companyId, type: "admin_paid", expenseId: expense._id, memo: expense.description, createdBy: userId },
      [
        { account: await expenseAccount(expense.companyId, expense.category), debit: expense.amount },
        { account: await payableAccount(expense.companyId, personUserId), credit: expense.amount },
      ]
    );
    claimed.transactionId = tx._id;
    await claimed.save();
  } catch (e) {
    await Expense.updateOne({ _id: expense._id }, { $set: { lifecycle: "approved", status: "outstanding", payerType: "unpaid", paidByUserId: null, paidByAdminId: null } });
    throw e;
  }
  await audit(userId, expense.companyId, "acknowledge_claim", "expense", expense._id, null, { paidByUserId: personUserId, amount: expense.amount });
  return true;
}

exports.payableBills = handle(async (req, res) => {
  const { companyId, personId } = req.params;
  const { userId } = req.query;
  const role = await requireRole(companyId, userId, ["employee", "admin", "super_admin"]);
  if (!isAdminRole(role) && String(personId) !== String(userId)) throw fail(403, "You can only view your own open bills");
  const recorded = await openPayableBills(companyId, personId);
  const claims = (await pendingClaims(companyId, personId)).map((c) => ({
    transactionId: null,
    expenseId: c._id,
    description: c.description,
    category: c.category,
    date: c.date || c.createdAt,
    amount: c.amount,
    remaining: c.amount,
    claim: true,
  }));
  const owed = round((await adminOwed(companyId, personId)) + claims.reduce((s, c) => s + c.amount, 0));
  // recorded payables are closed first, then claims in date order (matches how reimburse books them)
  res.json({ success: true, owed, bills: [...recorded, ...claims] });
});

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

  // "borrow": a manager posts it as paid with money borrowed from another company (same as Record payment → Borrowed)
  const isBorrowPost = isAdminRole(role) && postAs === "borrow";
  const isCompanyPost = !isBorrowPost && isAdminRole(role) && (postAs === "company" || logAs === "company");
  await requirePermission(companyId, userId, "post_expenses");
  if (isCompanyPost) await requirePermission(companyId, userId, "post_as_company");
  if (isBorrowPost) {
    await requirePermission(companyId, userId, "intercompany");
    const { sourceCompanyId, newCompany } = req.body;
    if (!sourceCompanyId && !(newCompany && String(newCompany.name || "").trim())) throw fail(400, "Choose the company you borrowed from");
    if (sourceCompanyId && String(sourceCompanyId) === String(companyId)) throw fail(400, "A company can't borrow from itself");
    if (sourceCompanyId && !(await Company.exists({ _id: sourceCompanyId }))) throw fail(404, "Source company not found");
  }

  // Opt-in (the web sends checkDuplicate) so other clients keep posting as before.
  if (req.body.checkDuplicate && !req.body.confirmDuplicate) {
    const escaped = String(description).trim().replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    const duplicate = await Expense.findOne({
      companyId,
      amount: value,
      description: new RegExp(`^${escaped}$`, "i"),
      lifecycle: { $nin: [null, "rejected"] },
    }).select("description amount date createdAt lifecycle createdBy").populate("createdBy", "name").sort({ createdAt: -1 });
    if (duplicate) {
      return res.status(409).json({
        success: false,
        code: "DUPLICATE_EXPENSE",
        message: "An expense with the same amount and description already exists",
        duplicate,
      });
    }
  }

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
    // a borrow post starts approved; the borrow payment below moves it on (paid, or awaiting the lender's confirmation)
    lifecycle: isCompanyPost ? "paid_by_company" : isBorrowPost ? "approved" : (isAdminRole(role) && (await autoApproves(companyId, userId)) ? "approved" : "submitted"),
    approvedBy: isAdminRole(role) ? userId : null,
    status: isCompanyPost ? "paid" : "outstanding",
    logAs: isCompanyPost || isBorrowPost ? "company" : "self",
    // staff may ask for this to come out of the voucher balance they hold; it is taken when a manager approves
    useAdvance: role === "employee" && Boolean(req.body.useAdvance),
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

  let awaitingConfirmation = false;
  if (isBorrowPost) {
    // reuse Record payment's borrow flow (loan + both companies' entries + lender confirmation when needed);
    // if it fails, the new expense is removed so nothing half-done is left behind
    const result = { code: 200, body: null, status(c) { this.code = c; return this; }, json(b) { this.body = b; return this; } };
    await exports.payExpense({ params: { expenseId: String(expense._id) }, body: {
      userId, payer: "borrow", method: method || "Bank", reference: reference || "",
      sourceCompanyId: req.body.sourceCompanyId, newCompany: req.body.newCompany, sourceFundId: req.body.sourceFundId,
    } }, result);
    if (!result.body?.success) {
      await Expense.deleteOne({ _id: expense._id });
      return res.status(result.code >= 400 ? result.code : 400).json(result.body || { success: false, message: "Could not record the borrowed payment" });
    }
    awaitingConfirmation = Boolean(result.body.awaitingConfirmation);
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
  res.status(201).json({ success: true, awaitingConfirmation, expense: await Expense.findById(expense._id).select("-attachment -paymentReceipt").populate("paidByUserId", "name") });
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
      .select("companyId createdBy isAdminCreated visibleTo amount description category date lifecycle createdAt approvedBy verification logAs voucherId useAdvance advanceUsed")
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
  // older borrowed payments didn't store the paying company; recover it from the loan so "Paid by <company>" shows
  const missingPayer = expenses.filter((e) => e.payerType === "other_company" && !e.payerCompanyId);
  if (missingPayer.length) {
    const loans = await CompanyLoan.find({ expenseId: { $in: missingPayer.map((e) => e._id) } }).populate("lenderCompanyId", "name").select("expenseId lenderCompanyId");
    const lenderByExpense = new Map(loans.map((l) => [String(l.expenseId), l.lenderCompanyId]));
    for (const e of missingPayer) {
      const lender = lenderByExpense.get(String(e._id));
      if (lender) e.payerCompanyId = { _id: lender._id, name: lender.name };
    }
  }
  if (summary !== "1" && expenses.length) {
    expenses = expenses.map((expense) => ({
      ...expense,
      hasAttachment: Boolean(expense.hasAttachment),
      hasPaymentReceipt: Boolean(expense.hasPaymentReceipt),
    }));
  }
  const mine = isAdminRole(role) ? await permissionsFor(companyId, userId) : null;
  if (!isAdminRole(role) || (mine?.role === "custom" && !mine.perms.view_all)) {
    const admins = new Set(await adminIds(companyId));
    const company = await Company.findById(companyId).select("createdBy");
    if (company?.createdBy) admins.add(String(company.createdBy));
    expenses = expenses.filter((e) => {
      const creator = String(e.createdBy?._id || e.createdBy);
      if (creator === String(userId)) return true;
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
  await requirePermission(expense.companyId, userId, "approve_expenses");
  const before = snapshot(expense);
  const approveAndApply = async () => {
    const approved = await Expense.findOneAndUpdate(
      { _id: expense._id, lifecycle: "submitted" },
      { $set: { lifecycle: target, approvedBy: userId } },
      { returnDocument: "after" }
    );
    if (!approved) throw fail(400, `Only submitted expenses can be ${target}`);
    if (target === "approved" && approved.useAdvance) {
      try {
        await applyAdvanceToExpense(approved, userId);
      } catch (e) {
        // the expense stays approved (owed to its creator) if the balance couldn't be booked
        console.error("applying voucher balance failed:", e.message);
      }
    }
  };
  if (target === "approved" && expense.useAdvance) await withAdvanceLock(expense.companyId, expense.createdBy, approveAndApply);
  else await approveAndApply();
  const updated = await Expense.findById(expense._id).select("-attachment -paymentReceipt")
    .populate("createdBy", "name email").populate("approvedBy", "name email").populate("paidByUserId", "name");
  await audit(userId, expense.companyId, target === "approved" ? "approve" : "reject", "expense", expense._id, before, snapshot(updated));
  notifyUsers([expense.createdBy], { title: target === "approved" ? "Expense approved" : "Expense rejected", body: `${expense.description} · ₹${expense.amount}`, data: { expenseId: expense._id, companyId: expense.companyId } }, userId);
  res.json({ success: true, expense: updated });
}

exports.approveExpense = handle((req, res) => decide(req, res, "approved"));
exports.rejectExpense = handle((req, res) => decide(req, res, "rejected"));

exports.payExpense = handle(async (req, res) => {
  const { userId, payer, fundId, method, reference, sourceCompanyId, newCompany, sourceFundId, paidByUserId, paymentReceipt } = req.body;
  if (!["admin", "person", "company", "borrow"].includes(payer)) throw fail(400, "Choose a valid payment type");
  // the payment receipt is optional; the method is still needed for the books
  if (!method || !String(method).trim()) throw fail(400, "Payment method is required");
  const expense = await Expense.findById(req.params.expenseId);
  if (!expense) throw fail(404, "Expense not found");
  if (expense.groupId) throw fail(403, "Group expenses are settled only when the group is closed");
  const companyId = expense.companyId;
  const role = await requireRole(companyId, userId, ["employee", "admin", "super_admin"]);
  const isAdmin = isAdminRole(role);
  const staffBorrow = payer === "borrow" && !isAdmin;
  await requirePermission(companyId, userId, staffBorrow ? "borrow" : payer === "borrow" ? "intercompany" : "record_payments");
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
    ? await fundAccount(source._id, source.external || staffBorrow ? "cash" : (sourceFundId || "cash"))
    : null;
  // A manager of both companies is the lender's admin too, so there is nobody else to confirm.
  // borrowing never depends on the lender's balance; it is tracked as a loan instead
  const managesSource = Boolean(source && !source.external && isAdminRole(await roleIn(source._id, userId)));

  // Staff borrow payments settle immediately, like a group settlement; admin-recorded
  // company payments still require a registered lender's confirmation unless the payer manages the lender.
  if (payer === "borrow" && !source.external && !staffBorrow && !managesSource) {
    const requested = await Expense.findOneAndUpdate(
      { _id: expense._id, lifecycle: "approved", status: "outstanding" },
      { $set: { lifecycle: "awaiting_confirmation", status: "outstanding", payerType: "other_company", payerCompanyId: source._id, payerConfirmation: "pending", payerMethod: method || "", payerReference: reference || "", paymentReceipt: paymentReceipt || "", hasPaymentReceipt: Boolean(paymentReceipt) } },
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
    { $set: { lifecycle: target, paidByAdminId: payer === "admin" ? userId : null, paidByUserId: ["admin", "person"].includes(payer) ? recordedPayerId : null, payerType: ["admin", "person"].includes(payer) ? "person" : payer === "company" ? "company" : "other_company", payerCompanyId: payer === "borrow" ? source._id : null, payerMethod: method || "", payerReference: reference || "", ...(paymentReceipt ? { paymentReceipt, hasPaymentReceipt: true } : {}), status: "paid", verification } },
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
  await requirePermission(expense.companyId, userId, "edit_expenses");
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
  if (!userId) throw fail(400, "User ID is required");
  const expense = await Expense.findById(req.params.expenseId).select("-attachment -paymentReceipt");
  if (!expense) throw fail(404, "Expense not found");

  const role = await roleIn(expense.companyId, userId);
  const isAdmin = isAdminRole(role);
  const isCreator = expense.createdBy && expense.createdBy.toString() === userId.toString();

  if (!isAdmin && !isCreator) {
    throw fail(403, "You can only delete your own expenses");
  }
  await requirePermission(expense.companyId, userId, "edit_expenses");
  if (!isAdmin && expense.lifecycle !== "submitted") {
    throw fail(400, "Staff can only delete expenses before approval");
  }
  if (expense.lifecycle && expense.lifecycle.startsWith("paid")) {
    throw fail(400, "Paid expenses cannot be deleted directly; booked payments must be reversed");
  }

  await audit(userId, expense.companyId, "delete", "expense", expense._id, snapshot(expense), null);
  await Expense.deleteOne({ _id: expense._id });
  res.json({ success: true });
});

exports.updateExpense = handle(async (req, res) => {
  const { userId, amount, description, category, date } = req.body;
  if (!userId) throw fail(400, "User ID is required");
  const expense = await Expense.findById(req.params.expenseId);
  if (!expense) throw fail(404, "Expense not found");

  const role = await roleIn(expense.companyId, userId);
  const isAdmin = isAdminRole(role);
  const isCreator = expense.createdBy && expense.createdBy.toString() === userId.toString();

  if (!isAdmin && !isCreator) {
    throw fail(403, "You can only edit your own expenses");
  }
  await requirePermission(expense.companyId, userId, "edit_expenses");

  // Staff can only edit before approval
  if (!isAdmin && expense.lifecycle && expense.lifecycle !== "submitted") {
    throw fail(400, "Staff can only edit expenses before approval");
  }

  // Manager can edit before paid by company
  const isPaid = expense.status === "paid" || (expense.lifecycle && expense.lifecycle.startsWith("paid"));
  if (isPaid) {
    throw fail(400, "This expense can no longer be edited because it has already been paid");
  }
  // the lender company is confirming this exact amount
  if (expense.lifecycle === "awaiting_confirmation") {
    throw fail(409, "This expense is awaiting payer confirmation and can't be edited");
  }

  const before = snapshot(expense);
  if (amount !== undefined) {
    const parsed = parseFloat(amount);
    if (!(parsed > 0)) throw fail(400, "Amount must be greater than zero");
    expense.amount = parsed;
  }
  if (description !== undefined) {
    if (!String(description).trim()) throw fail(400, "Description is required");
    expense.description = String(description).trim();
  }
  if (category !== undefined && String(category).trim()) {
    expense.category = String(category).trim();
  }
  if (date) expense.date = new Date(date);

  await expense.save();
  await audit(userId, expense.companyId, "update", "expense", expense._id, before, snapshot(expense));
  if (!BASE_EXPENSE_CATEGORIES.includes(expense.category)) {
    await Company.updateOne({ _id: expense.companyId }, { $addToSet: { customCategories: expense.category } });
  }
  if (!isCreator) {
    notifyUsers([expense.createdBy], { title: "Expense edited by a manager", body: `${expense.description} · ₹${expense.amount}`, data: { expenseId: expense._id, companyId: expense.companyId } }, userId);
  }
  res.json({ success: true, message: "Expense updated successfully", expense });
});

// The manager who created an expense can switch who paid it — themselves or the company — at any time.
// The old payment is reversed in the books (and fund balance restored) before the new one is posted.
exports.changePayerType = handle(async (req, res) => {
  const { userId, payerType, fundId } = req.body;
  if (!["manager", "company"].includes(payerType)) throw fail(400, "Choose who paid: manager or company");
  const expense = await Expense.findById(req.params.expenseId);
  if (!expense) throw fail(404, "Expense not found");
  const companyId = expense.companyId;
  const role = await requireRole(companyId, userId, ["employee", "admin", "super_admin"]);
  if (!isAdminRole(role) || String(expense.createdBy) !== String(userId)) {
    throw fail(403, "Only the manager who created this expense can change who paid it");
  }
  await requirePermission(companyId, userId, "record_payments");
  if (expense.groupId) throw fail(400, "Group expenses are settled with the group");
  if (expense.lifecycle === "reimbursed") throw fail(400, "You were already reimbursed for this expense, so it can't be switched");
  const current = expense.lifecycle === "paid_by_company" && expense.payerType === "company" ? "company"
    : expense.lifecycle === "paid_by_admin" && String(expense.paidByAdminId) === String(userId) ? "manager"
    : expense.lifecycle === "approved" ? "unpaid" : null;
  if (!current) throw fail(400, "This expense was paid another way (by someone else or another company) and can't be switched here");
  if (current === payerType) throw fail(400, `It's already marked as paid by ${payerType === "company" ? "the company" : "you"}`);

  const amount = expense.amount;
  if (payerType === "company") {
    const fund = fundId || "cash";
    const available = await getEffectiveFundBalance(companyId, fund);
    if (available < amount) throw fail(400, `Insufficient balance in the selected fund (₹${available.toFixed(2)} available, ₹${amount.toFixed(2)} required)`);
  }
  // moving off "paid by me" must not take back money already reimbursed on this bill
  if (current === "manager" && (await adminOwed(companyId, userId)) < amount) {
    throw fail(400, "Part of what the company owed you has already been reimbursed; this expense can't be switched to company");
  }

  const before = snapshot(expense);
  // 1. undo the old payment
  const oldTx = expense.transactionId ? await LedgerTransaction.findById(expense.transactionId) : null;
  if (oldTx && !oldTx.reversedBy) {
    const entries = await LedgerEntry.find({ transactionId: oldTx._id });
    const accounts = await LedgerAccount.find({ _id: { $in: entries.map((e) => e.accountId) } });
    const accMap = new Map(accounts.map((a) => [a._id.toString(), a]));
    const reversal = await post(
      { companyId, type: "reversal", memo: `Payer changed: ${expense.description}`, expenseId: expense._id, reverses: oldTx._id, createdBy: userId },
      entries.map((e) => ({ account: accMap.get(e.accountId.toString()), debit: e.credit, credit: e.debit }))
    );
    oldTx.reversedBy = reversal._id;
    await oldTx.save();
    if (current === "company") {
      const fundAcc = accounts.find((a) => a.type === "bank" && entries.some((e) => String(e.accountId) === String(a._id) && e.credit > 0));
      await applyCompanyFund(companyId, fundAcc?.bankAccountId ? String(fundAcc.bankAccountId) : "cash", amount);
    }
  }

  // 2. book the new payment
  const isCompany = payerType === "company";
  const verification = isCompany && (await needsVerification(companyId, amount)) ? "pending" : null;
  const tx = await post(
    { companyId, type: isCompany ? "company_paid" : "admin_paid", expenseId: expense._id, memo: expense.description, method: expense.payerMethod || "", reference: expense.payerReference || "", createdBy: userId, verification },
    [
      { account: await expenseAccount(companyId, expense.category), debit: amount },
      { account: isCompany ? await fundAccount(companyId, fundId || "cash") : await payableAccount(companyId, userId), credit: amount },
    ]
  );
  if (isCompany) await applyCompanyFund(companyId, fundId || "cash", -amount);

  Object.assign(expense, {
    lifecycle: isCompany ? "paid_by_company" : "paid_by_admin",
    status: "paid",
    payerType: isCompany ? "company" : "person",
    paidByAdminId: isCompany ? null : userId,
    paidByUserId: isCompany ? null : userId,
    logAs: isCompany ? "company" : "self",
    transactionId: tx._id,
    verification,
  });
  await expense.save();
  if (current === "manager") await recomputeReimbursed(companyId, userId);
  await audit(userId, companyId, "change_payer", "expense", expense._id, before, snapshot(expense));
  if (verification) await notifyCompanyAdmins(companyId, { title: "Payment needs verification", body: `${expense.description} · ₹${amount}`, data: { transactionId: tx._id, companyId } }, userId);
  res.json({ success: true, expense: await Expense.findById(expense._id).select("-attachment -paymentReceipt") });
});

// Managers can swap receipt images at any status (after payment the amount and details stay locked).
exports.updateExpenseReceipts = handle(async (req, res) => {
  const { userId, attachment, paymentReceipt } = req.body;
  if (!userId) throw fail(400, "User ID is required");
  const isImage = (v) => typeof v === "string" && v.startsWith("data:image/");
  // an empty string removes that receipt (managers only, checked below); an expense may have none
  const valid = (v) => v === undefined || v === "" || isImage(v);
  if (attachment === undefined && paymentReceipt === undefined) throw fail(400, "Attach a receipt to upload");
  if (!valid(attachment) || !valid(paymentReceipt)) throw fail(400, "Receipts must be image files");
  const removing = attachment === "" || paymentReceipt === "";
  const expense = await Expense.findById(req.params.expenseId);
  if (!expense) throw fail(404, "Expense not found");
  // receipts are evidence, not amounts, so managers may fix them at any status;
  // the creator may fix their own bill receipt while it still awaits approval (same as editing)
  const role = await requireRole(expense.companyId, userId, ["employee", "admin", "super_admin"]);
  if (!isAdminRole(role)) {
    const ownSubmitted = String(expense.createdBy) === String(userId) && expense.lifecycle === "submitted";
    if (removing) throw fail(403, "Only managers can remove receipts");
    if (!ownSubmitted || paymentReceipt !== undefined) throw fail(403, "Only managers can change receipts after approval");
  }
  await requirePermission(expense.companyId, userId, removing ? "remove_receipts" : "edit_expenses");

  const replaced = [];
  const removed = [];
  for (const [field, value] of [["attachment", attachment], ["paymentReceipt", paymentReceipt]]) {
    if (value === undefined) continue;
    expense[field] = value;
    (value === "" ? removed : replaced).push(field);
  }
  await expense.save();
  await audit(userId, expense.companyId, removed.length && !replaced.length ? "remove_receipts" : "update_receipts", "expense", expense._id, null, { replaced, removed });
  res.json({ success: true, hasAttachment: expense.hasAttachment, hasPaymentReceipt: expense.hasPaymentReceipt });
});

// ---------- reimburse & lend ----------
exports.reimburse = handle(async (req, res) => {
  const { companyId, userId, adminUserId, amount, fundId, method, reference, offsetAdvance } = req.body;
  // paidBy "self": the manager pays the person out of their own pocket, so the company now owes the manager instead
  const bySelf = req.body.paidBy === "self";
  const value = round(parseFloat(amount) || 0);
  if (value < 0) throw fail(400, "Enter a valid amount");
  if (!adminUserId) throw fail(400, "Choose who to reimburse");
  const role = await requireRole(companyId, userId, ["admin", "super_admin"]);
  await requirePermission(companyId, userId, "reimburse");
  const targetRole = await roleIn(companyId, adminUserId);
  if (!targetRole) throw fail(400, "The payee must be a member of this company");
  if (adminUserId.toString() === userId.toString()) throw fail(403, "You cannot reimburse yourself");

  const run = async () => {
    const recordedOwed = await adminOwed(companyId, adminUserId);
    const claims = await pendingClaims(companyId, adminUserId);
    const owed = round(recordedOwed + claims.reduce((s, c) => s + c.amount, 0));
    // optional netting: voucher balance the person still holds is set against what they are owed
    const held = offsetAdvance ? Math.max(0, await heldAdvance(companyId, adminUserId)) : 0;
    const offset = round(Math.min(held, Math.max(0, owed - value)));
    if (!(value > 0) && !(offset > 0)) throw fail(400, "Enter a valid amount");
    const settled = round(value + offset);
    if (settled > owed) throw fail(400, `Amount exceeds the open balance (₹${owed})`);
    if (value > 0 && !bySelf) {
      const available = await getEffectiveFundBalance(companyId, fundId);
      if (available < value) throw fail(400, `Insufficient balance in the selected fund (₹${available.toFixed(2)} available)`);
    }
    const openBefore = (await openPayableBills(companyId, adminUserId)).length + claims.length;

    // book only as many of the oldest approved claims as this payment needs; the rest stay approved
    let covered = recordedOwed;
    let acknowledged = 0;
    for (const claim of claims) {
      if (covered >= settled) break;
      if (await acknowledgeClaim(claim, adminUserId, userId)) {
        covered = round(covered + claim.amount);
        acknowledged += 1;
      }
    }
    if (covered < settled) throw fail(409, "Some claims changed while paying; refresh and try again");

    let offsetTx = null;
    if (offset > 0) {
      offsetTx = await post(
        { companyId, type: "advance_offset", memo: "Voucher balance set against reimbursement", createdBy: userId },
        [
          { account: await payableAccount(companyId, adminUserId), debit: offset },
          { account: await advanceAccount(companyId, adminUserId), credit: offset },
        ]
      );
      await audit(userId, companyId, "advance_offset", "transaction", offsetTx._id, null, { adminUserId, amount: offset });
    }
    let tx = null;
    const payer = bySelf ? await User.findById(userId).select("name") : null;
    if (value > 0 && bySelf) {
      // person's payable goes down, the paying manager's goes up; company Cash/Bank is untouched
      tx = await post(
        { companyId, type: "reimburse", memo: `Paid by ${payer?.name || "manager"} personally`, method: method || "", reference: reference || "", createdBy: userId },
        [
          { account: await payableAccount(companyId, adminUserId), debit: value },
          { account: await payableAccount(companyId, userId), credit: value },
        ]
      );
      await audit(userId, companyId, "reimburse_by_self", "transaction", tx._id, null, { adminUserId, amount: value });
    } else if (value > 0) {
      tx = await post(
        { companyId, type: "reimburse", memo: "Admin reimbursement", method: method || "", reference: reference || "", createdBy: userId, verification: (await needsVerification(companyId, value)) ? "pending" : null },
        [
          { account: await payableAccount(companyId, adminUserId), debit: value },
          { account: await fundAccount(companyId, fundId), credit: value },
        ]
      );
      await applyCompanyFund(companyId, fundId, -value);
      await audit(userId, companyId, "reimburse", "transaction", tx._id, null, { adminUserId, amount: value });
    }
    await recomputeReimbursed(companyId, adminUserId);
    const lead = tx || offsetTx;
    const paidLine = bySelf ? `₹${value} paid to you by ${payer?.name || "a manager"}` : `₹${value} paid back to you`;
    const body = value > 0 && offset > 0 ? `${paidLine}, ₹${offset} taken from your voucher balance`
      : value > 0 ? paidLine : `₹${offset} taken from your voucher balance`;
    notifyUsers([adminUserId], { title: "You were reimbursed", body, data: { transactionId: lead._id, companyId } });
    if (tx?.verification === "pending") await notifyCompanyAdmins(companyId, { title: "Payment needs verification", body: `Reimbursement of ₹${value}`, data: { transactionId: tx._id, companyId } }, userId);
    const openAfter = (await openPayableBills(companyId, adminUserId)).length + (claims.length - acknowledged);
    const billsClosed = Math.max(0, openBefore - openAfter);
    res.json({ success: true, transaction: lead, offset, owed: await adminOwed(companyId, adminUserId), billsClosed });
  };
  if (offsetAdvance) await withAdvanceLock(companyId, adminUserId, run);
  else await run();
});

// A manager's own expense (posted as themselves, so the company owes them): they record that they got the money
// back — from the company's Cash/Bank, or from another member who paid them personally (the company then owes
// that member instead). Closes this exact expense as reimbursed.
// body: { userId, from: "company" | "person", fundId?, personId?, method?, reference? }
exports.receivedExpense = handle(async (req, res) => {
  const { userId, from, fundId, personId, method, reference } = req.body;
  // from: "company" (its Cash/Bank) | "person" (another member paid me) | "borrow" (another company paid me, so this company borrows from it)
  if (!["company", "person", "borrow"].includes(from)) throw fail(400, "Choose who you received it from");
  const expense = await Expense.findById(req.params.expenseId).select("-attachment -paymentReceipt");
  if (!expense) throw fail(404, "Expense not found");
  const companyId = expense.companyId;
  const role = await requireRole(companyId, userId, ["admin", "super_admin"]);
  if (!isAdminRole(role) || String(expense.createdBy) !== String(userId)) throw fail(403, "Only the manager who posted this expense can mark it received");
  if (expense.groupId) throw fail(400, "Group expenses are settled with the group");
  if (expense.logAs === "company") throw fail(400, "Company expenses are paid by the company, so there is nothing to receive");
  const paidByMe = ["paid_by_admin", "paid_by_person"].includes(expense.lifecycle) && String(expense.paidByUserId || expense.paidByAdminId) === String(userId);
  if (!(expense.lifecycle === "approved" && expense.status === "outstanding") && !paidByMe) {
    throw fail(409, expense.lifecycle === "reimbursed" ? "This expense is already closed" : "Only an approved or self-paid expense can be marked received");
  }
  await requirePermission(companyId, userId, "reimburse");
  const value = round(expense.amount);

  let person = null;
  let lender = null;
  if (from === "borrow") {
    await requirePermission(companyId, userId, "intercompany");
    lender = await resolveSourceCompany(userId, companyId, req.body.sourceCompanyId, req.body.newCompany);
    if (String(lender._id) === String(companyId)) throw fail(400, "Choose another company");
    // any company can be picked; one I don't manage is told about it (below), as its books now show the money as lent
  } else if (from === "person") {
    if (!personId || String(personId) === String(userId)) throw fail(400, "Choose who paid you");
    if (!(await roleIn(companyId, personId))) throw fail(400, "That person is not a member of this company");
    person = await User.findById(personId).select("name");
  } else {
    const available = await getEffectiveFundBalance(companyId, fundId);
    if (available < value) throw fail(400, `Insufficient balance in the selected fund (₹${available.toFixed(2)} available)`);
  }

  // an approved claim becomes "paid by me" first, so there is a bill on my payable for this money to close
  if (expense.lifecycle === "approved" && !(await acknowledgeClaim(expense, userId, userId))) {
    throw fail(409, "This expense changed meanwhile; refresh and try again");
  }
  const me = await User.findById(userId).select("name");
  if (from === "borrow") {
    // this company owes the lender now (a loan); the lender's side is booked like any loan (its shown Cash/Bank stay as they are)
    const company = await Company.findById(companyId).select("name");
    const routeId = newRouteId();
    const loan = await CompanyLoan.create({ borrowerCompanyId: companyId, lenderCompanyId: lender._id, amount: value, source: "expense", expenseId: expense._id, createdBy: userId, method: method || "", reference: reference || "" });
    const legs = await postAll([
      [
        // a reimbursement tied to this expense, so exactly this bill closes (see payableWalk)
        { companyId, type: "reimburse", expenseId: expense._id, loanId: loan._id, routeId, memo: `${expense.description} · received from ${lender.name} (borrowed)`, method: method || "", reference: reference || "", createdBy: userId },
        [{ account: await payableAccount(companyId, userId), debit: value }, { account: await intercoAccount(companyId, lender), credit: value }],
      ],
      [
        { companyId: lender._id, type: "intercompany", loanId: loan._id, routeId, memo: `Paid ${me?.name || "a manager"} for ${company.name}: ${expense.description}`, method: method || "", reference: reference || "", createdBy: userId },
        [{ account: await intercoAccount(lender._id, company), debit: value }, { account: await fundAccount(lender._id, lender.external ? "cash" : req.body.sourceFundId || "cash"), credit: value }],
      ],
    ]);
    loan.transactionIds = legs.map((t) => t._id);
    await loan.save();
    await recomputeReimbursed(companyId, userId);
    await audit(userId, companyId, "expense_received", "expense", expense._id, null, { amount: value, from, lenderCompanyId: lender._id, loanId: loan._id, transactionId: legs[0]._id });
    await audit(userId, lender._id, "loan_received", "loan", loan._id, null, { borrowerCompanyId: companyId, amount: value });
    if (!lender.external && !isAdminRole(await roleIn(lender._id, userId))) {
      await notifyCompanyAdmins(lender._id, {
        title: "Money lent recorded",
        body: `${me?.name || "A manager"} of ${company.name} recorded that ${lender.name} paid them ₹${value} for ${expense.description}. It shows as lent to ${company.name}.`,
        data: { companyId: String(lender._id), loanId: String(loan._id) },
      }, userId);
    }
    const updated = await Expense.findById(expense._id).select("-attachment -paymentReceipt");
    return res.json({ success: true, expense: updated, transaction: legs[0], loan });
  }
  const fund = from === "company" ? await fundAccount(companyId, fundId) : null;
  const tx = await post(
    {
      companyId,
      type: "reimburse",
      expenseId: expense._id, // ties the payment to this bill (see payableWalk)
      memo: from === "person" ? `${expense.description} · received from ${person?.name || "member"} personally` : `${expense.description} · received from company`,
      method: method || "",
      reference: reference || "",
      createdBy: userId,
      verification: from === "company" && (await needsVerification(companyId, value)) ? "pending" : null,
    },
    [
      { account: await payableAccount(companyId, userId), debit: value },
      from === "person" ? { account: await payableAccount(companyId, personId), credit: value } : { account: fund, credit: value },
    ]
  );
  if (from === "company") await applyCompanyFund(companyId, fundId, -value);
  await recomputeReimbursed(companyId, userId);
  await audit(userId, companyId, "expense_received", "expense", expense._id, null, {
    amount: value, from, fundId: from === "company" ? fundId || "cash" : null, personId: person ? personId : null, transactionId: tx._id,
  });
  if (person) {
    notifyUsers([personId], { title: "Company owes you", body: `${me?.name || "A manager"} recorded you paid them ₹${value} for ${expense.description}`, data: { expenseId: expense._id, companyId } });
  }
  if (tx.verification === "pending") {
    await notifyCompanyAdmins(companyId, { title: "Payment needs verification", body: `${me?.name || "A manager"} received ₹${value} for ${expense.description}`, data: { transactionId: tx._id, companyId } }, userId);
  }
  const updated = await Expense.findById(expense._id).select("-attachment -paymentReceipt");
  res.json({ success: true, expense: updated, transaction: tx });
});

// A manager pays off their OWN outstanding from company Cash/Bank — all of it or chosen bills (company only,
// never "by self"). items: [{ transactionId }] for recorded bills, [{ expenseId }] for approved claims.
// Each bill gets its own reimbursement tied to it, so exactly the chosen bills close.
// Or { amount }: that much is spread over the bills oldest first (by bill date); the last one may be part-paid.
// body: { userId, items | amount, fundId, method?, reference? }
exports.payOwnOutstanding = handle(async (req, res) => {
  const { companyId } = req.params;
  const { userId, items, fundId, method, reference } = req.body;
  const note = String(req.body.note || "").trim().slice(0, 200); // optional description, saved on each payment
  // optional payment date (YYYY-MM-DD, an IST day); today keeps the current time, a past day is booked at noon IST
  let paidOn = new Date();
  const istToday = new Date(Date.now() + 330 * 60000).toISOString().slice(0, 10);
  const day = String(req.body.date || "").slice(0, 10);
  if (day && day !== istToday) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(day) || isNaN(new Date(day).getTime())) throw fail(400, "Enter a valid payment date");
    if (day > istToday) throw fail(400, "Payment date can't be in the future");
    paidOn = new Date(`${day}T12:00:00+05:30`);
  }
  const byAmount = !(Array.isArray(items) && items.length) && req.body.amount !== undefined && req.body.amount !== null && req.body.amount !== "";
  if (!byAmount && !(Array.isArray(items) && items.length)) throw fail(400, "Choose at least one bill to pay");
  const role = await requireRole(companyId, userId, ["admin", "super_admin"]);
  if (!isAdminRole(role)) throw fail(403, "Only managers can pay their own outstanding");
  await requirePermission(companyId, userId, "reimburse");

  const open = await openPayableBills(companyId, userId);
  const claims = await pendingClaims(companyId, userId);
  const picked = [];
  if (byAmount) {
    let left = round(parseFloat(req.body.amount));
    if (!(left > 0)) throw fail(400, "Enter a valid amount");
    const all = [
      ...open.map((bill) => ({ kind: "bill", bill, amount: round(bill.remaining), label: bill.description, date: bill.date || bill.postedAt })),
      ...claims.map((claim) => ({ kind: "claim", claim, amount: round(claim.amount), label: claim.description, date: claim.date || claim.createdAt })),
    ].sort((a, b) => new Date(a.date) - new Date(b.date));
    const owed = round(all.reduce((s, x) => s + x.amount, 0));
    if (left > owed + 0.001) throw fail(400, `You are owed only ₹${owed}`);
    for (const x of all) {
      if (!(left > 0)) break;
      const take = round(Math.min(left, x.amount));
      picked.push({ ...x, amount: take, partial: take < x.amount });
      left = round(left - take);
    }
  }
  for (const item of byAmount ? [] : items) {
    if (item?.transactionId) {
      const bill = open.find((b) => String(b.transactionId) === String(item.transactionId));
      if (!bill) throw fail(409, "One of the bills is already paid or changed; refresh and try again");
      picked.push({ kind: "bill", bill, amount: bill.remaining, label: bill.description });
    } else if (item?.expenseId) {
      const claim = claims.find((c) => String(c._id) === String(item.expenseId));
      if (!claim) throw fail(409, "One of the expenses is already paid or changed; refresh and try again");
      picked.push({ kind: "claim", claim, amount: round(claim.amount), label: claim.description });
    }
  }
  if (!picked.length) throw fail(400, "Choose at least one bill to pay");
  const total = round(picked.reduce((s, p) => s + p.amount, 0));
  const available = await getEffectiveFundBalance(companyId, fundId);
  if (available < total) throw fail(400, `Insufficient balance in the selected fund (₹${available.toFixed(2)} available, ₹${total.toFixed(2)} needed)`);

  const fund = await fundAccount(companyId, fundId);
  const me = await User.findById(userId).select("name");
  const verify = await needsVerification(companyId, total);
  const txs = [];
  let paid = 0;
  for (const p of picked) {
    let creditTxId;
    if (p.kind === "claim") {
      // an approved claim becomes a bill on my payable first, then the payment closes it
      if (!(await acknowledgeClaim(p.claim, userId, userId))) continue;
      creditTxId = (await Expense.findById(p.claim._id).select("transactionId"))?.transactionId;
    } else {
      creditTxId = p.bill.transactionId;
    }
    const tx = await post(
      {
        companyId,
        type: "reimburse",
        settlesTransactionId: creditTxId,
        expenseId: p.kind === "claim" ? p.claim._id : p.bill.expenseId || null,
        memo: `${note ? `${note} · ` : ""}${p.label} · ${me?.name || "manager"}'s own outstanding paid by company${p.partial ? " (part)" : ""}`,
        note,
        date: paidOn,
        method: method || "",
        reference: reference || "",
        createdBy: userId,
        verification: verify ? "pending" : null,
      },
      [
        { account: await payableAccount(companyId, userId), debit: p.amount },
        { account: fund, credit: p.amount },
      ]
    );
    await applyCompanyFund(companyId, fundId, -p.amount);
    txs.push(tx);
    paid = round(paid + p.amount);
  }
  await recomputeReimbursed(companyId, userId);
  await audit(userId, companyId, "pay_own_outstanding", "transaction", txs[0]?._id || null, null, {
    amount: paid, bills: txs.length, fundId: fundId || "cash", note, transactions: txs.map((t) => t._id),
  });
  if (verify && txs.length) {
    await notifyCompanyAdmins(companyId, { title: "Payment needs verification", body: `${me?.name || "A manager"} paid their own outstanding · ₹${paid}`, data: { transactionId: txs[0]._id, companyId } }, userId);
  }
  res.json({ success: true, paid, bills: txs.length, closed: picked.filter((x) => !x.partial).length, owed: round((await adminOwed(companyId, userId)) + (await pendingClaims(companyId, userId)).reduce((s, c) => s + c.amount, 0)) });
});

exports.lend = handle(async (req, res) => {
  const { companyId, userId, amount, fundId, method, reference } = req.body;
  const value = round(parseFloat(amount));
  if (!(value > 0)) throw fail(400, "Enter a valid amount");
  await requireRole(companyId, userId, ["admin", "super_admin"]);
  await requirePermission(companyId, userId, "reimburse");
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
  const reverser = await requireRole(original.companyId, userId, ["admin", "super_admin"]);
  if (reverser !== "super_admin") {
    const mine = await permissionsFor(original.companyId, userId);
    if (!(mine.role === "custom" && mine.perms.reverse_transactions)) throw fail(403, "You do not have permission for this action");
  }
  if (original.reversedBy) throw fail(400, "This transaction has already been reversed");
  if (original.type === "reversal") throw fail(400, "A reversal cannot be reversed");

  // a voucher can't lose its funding while its claim still stands
  if (original.type === "voucher_issue" && original.voucherId) {
    const voucher = await Voucher.findById(original.voucherId).select("status");
    if (voucher && voucher.status !== "open") throw fail(400, "Reverse the voucher claim first");
  }

  // linked legs (same routeId) are reversed together so both companies stay in step
  const legs = original.routeId ? await LedgerTransaction.find({ routeId: original.routeId, reversedBy: null }) : [original];
  const reversals = [];
  const touched = [];
  for (const leg of legs) {
    const { reversal, accounts } = await postReversal(leg, userId);
    reversals.push(reversal);
    touched.push(...accounts.filter((a) => a.type === "admin_payable"));
  }

  if (original.expenseId && ["admin_paid", "company_paid", "borrowed", "intercompany", "advance_used"].includes(original.type)) {
    await Expense.updateOne(
      { _id: original.expenseId },
      { $set: { lifecycle: "approved", paidByAdminId: null, paidByUserId: null, payerType: "unpaid", transactionId: null, status: "outstanding", verification: null, advanceUsed: 0 } }
    );
  }
  await undoVoucherRecords(original, userId);
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
    .map((a) => ({ userId: a.userId?._id, name: a.userId?.name || a.name, owed: round(get(a).credit - get(a).debit), claims: 0 }));

  // Approved-but-unpaid expenses are owed to whoever posted them, so they count towards what each person is owed.
  const claimRows = await Expense.find({ companyId, lifecycle: "approved", status: "outstanding", groupId: null }).select("createdBy amount");
  const claimByUser = new Map();
  for (const e of claimRows) claimByUser.set(String(e.createdBy), round((claimByUser.get(String(e.createdBy)) || 0) + e.amount));
  const missing = [...claimByUser.keys()].filter((id) => !admins.some((a) => String(a.userId) === id));
  const missingUsers = await User.find({ _id: { $in: missing } }).select("name");
  for (const u of missingUsers) admins.push({ userId: u._id, name: u.name, owed: 0, claims: 0 });
  for (const a of admins) {
    a.claims = claimByUser.get(String(a.userId)) || 0;
    a.owed = round(a.owed + a.claims);
  }
  const myOwed = admins.find((a) => a.userId && a.userId.toString() === userId.toString())?.owed || 0;
  const advances = await advanceHeldByPerson(companyId);
  for (const a of admins) a.advance = advances.get(String(a.userId)) || 0;
  const myAdvance = advances.get(String(userId)) || 0;

  if (!isAdminRole(role)) return res.json({ success: true, role, myOwed, myAdvance });

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
    myAdvance,
    totalAdvanceHeld: round([...advances.values()].reduce((s, v) => s + Math.max(0, v), 0)),
    totalOwedToAdmins: round(admins.reduce((s, a) => s + a.owed, 0)),
    admins,
    funds,
  });
});

exports.listTransactions = handle(async (req, res) => {
  const { companyId } = req.params;
  const { userId } = req.query;
  await requireRole(companyId, userId, ["admin", "super_admin"]);
  await requirePermission(companyId, userId, "ledger_audit");
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
  await requirePermission(companyId, userId, "ledger_audit");
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

// One loan in full: the bill (or group) it paid, who started the payment, who confirmed it, and every repayment.
exports.loanDetail = handle(async (req, res) => {
  const { userId, receipts } = req.query;
  const loan = await CompanyLoan.findById(req.params.loanId)
    .populate("borrowerCompanyId", "name external").populate("lenderCompanyId", "name external").populate("createdBy", "name");
  if (!loan) throw fail(404, "Loan not found");
  const roles = await Promise.all([roleIn(loan.borrowerCompanyId?._id, userId), roleIn(loan.lenderCompanyId?._id, userId)]);
  if (!roles.some(Boolean)) throw fail(403, "You are not a member of either company");

  // receipt images are large, so the popup asks for them separately after the details are on screen
  if (receipts === "1") {
    const expense = loan.expenseId ? await Expense.findById(loan.expenseId).select("attachment paymentReceipt").lean() : null;
    return res.json({ success: true, attachment: expense?.attachment || "", paymentReceipt: expense?.paymentReceipt || "" });
  }

  const borrowerId = loan.borrowerCompanyId?._id;
  // every lookup below is independent, so they run together (one round trip to the database instead of a dozen)
  const [expense, audits, g, repaymentTxs, issueAlive, lenderMarks] = await Promise.all([
    loan.expenseId ? Expense.findById(loan.expenseId).select("-attachment -paymentReceipt").populate("createdBy", "name").populate("approvedBy", "name").lean() : null,
    loan.expenseId
      ? AuditLog.find({ objectId: loan.expenseId, action: { $in: ["request_payer_confirmation", "accept_payer"] } }).select("action userId at").sort({ at: -1 }).populate("userId", "name").lean()
      : [],
    loan.groupId ? ExpenseGroup.findById(loan.groupId).select("name createdBy settledAt settledAmount").populate("createdBy", "name").lean() : null,
    LedgerTransaction.find({ loanId: loan._id, companyId: borrowerId, type: "loan_repayment" }).populate("createdBy", "name").sort({ createdAt: 1 }).lean(),
    LedgerTransaction.exists({ _id: { $in: loan.transactionIds }, reversedBy: null, type: { $ne: "reversal" } }),
    AuditLog.find({ objectId: loan._id, action: "repay_marked_by_lender" }).select("after").lean(),
  ]);
  // repayments the lender marked as received (rather than the borrower paying them)
  const markedByLender = new Set(lenderMarks.flatMap((a) => (a.after?.transactions || []).map(String)));

  let initiatedBy = loan.createdBy ? { _id: loan.createdBy._id, name: loan.createdBy.name } : null;
  let confirmedBy = null;
  let bill = null;
  if (expense) {
    bill = {
      _id: expense._id,
      description: expense.description,
      category: expense.category,
      amount: expense.amount,
      date: expense.date || expense.createdAt,
      postedBy: expense.createdBy?.name || "",
      approvedBy: expense.approvedBy?.name || "",
      method: expense.payerMethod || loan.method || "",
      reference: expense.payerReference || loan.reference || "",
      hasAttachment: Boolean(expense.hasAttachment),
      hasPaymentReceipt: Boolean(expense.hasPaymentReceipt),
    };
    // a payment that waited for the lender's confirmation: the requester started it, a lender admin confirmed it
    const request = audits.find((a) => a.action === "request_payer_confirmation");
    const accepted = audits.find((a) => a.action === "accept_payer");
    if (request?.userId) initiatedBy = { _id: request.userId._id, name: request.userId.name };
    if (accepted?.userId) confirmedBy = { _id: accepted.userId._id, name: accepted.userId.name };
  }
  const group = g ? { _id: g._id, name: g.name, createdBy: g.createdBy?.name || "", settledAt: g.settledAt, amount: g.settledAmount } : null;

  const entries = repaymentTxs.length ? await LedgerEntry.find({ transactionId: { $in: repaymentTxs.map((t) => t._id) } }).select("transactionId debit").lean() : [];
  const repayments = repaymentTxs.map((t) => ({
    _id: t._id,
    amount: round(entries.filter((e) => String(e.transactionId) === String(t._id)).reduce((s, e) => s + e.debit, 0)),
    date: t.createdAt,
    by: t.createdBy?.name || "",
    method: t.method,
    reference: t.reference,
    reversed: Boolean(t.reversedBy),
    byLender: markedByLender.has(String(t._id)),
  }));
  // same rule as loanBalance(), from the rows already loaded
  const repaid = repayments.filter((r) => !r.reversed).reduce((s, r) => s + r.amount, 0);
  const balance = issueAlive ? round(Math.max(0, loan.amount - repaid)) : 0;

  res.json({ success: true, loan: loanView(loan, balance), bill, group, initiatedBy, confirmedBy, repayments });
});

exports.createLoan = handle(async (req, res) => {
  const { userId, borrowerCompanyId, lenderCompanyId, amount, fundId, method, reference, note } = req.body;
  const value = round(parseFloat(amount));
  if (!(value > 0) || !borrowerCompanyId || !lenderCompanyId || String(borrowerCompanyId) === String(lenderCompanyId)) throw fail(400, "Choose two companies and a valid amount");
  await requireRole(borrowerCompanyId, userId, ["admin", "super_admin"]);
  await requirePermission(borrowerCompanyId, userId, "intercompany");
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
  // borrowed money lands in the borrower's chosen fund; the lender's Cash/Bank is left as is
  await applyIfTracked(borrower, fundId, value);
  await audit(userId, borrower._id, "borrow", "loan", loan._id, null, { lenderCompanyId, amount: value });
  await audit(userId, lender._id, "loan_received", "loan", loan._id, null, { borrowerCompanyId, amount: value });
  await notifyCompanyAdmins(borrower._id, { title: "Company loan recorded", body: `Borrowed ₹${value} from ${lender.name}`, data: { loanId: loan._id, companyId: borrower._id } }, userId);
  await notifyCompanyAdmins(lender._id, { title: "Company loan recorded", body: `${borrower.name} recorded a loan from ${lender.name} · ₹${value}`, data: { loanId: loan._id, companyId: lender._id } }, userId);
  res.status(201).json({ success: true, loan: loanView(loan, value) });
});

// Posts one repayment on both companies' books (borrower: Cash/Bank out; lender: what they're owed goes down).
// Used by the borrower's "Repay" and by the lender's "Received". `fundId` is always the BORROWER's Cash/Bank.
async function recordLoanRepayment(loan, userId, { value, fundId, method, reference, note, lenderFundId }, byLender) {
  const locked = await CompanyLoan.findOneAndUpdate({ _id: loan._id, repaymentLock: false }, { $set: { repaymentLock: true } }, { returnDocument: "after" });
  if (!locked) throw fail(409, "A repayment is already being recorded");
  try {
    let shortBy = 0;
    const balance = await loanBalance(loan);
    if (!(value > 0) || value > balance) throw fail(400, `${byLender ? "Received amount" : "Repayment"} must be positive and no more than the outstanding balance (₹${balance})`);
    const [borrower, lender, actor] = await Promise.all([Company.findById(loan.borrowerCompanyId), Company.findById(loan.lenderCompanyId), User.findById(userId).select("name")]);
    if (!borrower.external) {
      if (fundId && fundId !== "cash" && !(borrower.bankAccounts || []).some((b) => String(b._id) === String(fundId))) throw fail(400, `Choose one of ${borrower.name}'s accounts`);
      // the borrower paying out of their own books must have the money; the lender only confirms money that
      // already arrived, so the borrower's recorded balance doesn't block it (the account may dip below zero)
      const available = await getEffectiveFundBalance(borrower._id, fundId);
      shortBy = round(Math.max(0, value - available));
      if (!byLender && shortBy > 0) throw fail(400, `Insufficient balance in the selected fund (₹${available.toFixed(2)} available)`);
    }
    const who = actor?.name || "a manager";
    const routeId = newRouteId();
    const txs = await postAll([
      [{ companyId: borrower._id, type: "loan_repayment", loanId: loan._id, routeId, memo: note || (byLender ? `Repayment to ${lender.name} (marked received by ${who})` : `Repayment to ${lender.name}`), method: method || "", reference: reference || "", createdBy: userId }, [{ account: await intercoAccount(borrower._id, lender), debit: value }, { account: await fundAccount(borrower._id, borrower.external ? "cash" : fundId), credit: value }]],
      [{ companyId: lender._id, type: "loan_repayment", loanId: loan._id, routeId, memo: note || (byLender ? `Received from ${borrower.name}` : `Repayment from ${borrower.name}`), method: method || "", reference: reference || "", createdBy: userId }, [{ account: await fundAccount(lender._id, lender.external ? "cash" : (lenderFundId || "cash")), debit: value }, { account: await intercoAccount(lender._id, borrower), credit: value }]],
    ]);
    await applyIfTracked(borrower, fundId, -value);
    const ids = { amount: value, transactions: txs.map((t) => t._id) };
    await audit(userId, borrower._id, byLender ? "repay_marked_by_lender" : "repay", "loan", loan._id, { balance }, ids);
    await audit(userId, lender._id, byLender ? "loan_repayment_received" : "loan_repaid", "loan", loan._id, { balance }, ids);
    if (byLender) {
      await notifyCompanyAdmins(borrower._id, { title: "Loan repayment marked received", body: `${lender.name} marked ₹${value} as received · ${borrower.name}${shortBy > 0 ? ` · the account it came from is now ₹${shortBy} below zero, please check` : ""}`, data: { loanId: loan._id, companyId: borrower._id } }, userId);
      await notifyCompanyAdmins(lender._id, { title: "Company loan repayment received", body: `${who} marked ₹${value} received from ${borrower.name}`, data: { loanId: loan._id, companyId: lender._id } }, userId);
    } else {
      await notifyCompanyAdmins(borrower._id, { title: "Company loan repayment recorded", body: `Repaid ₹${value} to ${lender.name}`, data: { loanId: loan._id, companyId: borrower._id } }, userId);
      await notifyCompanyAdmins(lender._id, { title: "Company loan repaid", body: `${borrower.name} repaid ₹${value} · ${lender.name}`, data: { loanId: loan._id, companyId: lender._id } }, userId);
    }
    return { loan: loanView(loan, await loanBalance(loan)), transactions: txs, borrowerShort: shortBy };
  } finally {
    await CompanyLoan.updateOne({ _id: loan._id }, { $set: { repaymentLock: false } });
  }
}

exports.repayLoan = handle(async (req, res) => {
  const { userId, amount, fundId, method, reference, note, lenderFundId } = req.body;
  const loan = await CompanyLoan.findById(req.params.loanId);
  if (!loan) throw fail(404, "Loan not found");
  await requireRole(loan.borrowerCompanyId, userId, ["admin", "super_admin"]);
  await requirePermission(loan.borrowerCompanyId, userId, "intercompany");
  const result = await recordLoanRepayment(loan, userId, { value: round(parseFloat(amount)), fundId, method, reference, note, lenderFundId }, false);
  res.json({ success: true, ...result });
});

// The LENDER's managers mark money as received; they pick which of the borrower's Cash/Bank it came out of.
exports.receiveLoan = handle(async (req, res) => {
  const { userId, amount, borrowerFundId, method, reference, note } = req.body;
  const loan = await CompanyLoan.findById(req.params.loanId);
  if (!loan) throw fail(404, "Loan not found");
  await requireRole(loan.lenderCompanyId, userId, ["admin", "super_admin"]);
  await requirePermission(loan.lenderCompanyId, userId, "intercompany");
  const result = await recordLoanRepayment(loan, userId, { value: round(parseFloat(amount)), fundId: borrowerFundId || "cash", method, reference, note }, true);
  res.json({ success: true, ...result });
});

// Names of the borrower's Cash/Bank accounts, for the lender's "Received" form (no balances: they're the other company's).
exports.loanBorrowerFunds = handle(async (req, res) => {
  const loan = await CompanyLoan.findById(req.params.loanId);
  if (!loan) throw fail(404, "Loan not found");
  await requireRole(loan.lenderCompanyId, req.query.userId, ["admin", "super_admin"]);
  await requirePermission(loan.lenderCompanyId, req.query.userId, "intercompany");
  const borrower = await Company.findById(loan.borrowerCompanyId).select("name external cashAccountName bankAccounts");
  const funds = borrower.external
    ? []
    : [
        { fundId: "cash", name: borrower.cashAccountName || "InCash" },
        ...(borrower.bankAccounts || []).map((b) => ({ fundId: String(b._id), name: `${b.bankName}${b.accountNumber ? ` ••${String(b.accountNumber).slice(-4)}` : ""}` })),
      ];
  res.json({ success: true, borrower: { _id: borrower._id, name: borrower.name }, funds });
});

// The person who recorded a borrow can delete it: every leg is reversed in BOTH companies (the lender's
// "lent" side included), the borrower's Cash/Bank is put back, and a bill or group it paid is reopened.
// Not allowed once repayments exist, so real repayments are never silently undone.
exports.deleteLoan = handle(async (req, res) => {
  const { userId } = req.body;
  const loan = await CompanyLoan.findById(req.params.loanId);
  if (!loan) throw fail(404, "Loan not found");
  if (!loan.createdBy || String(loan.createdBy) !== String(userId)) throw fail(403, "Only the person who recorded this borrow can delete it");
  await requirePermission(loan.borrowerCompanyId, userId, "intercompany");
  const repaid = await LedgerTransaction.exists({ loanId: loan._id, type: "loan_repayment", reversedBy: null });
  if (repaid) throw fail(400, "This loan already has repayments, so it can't be deleted");

  // same lock as repayments, so a repayment and a delete can't run together
  const locked = await CompanyLoan.findOneAndUpdate({ _id: loan._id, repaymentLock: false }, { $set: { repaymentLock: true } }, { returnDocument: "after" });
  if (!locked) throw fail(409, "This loan is being updated; try again in a moment");

  const [borrower, lender] = await Promise.all([Company.findById(loan.borrowerCompanyId).select("name"), Company.findById(loan.lenderCompanyId).select("name")]);
  const label = `${lender?.name || "lender"} → ${borrower?.name || "borrower"} ₹${loan.amount}`;
  try {
    // the loan's own legs plus anything sharing their route (both companies' books)
    const own = await LedgerTransaction.find({ _id: { $in: loan.transactionIds }, reversedBy: null, type: { $ne: "reversal" } });
    const routeIds = [...new Set(own.map((t) => t.routeId).filter(Boolean))];
    const legs = routeIds.length
      ? await LedgerTransaction.find({ $or: [{ _id: { $in: own.map((t) => t._id) } }, { routeId: { $in: routeIds } }], reversedBy: null, type: { $ne: "reversal" } })
      : own;
    const payables = [];
    for (const leg of legs) {
      const { accounts } = await postReversal(leg, userId, `Loan deleted: ${label}`);
      payables.push(...accounts.filter((a) => a.type === "admin_payable"));
    }
    for (const a of payables) await recomputeReimbursed(a.companyId, a.userId);

    if (loan.expenseId) {
      await Expense.updateOne(
        { _id: loan.expenseId },
        { $set: { lifecycle: "approved", status: "outstanding", payerType: "unpaid", payerCompanyId: null, payerConfirmation: null, paidByAdminId: null, paidByUserId: null, transactionId: null, verification: null } }
      );
    }
    if (loan.groupId) {
      await ExpenseGroup.updateOne(
        { _id: loan.groupId },
        { $set: { settlementStatus: "active", settlementType: null, settlementCompanyId: null, settlementLoanId: null, settledAmount: null, settledBy: null, settledAt: null, settlementLock: false } }
      );
    }
    await CompanyLoan.deleteOne({ _id: loan._id });
  } catch (e) {
    await CompanyLoan.updateOne({ _id: loan._id }, { $set: { repaymentLock: false } });
    throw e;
  }

  const snapshotOfLoan = { amount: loan.amount, source: loan.source, note: loan.note, borrowerCompanyId: loan.borrowerCompanyId, lenderCompanyId: loan.lenderCompanyId, expenseId: loan.expenseId, groupId: loan.groupId };
  await audit(userId, loan.borrowerCompanyId, "delete", "loan", loan._id, snapshotOfLoan, null);
  await audit(userId, loan.lenderCompanyId, "delete", "loan", loan._id, snapshotOfLoan, null);
  for (const co of [loan.borrowerCompanyId, loan.lenderCompanyId]) {
    await notifyCompanyAdmins(co, {
      title: "Company loan deleted",
      body: `${label} was deleted and reversed in both companies`,
      data: { companyId: co },
    }, userId);
  }
  res.json({ success: true });
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
    // one copy per company, each tagged with its own company so a tap opens the right one
    for (const co of [borrower, lender]) {
      await notifyCompanyAdmins(co._id, {
        title: "Group settlement recorded",
        body: `${borrower.name} owes ${lender.name} ₹${total} for ${group.name}`,
        data: { groupId: group._id, loanId: loan._id, companyId: co._id },
      }, userId);
    }
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
  await requirePermission(expense.payerCompanyId, userId, "intercompany");
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
  await requirePermission(tx.companyId, userId, "verify");
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
  for (const co of [from, to]) {
    await notifyCompanyAdmins(co._id, { title: "Inter-company payment", body: `${from.name} → ${to.name} · ₹${value}`, data: { transactionId: txs[0]._id, companyId: co._id } }, userId);
  }
  res.json({ success: true, transactions: txs });
});

// B → A → admin: settles the admin's open balance in A with money from B. Never B → admin directly.
exports.routedPayment = handle(async (req, res) => {
  const { userId, companyId, adminUserId, amount, sourceCompanyId, newCompany, sourceFundId, method, reference } = req.body;
  const value = round(parseFloat(amount));
  if (!(value > 0)) throw fail(400, "Enter a valid amount");
  if (!companyId || !adminUserId) throw fail(400, "A routed payment must name the company and the admin");
  const role = await requireRole(companyId, userId, ["admin", "super_admin"]);
  await requirePermission(companyId, userId, "intercompany");
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
  for (const co of [companyId, source._id]) {
    await notifyCompanyAdmins(co, { title: "Borrowed from another company", body: `${source.name} → ${company.name} → admin · ₹${value}`, data: { transactionId: txs[0]._id, companyId: co } }, userId);
  }
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
  await requirePermission(companyId, userId, "settings");
  const company = await Company.findById(companyId);
  const before = { gstin: company.gstin, currency: company.currency, verificationThreshold: company.verificationThreshold, cashAccountName: company.cashAccountName };
  if (gstin !== undefined) company.gstin = String(gstin).trim().toUpperCase();
  if (currency !== undefined) company.currency = String(currency).trim().toUpperCase() || "INR";
  if (req.body.cashAccountName !== undefined) company.cashAccountName = String(req.body.cashAccountName).trim() || "InCash";
  if (verificationThreshold !== undefined) {
    const t = verificationThreshold === null || verificationThreshold === "" ? null : parseFloat(verificationThreshold);
    if (t !== null && !(t >= 0)) throw fail(400, "Threshold must be a positive amount");
    company.verificationThreshold = t;
  }
  await company.save();
  const after = { gstin: company.gstin, currency: company.currency, verificationThreshold: company.verificationThreshold, cashAccountName: company.cashAccountName };
  await audit(userId, companyId, "update", "company", company._id, before, after);
  res.json({ success: true, company: after });
});

// Company logo, shown on the company tiles. Only the primary admin (creator / full Admin) may set or remove it.
const LOGO_MAX_CHARS = 400 * 1024; // the clients send ~256px images, far below this
exports.setCompanyLogo = handle(async (req, res) => {
  const { companyId } = req.params;
  const { userId } = req.body;
  const logo = String(req.body.logo || "");
  await requireRole(companyId, userId, ["admin", "super_admin"]);
  if ((await permissionsFor(companyId, userId)).role !== "primary") throw fail(403, "Only the company Admin can change the logo");
  if (logo && !/^data:image\/(png|jpe?g|webp);base64,[A-Za-z0-9+/=]+$/.test(logo)) throw fail(400, "Logo must be a PNG, JPG or WebP image");
  if (logo.length > LOGO_MAX_CHARS) throw fail(400, "Logo image is too large");
  const company = await Company.findById(companyId).select("logo");
  if (!company) throw fail(404, "Company not found");
  const had = Boolean(company.logo);
  company.logo = logo;
  await company.save();
  await audit(userId, companyId, "update", "company", company._id, { logo: had ? "[image]" : "" }, { logo: logo ? "[image]" : "" });
  res.json({ success: true, logo });
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
  const expQuery = { companyId, lifecycle: { $in: ["paid_by_admin", "paid_by_person", "paid_by_company", "reimbursed", "paid_by_voucher"] } };
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
    paidByAdmins: sum(expenses.filter((e) => e.lifecycle !== "paid_by_company" && e.lifecycle !== "paid_by_voucher")),
    owedToAdmins: round(owed),
    intercompanyNet: round(interco),
  };
}

exports.report = handle(async (req, res) => {
  const { companyId } = req.params;
  const { userId, from, to, category } = req.query;
  await requireRole(companyId, userId, ["admin", "super_admin"]);
  await requirePermission(companyId, userId, "reports");
  res.json({ success: true, report: await companyReport(companyId, from, to, category) });
});

// ---------- Categories (managers) ----------
const categoryState = (company) => ({ customCategories: company.customCategories || [], hiddenCategories: company.hiddenCategories || [] });
const sameName = (a, b) => String(a).trim().toLowerCase() === String(b).trim().toLowerCase();

exports.addCategory = handle(async (req, res) => {
  const { companyId } = req.params;
  const { userId } = req.body;
  const name = String(req.body.name || "").trim();
  if (!name) throw fail(400, "Category name is required");
  if (name.length > 40) throw fail(400, "Keep the category name under 40 characters");
  await requireRole(companyId, userId, ["admin", "super_admin"]);
  await requirePermission(companyId, userId, "settings");
  const company = await Company.findById(companyId).select("customCategories hiddenCategories");
  if (!company) throw fail(404, "Company not found");
  const hidden = (company.hiddenCategories || []).find((c) => sameName(c, name));
  if (hidden) {
    // re-adding a removed built-in category brings it back
    company.hiddenCategories = company.hiddenCategories.filter((c) => !sameName(c, name));
  } else if (!(company.customCategories || []).some((c) => sameName(c, name))) {
    company.customCategories.push(name);
  }
  await company.save();
  await audit(userId, companyId, "add_category", "company", company._id, null, { name });
  res.json({ success: true, ...categoryState(company) });
});

exports.deleteCategory = handle(async (req, res) => {
  const { companyId } = req.params;
  const { userId } = req.body;
  const name = String(req.body.name || "").trim();
  if (!name) throw fail(400, "Category name is required");
  await requireRole(companyId, userId, ["admin", "super_admin"]);
  await requirePermission(companyId, userId, "settings");
  const company = await Company.findById(companyId).select("customCategories hiddenCategories");
  if (!company) throw fail(404, "Company not found");
  const isCustom = (company.customCategories || []).some((c) => sameName(c, name));
  if (isCustom) company.customCategories = company.customCategories.filter((c) => !sameName(c, name));
  // built-in names (not stored per company) are hidden instead
  else if (!(company.hiddenCategories || []).some((c) => sameName(c, name))) company.hiddenCategories.push(name);
  await company.save();
  const inUse = await Expense.countDocuments({ companyId, category: name });
  await audit(userId, companyId, "delete_category", "company", company._id, { name }, null);
  res.json({ success: true, inUse, ...categoryState(company) });
});

// Spending patterns over the last N months (managers only). Months/weekdays are in IST.
exports.expenseAnalysis = handle(async (req, res) => {
  const { companyId } = req.params;
  const { userId } = req.query;
  await requireRole(companyId, userId, ["admin", "super_admin"]);
  await requirePermission(companyId, userId, "analysis");
  const months = Math.min(24, Math.max(3, parseInt(req.query.months, 10) || 12));
  const IST = 5.5 * 60 * 60 * 1000;
  const ist = (d) => new Date(new Date(d).getTime() + IST);
  const monthKey = (d) => { const x = ist(d); return `${x.getUTCFullYear()}-${String(x.getUTCMonth() + 1).padStart(2, "0")}`; };

  const nowIst = ist(new Date());
  const keys = [];
  for (let i = months - 1; i >= 0; i -= 1) {
    const d = new Date(Date.UTC(nowIst.getUTCFullYear(), nowIst.getUTCMonth() - i, 1));
    keys.push(`${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, "0")}`);
  }
  const start = new Date(Date.UTC(Number(keys[0].slice(0, 4)), Number(keys[0].slice(5)) - 1, 1) - IST);

  const company = await Company.findById(companyId).select("name");
  const expenses = await Expense.find({ companyId, groupId: null, lifecycle: { $nin: [null, "rejected"] }, date: { $gte: start } })
    .select("description category amount date createdAt createdBy logAs lifecycle")
    .populate("createdBy", "name")
    .lean();

  const monthly = new Map(keys.map((k) => [k, { month: k, total: 0, count: 0 }]));
  const byCategory = new Map();
  const byPerson = new Map();
  const weekday = Array.from({ length: 7 }, (_, day) => ({ day, total: 0, count: 0 }));
  const descMonths = new Map();
  for (const e of expenses) {
    const when = e.date || e.createdAt;
    const m = monthly.get(monthKey(when));
    if (m) { m.total = round(m.total + e.amount); m.count += 1; }
    const cat = e.category || "General";
    const c = byCategory.get(cat) || { category: cat, total: 0, count: 0 };
    c.total = round(c.total + e.amount); c.count += 1; byCategory.set(cat, c);
    const isCompany = e.logAs === "company";
    const pKey = isCompany ? "company" : String(e.createdBy?._id || e.createdBy);
    const p = byPerson.get(pKey) || { key: pKey, name: isCompany ? company?.name || "Company" : e.createdBy?.name || "Former member", total: 0, count: 0 };
    p.total = round(p.total + e.amount); p.count += 1; byPerson.set(pKey, p);
    const w = weekday[ist(when).getUTCDay()];
    w.total = round(w.total + e.amount); w.count += 1;
    const norm = String(e.description || "").trim().toLowerCase().replace(/\s+/g, " ");
    if (norm) {
      const r = descMonths.get(norm) || { description: e.description.trim(), months: new Set(), total: 0, count: 0, last: when };
      r.months.add(monthKey(when)); r.total = round(r.total + e.amount); r.count += 1;
      if (new Date(when) > new Date(r.last)) r.last = when;
      descMonths.set(norm, r);
    }
  }

  const categories = [...byCategory.values()].map((c) => ({ ...c, avg: round(c.total / c.count) })).sort((a, b) => b.total - a.total);
  const avgByCat = new Map(categories.map((c) => [c.category, c]));
  // unusual: at least double the category's average, in categories with enough history to compare
  const unusual = expenses
    .map((e) => {
      const c = avgByCat.get(e.category || "General");
      return { _id: e._id, description: e.description, category: e.category || "General", amount: e.amount, date: e.date || e.createdAt, by: e.logAs === "company" ? company?.name : e.createdBy?.name, categoryAvg: c.avg, ratio: round(e.amount / c.avg), sample: c.count };
    })
    .filter((x) => x.sample >= 3 && x.ratio >= 2)
    .sort((a, b) => b.ratio - a.ratio)
    .slice(0, 10);
  const recurring = [...descMonths.values()]
    .filter((r) => r.months.size >= 3)
    .map((r) => ({ description: r.description, months: r.months.size, count: r.count, avgAmount: round(r.total / r.count), total: r.total, lastDate: r.last }))
    .sort((a, b) => b.total - a.total)
    .slice(0, 10);

  const monthlyList = [...monthly.values()];
  const thisMonth = monthlyList[monthlyList.length - 1];
  const lastMonth = monthlyList[monthlyList.length - 2];
  const total = round(expenses.reduce((s, e) => s + e.amount, 0));
  const largest = expenses.reduce((best, e) => (!best || e.amount > best.amount ? e : best), null);
  res.json({
    success: true,
    months,
    summary: {
      total,
      count: expenses.length,
      average: expenses.length ? round(total / expenses.length) : 0,
      monthlyAverage: round(total / months),
      thisMonth: thisMonth.total,
      lastMonth: lastMonth.total,
      changePct: lastMonth.total > 0 ? round(((thisMonth.total - lastMonth.total) / lastMonth.total) * 100) : null,
      largest: largest ? { description: largest.description, amount: largest.amount, date: largest.date || largest.createdAt, category: largest.category } : null,
    },
    monthly: monthlyList,
    categories,
    people: [...byPerson.values()].sort((a, b) => b.total - a.total).slice(0, 10),
    weekday,
    unusual,
    recurring,
  });
});

// What is still open right now: per person (managers / staff) and per counterpart company.
exports.outstandingReport = handle(async (req, res) => {
  const { companyId } = req.params;
  const { userId } = req.query;
  await requireRole(companyId, userId, ["admin", "super_admin"]);
  await requirePermission(companyId, userId, "reports");
  const company = await Company.findById(companyId).select("createdBy");

  // people: recorded payables + approved claims (owed to them) and submitted expenses awaiting approval
  const people = new Map();
  const person = (id) => {
    const key = String(id);
    if (!people.has(key)) people.set(key, { userId: key, name: "", role: "staff", recorded: 0, claims: 0, claimCount: 0, awaitingApproval: 0, awaitingCount: 0, advanceHeld: 0 });
    return people.get(key);
  };
  const payables = await LedgerAccount.find({ companyId, type: "admin_payable" });
  for (const acc of payables) {
    const t = await accountTotals(acc._id);
    const owed = round(t.credit - t.debit);
    if (owed !== 0) person(acc.userId).recorded = owed;
  }
  const open = await Expense.find({ companyId, groupId: null, status: "outstanding", lifecycle: { $in: ["approved", "submitted"] } }).select("createdBy amount lifecycle");
  for (const e of open) {
    const p = person(e.createdBy);
    if (e.lifecycle === "approved") { p.claims = round(p.claims + e.amount); p.claimCount += 1; }
    else { p.awaitingApproval = round(p.awaitingApproval + e.amount); p.awaitingCount += 1; }
  }
  // voucher money a person is still holding for the company
  for (const [id, held] of await advanceHeldByPerson(companyId)) {
    if (held > 0) person(id).advanceHeld = held;
  }
  const ids = [...people.keys()];
  const [users, members] = await Promise.all([
    User.find({ _id: { $in: ids } }).select("name"),
    CompanyMember.find({ companyId, userId: { $in: ids } }).select("userId role"),
  ]);
  const nameById = new Map(users.map((u) => [String(u._id), u.name]));
  const roleById = new Map(members.map((m) => [String(m.userId), m.role]));
  const rows = [...people.values()].map((p) => {
    const isAdmin = roleById.get(p.userId) === "admin" || String(company?.createdBy) === p.userId;
    return { ...p, name: nameById.get(p.userId) || "Former member", role: isAdmin ? "manager" : "staff", owed: round(p.recorded + p.claims) };
  }).filter((p) => p.owed !== 0 || p.awaitingApproval !== 0 || p.advanceHeld !== 0).sort((a, b) => b.owed - a.owed);

  // companies: open loan balances, from this company's side
  const loans = await CompanyLoan.find({ $or: [{ borrowerCompanyId: companyId }, { lenderCompanyId: companyId }] })
    .populate("borrowerCompanyId", "name external").populate("lenderCompanyId", "name external");
  const byCompany = new Map();
  for (const loan of loans) {
    const balance = await loanBalance(loan);
    if (!(balance > 0)) continue;
    const weBorrowed = String(loan.borrowerCompanyId?._id) === String(companyId);
    const other = weBorrowed ? loan.lenderCompanyId : loan.borrowerCompanyId;
    if (!other) continue;
    const key = String(other._id);
    if (!byCompany.has(key)) byCompany.set(key, { companyId: key, name: other.name, external: Boolean(other.external), weOwe: 0, theyOwe: 0, loans: 0 });
    const row = byCompany.get(key);
    if (weBorrowed) row.weOwe = round(row.weOwe + balance);
    else row.theyOwe = round(row.theyOwe + balance);
    row.loans += 1;
  }
  const companies = [...byCompany.values()].map((c) => ({ ...c, net: round(c.theyOwe - c.weOwe) })).sort((a, b) => a.net - b.net);

  const sum = (list, f) => round(list.reduce((s, x) => s + x[f], 0));
  const managers = rows.filter((r) => r.role === "manager");
  const staff = rows.filter((r) => r.role === "staff");
  res.json({
    success: true,
    managers,
    staff,
    companies,
    totals: {
      owedToManagers: sum(managers, "owed"),
      owedToStaff: sum(staff, "owed"),
      awaitingApproval: sum(rows, "awaitingApproval"),
      advanceHeld: sum(rows, "advanceHeld"),
      weOweCompanies: sum(companies, "weOwe"),
      companiesOweUs: sum(companies, "theyOwe"),
    },
  });
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
  await requirePermission(companyId, userId, "reports");

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
  await requirePermission(companyId, userId, "members");
  const company = await Company.findById(companyId).select("createdBy name");
  if (company.createdBy && company.createdBy.toString() === String(memberUserId)) {
    throw fail(400, "The company creator is always an admin");
  }
  const member = await CompanyMember.findOne({ companyId, userId: memberUserId });
  if (!member) throw fail(404, "That person is not in this company");
  if (member.isAdmin) {
    if ((await permissionsFor(companyId, userId)).role !== "primary") throw fail(403, "Only an Admin can change another Admin");
    member.isAdmin = false;
  }
  if (member.customRoleId) {
    if (!hasPower(await permissionsFor(companyId, userId), "manage_roles")) throw fail(403, "Only the primary admin can change someone in a custom role");
    member.customRoleId = null;
  }
  const before = { role: member.role };
  member.role = role;
  await member.save();
  await audit(userId, companyId, "change_role", "member", member._id, before, { role, memberUserId });
  const names = await builtInRoleNames(companyId);
  notifyUsers([memberUserId], {
    title: "Your role changed",
    body: `You are now ${role === "admin" ? names.manager : names.staff} in ${company.name}`,
    data: { companyId },
  });
  res.json({ success: true });
});

// Add someone who already has an account, directly as admin or staff (no join code needed).
// Adding/inviting straight into a custom role: primary admin only; the base role follows the custom role.
async function inviteRole(companyId, userId, role, customRoleId) {
  if (!customRoleId) {
    if (!ROLES.includes(role)) throw fail(400, "Role must be admin or staff");
    const names = await builtInRoleNames(companyId);
    return { role, customRoleId: null, label: `"${role === "admin" ? names.manager : names.staff}"` };
  }
  if (!hasPower(await permissionsFor(companyId, userId), "manage_roles")) throw fail(403, "Only the primary admin can add people to a custom role");
  const company = await Company.findById(companyId).select("customRoles").lean();
  const custom = (company?.customRoles || []).find((r) => String(r._id) === String(customRoleId));
  if (!custom) throw fail(404, "That role no longer exists");
  return { role: roleBase(custom) === "manager" ? "admin" : "member", customRoleId: custom._id, label: `"${custom.name}"`, name: custom.name };
}

exports.addMember = handle(async (req, res) => {
  const { companyId } = req.params;
  const { userId, email } = req.body;
  await requireRole(companyId, userId, ["admin", "super_admin"]);
  await requirePermission(companyId, userId, "members");
  const { role, customRoleId, label, name: roleName } = await inviteRole(companyId, userId, req.body.role, req.body.customRoleId);
  const company = await Company.findById(companyId).select("name external");
  if (company.external) throw fail(400, "Outside companies can't have members");
  const user = await User.findOne({ email: String(email || "").trim() }).select("name");
  if (!user) {
    // the web offers to email a sign-up invite when it sees this code
    return res.status(404).json({ success: false, code: "USER_NOT_FOUND", message: "No account with that email. Ask them to sign up first." });
  }
  const existing = await CompanyMember.findOne({ companyId, userId: user._id });
  if (existing) throw fail(400, `${user.name} is already in this company — change their role instead`);
  const member = await CompanyMember.create({ companyId, userId: user._id, role, customRoleId });
  await audit(userId, companyId, "add_member", "member", member._id, null, { memberUserId: user._id, role, customRoleId });
  notifyUsers([user._id], {
    title: `Added to ${company.name}`,
    body: customRoleId ? `You were added to ${company.name} as ${label}` : role === "admin" ? `You were added as an admin of ${company.name}` : `You were added to ${company.name}`,
    data: { companyId },
  });
  res.status(201).json({ success: true, member: { userId: user._id, name: user.name, role, customRoleId, customRoleName: roleName || null } });
});

// Saves which members a manager keeps unticked under "Visible To" when posting expenses.
exports.setVisibilityPreference = handle(async (req, res) => {
  const { companyId } = req.params;
  const { userId, hiddenStaffIds } = req.body;
  await requireRole(companyId, userId, ["admin", "super_admin"]);
  const memberIds = new Set((await CompanyMember.find({ companyId }).distinct("userId")).map(String));
  const hidden = [...new Set((Array.isArray(hiddenStaffIds) ? hiddenStaffIds : []).map(String))].filter((id) => memberIds.has(id));
  const updated = await CompanyMember.findOneAndUpdate(
    { companyId, userId },
    { $set: { hiddenStaffIds: hidden } },
    { returnDocument: "after" }
  );
  if (!updated) throw fail(404, "You are not a member of this company");
  res.json({ success: true, hiddenStaffIds: hidden });
});

// Email a Q Fin sign-up link to someone without an account; they join this company on sign-up.
exports.inviteMember = handle(async (req, res) => {
  const { companyId } = req.params;
  const { userId } = req.body;
  const email = String(req.body.email || "").trim().toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) throw fail(400, "Enter a valid email address");
  await requireRole(companyId, userId, ["admin", "super_admin"]);
  await requirePermission(companyId, userId, "members");
  const { role, customRoleId, label: roleLabel } = await inviteRole(companyId, userId, req.body.role, req.body.customRoleId);
  const company = await Company.findById(companyId).select("name external");
  if (company.external) throw fail(400, "Outside companies can't have members");
  const escaped = email.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  if (await User.exists({ email: new RegExp(`^${escaped}$`, "i") })) {
    throw fail(400, "This email already has an account — add them directly instead");
  }

  const invite = await CompanyInvite.findOneAndUpdate(
    { companyId, email },
    { $set: { role, customRoleId, invitedBy: userId, status: "pending", acceptedAt: null, emailSentAt: null } },
    { upsert: true, returnDocument: "after" }
  );

  const inviter = await User.findById(userId).select("name");
  const appUrl = String(process.env.WEB_APP_URL || req.get("origin") || "https://fintrack-sooty-eta.vercel.app").replace(/\/+$/, "");
  const link = `${appUrl}/signup?email=${encodeURIComponent(email)}`;
  const esc = (s) => String(s).replace(/[&<>"']/g, (ch) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[ch]);
  const companyName = esc(company.name);
  try {
    const transporter = nodemailer.createTransport({
      service: "gmail",
      auth: { user: process.env.SMTP_USER, pass: process.env.SMTP_PASS },
    });
    await transporter.sendMail({
      from: process.env.SMTP_USER,
      to: email,
      subject: `You're invited to join ${company.name} on Q Fin`,
      html: `<h2>Join ${companyName} on Q Fin</h2>
<p>${esc(inviter?.name || "A manager")} invited you to join <strong>${companyName}</strong> as ${roleLabel}.</p>
<p><a href="${esc(link)}" style="display:inline-block;padding:10px 18px;background:#0C5F41;color:#fff;border-radius:8px;text-decoration:none;font-weight:700">Create your Q Fin account</a></p>
<p>Sign up with this email address (${esc(email)}) and you'll be added to ${companyName} automatically.</p>`,
    });
    await CompanyInvite.updateOne({ _id: invite._id }, { $set: { emailSentAt: new Date() } });
  } catch (e) {
    console.error("invite email failed:", e.message);
    throw fail(502, "Invite saved, but the email could not be sent. Try again later.");
  }

  await audit(userId, companyId, "invite_member", "invite", invite._id, null, { email, role });
  res.status(201).json({ success: true, invite: { email, role } });
});

// People invited by email, newest first, with where they are: invite sent (waiting to sign up), email failed, or joined.
exports.listInvites = handle(async (req, res) => {
  const { companyId } = req.params;
  const { userId } = req.query;
  await requireRole(companyId, userId, ["admin", "super_admin"]);
  await requirePermission(companyId, userId, "members");
  const company = await Company.findById(companyId).select("customRoles").lean();
  const invites = await CompanyInvite.find({ companyId }).populate("invitedBy", "name").sort({ updatedAt: -1 }).lean();
  res.json({
    success: true,
    invites: invites.map((i) => ({
      _id: i._id,
      email: i.email,
      role: i.role,
      roleName: i.customRoleId ? (company?.customRoles || []).find((r) => String(r._id) === String(i.customRoleId))?.name || null : null,
      customRoleId: i.customRoleId || null,
      status: i.status, // pending | accepted
      // invites from before this was tracked have no emailSentAt field at all: assume their email went out
      emailSent: Boolean(i.emailSentAt) || !("emailSentAt" in i),
      sentAt: i.emailSentAt || null,
      acceptedAt: i.acceptedAt || null,
      invitedBy: i.invitedBy?.name || null,
      createdAt: i.createdAt,
    })),
  });
});

// Withdraw an invite that hasn't been accepted yet (the email's sign-up link then just makes an account, no company).
exports.cancelInvite = handle(async (req, res) => {
  const { companyId, inviteId } = req.params;
  const { userId } = req.body;
  await requireRole(companyId, userId, ["admin", "super_admin"]);
  await requirePermission(companyId, userId, "members");
  const invite = await CompanyInvite.findOne({ _id: inviteId, companyId });
  if (!invite) throw fail(404, "Invite not found");
  if (invite.status === "accepted") throw fail(400, "They have already joined; remove them from the members list instead");
  await invite.deleteOne();
  await audit(userId, companyId, "cancel_invite", "invite", invite._id, { email: invite.email }, null);
  res.json({ success: true });
});

// ---------- vouchers (money handed to staff up front) ----------
// Each staff member has an "advance" account: debit = voucher money given to them, credit = spent or handed back.
// "Held" balance = advance balance minus vouchers still open (those are shown separately until claimed).

async function advanceAccount(companyId, personUserId) {
  const user = await User.findById(personUserId).select("name");
  return getAccount(companyId, { type: "advance", userId: personUserId, name: `Advance with ${user ? user.name : "member"}` });
}

async function heldAdvance(companyId, personUserId) {
  const acc = await LedgerAccount.findOne({ companyId, type: "advance", userId: personUserId });
  if (!acc) return 0;
  const t = await accountTotals(acc._id);
  const open = await Voucher.find({ companyId, recipientId: personUserId, status: "open" }).select("amount");
  return round(t.debit - t.credit - open.reduce((s, v) => s + v.amount, 0));
}

// userId -> held balance, for everyone in the company who has an advance account
async function advanceHeldByPerson(companyId) {
  const out = new Map();
  const accounts = await LedgerAccount.find({ companyId, type: "advance" }).select("userId");
  if (!accounts.length) return out;
  const totals = await LedgerEntry.aggregate([
    { $match: { accountId: { $in: accounts.map((a) => a._id) } } },
    { $group: { _id: "$accountId", debit: { $sum: "$debit" }, credit: { $sum: "$credit" } } },
  ]);
  const t = new Map(totals.map((x) => [String(x._id), x]));
  for (const a of accounts) {
    const x = t.get(String(a._id));
    out.set(String(a.userId), round((x?.debit || 0) - (x?.credit || 0)));
  }
  const open = await Voucher.find({ companyId, status: "open" }).select("recipientId amount");
  for (const v of open) {
    const key = String(v.recipientId);
    out.set(key, round((out.get(key) || 0) - v.amount));
  }
  return out;
}

// One change to a person's advance at a time (claim, use on an expense, netting, hand-back, cancel).
const ADVANCE_LOCK_MS = 2 * 60 * 1000;
async function withAdvanceLock(companyId, personUserId, fn) {
  const now = new Date();
  const locked = await CompanyMember.findOneAndUpdate(
    { companyId, userId: personUserId, $or: [{ advanceLockAt: null }, { advanceLockAt: { $lt: new Date(now.getTime() - ADVANCE_LOCK_MS) } }] },
    { $set: { advanceLockAt: now } }
  );
  if (!locked) {
    // a company creator without a member row never receives vouchers, so there is nothing to protect
    if (!(await CompanyMember.exists({ companyId, userId: personUserId }))) return fn();
    throw fail(409, "This person's voucher balance is being updated; try again in a moment");
  }
  try {
    return await fn();
  } finally {
    await CompanyMember.updateOne({ _id: locked._id, advanceLockAt: now }, { $set: { advanceLockAt: null } });
  }
}

// Takes money out of the displayed Cash/Bank only if it is there (no check-then-deduct race).
async function takeCompanyFund(companyId, fundId, amount, label) {
  const isCash = !fundId || fundId === "cash";
  const result = await Company.updateOne(
    isCash
      ? { _id: companyId, cashBalance: { $gte: amount } }
      : { _id: companyId, bankAccounts: { $elemMatch: { _id: new mongoose.Types.ObjectId(String(fundId)), balance: { $gte: amount } } } },
    isCash ? { $inc: { cashBalance: -amount } } : { $inc: { "bankAccounts.$.balance": -amount } }
  );
  if (!result.modifiedCount) {
    const available = await getEffectiveFundBalance(companyId, fundId);
    throw fail(400, `Insufficient balance in ${label} (₹${available.toFixed(2)} available, ₹${amount.toFixed(2)} required)`);
  }
}

// A staff expense approved with "use my balance": the held balance pays what it can, the company owes the rest.
async function applyAdvanceToExpense(expense, userId) {
  const { companyId, createdBy } = expense;
  const held = await heldAdvance(companyId, createdBy);
  const used = round(Math.min(expense.amount, Math.max(0, held)));
  if (!(used > 0)) return;
  const rest = round(expense.amount - used);
  const lines = [
    { account: await expenseAccount(companyId, expense.category), debit: expense.amount },
    { account: await advanceAccount(companyId, createdBy), credit: used },
  ];
  if (rest > 0) lines.push({ account: await payableAccount(companyId, createdBy), credit: rest });
  const tx = await post({ companyId, type: "advance_used", expenseId: expense._id, memo: expense.description, createdBy: userId }, lines);
  await Expense.updateOne(
    { _id: expense._id, lifecycle: "approved" },
    { $set: { lifecycle: rest > 0 ? "paid_by_person" : "paid_by_voucher", status: "paid", payerType: "person", paidByUserId: createdBy, advanceUsed: used, transactionId: tx._id } }
  );
  await audit(userId, companyId, "use_advance", "expense", expense._id, null, { used, owed: rest });
  notifyUsers([createdBy], { title: "Voucher balance used", body: `₹${used} of your balance paid ${expense.description}${rest > 0 ? `; ₹${rest} is owed to you` : ""}`, data: { expenseId: expense._id, companyId } }, userId);
}

// Keeps vouchers / hand-backs in step when a super admin reverses their ledger transaction.
async function undoVoucherRecords(tx, userId) {
  if (tx.type === "voucher_issue" && tx.voucherId) {
    await Voucher.updateOne({ _id: tx.voucherId, status: "open" }, { $set: { status: "cancelled", cancelledBy: userId, cancelledAt: new Date() } });
  }
  if (tx.type === "voucher_claim" && tx.voucherId) {
    await Voucher.updateOne(
      { _id: tx.voucherId, status: "claimed" },
      { $set: { status: "open", claimedAmount: 0, fromAdvance: 0, owedToRecipient: 0, expenseId: null, claimTxId: null, claimedAt: null, closedBy: null, closedAt: null } }
    );
    if (tx.expenseId) await Expense.updateOne({ _id: tx.expenseId }, { $set: { lifecycle: "rejected", status: "outstanding", transactionId: null, advanceUsed: 0 } });
  }
  if (tx.type === "advance_return" && tx.advanceReturnId) {
    await AdvanceReturn.updateOne({ _id: tx.advanceReturnId }, { $set: { status: "reversed" } });
  }
}

const voucherPopulate = (q) => q.populate("recipientId", "name").populate("createdBy", "name").populate("cancelledBy", "name").populate("closedBy", "name");

exports.createVoucher = handle(async (req, res) => {
  const { companyId } = req.params;
  const { userId, recipientId, amount, purpose, fundedBy, fundId } = req.body;
  const value = round(parseFloat(amount));
  if (!(value > 0)) throw fail(400, "Enter a valid amount");
  if (!purpose || !String(purpose).trim()) throw fail(400, "Enter what the voucher is for");
  if (!["company", "manager"].includes(fundedBy)) throw fail(400, "Choose who funds the voucher: company or manager");
  if (!recipientId) throw fail(400, "Choose who receives the voucher");
  await requireRole(companyId, userId, ["admin", "super_admin"]);
  await requirePermission(companyId, userId, "vouchers");
  if ((await roleIn(companyId, recipientId)) !== "employee") throw fail(400, "Vouchers can be given to staff only");

  let fund = null;
  let fundName = "";
  let creditAccount;
  if (fundedBy === "company") {
    fund = fundId || "cash";
    creditAccount = await fundAccount(companyId, fund);
    const company = await Company.findById(companyId).select("cashAccountName");
    fundName = fund === "cash" ? (company?.cashAccountName || "Cash") : creditAccount.name;
    await takeCompanyFund(companyId, fund, value, fundName);
  } else {
    creditAccount = await payableAccount(companyId, userId);
  }

  let voucher;
  try {
    voucher = await Voucher.create({ companyId, recipientId, createdBy: userId, amount: value, purpose: String(purpose).trim(), fundedBy, fundId: fund, fundName });
    const verification = fundedBy === "company" && (await needsVerification(companyId, value)) ? "pending" : null;
    const tx = await post(
      { companyId, type: "voucher_issue", voucherId: voucher._id, memo: `Voucher: ${voucher.purpose}`, createdBy: userId, verification },
      [
        { account: await advanceAccount(companyId, recipientId), debit: value },
        { account: creditAccount, credit: value },
      ]
    );
    voucher.issueTxId = tx._id;
    await voucher.save();
    if (verification) await notifyCompanyAdmins(companyId, { title: "Payment needs verification", body: `Voucher ${voucher.purpose} · ₹${value}`, data: { transactionId: tx._id, companyId } }, userId);
  } catch (e) {
    if (voucher) await Voucher.deleteOne({ _id: voucher._id });
    if (fund) await applyCompanyFund(companyId, fund, value);
    throw e;
  }

  await audit(userId, companyId, "create", "voucher", voucher._id, null, { recipientId, amount: value, purpose: voucher.purpose, fundedBy, fundId: fund });
  const giver = await User.findById(userId).select("name");
  notifyUsers([recipientId], { title: "Voucher received", body: `${giver?.name || "A manager"} gave you ₹${value} for ${voucher.purpose}`, data: { voucherId: voucher._id, companyId } }, userId);
  res.status(201).json({ success: true, voucher: await voucherPopulate(Voucher.findById(voucher._id)) });
});

exports.listVouchers = handle(async (req, res) => {
  const { companyId } = req.params;
  const { userId } = req.query;
  const role = await requireRole(companyId, userId, ["employee", "admin", "super_admin"]);
  const admin = isAdminRole(role);
  const vouchers = await voucherPopulate(Voucher.find(admin ? { companyId } : { companyId, recipientId: userId }))
    .sort({ createdAt: -1 }).limit(500).lean();
  const returns = await AdvanceReturn.find(admin ? { companyId } : { companyId, userId })
    .populate("userId", "name").populate("decidedBy", "name").sort({ createdAt: -1 }).limit(200).lean();
  const held = await advanceHeldByPerson(companyId);
  const myAdvance = held.get(String(userId)) || 0;
  if (!admin) return res.json({ success: true, role, vouchers, returns, myAdvance });

  // per staff member: given, claimed, still open, and balance held
  const ids = new Set([...held.keys(), ...vouchers.map((v) => String(v.recipientId?._id || v.recipientId))]);
  const users = await User.find({ _id: { $in: [...ids] } }).select("name");
  const total = (list, f) => round(list.reduce((s, v) => s + (v[f] || 0), 0));
  const people = users.map((u) => {
    const mine = vouchers.filter((v) => String(v.recipientId?._id || v.recipientId) === String(u._id) && v.status !== "cancelled");
    return {
      userId: u._id,
      name: u.name,
      given: total(mine, "amount"),
      claimed: total(mine.filter((v) => v.status === "claimed"), "claimedAmount"),
      open: total(mine.filter((v) => v.status === "open"), "amount"),
      held: held.get(String(u._id)) || 0,
    };
  }).sort((a, b) => a.name.localeCompare(b.name));
  res.json({ success: true, role, vouchers, returns, people, myAdvance });
});

// Records what was spent from a voucher, always in the recipient's name. Used by Claim (the staff member)
// and Close (the manager who created it). Same money rules either way: under-spend stays as the
// recipient's balance, over-spend comes from their held balance first and the rest is owed to them.
async function settleVoucher(found, actorId, body, closing) {
  const { amount, category, description, attachment, date } = body;
  const value = round(parseFloat(amount));
  if (!(value > 0)) throw fail(400, closing ? "Enter the amount used" : "Enter the amount you spent");
  if (attachment && !(typeof attachment === "string" && attachment.startsWith("data:image/"))) throw fail(400, "Receipts must be image files");
  const companyId = found.companyId;
  const recipientId = found.recipientId;

  let voucher;
  let expense;
  await withAdvanceLock(companyId, recipientId, async () => {
    voucher = await Voucher.findOneAndUpdate({ _id: found._id, status: "open" }, { $set: { status: "claiming" } }, { returnDocument: "after" });
    if (!voucher) throw fail(409, "This voucher was already claimed, closed or cancelled");
    try {
      // this voucher is no longer "open", so the held balance now includes it: use it first, then the rest
      const available = Math.max(0, await heldAdvance(companyId, recipientId));
      const fromAdvance = round(Math.min(value, available));
      const owedToRecipient = round(value - fromAdvance);
      const cat = String(category || "").trim() || "General";
      expense = await Expense.create({
        companyId,
        createdBy: recipientId,
        isAdminCreated: false,
        amount: value,
        description: String(description || "").trim() || voucher.purpose,
        category: cat,
        date: date ? new Date(date) : new Date(),
        attachment: attachment || "",
        lifecycle: "paid_by_voucher",
        approvedBy: voucher.createdBy,
        status: "paid",
        payerType: voucher.fundedBy === "company" ? "company" : "person",
        logAs: "self",
        voucherId: voucher._id,
        advanceUsed: fromAdvance,
      });
      const lines = [{ account: await expenseAccount(companyId, cat), debit: value }];
      if (fromAdvance > 0) lines.push({ account: await advanceAccount(companyId, recipientId), credit: fromAdvance });
      if (owedToRecipient > 0) lines.push({ account: await payableAccount(companyId, recipientId), credit: owedToRecipient });
      const tx = await post(
        { companyId, type: "voucher_claim", expenseId: expense._id, voucherId: voucher._id, memo: `${closing ? "Voucher closed" : "Voucher claim"}: ${expense.description}`, createdBy: actorId },
        lines
      );
      expense.transactionId = tx._id;
      await expense.save();
      Object.assign(voucher, {
        status: "claimed",
        claimedAmount: value,
        fromAdvance,
        owedToRecipient,
        expenseId: expense._id,
        claimTxId: tx._id,
        claimedAt: new Date(),
        ...(closing ? { closedBy: actorId, closedAt: new Date() } : {}),
      });
      await voucher.save();
    } catch (e) {
      if (expense && !expense.transactionId) await Expense.deleteOne({ _id: expense._id });
      await Voucher.updateOne({ _id: voucher._id, status: "claiming" }, { $set: { status: "open" } });
      throw e;
    }
  });

  if (!BASE_EXPENSE_CATEGORIES.includes(expense.category)) {
    await Company.updateOne({ _id: companyId }, { $addToSet: { customCategories: expense.category } });
  }
  await audit(actorId, companyId, closing ? "close" : "claim", "voucher", voucher._id, null, {
    amount: value,
    fromAdvance: voucher.fromAdvance,
    owedToRecipient: voucher.owedToRecipient,
    expenseId: expense._id,
    recipientId,
  });
  return { voucher, expense, value };
}

const voucherTail = (voucher, value) => {
  const left = round(voucher.amount - value);
  return left > 0 ? ` · ₹${left} stays with them` : voucher.owedToRecipient > 0 ? ` · ₹${voucher.owedToRecipient} owed to them` : "";
};

exports.claimVoucher = handle(async (req, res) => {
  const { userId } = req.body;
  const found = await Voucher.findById(req.params.voucherId);
  if (!found) throw fail(404, "Voucher not found");
  if (String(found.recipientId) !== String(userId)) throw fail(403, "Only the person who received this voucher can claim it");
  await requireRole(found.companyId, userId, ["employee", "admin", "super_admin"]);
  await requirePermission(found.companyId, userId, "vouchers");
  const { voucher, expense, value } = await settleVoucher(found, userId, req.body, false);

  const claimer = await User.findById(userId).select("name");
  await notifyCompanyAdmins(found.companyId, {
    title: "Voucher claimed",
    body: `${claimer?.name || "Staff"} claimed ₹${value} of ₹${voucher.amount} for ${voucher.purpose}${voucherTail(voucher, value)}`,
    data: { voucherId: voucher._id, expenseId: expense._id, companyId: found.companyId },
  }, userId);
  res.json({
    success: true,
    voucher: await voucherPopulate(Voucher.findById(voucher._id)),
    expense: await Expense.findById(expense._id).select("-attachment -paymentReceipt"),
    myAdvance: await heldAdvance(found.companyId, userId),
  });
});

// The manager who created a voucher closes it for the staff member: recorded as that staff member's use, amount editable.
exports.closeVoucher = handle(async (req, res) => {
  const { userId } = req.body;
  const found = await Voucher.findById(req.params.voucherId);
  if (!found) throw fail(404, "Voucher not found");
  await requireRole(found.companyId, userId, ["admin", "super_admin"]);
  await requirePermission(found.companyId, userId, "vouchers");
  if (String(found.createdBy) !== String(userId)) throw fail(403, "Only the manager who created this voucher can close it");
  const { voucher, expense, value } = await settleVoucher(found, userId, req.body, true);

  const [closer, recipient] = await Promise.all([User.findById(userId).select("name"), User.findById(found.recipientId).select("name")]);
  notifyUsers([found.recipientId], {
    title: "Voucher closed",
    body: `${closer?.name || "Your manager"} closed ${voucher.purpose}: ₹${value} recorded as used by you${voucherTail(voucher, value).replace("them", "you")}`,
    data: { voucherId: voucher._id, expenseId: expense._id, companyId: found.companyId },
  }, userId);
  await notifyCompanyAdmins(found.companyId, {
    title: "Voucher closed",
    body: `${closer?.name || "A manager"} closed ${voucher.purpose} for ${recipient?.name || "staff"}: ₹${value} of ₹${voucher.amount}${voucherTail(voucher, value)}`,
    data: { voucherId: voucher._id, expenseId: expense._id, companyId: found.companyId },
  }, userId);
  res.json({
    success: true,
    voucher: await voucherPopulate(Voucher.findById(voucher._id)),
    expense: await Expense.findById(expense._id).select("-attachment -paymentReceipt"),
  });
});

// Cancel and Delete share this: only the creating manager, only while unclaimed; the money goes back where it
// came from (company Cash/Bank, or off the manager's owed balance). The voucher is left marked "cancelled".
async function returnVoucherMoney(req, verb) {
  const { userId } = req.body;
  const found = await Voucher.findById(req.params.voucherId);
  if (!found) throw fail(404, "Voucher not found");
  const companyId = found.companyId;
  await requireRole(companyId, userId, ["admin", "super_admin"]);
  await requirePermission(companyId, userId, "vouchers");
  if (String(found.createdBy) !== String(userId)) throw fail(403, `Only the manager who created this voucher can ${verb} it`);

  await withAdvanceLock(companyId, found.recipientId, async () => {
    const voucher = await Voucher.findOneAndUpdate(
      { _id: found._id, status: "open" },
      { $set: { status: "cancelled", cancelledBy: userId, cancelledAt: new Date() } },
      { returnDocument: "after" }
    );
    if (!voucher) throw fail(409, `Only an unclaimed voucher can be ${verb === "delete" ? "deleted" : "cancelled"}`);
    try {
      if (voucher.fundedBy === "manager" && (await adminOwed(companyId, voucher.createdBy)) < voucher.amount) {
        throw fail(400, `The manager who funded this voucher has already been reimbursed for it, so it can't be ${verb === "delete" ? "deleted" : "cancelled"}`);
      }
      const issue = voucher.issueTxId ? await LedgerTransaction.findById(voucher.issueTxId) : null;
      if (issue && !issue.reversedBy) await postReversal(issue, userId, `Voucher ${verb === "delete" ? "deleted" : "cancelled"}: ${voucher.purpose}`);
      if (voucher.fundedBy === "manager") await recomputeReimbursed(companyId, voucher.createdBy);
    } catch (e) {
      await Voucher.updateOne({ _id: voucher._id, status: "cancelled" }, { $set: { status: "open", cancelledBy: null, cancelledAt: null } });
      throw e;
    }
  });
  return found;
}

exports.cancelVoucher = handle(async (req, res) => {
  const found = await returnVoucherMoney(req, "cancel");
  const { userId } = req.body;
  await audit(userId, found.companyId, "cancel", "voucher", found._id, { status: "open" }, { status: "cancelled" });
  notifyUsers([found.recipientId], { title: "Voucher cancelled", body: `₹${found.amount} for ${found.purpose} was cancelled`, data: { voucherId: found._id, companyId: found.companyId } }, userId);
  res.json({ success: true, voucher: await voucherPopulate(Voucher.findById(found._id)) });
});

// Same as cancel, then the voucher is removed from every list. The ledger keeps the issue and its reversal,
// and the audit log keeps what was deleted.
exports.deleteVoucher = handle(async (req, res) => {
  const found = await returnVoucherMoney(req, "delete");
  const { userId } = req.body;
  await Voucher.deleteOne({ _id: found._id });
  await audit(userId, found.companyId, "delete", "voucher", found._id, {
    purpose: found.purpose,
    amount: found.amount,
    recipientId: found.recipientId,
    fundedBy: found.fundedBy,
    fundName: found.fundName,
  }, null);
  notifyUsers([found.recipientId], { title: "Voucher removed", body: `₹${found.amount} for ${found.purpose} was withdrawn`, data: { companyId: found.companyId } }, userId);
  res.json({ success: true });
});

// Staff asks to hand back unused balance; nothing moves until a manager confirms they received the cash.
exports.requestAdvanceReturn = handle(async (req, res) => {
  const { companyId } = req.params;
  const { userId, amount, note } = req.body;
  const value = round(parseFloat(amount));
  if (!(value > 0)) throw fail(400, "Enter a valid amount");
  await requireRole(companyId, userId, ["employee", "admin", "super_admin"]);
  await requirePermission(companyId, userId, "vouchers");
  const held = await heldAdvance(companyId, userId);
  const pending = await AdvanceReturn.find({ companyId, userId, status: { $in: ["pending", "processing"] } }).select("amount");
  const free = round(held - pending.reduce((s, r) => s + r.amount, 0));
  if (value > free) throw fail(400, free > 0 ? `You can hand back up to ₹${free}` : "You have no voucher balance to hand back");
  const advanceReturn = await AdvanceReturn.create({ companyId, userId, amount: value, note: String(note || "").trim() });
  await audit(userId, companyId, "request_return", "advance_return", advanceReturn._id, null, { amount: value });
  const person = await User.findById(userId).select("name");
  await notifyCompanyAdmins(companyId, { title: "Hand-back to confirm", body: `${person?.name || "Staff"} is handing back ₹${value} of voucher balance`, data: { advanceReturnId: advanceReturn._id, companyId } }, userId);
  res.status(201).json({ success: true, advanceReturn });
});

exports.decideAdvanceReturn = handle(async (req, res) => {
  const { userId, accept } = req.body;
  const found = await AdvanceReturn.findById(req.params.returnId);
  if (!found) throw fail(404, "Hand-back not found");
  const companyId = found.companyId;
  await requireRole(companyId, userId, ["admin", "super_admin"]);
  await requirePermission(companyId, userId, "vouchers");
  if (String(found.userId) === String(userId)) throw fail(403, "Another manager must confirm your hand-back");

  let advanceReturn;
  await withAdvanceLock(companyId, found.userId, async () => {
    advanceReturn = await AdvanceReturn.findOneAndUpdate({ _id: found._id, status: "pending" }, { $set: { status: "processing" } }, { returnDocument: "after" });
    if (!advanceReturn) throw fail(409, "This hand-back was already handled");
    try {
      if (accept) {
        const held = await heldAdvance(companyId, advanceReturn.userId);
        if (held < advanceReturn.amount) throw fail(400, `They now hold only ₹${Math.max(0, held)}; ask them to send a new hand-back`);
        const tx = await post(
          { companyId, type: "advance_return", advanceReturnId: advanceReturn._id, memo: `Voucher balance handed back${advanceReturn.note ? `: ${advanceReturn.note}` : ""}`, method: "Cash", createdBy: userId },
          [
            { account: await fundAccount(companyId, "cash"), debit: advanceReturn.amount },
            { account: await advanceAccount(companyId, advanceReturn.userId), credit: advanceReturn.amount },
          ]
        );
        await applyCompanyFund(companyId, "cash", advanceReturn.amount);
        advanceReturn.transactionId = tx._id;
      }
      Object.assign(advanceReturn, { status: accept ? "confirmed" : "rejected", decidedBy: userId, decidedAt: new Date() });
      await advanceReturn.save();
    } catch (e) {
      await AdvanceReturn.updateOne({ _id: advanceReturn._id, status: "processing" }, { $set: { status: "pending" } });
      throw e;
    }
  });

  await audit(userId, companyId, accept ? "confirm_return" : "reject_return", "advance_return", advanceReturn._id, null, { amount: advanceReturn.amount });
  notifyUsers([advanceReturn.userId], {
    title: accept ? "Hand-back confirmed" : "Hand-back declined",
    body: accept ? `₹${advanceReturn.amount} received back into company cash` : `Your hand-back of ₹${advanceReturn.amount} was declined; the balance stays with you`,
    data: { advanceReturnId: advanceReturn._id, companyId },
  }, userId);
  res.json({ success: true, advanceReturn });
});

// ---------- feature permissions ----------
// Everyone in the company can read their own switches (the apps hide what's off); editors also get both lists.
exports.getPermissions = handle(async (req, res) => {
  const { companyId } = req.params;
  const { userId } = req.query;
  await requireRole(companyId, userId, ["employee", "admin", "super_admin"]);
  const [mine, company] = await Promise.all([permissionsFor(companyId, userId), Company.findById(companyId).select("permissions customRoles").lean()]);
  const canEditManagers = hasPower(mine, "manager_permissions");
  const managerLike = mine.role === "manager" || (mine.role === "custom" && mine.base === "manager");
  const canManageRoles = hasPower(mine, "manage_roles");
  const canEditStaff = canEditManagers || canManageRoles || (managerLike && mine.perms.staff_permissions);
  res.json({
    success: true,
    role: mine.role,
    mine: mine.perms,
    canEditManagers,
    canEditStaff,
    ...(canEditStaff
      ? {
          definitions: LISTS,
          manager: resolved(LISTS.manager, company?.permissions?.manager),
          staff: resolved(LISTS.staff, company?.permissions?.staff),
        }
      : {}),
    // custom roles: only the primary admin manages them
    canManageRoles,
    ...(canManageRoles ? { customRoles: await customRolesView(companyId, company) } : {}),
  });
});

// body: { userId, role: "manager" | "staff", permissions: { key: boolean } }
// Primary admin: both lists. Other managers (with "Change staff permissions"): the staff list, and they can't
// switch on a staff feature that is off for managers.
exports.updatePermissions = handle(async (req, res) => {
  const { companyId } = req.params;
  const { userId, role: target, permissions } = req.body;
  if (!["manager", "staff"].includes(target)) throw fail(400, "Choose manager or staff permissions");
  if (!permissions || typeof permissions !== "object") throw fail(400, "Permissions are required");
  await requireRole(companyId, userId, ["admin", "super_admin"]);
  const mine = await permissionsFor(companyId, userId);
  if (target === "manager" && !hasPower(mine, "manager_permissions")) throw fail(403, "Only the primary admin can change manager permissions");
  if (target === "staff" && mine.role !== "primary" && !mine.perms.staff_permissions && !hasPower(mine, "manager_permissions")) {
    throw fail(403, '"Change staff permissions" is turned off for managers in this company');
  }

  const company = await Company.findById(companyId).select("permissions");
  const before = resolved(LISTS[target], company.permissions?.[target]);
  const next = { ...before };
  for (const def of LISTS[target]) {
    if (typeof permissions[def.key] === "boolean") next[def.key] = permissions[def.key];
  }
  if (target === "staff" && mine.role !== "primary" && !hasPower(mine, "manager_permissions")) {
    for (const def of LISTS.staff) {
      if (next[def.key] && !before[def.key] && def.needs && !mine.perms[def.needs]) {
        throw fail(403, `You can't turn on "${def.label}" for staff because it's off for managers`);
      }
    }
  }
  // only switched-off keys are stored, so features added later start switched on
  const stored = Object.fromEntries(Object.entries(next).filter(([, on]) => !on).map(([key]) => [key, false]));
  await Company.updateOne({ _id: companyId }, { $set: { [`permissions.${target}`]: stored } });
  await audit(userId, companyId, "update_permissions", "company", companyId, { [target]: before }, { [target]: next });
  res.json({ success: true, [target]: next });
});

// ---------- custom roles (primary admin only) ----------
// Roles on top of Manager/Staff. Each has a base (manager-like = admin, staff-like = member, mirrored on
// CompanyMember.role so every existing rule keeps working) and its own switches, all OFF until turned on.
async function requirePrimary(companyId, userId) {
  const mine = await permissionsFor(companyId, userId);
  if (!hasPower(mine, "manage_roles")) throw fail(403, "Only the primary admin can manage roles");
}

// Manager-level access follows the switches: everyone in the role is stored as admin (manager-level) or member.
async function syncRoleMembers(companyId, role) {
  await CompanyMember.updateMany({ companyId, customRoleId: role._id }, { $set: { role: roleBase(role) === "manager" ? "admin" : "member" } });
}

// A manager-level member's own posts are approved straight away, except in a custom role without "auto_approve".
async function autoApproves(companyId, userId) {
  const mine = await permissionsFor(companyId, userId);
  return mine.role !== "custom" || mine.perms.auto_approve === true;
}

async function customRolesView(companyId, company) {
  const roles = company?.customRoles || [];
  if (!roles.length) return [];
  const members = await CompanyMember.find({ companyId, customRoleId: { $in: roles.map((r) => r._id) } }).select("userId customRoleId").lean();
  const users = await User.find({ _id: { $in: members.map((m) => m.userId) } }).select("name email").lean();
  const byId = new Map(users.map((u) => [String(u._id), u]));
  return roles.map((r) => ({
    _id: r._id,
    name: r.name,
    base: roleBase(r),
    createdAt: r.createdAt,
    permissions: resolvedCustom(r),
    members: members
      .filter((m) => String(m.customRoleId) === String(r._id))
      .map((m) => ({ userId: m.userId, name: byId.get(String(m.userId))?.name || "Member", email: byId.get(String(m.userId))?.email || "" })),
  }));
}

const roleNameTaken = (company, name, exceptId) =>
  ["manager", "managers", "staff", "admin", "primary admin", company.roleNames?.manager, company.roleNames?.staff]
    .filter(Boolean)
    .map((n) => n.toLowerCase())
    .includes(name.toLowerCase()) ||
  (company.customRoles || []).some((r) => r.name.toLowerCase() === name.toLowerCase() && String(r._id) !== String(exceptId || ""));

// body: { userId, name } — every switch starts off
exports.createCustomRole = handle(async (req, res) => {
  const { companyId } = req.params;
  const { userId } = req.body;
  const base = "staff";
  const name = String(req.body.name || "").trim();
  await requirePrimary(companyId, userId);
  if (!name) throw fail(400, "Give the role a name");
  if (name.length > 40) throw fail(400, "Keep the role name under 40 characters");
  const company = await Company.findById(companyId).select("customRoles roleNames");
  if (roleNameTaken(company, name)) throw fail(400, `A role called "${name}" already exists`);
  company.customRoles.push({ name, base, permissions: {}, createdBy: userId });
  await company.save();
  const role = company.customRoles[company.customRoles.length - 1];
  await audit(userId, companyId, "create_role", "company", companyId, null, { roleId: role._id, name, base });
  res.json({ success: true, role: { _id: role._id, name, base, permissions: resolvedCustom(role), members: [] } });
});

// body: { userId, name?, permissions?: { key: boolean } }
exports.updateCustomRole = handle(async (req, res) => {
  const { companyId, roleId } = req.params;
  const { userId, permissions } = req.body;
  await requirePrimary(companyId, userId);
  const company = await Company.findById(companyId).select("customRoles roleNames");
  const role = company.customRoles.id(roleId);
  if (!role) throw fail(404, "Role not found");
  const before = { name: role.name, permissions: resolvedCustom(role) };
  if (req.body.name !== undefined) {
    const name = String(req.body.name).trim();
    if (!name) throw fail(400, "Give the role a name");
    if (name.length > 40) throw fail(400, "Keep the role name under 40 characters");
    if (roleNameTaken(company, name, roleId)) throw fail(400, `A role called "${name}" already exists`);
    role.name = name;
  }
  if (permissions && typeof permissions === "object") {
    const next = { ...(role.permissions || {}) };
    for (const def of LISTS.custom) {
      if (typeof permissions[def.key] !== "boolean") continue;
      if (permissions[def.key]) next[def.key] = true;
      else delete next[def.key];
    }
    role.permissions = next;
    role.base = roleBase(role);
    company.markModified("customRoles");
  }
  await company.save();
  await syncRoleMembers(companyId, role);
  await audit(userId, companyId, "update_role", "company", companyId, before, { roleId, name: role.name, permissions: resolvedCustom(role) });
  res.json({ success: true, role: { _id: role._id, name: role.name, base: roleBase(role), permissions: resolvedCustom(role) } });
});

// Deletes the role AND removes its members from the company (the web asks first, listing them).
exports.deleteCustomRole = handle(async (req, res) => {
  const { companyId, roleId } = req.params;
  const { userId } = req.body;
  await requirePrimary(companyId, userId);
  const company = await Company.findById(companyId).select("customRoles createdBy name");
  const role = company.customRoles.id(roleId);
  if (!role) throw fail(404, "Role not found");
  const members = await CompanyMember.find({ companyId, customRoleId: role._id });
  const removed = members.filter((m) => String(m.userId) !== String(company.createdBy));
  await CompanyMember.deleteMany({ _id: { $in: removed.map((m) => m._id) } });
  const name = role.name;
  company.customRoles.pull(role._id);
  await company.save();
  await audit(userId, companyId, "delete_role", "company", companyId, { roleId, name, members: removed.map((m) => m.userId) }, null);
  if (removed.length) {
    notifyUsers(removed.map((m) => m.userId), { title: "Removed from company", body: `The "${name}" role in ${company.name} was deleted, and you were removed with it`, data: { companyId } });
  }
  res.json({ success: true, removed: removed.length });
});

// Puts a member into a custom role (their Manager/Staff base follows it), or takes them out (roleId null → staff).
exports.setMemberCustomRole = handle(async (req, res) => {
  const { companyId, memberUserId } = req.params;
  const { userId, roleId } = req.body;
  await requirePrimary(companyId, userId);
  const company = await Company.findById(companyId).select("customRoles createdBy name");
  if (String(company.createdBy) === String(memberUserId)) throw fail(400, "The primary admin can't be given a role");
  const member = await CompanyMember.findOne({ companyId, userId: memberUserId });
  if (!member) throw fail(404, "That person is not in this company");
  const before = { role: member.role, customRoleId: member.customRoleId, isAdmin: member.isAdmin };
  if (member.isAdmin && (await permissionsFor(companyId, userId)).role !== "primary") throw fail(403, "Only an Admin can change another Admin");
  member.isAdmin = false;
  let role = null;
  if (roleId) {
    role = company.customRoles.id(roleId);
    if (!role) throw fail(404, "Role not found");
    member.customRoleId = role._id;
    member.role = roleBase(role) === "manager" ? "admin" : "member";
  } else {
    member.customRoleId = null;
    member.role = "member";
  }
  await member.save();
  await audit(userId, companyId, "set_member_role", "member", member._id, before, { role: member.role, customRoleId: member.customRoleId, memberUserId });
  notifyUsers([memberUserId], {
    title: "Your role changed",
    body: role ? `You are now "${role.name}" in ${company.name}` : `You are now staff in ${company.name}`,
    data: { companyId },
  });
  res.json({ success: true });
});

// ---------- names of the built-in roles ----------
// A company can call its managers and staff something else (e.g. "Supervisor" / "Employee"); blank = default.
async function builtInRoleNames(companyId) {
  const company = await Company.findById(companyId).select("roleNames").lean();
  return { manager: company?.roleNames?.manager || "Manager", staff: company?.roleNames?.staff || "Staff" };
}

// body: { userId, manager?, staff? } — "" puts the default back. Primary admin or "Manage custom roles".
exports.renameBuiltInRoles = handle(async (req, res) => {
  const { companyId } = req.params;
  const { userId } = req.body;
  await requirePrimary(companyId, userId);
  const company = await Company.findById(companyId).select("roleNames customRoles");
  const before = { manager: company.roleNames?.manager || "", staff: company.roleNames?.staff || "" };
  const next = { ...before };
  for (const key of ["manager", "staff"]) {
    if (req.body[key] === undefined) continue;
    const name = String(req.body[key] || "").trim();
    if (name.length > 30) throw fail(400, "Keep role names under 30 characters");
    next[key] = name;
  }
  const shown = { manager: next.manager || "Manager", staff: next.staff || "Staff" };
  if (shown.manager.toLowerCase() === shown.staff.toLowerCase()) throw fail(400, "The two roles need different names");
  for (const key of ["manager", "staff"]) {
    if ((company.customRoles || []).some((r) => r.name.toLowerCase() === shown[key].toLowerCase())) {
      throw fail(400, `A custom role is already called "${shown[key]}"`);
    }
  }
  company.roleNames = next;
  await company.save();
  await audit(userId, companyId, "rename_roles", "company", companyId, before, next);
  res.json({ success: true, roleNames: shown });
});

// ---------- Admins ----------
// Only an Admin (the creator, or someone an Admin made Admin) can make or unmake an Admin. Admins have full access
// like the creator. The creator is always Admin. body: { userId, admin: boolean }
exports.setMemberAdmin = handle(async (req, res) => {
  const { companyId, memberUserId } = req.params;
  const { userId, admin } = req.body;
  if ((await permissionsFor(companyId, userId)).role !== "primary") throw fail(403, "Only an Admin can make someone an Admin");
  const company = await Company.findById(companyId).select("createdBy name");
  if (String(company.createdBy) === String(memberUserId)) throw fail(400, "The company's creator is always an Admin");
  const member = await CompanyMember.findOne({ companyId, userId: memberUserId });
  if (!member) throw fail(404, "That person is not in this company");
  const before = { role: member.role, isAdmin: member.isAdmin, customRoleId: member.customRoleId };
  if (admin) {
    member.isAdmin = true;
    member.role = "admin";
    member.customRoleId = null;
  } else {
    member.isAdmin = false; // stays a manager
  }
  await member.save();
  await audit(userId, companyId, admin ? "make_admin" : "remove_admin", "member", member._id, before, { memberUserId, isAdmin: member.isAdmin });
  const names = await builtInRoleNames(companyId);
  notifyUsers([memberUserId], {
    title: admin ? "You're now an Admin" : "Your role changed",
    body: admin ? `You now have full Admin access in ${company.name}` : `You are now ${names.manager} in ${company.name}`,
    data: { companyId },
  });
  res.json({ success: true });
});

// Past descriptions for the "description" fields, newest first and de-duplicated (case-insensitive).
// kind: expense (expense descriptions; staff only see their own), payment (payment notes), fund (income descriptions)
const CompanyIncome = require("../models/companyIncome");
const DESCRIPTION_SOURCES = {
  expense: (companyId, userId, admin) => ({
    model: Expense,
    field: "description",
    match: { companyId, lifecycle: { $ne: null }, ...(admin ? {} : { createdBy: userId }) },
  }),
  payment: (companyId) => ({ model: LedgerTransaction, field: "note", match: { companyId } }),
  fund: (companyId) => ({ model: CompanyIncome, field: "description", match: { companyId } }),
};

exports.descriptionSuggestions = handle(async (req, res) => {
  const { companyId } = req.params;
  const { userId, kind } = req.query;
  const source = DESCRIPTION_SOURCES[kind];
  if (!source) throw fail(400, "Unknown description type");
  const role = await requireRole(companyId, userId, ["admin", "employee", "super_admin"]);
  if (kind !== "expense" && !isAdminRole(role)) return res.json({ success: true, descriptions: [] });
  const { model, field, match } = source(new mongoose.Types.ObjectId(companyId), new mongoose.Types.ObjectId(userId), isAdminRole(role));
  const rows = await model.aggregate([
    { $match: { ...match, [field]: { $type: "string", $nin: ["", null] } } },
    { $project: { text: { $trim: { input: `$${field}` } }, createdAt: 1 } },
    { $match: { text: { $ne: "" } } },
    { $sort: { createdAt: -1 } },
    { $group: { _id: { $toLower: "$text" }, text: { $first: "$text" }, last: { $first: "$createdAt" }, uses: { $sum: 1 } } },
    { $sort: { last: -1 } },
    { $limit: 100 },
  ]);
  res.json({ success: true, descriptions: rows.map((r) => r.text) });
});

// ---- Company groups: a named set of companies, only for organising the companies list ----
const CompanyGroup = require("../models/companyGroup");

// Group name + companies. Every company must be one this user runs (Admin or manager); a company already in another
// group moves to this one. groupId in the URL = edit that group (its creator, or someone who runs all its companies).
exports.saveCompanyGroup = handle(async (req, res) => {
  const { userId } = req.body;
  const name = String(req.body.name || "").trim();
  const companyIds = [...new Set((Array.isArray(req.body.companyIds) ? req.body.companyIds : []).map(String))];
  if (!userId) throw fail(400, "userId is required");
  if (!name) throw fail(400, "Enter a group name");
  if (companyIds.length < 2) throw fail(400, "Pick at least two companies for a group");
  const companies = await Company.find({ _id: { $in: companyIds } }).select("name external");
  if (companies.length !== companyIds.length) throw fail(404, "One of the companies was not found");
  for (const c of companies) {
    if (c.external) throw fail(400, `${c.name} is an outside company and can't be grouped`);
    if (!isAdminRole(await roleIn(c._id, userId))) throw fail(403, `You need to be an Admin or manager of ${c.name} to group it`);
  }

  let group;
  if (req.params.groupId) {
    group = await CompanyGroup.findById(req.params.groupId);
    if (!group) throw fail(404, "Company group not found");
    if (String(group.createdBy) !== String(userId)) {
      for (const id of group.companyIds) {
        if (!isAdminRole(await roleIn(id, userId))) throw fail(403, "Only the group's creator, or someone who runs all its companies, can edit it");
      }
    }
    group.name = name;
    group.companyIds = companyIds;
    await group.save();
  } else {
    group = await CompanyGroup.create({ name, companyIds, createdBy: userId });
  }
  // a company belongs to one group: take these companies out of any other group, and drop groups left with fewer than two
  await CompanyGroup.updateMany({ _id: { $ne: group._id }, companyIds: { $in: companyIds } }, { $pull: { companyIds: { $in: companyIds } } });
  await CompanyGroup.deleteMany({ _id: { $ne: group._id }, "companyIds.1": { $exists: false } });
  res.json({ success: true, group });
});

// Ungroup: the companies are untouched, they just show on their own again.
exports.deleteCompanyGroup = handle(async (req, res) => {
  const { userId } = req.body;
  const group = await CompanyGroup.findById(req.params.groupId);
  if (!group) throw fail(404, "Company group not found");
  if (String(group.createdBy) !== String(userId)) {
    for (const id of group.companyIds) {
      if (!isAdminRole(await roleIn(id, userId))) throw fail(403, "Only the group's creator, or someone who runs all its companies, can remove it");
    }
  }
  await group.deleteOne();
  res.json({ success: true });
});

// ---- Accounts: day by day — money in/out, the day's expenses, and the closing Cash + Bank balance ----
// Balances are worked backwards from today's real Cash + Bank (Company doc) using only movements that changed it:
// fund lines of FUND_TRACKED / borrower loan-repayment transactions (and their reversals) + money added via Add Income.
const IST_OFFSET = 330 * 60000;
const istDay = (d) => new Date(new Date(d).getTime() + IST_OFFSET).toISOString().slice(0, 10);
const istStart = (day) => new Date(`${day}T00:00:00+05:30`);
const nextDay = (day) => istDay(istStart(day).getTime() + 36 * 3600000); // midnight + 1.5 days lands on the next date
const MOVE_LABELS = {
  company_paid: "Paid by company",
  reimburse: "Reimbursement",
  lend: "Manager loan to company",
  borrowed: "Borrowed money",
  voucher_issue: "Voucher given",
  advance_return: "Voucher money handed back",
  loan_repayment: "Loan repayment",
};

exports.accountsDays = handle(async (req, res) => {
  const { companyId } = req.params;
  const { userId } = req.query;
  await requireRole(companyId, userId, ["admin", "super_admin"]);
  await requirePermission(companyId, userId, "funds");
  const company = await Company.findById(companyId).select("name cashBalance cashAccountName bankAccounts").lean();
  if (!company) throw fail(404, "Company not found");

  const today = istDay(Date.now());
  const valid = (d) => /^\d{4}-\d{2}-\d{2}$/.test(String(d || ""));
  const toDay = valid(req.query.to) && req.query.to < today ? req.query.to : today;
  const fromDay = valid(req.query.from) ? (req.query.from > toDay ? toDay : req.query.from) : `${toDay.slice(0, 8)}01`;
  const since = istStart(fromDay);
  const untilEnd = istStart(nextDay(toDay));

  // fund (Cash/Bank) accounts and their names
  const cashName = company.cashAccountName || "Cash";
  const bankName = (id) => {
    const b = (company.bankAccounts || []).find((x) => String(x._id) === String(id));
    return b ? `${b.bankName}${b.accountNumber ? ` (…${String(b.accountNumber).slice(-4)})` : ""}` : "Bank";
  };
  const fundAccs = await LedgerAccount.find({ companyId, type: "bank" }).lean();
  const fundName = new Map(fundAccs.map((a) => [String(a._id), a.bankAccountId ? bankName(a.bankAccountId) : cashName]));

  // ledger movements since the first day, up to now (later days are needed to walk the balance back)
  const txs = await LedgerTransaction.find({ companyId, date: { $gte: since } }).lean();
  const originals = new Map(
    (await LedgerTransaction.find({ _id: { $in: txs.filter((t) => t.reverses).map((t) => t.reverses) } }).lean()).map((t) => [String(t._id), t])
  );
  const loans = new Map(
    (await CompanyLoan.find({ _id: { $in: txs.map((t) => t.loanId).filter(Boolean) } }).select("borrowerCompanyId").lean()).map((l) => [String(l._id), l])
  );
  const moves = (t) => {
    if (FUND_TRACKED_TYPES.has(t.type)) return true;
    if (t.type === "loan_repayment" && t.loanId) return String(loans.get(String(t.loanId))?.borrowerCompanyId) === String(companyId);
    return false;
  };
  const counted = txs.filter((t) => (t.type === "reversal" ? Boolean(originals.get(String(t.reverses))) && moves(originals.get(String(t.reverses))) : moves(t)));
  const entries = await LedgerEntry.find({ transactionId: { $in: counted.map((t) => t._id) }, accountId: { $in: fundAccs.map((a) => a._id) } }).lean();
  const txById = new Map(counted.map((t) => [String(t._id), t]));
  const people = new Map((await User.find({ _id: { $in: counted.map((t) => t.createdBy) } }).select("name").lean()).map((u) => [String(u._id), u.name]));

  const days = new Map();
  const dayRow = (day) => {
    if (!days.has(day)) days.set(day, { date: day, moneyIn: 0, moneyOut: 0, net: 0, expensesTotal: 0, expenseCount: 0, expenses: [], income: [], movements: [] });
    return days.get(day);
  };
  for (const e of entries) {
    const t = txById.get(String(e.transactionId));
    const amount = round(e.debit - e.credit);
    if (!amount) continue;
    const row = dayRow(istDay(t.date));
    const original = t.type === "reversal" ? originals.get(String(t.reverses)) : null;
    row.movements.push({
      _id: `${t._id}:${e._id}`,
      at: t.date,
      type: t.type,
      label: original ? `Reversed: ${MOVE_LABELS[original.type] || original.type}` : MOVE_LABELS[t.type] || t.type,
      memo: t.memo || "",
      note: t.note || "",
      account: fundName.get(String(e.accountId)) || "Fund",
      amount, // + came in, − went out
      method: t.method || "",
      reference: t.reference || "",
      by: people.get(String(t.createdBy)) || "",
      expenseId: t.expenseId || null,
    });
    row.net = round(row.net + amount);
    if (amount > 0) row.moneyIn = round(row.moneyIn + amount);
    else row.moneyOut = round(row.moneyOut - amount);
  }

  // Add Income: new money in (no source bank), or a transfer between my own accounts (total unchanged)
  const incomes = await CompanyIncome.find({ companyId, createdAt: { $gte: since } }).populate("createdBy", "name").lean();
  for (const i of incomes) {
    const row = dayRow(istDay(i.createdAt));
    const transfer = Boolean(i.sourceBankAccountId);
    row.income.push({
      _id: String(i._id),
      at: i.createdAt,
      kind: transfer ? "transfer" : "income",
      description: i.description || "",
      amount: round(i.amount),
      to: i.destinationType === "cash" ? cashName : i.destinationName || "Bank",
      from: transfer ? i.sourceName || "Bank" : i.sourceName || "New money",
      by: i.createdBy?.name || "",
    });
    if (!transfer) {
      row.moneyIn = round(row.moneyIn + i.amount);
      row.net = round(row.net + i.amount);
    }
  }

  // the period's expenses, by their own expense date (rejected and group expenses left out)
  const expenses = await Expense.find({ companyId, lifecycle: { $nin: [null, "rejected"] }, groupId: null, date: { $gte: since, $lt: untilEnd } })
    .select("description category amount date lifecycle status payerType logAs createdBy createdAt")
    .populate("createdBy", "name")
    .lean();
  for (const x of expenses) {
    const row = dayRow(istDay(x.date));
    row.expenses.push({
      _id: x._id,
      description: x.description,
      category: x.category,
      amount: round(x.amount),
      lifecycle: x.lifecycle,
      status: x.status,
      payerType: x.payerType,
      logAs: x.logAs,
      by: x.createdBy?.name || "",
      createdAt: x.createdAt,
    });
    row.expensesTotal = round(row.expensesTotal + x.amount);
    row.expenseCount += 1;
  }

  // walk back from today's real Cash + Bank: each day closes at what's left after undoing every later day
  const current = round(Number(company.cashBalance || 0) + (company.bankAccounts || []).reduce((s, b) => s + Number(b.balance || 0), 0));
  const sorted = [...days.values()].sort((a, b) => b.date.localeCompare(a.date));
  let running = current;
  for (const d of sorted) {
    d.closing = running;
    d.opening = round(running - d.net);
    running = d.opening;
  }
  const inRange = sorted.filter((d) => d.date >= fromDay && d.date <= toDay);
  const afterPeriod = sorted.filter((d) => d.date > toDay);
  const periodClosing = afterPeriod.length ? afterPeriod[afterPeriod.length - 1].opening : current;
  const periodOpening = round(periodClosing - inRange.reduce((s, d) => s + d.net, 0));
  for (const d of inRange) {
    d.expenses.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
    d.income.sort((a, b) => new Date(b.at) - new Date(a.at));
    d.movements.sort((a, b) => new Date(b.at) - new Date(a.at));
  }

  res.json({
    success: true,
    from: fromDay,
    to: toDay,
    currentBalance: current,
    summary: {
      opening: periodOpening,
      closing: periodClosing,
      moneyIn: round(inRange.reduce((s, d) => s + d.moneyIn, 0)),
      moneyOut: round(inRange.reduce((s, d) => s + d.moneyOut, 0)),
      expensesTotal: round(inRange.reduce((s, d) => s + d.expensesTotal, 0)),
      expenseCount: inRange.reduce((s, d) => s + d.expenseCount, 0),
    },
    days: inRange,
  });
});
