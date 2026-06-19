const express = require("express");
const router = express.Router();

const {
  getNotificationLogs,
} = require("../controllers/cronreminderController");

router.get("/notification-logs", getNotificationLogs);

module.exports = router;