const express = require("express");
const router = express.Router();

const { signup, login,verifyOtp,forgotPassword,resetPassword,checkEmail, validateSession, updateFcmToken, deleteAccount, requestLoginOtp, verifyLoginOtp, removeFcmToken } = require("../controllers/authController");

router.post("/signup", signup);
router.post("/login", login);
router.post("/login-otp/request", requestLoginOtp);
router.post("/login-otp/verify", verifyLoginOtp);
router.post("/forgot-password", forgotPassword);
router.post("/verify-otp", verifyOtp);
router.post("/reset-password", resetPassword);
router.post("/check-email", checkEmail);
router.get("/session/:userId", validateSession);
router.post("/update-fcm-token", updateFcmToken);
router.post("/remove-fcm-token", removeFcmToken);
router.delete("/delete-account/:userId", deleteAccount);

module.exports = router;