const mongoose = require("mongoose");

const companyMemberSchema = new mongoose.Schema(
  {
    companyId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "Company",
      required: true,
    },
    userId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      required: true,
    },
    role: {
      type: String,
      enum: ["admin", "member"],
      default: "member",
    },
    joinedAt: {
      type: Date,
      default: Date.now,
    },
    // where this person put the company in their own companies list (0 = top); null = never arranged
    sortOrder: { type: Number, default: null },
    // Removed from this person's own company list (Admin only). The company itself is untouched; Restore brings it back.
    hiddenFromList: {
      type: Boolean,
      default: false,
    },
    // Members this manager last unticked under "Visible To" when posting; new members stay visible.
    hiddenStaffIds: {
      type: [mongoose.Schema.Types.ObjectId],
      ref: "User",
      default: [],
    },
    // Set while this person's voucher balance (advance) is being changed, so two changes can't spend it twice.
    advanceLockAt: { type: Date, default: null },
    // a custom role the primary admin made (Company.customRoles); role above mirrors its base (manager-like = admin)
    customRoleId: { type: mongoose.Schema.Types.ObjectId, default: null },
    // made Admin by an Admin: full access exactly like the company creator (role above stays "admin")
    isAdmin: { type: Boolean, default: false },
  },
  { timestamps: true }
);

// Ensure unique user per company
companyMemberSchema.index({ companyId: 1, userId: 1 }, { unique: true });
companyMemberSchema.index({ userId: 1 });

module.exports = mongoose.model("CompanyMember", companyMemberSchema);
