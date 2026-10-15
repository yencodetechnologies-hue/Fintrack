const Company = require("../models/company");
const CompanyMember = require("../models/companyMember");
const Expense = require("../models/expense");
const User = require("../models/user");
const { LedgerAccount, LedgerTransaction, LedgerEntry, AuditLog } = require("../models/ledger");
const { ExpenseGroup, GroupNote } = require("../models/expenseGroup");
const { notifyUsers, notifyCompanyAdmins } = require("../services/ledgerNotify");

const fail = (status, message) => Object.assign(new Error(message), { status });

const handle = (fn) => async (req, res) => {
  try {
    await fn(req, res);
  } catch (e) {
    res.status(e.status || 500).json({ success: false, message: e.message });
  }
};

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

async function payableAccount(companyId, adminUserId) {
  const user = await User.findById(adminUserId).select("name");
  return getAccount(companyId, { type: "admin_payable", userId: adminUserId, name: `Payable to ${user ? user.name : "admin"}` });
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

const snapshot = (doc) => (doc ? JSON.parse(JSON.stringify(doc.toObject ? doc.toObject() : doc)) : null);

// FIFO: walk the admin's payable credits oldest first; expenses fully covered by reimbursements become "reimbursed".
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
      await Expense.updateOne(
        { _id: tx.expenseId, lifecycle: { $in: ["paid_by_admin", "reimbursed"] } },
        { $set: { lifecycle: covered ? "reimbursed" : "paid_by_admin" } }
      );
    }
  }
}

// ---------- expenses ----------
exports.createExpense = handle(async (req, res) => {
  const { companyId, userId, amount, description, category, date, attachment, groupId } = req.body;
  const value = parseFloat(amount);
  if (!companyId || !userId || !(value > 0) || !description || !String(description).trim()) {
    throw fail(400, "Company, amount and description are required");
  }
  const role = await requireRole(companyId, userId, ["employee", "admin", "super_admin"]);
  let group = null;
  if (groupId) {
    group = await ExpenseGroup.findOne({ _id: groupId, companyId, active: true });
    if (!group) throw fail(404, "Group not found");
    if (!isAdminRole(role) && !group.members.some((m) => m.toString() === userId.toString())) throw fail(403, "You are not in this group");
  }
  const expense = await Expense.create({
    groupId: group ? group._id : null,
    companyId,
    createdBy: userId,
    amount: value,
    description: String(description).trim(),
    category: category || "General",
    date: date ? new Date(date) : new Date(),
    attachment: attachment || "",
    lifecycle: "submitted",
    status: "outstanding",
  });
  await audit(userId, companyId, "create", "expense", expense._id, null, snapshot(expense));
  const poster = await User.findById(userId).select("name");
  const msg = { title: "Expense posted", body: `${poster?.name || "Someone"} posted ${expense.category} · ₹${expense.amount}`, data: { expenseId: expense._id, companyId } };
  await notifyCompanyAdmins(companyId, msg, userId);
  if (group) notifyUsers(group.members, { ...msg, title: `New expense in ${group.name}` }, userId);
  res.status(201).json({ success: true, expense });
});

exports.listExpenses = handle(async (req, res) => {
  const { companyId } = req.params;
  const { userId, lifecycle } = req.query;
  const role = await requireRole(companyId, userId, ["employee", "admin", "super_admin"]);
  const query = { companyId, lifecycle: { $ne: null } };
  if (!isAdminRole(role)) {
    const groups = await ExpenseGroup.find({ companyId, members: userId }).select("_id");
    query.$or = [{ createdBy: userId }, { groupId: { $in: groups.map((g) => g._id) } }];
  }
  if (lifecycle) query.lifecycle = lifecycle;
  const expenses = await Expense.find(query)
    .populate("createdBy", "name email")
    .populate("approvedBy", "name")
    .populate("paidByAdminId", "name")
    .sort({ createdAt: -1 });
  res.json({ success: true, role, expenses });
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
    { new: true }
  );
  if (!updated) throw fail(400, `Only submitted expenses can be ${target}`);
  await audit(userId, expense.companyId, target === "approved" ? "approve" : "reject", "expense", expense._id, before, snapshot(updated));
  res.json({ success: true, expense: updated });
}

