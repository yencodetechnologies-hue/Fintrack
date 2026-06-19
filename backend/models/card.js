const mongoose = require("mongoose");

const cardSchema = new mongoose.Schema(
  {
    userId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
    },

    bankName: {
      type: String,
    },

    cardName: {
      type: String,
    },

    last4digits: {
      type: String,
      match: /^[0-9]{4}$/,
    },

    statementDate: {
      type: Date,
    },

    paymentDueDate: {
      type: Date
      ,
    },

    status: {
      type: String,
      enum: ["active", "inactive"],
      default: "active",
    },
  },
  { timestamps: true }
);

module.exports = mongoose.model("Card", cardSchema);