const express = require("express");
const router = express.Router();
const {
  getConnectUrl,
  oauthCallback,
  connectWithAuthCode,
  getStatus,
  syncEmails,
  getSuggestions,
  applyBill,
  dismissBill,
  disconnect,
} = require("../controllers/emailSyncController");

const yahooSyncController = require("../controllers/yahooSyncController");

router.get("/connect-url", getConnectUrl);
router.get("/oauth/callback", oauthCallback);
router.post("/connect", connectWithAuthCode);
router.get("/status", getStatus);
router.post("/sync", syncEmails);
router.get("/suggestions", getSuggestions);
router.post("/apply", applyBill);
router.post("/dismiss", dismissBill);
router.delete("/disconnect", disconnect);

// Yahoo Endpoints
router.get("/yahoo-connect-url", yahooSyncController.getConnectUrl);
router.get("/yahoo-status/:userId", yahooSyncController.getStatus);
router.post("/yahoo-disconnect", yahooSyncController.disconnect);
router.post("/yahoo-connect-app-password", yahooSyncController.connectAppPassword);

module.exports = router;
