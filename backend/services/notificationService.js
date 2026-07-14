const admin = require("../config/firebase");
const User = require("../models/user");

const DEFAULT_TITLE = "Q Fin Test";
const DEFAULT_BODY = "This is a test push notification from the Fintrack backend.";

function buildPushMessage({ title, body, data = {}, type = "test_notification" }) {
  return {
    notification: {
      title,
      body,
    },
    android: {
      priority: "high",
      notification: {
        channelId: "payment_reminder",
        sound: "default",
        color: "#00D9FF",
        defaultSound: true,
        defaultVibrateTimings: true,
      },
    },
    apns: {
      headers: {
        "apns-priority": "10",
      },
      payload: {
        aps: {
          sound: "default",
          badge: 1,
          alert: {
            title,
            body,
          },
        },
      },
    },
    data: {
      type,
      ...Object.fromEntries(
        Object.entries(data).map(([key, value]) => [key, String(value)])
      ),
    },
  };
}

async function sendPushToTokens(tokens, payload) {
  const results = [];

  for (const token of tokens) {
    try {
      const messageId = await admin.messaging().send({
        ...payload,
        token,
      });

      results.push({
        tokenSuffix: token.slice(-8),
        success: true,
        messageId,
      });
    } catch (error) {
      results.push({
        tokenSuffix: token.slice(-8),
        success: false,
        error: error.message,
      });
    }
  }

  return results;
}

async function sendTestNotification(user, { title, body } = {}) {
  const tokens = user.fcmTokens || [];

  if (!tokens.length) {
    return {
      sentCount: 0,
      failedCount: 0,
      results: [],
      message: "No FCM tokens registered for this user",
    };
  }

  const payload = buildPushMessage({
    title: title || DEFAULT_TITLE,
    body: body || DEFAULT_BODY,
    type: "test_notification",
    data: {
      userId: user._id.toString(),
      sentAt: new Date().toISOString(),
    },
  });

  const results = await sendPushToTokens(tokens, payload);
  const sentCount = results.filter((r) => r.success).length;
  const failedCount = results.length - sentCount;

  return {
    sentCount,
    failedCount,
    results,
    message:
      sentCount > 0
        ? `Test notification sent to ${sentCount} device(s)`
        : "Failed to send test notification",
  };
}

async function sendBroadcastNotification({ title, body } = {}) {
  const users = await User.find({
    fcmTokens: { $exists: true, $ne: [] },
  }).select("_id email fcmTokens");

  const uniqueTokens = [...new Set(
    users.flatMap((user) => (user.fcmTokens || []).filter(Boolean))
  )];

  if (!uniqueTokens.length) {
    return {
      userCount: users.length,
      deviceCount: 0,
      sentCount: 0,
      failedCount: 0,
      results: [],
      message: "No FCM tokens registered for any user",
    };
  }

  const payload = buildPushMessage({
    title: title || DEFAULT_TITLE,
    body: body || DEFAULT_BODY,
    type: "broadcast_notification",
    data: {
      sentAt: new Date().toISOString(),
      scope: "all_users",
    },
  });

  const results = await sendPushToTokens(uniqueTokens, payload);
  const sentCount = results.filter((r) => r.success).length;
  const failedCount = results.length - sentCount;

  return {
    userCount: users.length,
    deviceCount: uniqueTokens.length,
    sentCount,
    failedCount,
    results,
    message:
      sentCount > 0
        ? `Broadcast sent to ${sentCount} device(s) across ${users.length} user(s)`
        : "Failed to send broadcast notification",
  };
}

module.exports = {
  buildPushMessage,
  sendPushToTokens,
  sendTestNotification,
  sendBroadcastNotification,
};
