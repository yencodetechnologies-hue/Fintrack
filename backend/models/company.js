const mongoose = require("mongoose");

const companySchema = new mongoose.Schema(
  {
    name: {
      type: String,
      required: true,
      trim: true,
    },
    details: {
      type: String,
      trim: true,
      default: "",
    },
    joinCode: {
      type: String,
      required: true,
      unique: true,
      trim: true,
    },
    createdBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      required: true,
    },
    bankAccounts: [
      {
        bankName: { type: String, required: true, trim: true },
        accountHolder: { type: String, trim: true, default: "" },
        accountNumber: { type: String, required: true, trim: true },
        ifsc: { type: String, trim: true, default: "" },
        balance: { type: Number, default: 0 },
      },
    ],
    gstin: { type: String, trim: true, default: "" },
    currency: { type: String, default: "INR" },
    verificationThreshold: { type: Number, default: null },
    external: { type: Boolean, default: false },
    cashBalance: {
      type: Number,
      default: 0,
    },
    cashAccountName: {
      type: String,
      trim: true,
      default: "InCash",
    },
    customCategories: {
      type: [String],
      default: [],
    },
    // built-in categories a manager removed for this company (built-ins live in the apps, so they are hidden, not deleted)
    hiddenCategories: {
      type: [String],
      default: [],
    },
    joinCodeCreatedAt: {
      type: Date,
    },
  },
  { timestamps: true }
);

module.exports = mongoose.model("Company", companySchema);
