const mongoose = require("mongoose");

// An invite for someone with no account yet; it becomes a CompanyMember when that email signs up.
const companyInviteSchema = new mongoose.Schema(
  {
    companyId: { type: mongoose.Schema.Types.ObjectId, ref: "Company", required: true },
    email: { type: String, required: true, trim: true, lowercase: true },
    role: { type: String, enum: ["admin", "member"], default: "member" },
    // a custom role (Company.customRoles) to join into; role above is its base
    customRoleId: { type: mongoose.Schema.Types.ObjectId, default: null },
    invitedBy: { type: mongoose.Schema.Types.ObjectId, ref: "User", required: true },
    status: { type: String, enum: ["pending", "accepted"], default: "pending" },
    acceptedAt: { type: Date, default: null },
  },
  { timestamps: true }
);

companyInviteSchema.index({ companyId: 1, email: 1 }, { unique: true });
companyInviteSchema.index({ email: 1, status: 1 });

module.exports = mongoose.model("CompanyInvite", companyInviteSchema);
