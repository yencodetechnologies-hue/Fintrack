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
    // Members this manager last unticked under "Visible To" when posting; new members stay visible.
    hiddenStaffIds: {
      type: [mongoose.Schema.Types.ObjectId],
      ref: "User",
      default: [],
    },
  },
  { timestamps: true }
);

// Ensure unique user per company
companyMemberSchema.index({ companyId: 1, userId: 1 }, { unique: true });

module.exports = mongoose.model("CompanyMember", companyMemberSchema);
