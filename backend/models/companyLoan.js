const mongoose = require("mongoose");

const companyLoanSchema = new mongoose.Schema({
  borrowerCompanyId: { type: mongoose.Schema.Types.ObjectId, ref: "Company", required: true, index: true },
  lenderCompanyId: { type: mongoose.Schema.Types.ObjectId, ref: "Company", required: true, index: true },
  amount: { type: Number, required: true, min: 0.01 },
  source: { type: String, enum: ["direct", "expense", "group"], required: true },
  expenseId: { type: mongoose.Schema.Types.ObjectId, ref: "Expense", default: null },
  groupId: { type: mongoose.Schema.Types.ObjectId, ref: "ExpenseGroup", default: null },
  transactionIds: [{ type: mongoose.Schema.Types.ObjectId, ref: "LedgerTransaction" }],
  method: { type: String, default: "" },
  reference: { type: String, default: "" },
  note: { type: String, default: "" },
  repaymentLock: { type: Boolean, default: false },
  createdBy: { type: mongoose.Schema.Types.ObjectId, ref: "User", required: true },
}, { timestamps: true });

companyLoanSchema.index({ borrowerCompanyId: 1, lenderCompanyId: 1, createdAt: -1 });
module.exports = mongoose.model("CompanyLoan", companyLoanSchema);
