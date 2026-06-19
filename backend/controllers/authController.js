const User = require("../models/user");
const Card = require("../models/card");
const Reminder = require("../models/reminder");
const Lend = require("../models/lend");
const Liability = require("../models/liability");
const bcrypt = require("bcryptjs");
const nodemailer = require("nodemailer");


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


      if (fcmToken && !user.fcmTokens.includes(fcmToken)) {
        user.fcmTokens.push(fcmToken);
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