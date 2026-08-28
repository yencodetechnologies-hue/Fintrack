const { google } = require("googleapis");
const { encrypt, decrypt } = require("../utils/tokenCrypto");

const SCOPES = ["https://www.googleapis.com/auth/gmail.readonly"];

function getOAuth2Client() {
  return new google.auth.OAuth2(
    process.env.GOOGLE_CLIENT_ID,
    process.env.GOOGLE_CLIENT_SECRET,
    process.env.GOOGLE_REDIRECT_URI
  );
}

function getConnectUrl(userId) {
  const client = getOAuth2Client();
  return client.generateAuthUrl({
    access_type: "offline",
    prompt: "consent",
    scope: SCOPES,
    state: userId,
  });
}

async function exchangeCodeForTokens(code) {
  const client = getOAuth2Client();
  const { tokens } = await client.getToken(code);
  return tokens;
}

async function exchangeAuthCodeFromMobile(authCode) {
  try {
    const client = new google.auth.OAuth2(
      process.env.GOOGLE_CLIENT_ID,
      process.env.GOOGLE_CLIENT_SECRET,
      ""
    );
    const { tokens } = await client.getToken(authCode);
    return tokens;
  } catch (err) {
    const client = getOAuth2Client();
    const { tokens } = await client.getToken(authCode);
    return tokens;
  }
}

async function getGoogleEmail(accessToken) {
  const client = getOAuth2Client();
  client.setCredentials({ access_token: accessToken });
  const oauth2 = google.oauth2({ version: "v2", auth: client });
  const { data } = await oauth2.userinfo.get();
  return data.email;
}

function buildGmailConnection(tokens) {
  if (!tokens.refresh_token) {
    throw new Error("No refresh token received. Reconnect with consent.");
  }

  return {
    refreshTokenEnc: encrypt(tokens.refresh_token),
    accessToken: tokens.access_token || "",
    accessTokenExpiry: tokens.expiry_date
      ? new Date(tokens.expiry_date)
      : new Date(Date.now() + 3600 * 1000),
    connectedAt: new Date(),
    syncEnabled: true,
  };
}

async function getAuthenticatedGmailClient(user) {
  if (!user.gmailConnection?.refreshTokenEnc) {
    throw new Error("Gmail not connected");
  }

  const client = getOAuth2Client();
  const refreshToken = decrypt(user.gmailConnection.refreshTokenEnc);

  client.setCredentials({
    refresh_token: refreshToken,
    access_token: user.gmailConnection.accessToken,
    expiry_date: user.gmailConnection.accessTokenExpiry?.getTime(),
  });

  const isExpired =
    !user.gmailConnection.accessTokenExpiry ||
    user.gmailConnection.accessTokenExpiry <= new Date();

  if (isExpired) {
    const { credentials } = await client.refreshAccessToken();
    user.gmailConnection.accessToken = credentials.access_token;
    user.gmailConnection.accessTokenExpiry = credentials.expiry_date
      ? new Date(credentials.expiry_date)
      : new Date(Date.now() + 3600 * 1000);
    await user.save();
    client.setCredentials(credentials);
  }

  return google.gmail({ version: "v1", auth: client });
}

async function revokeTokens(user) {
  if (!user.gmailConnection?.accessToken) {
    return;
  }
  try {
    const client = getOAuth2Client();
    await client.revokeToken(user.gmailConnection.accessToken);
  } catch (err) {
    console.log("Token revoke skipped:", err.message);
  }
}

module.exports = {
  SCOPES,
  getConnectUrl,
  exchangeCodeForTokens,
  exchangeAuthCodeFromMobile,
  getGoogleEmail,
  buildGmailConnection,
  getAuthenticatedGmailClient,
  revokeTokens,
};
