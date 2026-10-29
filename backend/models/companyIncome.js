const mongoose = require("mongoose");

const companyIncomeSchema = new mongoose.Schema(
  {
    companyId: { type: mongoose.Schema.Types.ObjectId, ref: "Company", required: true },
    createdBy: { type: mongoose.Schema.Types.ObjectId, ref: "User", required: true },
    amount: { type: Number, required: true },
    description: { type: String, default: "" },
    destinationType: { type: String, enum: ["bank", "cash"], required: true },
    destinationBankAccountId: { type: mongoose.Schema.Types.ObjectId, default: null },
    destinationName: { type: String, default: "" },
    sourceBankAccountId: { type: mongoose.Schema.Types.ObjectId, default: null },
    sourceName: { type: String, default: "" },
  },
  { timestamps: true }
);

companyIncomeSchema.index({ companyId: 1, createdAt: -1 });

module.exports = mongoose.model("CompanyIncome", companyIncomeSchema);
