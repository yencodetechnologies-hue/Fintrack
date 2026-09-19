const mongoose = require("mongoose");

const settlementSchema = new mongoose.Schema(
  {
    companyId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "Company",
      required: true,
    },
    expenseId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "Expense",
      required: true,
    },
    paidBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      required: true,
    },
    paidTo: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      required: true,
    },
    amount: {
      type: Number,
      required: true,
    },
    paymentMode: {
      type: String,
      enum: ["cash", "card", "upi", "bank_transfer", "other"],
      default: "cash",
    },
    paymentProof: {
      type: String,
      default: "",
    },
    bankAccountId: {
      type: mongoose.Schema.Types.ObjectId,
      default: null,
    },
    bankName: {
      type: String,
      default: "",
    },
    initiatedBy: {
      type: String,
      enum: ["payer", "receiver"],
      required: true,
    },
  },
  { timestamps: true }
);

module.exports = mongoose.model("Settlement", settlementSchema);
