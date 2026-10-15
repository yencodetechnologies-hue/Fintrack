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
      enum: ["submitted", "approved", "rejected", "paid_by_admin", "paid_by_company", "reimbursed"],
      default: null,
    },
    verification: { type: String, enum: [null, "pending", "verified"], default: null },
    approvedBy: { type: mongoose.Schema.Types.ObjectId, ref: "User", default: null },
    paidByAdminId: { type: mongoose.Schema.Types.ObjectId, ref: "User", default: null },
    transactionId: { type: mongoose.Schema.Types.ObjectId, ref: "LedgerTransaction", default: null },
    groupId: { type: mongoose.Schema.Types.ObjectId, default: null },
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

module.exports = mongoose.model("Expense", expenseSchema);
