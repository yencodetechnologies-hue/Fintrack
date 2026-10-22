const mongoose = require("mongoose");
const ObjectId = mongoose.Schema.Types.ObjectId;

// A staff member handing unused voucher balance back to company Cash. Money moves only when a manager confirms.
const advanceReturnSchema = new mongoose.Schema(
  {
    companyId: { type: ObjectId, ref: "Company", required: true },
    userId: { type: ObjectId, ref: "User", required: true },
    amount: { type: Number, required: true, min: 0.01 },
    note: { type: String, default: "", trim: true },
    status: { type: String, enum: ["pending", "processing", "confirmed", "rejected", "reversed"], default: "pending" },
    decidedBy: { type: ObjectId, ref: "User", default: null },
    decidedAt: { type: Date, default: null },
    transactionId: { type: ObjectId, ref: "LedgerTransaction", default: null },
  },
  { timestamps: true }
);

advanceReturnSchema.index({ companyId: 1, status: 1, createdAt: -1 });

module.exports = mongoose.model("AdvanceReturn", advanceReturnSchema);
