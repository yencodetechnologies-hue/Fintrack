const express = require("express");
const router = express.Router();
const yahooSyncController = require("../controllers/yahooSyncController");

router.get("/connect-url", yahooSyncController.getConnectUrl);
router.get("/oauth/callback", yahooSyncController.handleCallback);
router.get("/status/:userId", yahooSyncController.getStatus);
router.post("/disconnect", yahooSyncController.disconnect);

module.exports = router;
