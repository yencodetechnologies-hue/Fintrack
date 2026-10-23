const mongoose = require("mongoose");
const User = require("../models/user");
const Card = require("../models/card");
const Reminder = require("../models/reminder");
const Lend = require("../models/lend");
const Liability = require("../models/liability");
const CompanyMember = require("../models/companyMember");
const CompanyInvite = require("../models/companyInvite");
const Company = require("../models/company");
const bcrypt = require("bcryptjs");
const nodemailer = require("nodemailer");

// A device token belongs to one account at a time, so a shared phone never gets the previous user's pushes.
const releaseTokenFromOthers = (userId, token) =>
  User.updateMany({ _id: { $ne: userId }, fcmTokens: token }, { $pull: { fcmTokens: token } });

// Companies that invited this email before it had an account get the new user as a member.
// Never fails signup: a broken invite is logged and skipped.
async function acceptPendingInvites(user) {
  try {
    const invites = await CompanyInvite.find({ email: String(user.email).trim().toLowerCase(), status: "pending" });
    for (const invite of invites) {
      const exists = await CompanyMember.exists({ companyId: invite.companyId, userId: user._id });
      if (!exists) {
        // join into the invited custom role if it still exists, otherwise as its base role
        let customRoleId = null;
        if (invite.customRoleId) {
          const company = await Company.findById(invite.companyId).select("customRoles").lean();
          if ((company?.customRoles || []).some((r) => String(r._id) === String(invite.customRoleId))) customRoleId = invite.customRoleId;
        }
        await CompanyMember.create({ companyId: invite.companyId, userId: user._id, role: invite.role, customRoleId });
      }
      invite.status = "accepted";
      invite.acceptedAt = new Date();
      await invite.save();
    }
  } catch (e) {
    console.error("accepting company invites failed:", e.message);
  }
}


  exports.signup = async (req, res) => {
    try {
      const { name, email, password, confirmPassword, fcmToken } = req.body;


      if (!name || !email || !password || !confirmPassword) {
        return res.status(400).json({ message: "All fields required" });
      }

      if (password !== confirmPassword) {
        return res.status(400).json({ message: "Passwords do not match" });
      }


      const existingUser = await User.findOne({ email });
      if (existingUser) {
        return res.status(400).json({ message: "User already exists" });
      }


      const hashedPassword = await bcrypt.hash(password, 10);


      const user = await User.create({
        name,
        email,
        password: hashedPassword,
        fcmTokens: fcmToken ? [fcmToken] : [],
      });

      await acceptPendingInvites(user);

      res.status(201).json({
        success: true,
        message: "User created successfully",
        userId: user._id,
      });
    } catch (error) {
      res.status(500).json({ message: error.message });
    }
  };

  exports.login = async (req, res) => {
    try {
      const { email, password, fcmToken } = req.body;

const isValidEmail = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
    if (!email || !isValidEmail) {
      return res.status(400).json({
        success: false,
        message: "Invalid email format",
      });
    }

      const user = await User.findOne({ email });
      if (!user) {
        return res.status(400).json({ message: "User not found" });
      }


      const isMatch = await bcrypt.compare(password, user.password);
      if (!isMatch) {
        return res.status(400).json({ message: "Invalid password" });
      }


      if (fcmToken) {
        await releaseTokenFromOthers(user._id, fcmToken);
        user.fcmTokens = [fcmToken, ...user.fcmTokens.filter((t) => t !== fcmToken)]
          .slice(0, 5);
        await user.save();
      }

      res.json({
        success: true,
        message: "Login successful",
        user: {
          id: user._id,
          name: user.name,
          email: user.email,
          fcmTokens: fcmToken ? [fcmToken] : [],
        },
      });
    } catch (error) {
      res.status(500).json({ message: error.message });
    }
  };

  const isValidEmail = (email) => {
    return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
  };

  exports.forgotPassword = async (req, res) => {
    try {
      const { email } = req.body;


      if (!email || !isValidEmail(email)) {
        return res.status(400).json({ message: "Invalid email format" });
      }


      const user = await User.findOne({ email });
      if (!user) {
        return res.status(404).json({ message: "Email not registered" });
      }


      const otp = Math.floor(100000 + Math.random() * 900000).toString();

      user.otp = otp;
      user.otpExpiry = Date.now() + 5 * 60 * 1000;
      await user.save();


      const transporter = nodemailer.createTransport({
        service: "gmail",
        auth: {
          user: process.env.SMTP_USER,
          pass: process.env.SMTP_PASS,
        },
      });


      await transporter.sendMail({
        from: process.env.SMTP_USER,
        to: email,
        subject: "OTP for Password Reset",
        html: `<h2>Your OTP is: ${otp}</h2><p>Valid for 5 minutes</p>`,
      });

      res.json({ success: true, message: "OTP sent to email" });

    } catch (error) {
      console.error(error);
      res.status(500).json({ message: "Error sending OTP" });
    }
  };
  exports.verifyOtp = async (req, res) => {
    try {
      const { email, otp } = req.body;

      const user = await User.findOne({ email });

      if (!user || user.otp !== otp) {
        return res.status(400).json({ message: "Invalid OTP" });
      }

      if (user.otpExpiry < Date.now()) {
        return res.status(400).json({ message: "OTP expired" });
      }

      res.json({ success: true, message: "OTP verified" });

    } catch (error) {
      res.status(500).json({ message: error.message });
    }
  };
  exports.resetPassword = async (req, res) => {
    try {
      const { email, newPassword } = req.body;

      const user = await User.findOne({ email });

      if (!user) {
        return res.status(404).json({ message: "User not found" });
      }


      const hashedPassword = await bcrypt.hash(newPassword, 10);

      user.password = hashedPassword;


      user.otp = null;
      user.otpExpiry = null;

      await user.save();

      res.json({ success: true, message: "Password reset successful" });

    } catch (error) {
      res.status(500).json({ message: error.message });
    }
  };
  exports.checkEmail = async (req, res) => {
    try {
      const { email } = req.body;

      if (!email) {
        return res.status(400).json({
          success: false,
          message: "Email required",
        });
      }

      if (!isValidEmail(email)) {
        return res.status(400).json({
          success: false,
          message: "Invalid email format",
        });
      }

      const user = await User.findOne({ email });

      return res.status(200).json({
        success: true,
        exists: !!user, // true = already registered
        message: user ? "Email already exists" : "Email available",
      });

    } catch (error) {
      return res.status(500).json({
        success: false,
        message: error.message,
        
      });
    }
  };

  exports.validateSession = async (req, res) => {
    try {
      const userId = String(req.params.userId || "").trim();

      if (!mongoose.Types.ObjectId.isValid(userId)) {
        return res.status(400).json({
          success: false,
          message: "Invalid userId",
        });
      }

      const user = await User.findById(userId).select("_id");
      if (!user) {
        return res.status(404).json({
          success: false,
          message: "User not found",
        });
      }

      return res.json({ success: true });
    } catch (error) {
      return res.status(500).json({ success: false, message: error.message });
    }
  };

  exports.updateFcmToken = async (req, res) => {
    try {
      const userId = String(req.body.userId || "").trim();
      const fcmToken = String(req.body.fcmToken || "").trim();

      if (!userId || !fcmToken) {
        return res.status(400).json({
          success: false,
          message: "userId and fcmToken are required",
        });
      }

      if (!mongoose.Types.ObjectId.isValid(userId)) {
        return res.status(400).json({
          success: false,
          message: "Invalid userId",
        });
      }

      const user = await User.findById(userId);
      if (!user) {
        return res.status(404).json({
          success: false,
          message: "User not found",
        });
      }

      await releaseTokenFromOthers(user._id, fcmToken);
      user.fcmTokens = [fcmToken, ...user.fcmTokens.filter((t) => t !== fcmToken)]
        .slice(0, 5);
      await user.save();

      res.json({
        success: true,
        message: "FCM token updated",
      });
    } catch (error) {
      res.status(500).json({ success: false, message: error.message });
    }
  };

  exports.deleteAccount = async (req, res) => {
    try {
      const { userId } = req.params;

      if (!userId) {
        return res.status(400).json({ success: false, message: "User ID is required" });
      }

      // Delete user details and all associated documents
      await Card.deleteMany({ userId });
      await Reminder.deleteMany({ userId });
      await Lend.deleteMany({ userId });
      await Liability.deleteMany({ userId });
      await User.findByIdAndDelete(userId);

      return res.status(200).json({
        success: true,
        message: "Account and all associated cards, reminders, and data deleted successfully",
      });
    } catch (error) {
      return res.status(500).json({
        success: false,
        message: error.message,
      });
    }
  };
