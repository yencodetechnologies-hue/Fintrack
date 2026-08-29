const User = require("../models/user");
const { encrypt, decrypt } = require("../utils/tokenCrypto");

const YAHOO_AUTH_URL = "https://api.login.yahoo.com/oauth2/request_auth";
const YAHOO_TOKEN_URL = "https://api.login.yahoo.com/oauth2/get_token";
const YAHOO_USERINFO_URL = "https://api.login.yahoo.com/openid/v1/userinfo";

function getRedirectUri() {
  return process.env.YAHOO_REDIRECT_URI || "https://fintrack.yencodetechnologies.in/api/email/oauth/callback";
}

function getConnectUrl(userId) {
  console.log(`🟣 [Yahoo OAuth Service] Generating connect URL for userId: ${userId}`);
  const clientId = process.env.YAHOO_CLIENT_ID;
  if (!clientId) {
    console.error("🔴 [Yahoo OAuth Service] ERROR: YAHOO_CLIENT_ID is missing in .env");
    throw new Error("YAHOO_CLIENT_ID is not configured in backend/.env");
  }

  const primaryClientId = clientId.split("&")[0].split("JnM9")[0];
  const redirectUri = getRedirectUri();
  const encodedRedirectUri = encodeURIComponent(redirectUri);
  const encodedState = encodeURIComponent(`yahoo_${userId}`);
  const encodedScope = encodeURIComponent("openid email profile");

  const authUrl = `${YAHOO_AUTH_URL}?client_id=${primaryClientId}&redirect_uri=${encodedRedirectUri}&response_type=code&state=${encodedState}&scope=${encodedScope}&prompt=consent`;
  console.log(`🟣 [Yahoo OAuth Service] Redirect URI: ${redirectUri}`);
  console.log(`🟣 [Yahoo OAuth Service] Generated Auth URL: ${authUrl}`);
  return authUrl;
}

async function handleOAuthCallback(code, stateOrUserId) {
  const cleanUserId = String(stateOrUserId).replace(/^yahoo_/, "");
  console.log(`🟣 [Yahoo OAuth Service] Handling OAuth callback for userId: ${cleanUserId}`);
  
  const clientId = process.env.YAHOO_CLIENT_ID;
  const clientSecret = process.env.YAHOO_CLIENT_SECRET;
  if (!clientId || !clientSecret) {
    console.error("🔴 [Yahoo OAuth Service] ERROR: YAHOO_CLIENT_ID or YAHOO_CLIENT_SECRET missing in .env");
    throw new Error("YAHOO_CLIENT_ID or YAHOO_CLIENT_SECRET is missing in .env");
  }

  const primaryClientId = clientId.split("&")[0].split("JnM9")[0];
  const redirectUri = getRedirectUri();
  const basicAuth = Buffer.from(`${primaryClientId}:${clientSecret}`).toString("base64");

  console.log(`🟣 [Yahoo OAuth Service] Exchanging authorization code for access token at Yahoo Token Endpoint...`);
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
    console.error("🔴 [Yahoo OAuth Service] Token Exchange Failed:", response.status, tokenData);
    throw new Error(tokenData.error_description || tokenData.error || "Failed to retrieve access token from Yahoo");
  }

  console.log(`🟢 [Yahoo OAuth Service] Token exchange successful! Fetching Yahoo profile userinfo...`);
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
      console.log(`🟢 [Yahoo OAuth Service] Fetched Yahoo email: ${yahooEmail}`);
    } else {
      console.warn(`⚠️ [Yahoo OAuth Service] UserInfo response status: ${userInfoRes.status}`);
    }
  } catch (err) {
    console.warn("⚠️ [Yahoo OAuth Service] Could not fetch Yahoo userinfo:", err.message);
  }

  const encryptedAccess = encrypt(access_token);
  const encryptedRefresh = refresh_token ? encrypt(refresh_token) : "";
  const tokenExpiry = new Date(Date.now() + (expires_in || 3600) * 1000);

  const updatedUser = await User.findByIdAndUpdate(
    cleanUserId,
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
    console.error(`🔴 [Yahoo OAuth Service] User not found in database for ID: ${cleanUserId}`);
    throw new Error("User not found in database");
  }

  console.log(`✅ [Yahoo OAuth Service] Account linked & tokens saved successfully for userId: ${cleanUserId}`);
  return {
    success: true,
    yahooEmail: updatedUser.yahooEmailSync?.yahooEmail || yahooEmail,
  };
}

async function getYahooStatus(userId) {
  console.log(`🟣 [Yahoo OAuth Service] Checking status for userId: ${userId}`);
  const user = await User.findById(userId);
  if (!user || !user.yahooEmailSync) {
    console.log(`🟣 [Yahoo OAuth Service] Status result for ${userId}: connected=false`);
    return { connected: false };
  }

  const result = {
    connected: !!user.yahooEmailSync.connected,
    yahooEmail: user.yahooEmailSync.yahooEmail || null,
    lastSyncAt: user.yahooEmailSync.lastSyncAt || null,
  };
  console.log(`🟣 [Yahoo OAuth Service] Status result for ${userId}: connected=${result.connected}, email=${result.yahooEmail}`);
  return result;
}

async function disconnectYahoo(userId) {
  console.log(`🟣 [Yahoo OAuth Service] Disconnecting Yahoo account for userId: ${userId}`);
  await User.findByIdAndUpdate(userId, {
    $unset: { yahooEmailSync: 1 },
  });
  console.log(`✅ [Yahoo OAuth Service] Disconnected Yahoo account for userId: ${userId}`);
  return { success: true, message: "Yahoo disconnected successfully" };
}

module.exports = {
  getConnectUrl,
  handleOAuthCallback,
  getYahooStatus,
  disconnectYahoo,
};