exports.approveExpense = handle((req, res) => decide(req, res, "approved"));
exports.rejectExpense = handle((req, res) => decide(req, res, "rejected"));

exports.payExpense = handle(async (req, res) => {
  const { userId, payer, fundId, method, reference, sourceCompanyId, newCompany, sourceFundId } = req.body;
  if (!["admin", "company", "borrow"].includes(payer)) throw fail(400, "Choose Paid by me, Paid by company or Borrow");
  const expense = await Expense.findById(req.params.expenseId);
  if (!expense) throw fail(404, "Expense not found");
  const companyId = expense.companyId;
  await requireRole(companyId, userId, ["admin", "super_admin"]);

  const debit = await expenseAccount(companyId, expense.category);
  let source = null;
  let credit;
  if (payer === "admin") credit = await payableAccount(companyId, userId);
  else if (payer === "company") credit = await fundAccount(companyId, fundId);
  else {
    source = await resolveSourceCompany(userId, companyId, sourceCompanyId, newCompany);
    credit = await intercoAccount(companyId, source);
  }
  const sourceFund = source ? await fundAccount(source._id, source.external ? "cash" : sourceFundId) : null;

  const target = payer === "admin" ? "paid_by_admin" : "paid_by_company";
  const verification = (await needsVerification(companyId, expense.amount)) ? "pending" : null;

  // first admin to claim an approved expense locks it
  const before = snapshot(expense);
  const claimed = await Expense.findOneAndUpdate(
    { _id: expense._id, lifecycle: "approved" },
    { $set: { lifecycle: target, paidByAdminId: payer === "admin" ? userId : null, status: "paid", verification } },
    { new: true }
  );
  if (!claimed) throw fail(409, "This expense is not approved or has already been paid");

  const base = { method: method || "", reference: reference || "", expenseId: expense._id, createdBy: userId, verification };
  let txs;
  try {
    if (payer === "borrow") {
      const routeId = newRouteId();
      const company = await Company.findById(companyId).select("name");
      txs = await postAll([
        [
          { ...base, companyId, type: "borrowed", routeId, memo: `${expense.description} (borrowed from ${source.name})` },
          [{ account: debit, debit: expense.amount }, { account: credit, credit: expense.amount }],
        ],
        [
          { ...base, companyId: source._id, type: "intercompany", routeId, memo: `Paid for ${company.name}: ${expense.description}` },
          [{ account: await intercoAccount(source._id, company), debit: expense.amount }, { account: sourceFund, credit: expense.amount }],
        ],
      ]);
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
  await audit(userId, companyId, "pay", "expense", expense._id, before, snapshot(claimed));
  const payerName = (await User.findById(userId).select("name"))?.name || "An admin";
  const how = payer === "admin" ? "paid it themselves" : payer === "company" ? "paid it from company funds" : `paid it with money borrowed from ${source.name}`;
  await notifyCompanyAdmins(source ? [companyId, source._id] : companyId, {
    title: payer === "borrow" ? "Borrowed from another company" : "Expense paid",
    body: `${payerName} ${how}: ${expense.description} · ₹${expense.amount}`,
    data: { expenseId: expense._id, companyId },
  }, userId);
  if (verification) await notifyCompanyAdmins(companyId, { title: "Payment needs verification", body: `${expense.description} · ₹${expense.amount} paid by ${payerName}`, data: { transactionId: txs[0]._id, companyId } }, userId);
  res.json({ success: true, expense: claimed, transactions: txs });
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
  if (!isAdminRole(targetRole)) throw fail(400, "Reimbursements can only be made to an admin of this company");
  if (adminUserId.toString() === userId.toString() && role !== "super_admin") {
    throw fail(403, "Another admin must record your reimbursement");
  }
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
  await audit(userId, original.companyId, "reverse", "transaction", original._id, null, { reversals: reversals.map((r) => r._id) });
  res.json({ success: true, reversals });
});

// ---------- reads ----------
exports.balances = handle(async (req, res) => {
  const { companyId } = req.params;
  const { userId } = req.query;
  const role = await requireRole(companyId, userId, ["employee", "admin", "super_admin"]);
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
    .map((a) => ({ accountId: a._id, fundId: a.bankAccountId || "cash", name: a.name, balance: round(get(a).debit - get(a).credit) }));
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
  const logs = await AuditLog.find({ companyId }).populate("userId", "name").sort({ at: -1 }).limit(300);
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
  if (adminUserId.toString() === userId.toString() && role !== "super_admin") throw fail(403, "Another admin must record your reimbursement");
  const owed = await adminOwed(companyId, adminUserId);
  if (value > owed) throw fail(400, `Amount exceeds the open balance (₹${owed})`);

  const company = await Company.findById(companyId);
  const source = await resolveSourceCompany(userId, companyId, sourceCompanyId, newCompany);
  const routeId = newRouteId();
  const verification = (await needsVerification(companyId, value)) ? "pending" : null;
  const base = { method: method || "", reference: reference || "", createdBy: userId, routeId, verification };
  const txs = await postAll([
    [
      { ...base, companyId, type: "routed", memo: `Admin paid via ${source.name}` },
      [{ account: await payableAccount(companyId, adminUserId), debit: value }, { account: await intercoAccount(companyId, source), credit: value }],
    ],
    [
      { ...base, companyId: source._id, type: "intercompany", memo: `Paid admin of ${company.name}` },
      [{ account: await intercoAccount(source._id, company), debit: value }, { account: await fundAccount(source._id, source.external ? "cash" : sourceFundId), credit: value }],
    ],
  ]);
  await recomputeReimbursed(companyId, adminUserId);
  await audit(userId, companyId, "routed_payment", "transaction", txs[0]._id, null, { source: source._id, adminUserId, amount: value });
  notifyUsers([adminUserId], { title: "You were reimbursed", body: `₹${value} paid to you via ${source.name}`, data: { transactionId: txs[0]._id, companyId } });
  await notifyCompanyAdmins([companyId, source._id], { title: "Borrowed from another company", body: `${source.name} → ${company.name} → admin · ₹${value}`, data: { transactionId: txs[0]._id } }, userId);
  if (verification) await notifyCompanyAdmins(companyId, { title: "Payment needs verification", body: `Routed payment of ₹${value}`, data: { transactionId: txs[0]._id, companyId } }, userId);
  res.json({ success: true, transactions: txs, owed: await adminOwed(companyId, adminUserId) });
});

// Who owes whom, with a mismatch flag when the two mirror accounts disagree.
exports.intercompanyBalances = handle(async (req, res) => {
  const { companyId } = req.params;
  const { userId } = req.query;
  await requireRole(companyId, userId, ["admin", "super_admin"]);
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
  await requireRole(companyId, userId, ["admin", "super_admin"]);
  const people = [...new Set([...(await adminIds(companyId)), String(userId)])];
  const memberOf = (await CompanyMember.find({ userId: { $in: people } })).map((m) => m.companyId);
  const counterparts = await LedgerAccount.distinct("counterpartCompanyId", { companyId, type: "intercompany" });
  const companies = await Company.find({
    _id: { $ne: companyId },
    $or: [{ _id: { $in: [...memberOf, ...counterparts] } }, { createdBy: { $in: people } }],
  })
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
  const expQuery = { companyId, lifecycle: { $in: ["paid_by_admin", "paid_by_company", "reimbursed"] } };
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
    const logs = await AuditLog.find(period ? { at: period } : {}).populate("userId", "name").sort({ at: 1 }).lean();
    rows.push([], ["Audit log"], ["At", "User", "Action", "Object", "Object ID"]);
    for (const l of logs) rows.push([new Date(l.at).toISOString(), l.userId?.name, l.action, l.object, l.objectId]);
  }

  res.setHeader("Content-Type", "text/csv; charset=utf-8");
  res.setHeader("Content-Disposition", `attachment; filename="${full ? "full-audit" : "company-report"}.csv"`);
  res.send("﻿" + rows.map((r) => r.map(csvCell).join(",")).join("\r\n"));
});

// ---------- Slice 4: expense groups ----------
async function loadGroupFor(groupId, userId) {
  const group = await ExpenseGroup.findById(groupId);
  if (!group || !group.active) throw fail(404, "Group not found");
  const role = await requireRole(group.companyId, userId, ["employee", "admin", "super_admin"]);
  const isMember = group.members.some((m) => m.toString() === userId.toString());
  if (!isMember && !isAdminRole(role)) throw fail(403, "Only group members can see this group");
  return { group, role, isMember };
}

async function companyMemberIds(companyId) {
  const company = await Company.findById(companyId).select("createdBy");
  const ids = new Set((await CompanyMember.find({ companyId })).map((m) => m.userId.toString()));
  if (company?.createdBy) ids.add(company.createdBy.toString());
  return ids;
}

exports.createGroup = handle(async (req, res) => {
  const { companyId, userId, name, project, memberIds } = req.body;
  if (!name || !String(name).trim()) throw fail(400, "Group name is required");
  await requireRole(companyId, userId, ["employee", "admin", "super_admin"]);
  const valid = await companyMemberIds(companyId);
  const members = [...new Set([userId, ...(memberIds || [])].map(String))].filter((id) => valid.has(id));
  const group = await ExpenseGroup.create({ companyId, name: String(name).trim(), project: project || "", createdBy: userId, members });
  await audit(userId, companyId, "create", "group", group._id, null, { name: group.name, members });
  res.status(201).json({ success: true, group });
});

exports.listGroups = handle(async (req, res) => {
  const { companyId } = req.params;
  const { userId } = req.query;
  const role = await requireRole(companyId, userId, ["employee", "admin", "super_admin"]);
  const query = { companyId, active: true };
  if (!isAdminRole(role)) query.members = userId;
  const groups = await ExpenseGroup.find(query).sort({ createdAt: -1 }).lean();
  const totals = await Expense.aggregate([
    { $match: { groupId: { $in: groups.map((g) => g._id) }, lifecycle: { $ne: "rejected" } } },
    { $group: { _id: "$groupId", total: { $sum: "$amount" } } },
  ]);
  const t = new Map(totals.map((x) => [x._id.toString(), x.total]));
  res.json({
    success: true,
    groups: groups.map((g) => ({ ...g, memberCount: g.members.length, total: round(t.get(g._id.toString()) || 0) })),
  });
});

exports.groupDetail = handle(async (req, res) => {
  const { userId } = req.query;
  const { group } = await loadGroupFor(req.params.groupId, userId);
  await group.populate("members", "name email");
  const [expenses, notes] = await Promise.all([
    Expense.find({ groupId: group._id }).populate("createdBy", "name").sort({ createdAt: -1 }),
    GroupNote.find({ groupId: group._id }).populate("userId", "name").sort({ createdAt: -1 }).limit(100),
  ]);
  res.json({ success: true, group, expenses, notes, total: round(expenses.filter((e) => e.lifecycle !== "rejected").reduce((s, e) => s + e.amount, 0)) });
});

exports.addGroupMember = handle(async (req, res) => {
  const { userId, memberUserId } = req.body;
  const { group, isMember, role } = await loadGroupFor(req.params.groupId, userId);
  if (!isMember && !isAdminRole(role)) throw fail(403, "Only group members can invite staff");
  if (!(await companyMemberIds(group.companyId)).has(String(memberUserId))) throw fail(400, "That person is not in this company");
  await ExpenseGroup.updateOne({ _id: group._id }, { $addToSet: { members: memberUserId } });
  await audit(userId, group.companyId, "add_member", "group", group._id, null, { memberUserId });
  notifyUsers([memberUserId], { title: "Added to a group", body: `You were added to ${group.name}`, data: { groupId: group._id } });
  res.json({ success: true });
});

exports.addGroupNote = handle(async (req, res) => {
  const { userId, text } = req.body;
  if (!text || !String(text).trim()) throw fail(400, "Write a note first");
  const { group, isMember } = await loadGroupFor(req.params.groupId, userId);
  if (!isMember) throw fail(403, "Only group members can post notes");
  const note = await GroupNote.create({ groupId: group._id, userId, text: String(text).trim() });
  const author = (await User.findById(userId).select("name"))?.name || "Someone";
  notifyUsers(group.members, { title: group.name, body: `${author}: ${note.text}`, data: { groupId: group._id } }, userId);
  res.status(201).json({ success: true, note });
});
