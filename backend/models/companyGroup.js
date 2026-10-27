const mongoose = require("mongoose");

// A named set of companies kept together (e.g. "YD Group"). Purely for organising the companies list:
// every company stays a separate company with its own members, money and books. A company is in at most one group.
const companyGroupSchema = new mongoose.Schema(
  {
    name: { type: String, required: true, trim: true },
    companyIds: [{ type: mongoose.Schema.Types.ObjectId, ref: "Company" }],
    createdBy: { type: mongoose.Schema.Types.ObjectId, ref: "User", required: true },
  },
  { timestamps: true }
);

companyGroupSchema.index({ companyIds: 1 });

module.exports = mongoose.model("CompanyGroup", companyGroupSchema);
