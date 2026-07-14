const express = require("express");
const router = express.Router();

const {
  getNotificationLogs,
} = require("../controllers/cronReminderController");

router.get("/notification-logs", getNotificationLogs);

module.exports = router;