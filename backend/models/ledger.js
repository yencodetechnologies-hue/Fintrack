const mongoose = require("mongoose");
const { Schema } = mongoose;
const ObjectId = Schema.Types.ObjectId;

// bankAccountId: a Company.bankAccounts subdoc id, or null for the company's Cash account.
const accountSchema = new Schema(
  {
    companyId: { type: ObjectId, ref: "Company", required: true },
    type: { type: String, enum: ["bank", "expense", "admin_payable", "intercompany", "advance"], required: true },
    name: { type: String, required: true },
    bankAccountId: { type: ObjectId, default: null },
    category: { type: String, default: null },
    userId: { type: ObjectId, ref: "User", default: null },
    counterpartCompanyId: { type: ObjectId, ref: "Company", default: null },
  },
  { timestamps: true }
);
accountSchema.index({ companyId: 1, type: 1, bankAccountId: 1, category: 1, userId: 1, counterpartCompanyId: 1 }, { unique: true });

const transactionSchema = new Schema(
  {
    companyId: { type: ObjectId, ref: "Company", required: true },
    type: { type: String, enum: ["admin_paid", "company_paid", "borrowed", "reimburse", "lend", "intercompany", "routed", "loan_repayment", "reversal", "voucher_issue", "voucher_claim", "advance_used", "advance_offset", "advance_return"], required: true },
    date: { type: Date, default: Date.now },
    memo: { type: String, default: "" },
    note: { type: String, default: "" }, // the user's own description, kept apart from the generated memo
    method: { type: String, default: "" },
    reference: { type: String, default: "" },
    expenseId: { type: ObjectId, ref: "Expense", default: null },
    // a reimbursement aimed at one bill on a person's payable (the credit transaction it pays), see payableWalk
    settlesTransactionId: { type: ObjectId, default: null },
    loanId: { type: ObjectId, ref: "CompanyLoan", default: null },
    voucherId: { type: ObjectId, ref: "Voucher", default: null },
    advanceReturnId: { type: ObjectId, ref: "AdvanceReturn", default: null },
    routeId: { type: String, default: null },
    createdBy: { type: ObjectId, ref: "User", required: true },
    approvedBy: { type: ObjectId, ref: "User", default: null },
    reversedBy: { type: ObjectId, ref: "LedgerTransaction", default: null },
    verification: { type: String, enum: [null, "pending", "verified"], default: null },
    verifiedBy: { type: ObjectId, ref: "User", default: null },
    reverses: { type: ObjectId, ref: "LedgerTransaction", default: null },
  },
  { timestamps: true }
);

transactionSchema.index({ loanId: 1 });

const entrySchema = new Schema(
  {
    transactionId: { type: ObjectId, ref: "LedgerTransaction", required: true },
    accountId: { type: ObjectId, ref: "LedgerAccount", required: true },
    companyId: { type: ObjectId, ref: "Company", required: true },
    debit: { type: Number, default: 0, min: 0 },
    credit: { type: Number, default: 0, min: 0 },
  },
  { timestamps: true }
);
entrySchema.index({ accountId: 1 });

const auditSchema = new Schema(
  {
    companyId: { type: ObjectId, ref: "Company", default: null },
    userId: { type: ObjectId, ref: "User", required: true },
    action: { type: String, required: true },
    object: { type: String, required: true },
    objectId: { type: ObjectId, default: null },
    before: { type: Schema.Types.Mixed, default: null },
    after: { type: Schema.Types.Mixed, default: null },
  },
  { timestamps: { createdAt: "at", updatedAt: false } }
);
auditSchema.index({ companyId: 1, at: -1 });
auditSchema.index({ userId: 1, at: -1 });
auditSchema.index({ objectId: 1, action: 1 });

module.exports = {
  LedgerAccount: mongoose.model("LedgerAccount", accountSchema),
  LedgerTransaction: mongoose.model("LedgerTransaction", transactionSchema),
  LedgerEntry: mongoose.model("LedgerEntry", entrySchema),
  AuditLog: mongoose.model("AuditLog", auditSchema),
};
