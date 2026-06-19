const mongoose = require("mongoose");

const userSchema = new mongoose.Schema(
  {
    name: {
      type: String,
      required: true,
      trim: true,
    },

    email: {
      type: String,
      required: true,
      unique: true,
      trim: true,
    },

    password: {
      type: String,
      required: true,
    },

    fcmTokens: {
        type: [String],
        default: [],
      },
      otp: {
            type: String,
            default: null,
          },

          otpExpiry: {
            type: Date,
            default: null,
          },


          otpVerified: {
            type: Boolean,
            default: false,
          },
  },
  { timestamps: true }
);

module.exports = mongoose.model("User", userSchema);