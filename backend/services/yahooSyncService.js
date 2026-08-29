const { ImapFlow } = require("imapflow");
const { simpleParser } = require("mailparser");
const User = require("../models/user");
const Card = require("../models/card");
const ParsedBill = require("../models/parsedBill");
const { decrypt } = require("../utils/tokenCrypto");
const { parseEmail } = require("./emailParsers");

const YAHOO_TOKEN_URL = "https://api.login.yahoo.com/oauth2/get_token";

async function refreshYahooAccessToken(user) {
  const clientId = process.env.YAHOO_CLIENT_ID;
  const clientSecret = process.env.YAHOO_CLIENT_SECRET;
  const refreshToken = decrypt(user.yahooEmailSync?.refreshToken);

  if (!refreshToken) {
    throw new Error("No refresh token available for Yahoo user");
  }

  console.log(`🟣 [Yahoo Token Refresh] Refreshing access token for ${user.yahooEmailSync.yahooEmail}...`);
  const basicAuth = Buffer.from(`${clientId}:${clientSecret}`).toString("base64");
  const redirectUri = process.env.YAHOO_REDIRECT_URI || "https://fintrack.yencodetechnologies.in/api/email/oauth/callback";

  const params = new URLSearchParams({
    grant_type: "refresh_token",
    redirect_uri: redirectUri,
    refresh_token: refreshToken,
  });

  const response = await fetch(YAHOO_TOKEN_URL, {
    method: "POST",
    headers: {
      Authorization: `Basic ${basicAuth}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: params.toString(),
  });

  const data = await response.json();
  if (!response.ok || !data.access_token) {
    console.error("🔴 [Yahoo Token Refresh] Failed:", response.status, data);
    throw new Error(data.error_description || data.error || "Failed to refresh Yahoo access token");
  }

  const { encrypt } = require("../utils/tokenCrypto");
  const encryptedAccess = encrypt(data.access_token);
  const encryptedRefresh = data.refresh_token ? encrypt(data.refresh_token) : user.yahooEmailSync.refreshToken;
  const tokenExpiry = new Date(Date.now() + (data.expires_in || 3600) * 1000);

  user.yahooEmailSync.accessToken = encryptedAccess;
  user.yahooEmailSync.refreshToken = encryptedRefresh;
  user.yahooEmailSync.tokenExpiry = tokenExpiry;
  await user.save();

  console.log(`🟢 [Yahoo Token Refresh] Token refreshed successfully! Expires in ${data.expires_in}s`);
  return data.access_token;
}

async function syncYahooUser(userId) {
  const user = await User.findById(userId);
  if (!user || !user.yahooEmailSync || !user.yahooEmailSync.connected) {
    console.log(`🟣 [Yahoo Sync Service] Yahoo is not connected for userId: ${userId}`);
    return { parsedCount: 0, newBillCount: 0 };
  }

  let decryptedToken = decrypt(user.yahooEmailSync.accessToken);
  const yahooEmail = user.yahooEmailSync.yahooEmail;

  if (!decryptedToken || !yahooEmail) {
    console.warn(`⚠️ [Yahoo Sync Service] OAuth access token or Yahoo email missing for userId: ${userId}`);
    return { parsedCount: 0, newBillCount: 0 };
  }

  // Check if token is expired or close to expiry (within 5 minutes)
  const isExpired = user.yahooEmailSync.tokenExpiry && new Date(user.yahooEmailSync.tokenExpiry).getTime() - Date.now() < 300000;
  if (isExpired) {
    try {
      decryptedToken = await refreshYahooAccessToken(user);
    } catch (rErr) {
      console.warn("⚠️ Token refresh failed before IMAP connect:", rErr.message);
    }
  }

  console.log(`🟣 [Yahoo IMAP Sync] Connecting to imap.mail.yahoo.com for ${yahooEmail}...`);

  const decryptedAppPassword = user.yahooEmailSync.appPassword ? decrypt(user.yahooEmailSync.appPassword) : null;

  let authObject;
  if (decryptedAppPassword) {
    console.log(`🔑 [Yahoo IMAP Sync] Using Yahoo App Password for authentication...`);
    authObject = { user: yahooEmail, pass: decryptedAppPassword };
  } else {
    authObject = { user: yahooEmail, accessToken: decryptedToken };
  }

  let client = new ImapFlow({
    host: "imap.mail.yahoo.com",
    port: 993,
    secure: true,
    auth: authObject,
    logger: false,
  });

  let parsedCount = 0;
  let newBillCount = 0;

  let connected = false;
  try {
    await client.connect();
    connected = true;
  } catch (cErr) {
    console.warn(`⚠️ [Yahoo IMAP Sync] Initial IMAP connect failed: ${cErr.message}`);
    if (!decryptedAppPassword) {
      try {
        console.log(`🟣 [Yahoo IMAP Sync] Retrying with refreshed OAuth token...`);
        decryptedToken = await refreshYahooAccessToken(user);
        client = new ImapFlow({
          host: "imap.mail.yahoo.com",
          port: 993,
          secure: true,
          auth: {
            user: yahooEmail,
            accessToken: decryptedToken,
          },
          logger: false,
        });
        await client.connect();
        connected = true;
        console.log(`🟢 [Yahoo IMAP Sync] Reconnected successfully after token refresh!`);
      } catch (rfErr) {
        console.error(`🔴 [Yahoo IMAP Sync] Reconnect after token refresh failed:`, rfErr.message);
      }
    }
  }

  if (!connected) {
    console.error(`🔴 [Yahoo IMAP Sync] Could not establish IMAP connection for ${yahooEmail}`);
    user.yahooEmailSync.lastSyncAt = new Date();
    await user.save();
    return { parsedCount: 0, newBillCount: 0 };
  }

  try {
    console.log(`🟢 [Yahoo IMAP Sync] Connected to Yahoo IMAP! Accessing INBOX...`);

    const lock = await client.getMailboxLock("INBOX");
    try {
      const sinceDate = new Date();
      sinceDate.setDate(sinceDate.getDate() - 30);

      const messages = client.fetch({ since: sinceDate }, { source: true, envelope: true });
      for await (const message of messages) {
        let from = message.envelope?.from?.[0]?.address || "";
        let subject = message.envelope?.subject || "";
        let body = "";
        const messageId = message.envelope?.messageId || String(message.uid);

        if (message.source) {
          try {
            const parsed = await simpleParser(message.source);
            from = parsed.from?.text || from;
            subject = parsed.subject || subject;
            body = parsed.text || parsed.html || "";
          } catch (pErr) {
            console.warn(`⚠️ Error parsing MIME source for uid ${message.uid}:`, pErr.message);
          }
        }

        console.log(`🔍 [Yahoo IMAP Sync] Inspecting message: "${subject}" from: ${from}`);

        const bill = parseEmail({ from, subject, body, messageId });
        if (bill) {
          parsedCount++;
          console.log(`🎉 [Yahoo IMAP Sync] Found credit card bill!`, bill);

          const cards = await Card.find({ userId, status: "active" });
          const matchedCard = cards.find(
            (c) =>
              (bill.last4Digits && c.last4Digits === bill.last4Digits) ||
              (c.bankName && bill.bankName && c.bankName.toLowerCase().includes(bill.bankName.toLowerCase()))
          );

          const existing = await ParsedBill.findOne({ userId, messageId });
          if (!existing) {
            await ParsedBill.create({
              userId,
              cardId: matchedCard ? matchedCard._id : null,
              messageId,
              bankName: bill.bankName,
              last4Digits: bill.last4Digits,
              amount: bill.amount,
              totalDue: bill.totalDue,
              statementDate: bill.statementDate,
              paymentDueDate: bill.paymentDueDate,
              status: "pending",
              syncedAt: new Date(),
            });
            newBillCount++;
          }
        }
      }
    } finally {
      lock.release();
    }

    await client.logout();
    console.log(`✅ [Yahoo IMAP Sync] Completed! Parsed: ${parsedCount}, New Bills: ${newBillCount}`);
  } catch (err) {
    console.error("🔴 [Yahoo IMAP Sync] Connection or fetch error:", err.message);
  }

  user.yahooEmailSync.lastSyncAt = new Date();
  await user.save();

  return { parsedCount, newBillCount };
}

module.exports = { syncYahooUser };
