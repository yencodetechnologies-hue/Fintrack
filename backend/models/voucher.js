const mongoose = require("mongoose");
const ObjectId = mongoose.Schema.Types.ObjectId;

// Money a manager hands a staff member up front. Funded by the company (taken from Cash/Bank now)
// or by the manager (the company then owes the manager). Claimed once; any leftover stays with the
// staff member as their advance balance.
const voucherSchema = new mongoose.Schema(
  {
    companyId: { type: ObjectId, ref: "Company", required: true },
    recipientId: { type: ObjectId, ref: "User", required: true },
    createdBy: { type: ObjectId, ref: "User", required: true },
    amount: { type: Number, required: true, min: 0.01 },
    purpose: { type: String, required: true, trim: true },
    fundedBy: { type: String, enum: ["company", "manager"], required: true },
    fundId: { type: String, default: null }, // "cash" or a Company.bankAccounts id, when funded by the company
    fundName: { type: String, default: "" },
    status: { type: String, enum: ["open", "claiming", "claimed", "cancelled"], default: "open" },
    claimedAmount: { type: Number, default: 0 },
    fromAdvance: { type: Number, default: 0 }, // part of the claim covered by the voucher and held balance
    owedToRecipient: { type: Number, default: 0 }, // claimed above what they held; the company owes it
    expenseId: { type: ObjectId, ref: "Expense", default: null },
    issueTxId: { type: ObjectId, ref: "LedgerTransaction", default: null },
    claimTxId: { type: ObjectId, ref: "LedgerTransaction", default: null },
    claimedAt: { type: Date, default: null },
    // set when the manager who created it closed it on the staff member's behalf
    closedBy: { type: ObjectId, ref: "User", default: null },
    closedAt: { type: Date, default: null },
    cancelledBy: { type: ObjectId, ref: "User", default: null },
    cancelledAt: { type: Date, default: null },
  },
  { timestamps: true }
);

voucherSchema.index({ companyId: 1, recipientId: 1, status: 1 });
voucherSchema.index({ companyId: 1, createdAt: -1 });

module.exports = mongoose.model("Voucher", voucherSchema);
