const express = require("express");
const router = express.Router();

const {
  createReminder,
  getReminders,
  updateReminder,
  deleteReminder,
  updateStatus, // ✅ ADD THIS
} = require("../controllers/reminderController");


router.post("/add", createReminder);

/// ✅ GET
router.get("/", getReminders);

/// ✅ UPDATE FULL REMINDER
router.put("/update/:id", updateReminder);

/// 🔥 ✅ UPDATE PAID / UNPAID STATUS (MAIN FIX)
router.put("/status", updateStatus);

/// ✅ DELETE
router.delete("/", deleteReminder);

module.exports = router;