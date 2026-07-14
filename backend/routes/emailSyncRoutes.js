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

router.get("/connect-url", getConnectUrl);
router.get("/oauth/callback", oauthCallback);
router.post("/connect", connectWithAuthCode);
router.get("/status", getStatus);
router.post("/sync", syncEmails);
router.get("/suggestions", getSuggestions);
router.post("/apply", applyBill);
router.post("/dismiss", dismissBill);
router.delete("/disconnect", disconnect);

module.exports = router;
