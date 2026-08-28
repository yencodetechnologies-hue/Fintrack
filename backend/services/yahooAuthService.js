const User = require("../models/user");
const { encrypt, decrypt } = require("../utils/tokenCrypto");

const YAHOO_AUTH_URL = "https://api.login.yahoo.com/oauth2/request_auth";
const YAHOO_TOKEN_URL = "https://api.login.yahoo.com/oauth2/get_token";
const YAHOO_USERINFO_URL = "https://api.login.yahoo.com/openid/v1/userinfo";

function getRedirectUri() {
  return process.env.YAHOO_REDIRECT_URI || "https://fintrack.yencodetechnologies.in/api/email/yahoo/oauth/callback";
}

function getConnectUrl(userId) {
  const clientId = process.env.YAHOO_CLIENT_ID;
  if (!clientId) {
    throw new Error("YAHOO_CLIENT_ID is not configured in backend/.env");
  }

  const redirectUri = getRedirectUri();
  const params = new URLSearchParams({
    client_id: clientId,
    redirect_uri: redirectUri,
    response_type: "code",
    state: userId,
    scope: "openid email profile",
  });

  return `${YAHOO_AUTH_URL}?${params.toString()}`;
}

async function handleOAuthCallback(code, userId) {
  const clientId = process.env.YAHOO_CLIENT_ID;
  const clientSecret = process.env.YAHOO_CLIENT_SECRET;
  if (!clientId || !clientSecret) {
    throw new Error("YAHOO_CLIENT_ID or YAHOO_CLIENT_SECRET is missing in .env");
  }

  const redirectUri = getRedirectUri();
  const basicAuth = Buffer.from(`${clientId}:${clientSecret}`).toString("base64");

  const params = new URLSearchParams({
    grant_type: "authorization_code",
    redirect_uri: redirectUri,
    code: code,
  });

  const response = await fetch(YAHOO_TOKEN_URL, {
    method: "POST",
    headers: {
      Authorization: `Basic ${basicAuth}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: params.toString(),
  });

  const tokenData = await response.json();
  if (!response.ok || !tokenData.access_token) {
    throw new Error(tokenData.error_description || tokenData.error || "Failed to retrieve access token from Yahoo");
  }

  const { access_token, refresh_token, expires_in } = tokenData;

  // Fetch Yahoo user info
  let yahooEmail = "";
  try {
    const userInfoRes = await fetch(YAHOO_USERINFO_URL, {
      headers: { Authorization: `Bearer ${access_token}` },
    });
    if (userInfoRes.ok) {
      const userInfo = await userInfoRes.json();
      yahooEmail = userInfo.email || userInfo.email_address || "";
    }
  } catch (err) {
    console.warn("Could not fetch Yahoo userinfo:", err.message);
  }

  const encryptedAccess = encrypt(access_token);
  const encryptedRefresh = refresh_token ? encrypt(refresh_token) : "";
  const tokenExpiry = new Date(Date.now() + (expires_in || 3600) * 1000);

  const updatedUser = await User.findByIdAndUpdate(
    userId,
    {
      "yahooEmailSync.connected": true,
      "yahooEmailSync.yahooEmail": yahooEmail,
      "yahooEmailSync.accessToken": encryptedAccess,
      "yahooEmailSync.refreshToken": encryptedRefresh,
      "yahooEmailSync.tokenExpiry": tokenExpiry,
      "yahooEmailSync.lastSyncAt": new Date(),
    },
    { new: true }
  );

  if (!updatedUser) {
    throw new Error("User not found in database");
  }

  return {
    success: true,
    yahooEmail: updatedUser.yahooEmailSync?.yahooEmail || yahooEmail,
  };
}

async function getYahooStatus(userId) {
  const user = await User.findById(userId);
  if (!user || !user.yahooEmailSync) {
    return { connected: false };
  }

  return {
    connected: !!user.yahooEmailSync.connected,
    yahooEmail: user.yahooEmailSync.yahooEmail || null,
    lastSyncAt: user.yahooEmailSync.lastSyncAt || null,
  };
}

async function disconnectYahoo(userId) {
  await User.findByIdAndUpdate(userId, {
    $unset: { yahooEmailSync: 1 },
  });
  return { success: true, message: "Yahoo disconnected successfully" };
}

module.exports = {
  getConnectUrl,
  handleOAuthCallback,
  getYahooStatus,
  disconnectYahoo,
};
