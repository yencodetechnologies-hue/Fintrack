const mongoose = require("mongoose");

const lendSchema = new mongoose.Schema({

  userId: {
    type: String,
    required: true,
  },

  userName: {
    type: String,
    required: true,
  },

  name: {
    type: String,
    required: true,
  },

  reason: {
    type: String,
    required: true,
  },

  amount: {
    type: Number,
    required: true,
  },

  date: {
    type: String,
    required: true,
  },

  isReceived: {
    type: Boolean,
    default: false,
  },

  createdAt: {
    type: Date,
    default: Date.now,
  },

});

module.exports = mongoose.model("Lend", lendSchema);