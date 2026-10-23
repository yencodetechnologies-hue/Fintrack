// Live updates for the web and app (Socket.IO). Clients join a company's room; after any successful change the
// server tells that room which parts changed ({ companyId, topics }), and each screen reloads only what it shows.
// Topics: expenses, balances, funds, vouchers, loans, members, company, permissions, ledger (every change).
const { Server } = require("socket.io");
const Company = require("../models/company");
const CompanyMember = require("../models/companyMember");
const User = require("../models/user");
const Expense = require("../models/expense");
const CompanyLoan = require("../models/companyLoan");
const Voucher = require("../models/voucher");
const AdvanceReturn = require("../models/advanceReturn");
const { LedgerTransaction } = require("../models/ledger");
const { ExpenseGroup } = require("../models/expenseGroup");

let io = null;
const room = (companyId) => `company:${companyId}`;

async function isMember(companyId, userId) {
  if (!companyId || !userId) return false;
  const [user, company] = await Promise.all([
    User.findById(userId).select("platformRole").lean(),
    Company.findById(companyId).select("createdBy").lean(),
  ]);
  if (!company) return false;
  if (user?.platformRole === "super_admin" || String(company.createdBy) === String(userId)) return true;
  return Boolean(await CompanyMember.exists({ companyId, userId }));
}

function init(httpServer) {
  io = new Server(httpServer, { cors: { origin: true, credentials: true } });
  io.on("connection", (socket) => {
    // { companyId, userId }: only members of the company may listen to it
    socket.on("join", async ({ companyId, userId } = {}, ack) => {
      try {
        for (const r of socket.rooms) if (r.startsWith("company:")) socket.leave(r);
        const ok = await isMember(companyId, userId);
        if (ok) socket.join(room(companyId));
        if (typeof ack === "function") ack({ ok });
      } catch {
        if (typeof ack === "function") ack({ ok: false });
      }
    });
    socket.on("leave", ({ companyId } = {}) => companyId && socket.leave(room(companyId)));
  });
  return io;
}

// Tell everyone in these companies what changed. `exceptSocketId` is the device that made the change
// (it already reloads after its own action).
function emitChange(companyIds, topics, exceptSocketId) {
  if (!io) return;
  const payloadTopics = [...new Set([...topics, "ledger"])];
  for (const companyId of new Set(companyIds.filter(Boolean).map(String))) {
    let target = io.to(room(companyId));
    if (exceptSocketId) target = target.except(exceptSocketId);
    target.emit("company:changed", { companyId, topics: payloadTopics });
  }
}

const EXPENSE_TOPICS = ["expenses", "balances", "funds"];
const LOAN_TOPICS = ["loans", "balances", "funds", "expenses"];
const VOUCHER_TOPICS = ["vouchers", "balances", "funds", "expenses"];

// Which parts a write changes, from its path (relative to /api/ledger or /api/company-expense).
function topicsFor(base, path) {
  const p = path.toLowerCase();
  if (base === "ledger") {
    if (p.includes("/permissions")) return ["permissions"];
    if (/\/members|\/invites/.test(p)) return ["members"];
    if (/\/settings|\/categories|visibility-preference/.test(p)) return ["company"];
    if (/^\/vouchers|\/vouchers$|advance-returns/.test(p)) return VOUCHER_TOPICS;
    if (/^\/loans|routed-payments|payer-confirmation|^\/groups/.test(p)) return LOAN_TOPICS;
    if (/^\/reimbursements|^\/lend/.test(p)) return ["balances", "funds", "expenses"];
    if (/^\/transactions/.test(p)) return [...EXPENSE_TOPICS, "loans", "vouchers"];
    if (/^\/expenses/.test(p)) return EXPENSE_TOPICS;
    return [...EXPENSE_TOPICS, "loans", "vouchers"];
  }
  if (/bank-accounts|\/income|cash-account-name/.test(p)) return ["funds"];
  if (/\/member\/|\/join/.test(p)) return ["members"];
  if (/regenerate-code|touch-code|\/category/.test(p)) return ["company"];
  if (/^\/groups/.test(p)) return ["expenses"];
  return ["company", "expenses"];
}

// Companies a request touches, looked up BEFORE the handler runs (so deletes still resolve).
async function companiesFor(req) {
  const { params = {}, body = {}, query = {} } = req;
  const ids = [params.companyId, body.companyId, query.companyId, body.borrowerCompanyId, body.lenderCompanyId, body.sourceCompanyId];
  const path = req.path;
  const id = (re) => (path.match(re) || [])[1];
  const expenseId = id(/^\/expenses?\/([0-9a-f]{24})/i);
  const loanId = id(/^\/loans\/([0-9a-f]{24})/i);
  const voucherId = id(/^\/vouchers\/([0-9a-f]{24})/i);
  const txId = id(/^\/transactions\/([0-9a-f]{24})/i);
  const returnId = id(/^\/advance-returns\/([0-9a-f]{24})/i);
  const groupId = id(/^\/groups\/([0-9a-f]{24})/i);
  const companyInPath = id(/^\/compan(?:y|ies)\/([0-9a-f]{24})/i);
  ids.push(companyInPath);
  // joining by code: the company comes from its join code
  if (body.joinCode) ids.push((await Company.findOne({ joinCode: String(body.joinCode).trim() }).select("_id").lean())?._id);
  if (expenseId) {
    const e = await Expense.findById(expenseId).select("companyId payerCompanyId").lean();
    ids.push(e?.companyId, e?.payerCompanyId);
  }
  if (loanId) {
    const l = await CompanyLoan.findById(loanId).select("borrowerCompanyId lenderCompanyId").lean();
    ids.push(l?.borrowerCompanyId, l?.lenderCompanyId);
  }
  if (voucherId) ids.push((await Voucher.findById(voucherId).select("companyId").lean())?.companyId);
  if (returnId) ids.push((await AdvanceReturn.findById(returnId).select("companyId").lean())?.companyId);
  if (groupId) ids.push((await ExpenseGroup.findById(groupId).select("companyId").lean())?.companyId);
  if (txId) {
    const tx = await LedgerTransaction.findById(txId).select("companyId routeId").lean();
    ids.push(tx?.companyId);
    if (tx?.routeId) ids.push(...(await LedgerTransaction.find({ routeId: tx.routeId }).distinct("companyId")));
  }
  return ids.filter(Boolean).map(String);
}

// Express middleware for a router mounted at /api/<base>: after a successful write, announce it.
function announceWrites(base) {
  return async (req, res, next) => {
    if (req.method === "GET" || req.method === "OPTIONS" || !io) return next();
    let companies = [];
    try {
      companies = await companiesFor(req);
    } catch {
      companies = [];
    }
    const exceptSocketId = req.get("x-socket-id") || null;
    res.on("finish", () => {
      if (res.statusCode >= 200 && res.statusCode < 300 && companies.length) {
        emitChange(companies, topicsFor(base, req.path), exceptSocketId);
      }
    });
    next();
  };
}

module.exports = { init, emitChange, announceWrites };
