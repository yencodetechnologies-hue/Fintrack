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
      },
    ],
    customCategories: {
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
