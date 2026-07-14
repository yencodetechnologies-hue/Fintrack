const IOS_BUNDLE_ID = "com.yencode.fintracks";
const ANDROID_PACKAGE_NAME = "com.yencode.fintrack";

const INVALID_FCM_TOKEN_CODES = new Set([
  "messaging/registration-token-not-registered",
  "messaging/invalid-registration-token",
]);

function buildApnsConfig(title, body) {
  return {
    headers: {
      "apns-priority": "10",
      "apns-push-type": "alert",
      "apns-topic": IOS_BUNDLE_ID,
    },
    payload: {
      aps: {
        alert: {
          title,
          body,
        },
        sound: "default",
        badge: 1,
      },
    },
    fcmOptions: {
      analyticsLabel: "fintrack_notification",
    },
  };
}

function buildAndroidConfig(channelId = "payment_reminder") {
  return {
    priority: "high",
    notification: {
      channelId,
      sound: "default",
      icon: "ic_launcher",
      color: "#00D9FF",
      sticky: false,
      visibility: "public",
      notificationPriority: "PRIORITY_MAX",
      defaultSound: true,
      defaultVibrateTimings: true,
      ticker: "Card Payment Alert",
      tag: "payment-reminder",
    },
  };
}

function isInvalidFcmTokenError(error) {
  return INVALID_FCM_TOKEN_CODES.has(error?.code);
}

async function sendToUserTokens(user, messageFactory) {
  if (!user?.fcmTokens?.length) {
    return { sent: 0, removed: 0 };
  }

  const staleTokens = [];
  let sent = 0;

  for (const token of user.fcmTokens) {
    try {
      await messageFactory(token);
      sent += 1;
    } catch (error) {
      console.log("FCM send error:", error.code || error.message);
      if (isInvalidFcmTokenError(error)) {
        staleTokens.push(token);
      }
    }
  }

  if (staleTokens.length > 0) {
    user.fcmTokens = user.fcmTokens.filter(
      (token) => !staleTokens.includes(token)
    );
    await user.save();
  }

  return { sent, removed: staleTokens.length };
}

module.exports = {
  IOS_BUNDLE_ID,
  ANDROID_PACKAGE_NAME,
  buildApnsConfig,
  buildAndroidConfig,
  isInvalidFcmTokenError,
  sendToUserTokens,
};
