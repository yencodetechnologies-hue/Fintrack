const mongoose = require("mongoose");

const parsedBillSchema = new mongoose.Schema(
  {
    userId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      required: true,
      index: true,
    },
    cardId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "Card",
      default: null,
    },
    bankName: String,
    last4Digits: String,
    amount: Number,
    totalDue: Number,
    paymentDueDate: Date,
    statementDate: Date,
    sourceMessageId: {
      type: String,
      required: true,
    },
    emailSubject: String,
    confidence: {
      type: String,
      enum: ["high", "medium", "low"],
      default: "medium",
    },
    contentHash: String,
    status: {
      type: String,
      enum: ["pending", "applied", "dismissed"],
      default: "pending",
    },
  },
  { timestamps: true }
);

parsedBillSchema.index({ userId: 1, sourceMessageId: 1 }, { unique: true });

module.exports = mongoose.model("ParsedBill", parsedBillSchema);
