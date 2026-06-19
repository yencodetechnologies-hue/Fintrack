const mongoose = require("mongoose");

const reminderItemSchema = new mongoose.Schema({
  key: String,
  count: Number,
  times: [String],
});

const reminderSchema = new mongoose.Schema({
  userId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: "User",
    required: true,
  },

  cardId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: "Card",
    required: true,
  },
  bankName:{
  type: String,
  required:true,
  },
  amount:{
    type: Number,
    required: true,
  },
status: {
  type: String,
  enum: ["paid", "unpaid"],
  default: "unpaid"
},
  statementDate: Date,
  paymentDate: Date,

  reminders: [reminderItemSchema],
}, { timestamps: true });

module.exports = mongoose.model("Reminder", reminderSchema);