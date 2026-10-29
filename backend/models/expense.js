const mongoose = require("mongoose");

const expenseSchema = new mongoose.Schema(
  {
    companyId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "Company",
      required: true,
    },
    createdBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      required: true,
    },
    isAdminCreated: { type: Boolean, default: undefined, index: true },
    amount: {
      type: Number,
      required: true,
      min: 0.01,
    },
    description: {
      type: String,
      required: true,
      trim: true,
    },
    category: {
      type: String,
      trim: true,
      default: "General",
    },
    date: {
      type: Date,
      default: Date.now,
    },
    attachment: {
      type: String,
      default: "",
    },
    hasAttachment: {
      type: Boolean,
      default: false,
    },
    status: {
      type: String,
      enum: ["outstanding", "paid"],
      default: "outstanding",
    },
    fundType: {
      type: String,
      enum: ["bank", "cash", ""],
      default: "",
    },
    fundBankAccountId: {
      type: mongoose.Schema.Types.ObjectId,
      default: null,
    },
    fundName: {
      type: String,
      default: "",
    },
    lifecycle: {
      type: String,
      enum: ["submitted", "approved", "rejected", "paid_by_admin", "paid_by_company", "paid_by_person", "awaiting_confirmation", "reimbursed", "paid_by_voucher"],
      default: null,
    },
    verification: { type: String, enum: [null, "pending", "verified"], default: null },
    approvedBy: { type: mongoose.Schema.Types.ObjectId, ref: "User", default: null },
    paidByAdminId: { type: mongoose.Schema.Types.ObjectId, ref: "User", default: null },
    paidByUserId: { type: mongoose.Schema.Types.ObjectId, ref: "User", default: null },
    payerType: { type: String, enum: [null, "person", "company", "other_company", "unpaid"], default: null },
    payerCompanyId: { type: mongoose.Schema.Types.ObjectId, ref: "Company", default: null },
    payerConfirmation: { type: String, enum: [null, "pending", "processing", "accepted", "rejected"], default: null },
    payerMethod: { type: String, default: "" },
    payerReference: { type: String, default: "" },
    paymentReceipt: { type: String, default: "" },
    hasPaymentReceipt: { type: Boolean, default: false },
    transactionId: { type: mongoose.Schema.Types.ObjectId, ref: "LedgerTransaction", default: null },
    groupId: { type: mongoose.Schema.Types.ObjectId, ref: "ExpenseGroup", default: null, index: true },
    // a voucher claim, or a staff expense that asked to be paid from the voucher balance (advance) they hold
    voucherId: { type: mongoose.Schema.Types.ObjectId, ref: "Voucher", default: null },
    // a voucher's expense keeps the voucher's date; this is when it was actually claimed / closed
    voucherSettledAt: { type: Date, default: null },
    voucherClosed: { type: Boolean, default: false },
    useAdvance: { type: Boolean, default: false },
    advanceUsed: { type: Number, default: 0 },
    logAs: {
      type: String,
      enum: ["company", "self"],
      default: "self",
    },
    parentExpenseId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "Expense",
      default: null,
    },
    manuallyReopened: {
      type: Boolean,
      default: false,
    },
    visibleTo: [
      {
        type: mongoose.Schema.Types.ObjectId,
        ref: "User",
      },
    ],
  },
  { timestamps: true }
);

expenseSchema.pre("save", function () {
  this.hasAttachment = Boolean(this.attachment && this.attachment.length > 0);
  this.hasPaymentReceipt = Boolean(this.paymentReceipt && this.paymentReceipt.length > 0);
});

expenseSchema.index({ companyId: 1, createdAt: -1 });
expenseSchema.index({ companyId: 1, lifecycle: 1, status: 1 });
expenseSchema.index({ payerCompanyId: 1, lifecycle: 1 });
expenseSchema.index({ companyId: 1, parentExpenseId: 1, lifecycle: 1 });

module.exports = mongoose.model("Expense", expenseSchema);

