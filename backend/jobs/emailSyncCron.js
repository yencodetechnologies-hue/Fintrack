const cron = require("node-cron");
const User = require("../models/user");
const { syncUser } = require("../services/gmailSyncService");

// Daily at 8:00 AM IST (2:30 AM UTC)
cron.schedule("30 2 * * *", async () => {
  console.log("📧 Running daily Gmail bill sync...");

  try {
    const users = await User.find({
      "gmailConnection.refreshTokenEnc": { $ne: null },
      "gmailConnection.syncEnabled": true,
    }).select("_id");

    for (const user of users) {
      try {
        const result = await syncUser(user._id, { skipRateLimit: true });
        console.log(`✅ Synced user ${user._id}: ${result.newBills} new bills`);
      } catch (err) {
        console.log(`❌ Sync failed for user ${user._id}:`, err.message);
      }
    }
  } catch (err) {
    console.log("❌ Email sync cron error:", err.message);
  }
});

module.exports = {};