// Passwordless sign-in: email a 6-digit code, then exchange it for the same user payload as /login.
exports.requestLoginOtp = async (req, res) => {
  try {
    const email = String(req.body.email || "").trim();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      return res.status(400).json({ success: false, message: "Invalid email format" });
    }
    const user = await User.findOne({ email });
    if (!user) return res.status(404).json({ success: false, message: "Email not registered" });

    const otp = Math.floor(100000 + Math.random() * 900000).toString();
    user.otp = otp;
    user.otpExpiry = Date.now() + 5 * 60 * 1000;
    await user.save();

    const transporter = nodemailer.createTransport({
      service: "gmail",
      auth: { user: process.env.SMTP_USER, pass: process.env.SMTP_PASS },
    });
    await transporter.sendMail({
      from: process.env.SMTP_USER,
      to: user.email,
      subject: "Your Q Fin sign-in code",
      html: `<h2>Your sign-in code is: ${otp}</h2><p>Valid for 5 minutes. If you didn't request this, ignore this email.</p>`,
    });
    res.json({ success: true, message: "Sign-in code sent to your email" });
  } catch (error) {
    console.error(error);
    res.status(500).json({ success: false, message: "Error sending sign-in code" });
  }
};

exports.verifyLoginOtp = async (req, res) => {
  try {
    const email = String(req.body.email || "").trim();
    const { otp, fcmToken } = req.body;
    const user = await User.findOne({ email });
    if (!user || !user.otp || user.otp !== String(otp || "").trim()) {
      return res.status(400).json({ success: false, message: "Invalid code" });
    }
    if (!user.otpExpiry || user.otpExpiry < Date.now()) {
      return res.status(400).json({ success: false, message: "Code expired. Request a new one." });
    }
    user.otp = null;
    user.otpExpiry = null;
    if (fcmToken) await releaseTokenFromOthers(user._id, fcmToken);
    if (fcmToken) user.fcmTokens = [fcmToken, ...(user.fcmTokens || []).filter((t) => t !== fcmToken)].slice(0, 5);
    await user.save();
    res.json({
      success: true,
      message: "Login successful",
      user: { id: user._id, name: user.name, email: user.email, fcmTokens: fcmToken ? [fcmToken] : [] },
    });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};


// Called on logout so this device stops receiving the signed-out user's notifications.
exports.removeFcmToken = async (req, res) => {
  try {
    const fcmToken = String(req.body.fcmToken || "").trim();
    if (!fcmToken) return res.status(400).json({ success: false, message: "fcmToken is required" });
    // the device is signed out of everyone, so drop it from every account (also clears older shared tokens)
    await User.updateMany({ fcmTokens: fcmToken }, { $pull: { fcmTokens: fcmToken } });
    res.json({ success: true, message: "Device unregistered" });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};
