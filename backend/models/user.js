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

    gmailConnection: {
      googleEmail: { type: String, default: null },
      refreshTokenEnc: { type: String, default: null },
      accessToken: { type: String, default: null },
      accessTokenExpiry: { type: Date, default: null },
      connectedAt: { type: Date, default: null },
      lastSyncAt: { type: Date, default: null },
      syncEnabled: { type: Boolean, default: true },
    },

    yahooEmailSync: {
      connected: { type: Boolean, default: false },
      yahooEmail: { type: String, default: null },
      accessToken: { type: String, default: null },
      refreshToken: { type: String, default: null },
      tokenExpiry: { type: Date, default: null },
      lastSyncAt: { type: Date, default: null },
    },
  },
  { timestamps: true }
);

module.exports = mongoose.model("User", userSchema);