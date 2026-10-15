const cron = require("node-cron");
const Expense = require("../models/expense");
const { LedgerTransaction, LedgerEntry } = require("../models/ledger");
const { notifyCompanyAdmins } = require("../services/ledgerNotify");

const PAYMENT_TYPES = ["admin_paid", "company_paid", "borrowed", "reimburse", "routed"];

const IST_OFFSET_MS = 5.5 * 60 * 60 * 1000;

// Midnight in India, whatever timezone the server itself runs in.
function startOfIndiaDay(now = new Date()) {
  const india = new Date(now.getTime() + IST_OFFSET_MS);
  india.setUTCHours(0, 0, 0, 0);
  return new Date(india.getTime() - IST_OFFSET_MS);
}

async function sendDayCloseSummaries() {
  const start = startOfIndiaDay();

  const expenses = await Expense.find({ lifecycle: { $ne: null }, createdAt: { $gte: start } }).select("companyId amount");
  const txs = await LedgerTransaction.find({ createdAt: { $gte: start }, type: { $in: PAYMENT_TYPES } }).select("companyId");
  const debits = await LedgerEntry.aggregate([
    { $match: { transactionId: { $in: txs.map((t) => t._id) } } },
    { $group: { _id: "$transactionId", amount: { $sum: "$debit" } } },
  ]);
  const amountByTx = new Map(debits.map((d) => [d._id.toString(), d.amount]));

  const byCompany = new Map();
  const bucket = (id) => {
    const key = id.toString();
    if (!byCompany.has(key)) byCompany.set(key, { posted: 0, postedTotal: 0, payments: 0, paidTotal: 0 });
    return byCompany.get(key);
  };
  for (const e of expenses) {
    const b = bucket(e.companyId);
    b.posted += 1;
    b.postedTotal += e.amount;
  }
  for (const t of txs) {
    const b = bucket(t.companyId);
    b.payments += 1;
    b.paidTotal += amountByTx.get(t._id.toString()) || 0;
  }

  for (const [companyId, b] of byCompany) {
    await notifyCompanyAdmins(companyId, {
      title: "Day-close summary",
      body: `${b.posted} expense(s) posted (₹${Math.round(b.postedTotal)}), ${b.payments} payment(s) made (₹${Math.round(b.paidTotal)}) today`,
      data: { companyId, summary: "day_close" },
    });
  }
}

cron.schedule("0 20 * * *", () => {
  sendDayCloseSummaries().catch((e) => console.error("day-close summary failed:", e.message));
}, { timezone: "Asia/Kolkata" });

module.exports = { sendDayCloseSummaries };
