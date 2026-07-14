const express = require("express");
const router = express.Router();

const {
  sendTestNotification,
  sendBroadcastNotification,
} = require("../controllers/notificationController");

router.post("/test", sendTestNotification);
router.post("/broadcast", sendBroadcastNotification);

module.exports = router;
