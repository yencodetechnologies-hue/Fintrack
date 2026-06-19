const express = require("express");
const router = express.Router();

const { signup, login,verifyOtp,forgotPassword,resetPassword,checkEmail, deleteAccount } = require("../controllers/authController");

router.post("/signup", signup);
router.post("/login", login);
router.post("/forgot-password", forgotPassword);
router.post("/verify-otp", verifyOtp);
router.post("/reset-password", resetPassword);
router.post("/check-email", checkEmail);
router.delete("/delete-account/:userId", deleteAccount);

module.exports = router;