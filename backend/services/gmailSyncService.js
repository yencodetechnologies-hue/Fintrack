const { simpleParser } = require("mailparser");
const ParsedBill = require("../models/parsedBill");
const Card = require("../models/card");
const User = require("../models/user");
const admin = require("../config/firebase");
const {
  buildApnsConfig,
  sendToUserTokens,
} = require("../utils/fcmNotifications");
const { parseEmail, GMAIL_SEARCH_QUERY } = require("./emailParsers");
const { banksMatch, hashContent } = require("./emailParsers/helpers");
const { getAuthenticatedGmailClient } = require("./gmailAuthService");

const syncRateLimit = new Map();
const SYNC_COOLDOWN_MS = 5 * 60 * 1000;

function checkRateLimit(userId) {
  // Disabled rate limiting for testing
  return;
}

function decodeBase64Url(data) {
  const normalized = data.replace(/-/g, "+").replace(/_/g, "/");
  return Buffer.from(normalized, "base64").toString("utf8");
}

async function extractEmailBody(payload) {
  if (!payload) return { subject: "", body: "", from: "" };

  let subject = "";
  let from = "";
  let body = "";

  if (payload.headers) {
    for (const header of payload.headers) {
      if (header.name.toLowerCase() === "subject") subject = header.value;
      if (header.name.toLowerCase() === "from") from = header.value;
    }
  }

  async function walk(part) {
    if (!part) return;

    if (part.mimeType === "text/plain" && part.body?.data) {
      body += decodeBase64Url(part.body.data);
    }

    if (part.mimeType === "text/html" && part.body?.data && !body) {
      body += decodeBase64Url(part.body.data);
    }

    if (part.parts) {
      for (const child of part.parts) {
        await walk(child);
      }
    }
  }

  if (payload.body?.data) {
    body = decodeBase64Url(payload.body.data);
  }

  await walk(payload);

  if (!body && payload.body?.data) {
    body = decodeBase64Url(payload.body.data);
  }

  return { subject, body, from };
}

function matchCard(cards, parsed) {
  if (!cards.length) return null;

  if (parsed.last4Digits) {
    const byLast4 = cards.filter(
      (c) => c.last4digits === parsed.last4Digits && banksMatch(c.bankName, parsed.bankName)
    );
    if (byLast4.length === 1) return byLast4[0];
    if (byLast4.length > 1) return byLast4[0];
  }

  const byBank = cards.filter((c) => banksMatch(c.bankName, parsed.bankName));
  if (byBank.length === 1) return byBank[0];
  return null;
}

async function sendNewBillNotification(user, parsed, card) {
  if (!user.fcmTokens?.length) return;

  const last4 = parsed.last4Digits || card?.last4digits || "****";
  const dueStr = parsed.paymentDueDate
    ? new Date(parsed.paymentDueDate).toLocaleDateString("en-IN")
    : "soon";
  const title = "New bill detected";
  const body = `${parsed.bankName} •••• ${last4} — ₹${parsed.amount || "?"} due ${dueStr}`;

  await sendToUserTokens(user, async (token) => {
    await admin.messaging().send({
      token,
      notification: { title, body },
      apns: buildApnsConfig(title, body),
      data: {
        type: "bill_detected",
        bankName: parsed.bankName,
        parsedBillId: parsed._id.toString(),
      },
    });
  });
}

async function syncUser(userId, { skipRateLimit = false } = {}) {
  if (!skipRateLimit) {
    checkRateLimit(userId.toString());
  }

  const user = await User.findById(userId);
  if (!user?.gmailConnection?.refreshTokenEnc) {
    throw new Error("Gmail not connected");
  }

  const gmail = await getAuthenticatedGmailClient(user);
  const listRes = await gmail.users.messages.list({
    userId: "me",
    q: GMAIL_SEARCH_QUERY,
    maxResults: 30,
  });

  const messages = listRes.data.messages || [];
  const cards = await Card.find({ userId, status: "active" });
  const results = [];
  let newBillCount = 0;

  for (const msg of messages) {
    const full = await gmail.users.messages.get({
      userId: "me",
      id: msg.id,
      format: "full",
    });

    const { subject, body, from } = await extractEmailBody(full.data.payload);
    const parsed = parseEmail({
      from,
      subject,
      body,
      messageId: msg.id,
    });

    if (!parsed) continue;

    const contentHash = hashContent(`${msg.id}:${parsed.amount}:${parsed.paymentDueDate}`);

    const existing = await ParsedBill.findOne({
      userId,
      sourceMessageId: msg.id,
    });

    if (existing) {
      results.push(existing);
      continue;
    }

    const matchedCard = matchCard(cards, parsed);

    const bill = await ParsedBill.create({
      userId,
      cardId: matchedCard?._id || null,
      bankName: parsed.bankName,
      last4Digits: parsed.last4Digits,
      amount: parsed.amount,
      totalDue: parsed.totalDue,
      paymentDueDate: parsed.paymentDueDate,
      statementDate: parsed.statementDate,
      sourceMessageId: parsed.sourceMessageId,
      emailSubject: subject,
      confidence: parsed.confidence,
      contentHash,
      status: "pending",
    });

    results.push(bill);
    newBillCount += 1;

    if (matchedCard) {
      await sendNewBillNotification(user, bill, matchedCard);
    }
  }

  user.gmailConnection.lastSyncAt = new Date();
  await user.save();

  return {
    synced: results.length,
    newBills: newBillCount,
    suggestions: results.filter((b) => b.status === "pending"),
  };
}

module.exports = { syncUser, matchCard, checkRateLimit };
