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
    // feature switches per role, see utils/permissions.js ({ manager: { key: false }, staff: { key: false } }; missing = on)
    permissions: { type: mongoose.Schema.Types.Mixed, default: () => ({}) },
    // roles the primary admin created on top of Manager/Staff; permissions stores only switches that are ON (all start off)
    customRoles: [
      {
        name: { type: String, required: true, trim: true },
        base: { type: String, enum: ["manager", "staff"], required: true },
        permissions: { type: mongoose.Schema.Types.Mixed, default: () => ({}) },
        createdBy: { type: mongoose.Schema.Types.ObjectId, ref: "User" },
        createdAt: { type: Date, default: Date.now },
      },
    ],
    joinCodeCreatedAt: {
      type: Date,
    },
  },
  { timestamps: true }
);

module.exports = mongoose.model("Company", companySchema);
