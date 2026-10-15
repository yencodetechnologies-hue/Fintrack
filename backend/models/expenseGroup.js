const mongoose = require("mongoose");
const ObjectId = mongoose.Schema.Types.ObjectId;

const expenseGroupSchema = new mongoose.Schema(
  {
    companyId: { type: ObjectId, ref: "Company", required: true },
    name: { type: String, required: true, trim: true },
    project: { type: String, trim: true, default: "" },
    createdBy: { type: ObjectId, ref: "User", required: true },
    active: { type: Boolean, default: true },
    members: [{ type: ObjectId, ref: "User" }],
  },
  { timestamps: true }
);

const groupNoteSchema = new mongoose.Schema(
  {
    groupId: { type: ObjectId, ref: "ExpenseGroup", required: true },
    userId: { type: ObjectId, ref: "User", required: true },
    text: { type: String, required: true, trim: true },
  },
  { timestamps: true }
);

module.exports = {
  ExpenseGroup: mongoose.model("ExpenseGroup", expenseGroupSchema),
  GroupNote: mongoose.model("GroupNote", groupNoteSchema),
};
