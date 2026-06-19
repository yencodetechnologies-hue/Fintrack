const mongoose = require("mongoose");

const notificationLogSchema = new mongoose.Schema(
  {
    message: {
      type: String,
      required: true,
    },
  },
  {
    timestamps: true,
  }
);

module.exports = mongoose.model(
  "NotificationLog",
  notificationLogSchema
);