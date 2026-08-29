const { ImapFlow } = require("imapflow");
const { simpleParser } = require("mailparser");
const User = require("../models/user");
const Card = require("../models/card");
const ParsedBill = require("../models/parsedBill");
const { decrypt } = require("../utils/tokenCrypto");
const { parseEmail } = require("./emailParsers");

async function syncYahooUser(userId) {
  const user = await User.findById(userId);
  if (!user || !user.yahooEmailSync || !user.yahooEmailSync.connected) {
    console.log(`🟣 [Yahoo Sync Service] Yahoo is not connected for userId: ${userId}`);
    return { parsedCount: 0, newBillCount: 0 };
  }

  const decryptedToken = decrypt(user.yahooEmailSync.accessToken);
  const yahooEmail = user.yahooEmailSync.yahooEmail;

  if (!decryptedToken || !yahooEmail) {
    console.warn(`⚠️ [Yahoo Sync Service] OAuth access token or Yahoo email missing for userId: ${userId}`);
    return { parsedCount: 0, newBillCount: 0 };
  }

  console.log(`🟣 [Yahoo IMAP Sync] Connecting to imap.mail.yahoo.com for ${yahooEmail}...`);

  const client = new ImapFlow({
    host: "imap.mail.yahoo.com",
    port: 993,
    secure: true,
    auth: {
      user: yahooEmail,
      accessToken: decryptedToken,
    },
    logger: false,
  });

  let parsedCount = 0;
  let newBillCount = 0;

  try {
    await client.connect();
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
