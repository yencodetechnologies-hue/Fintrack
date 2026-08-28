const mongoose = require("mongoose");
const User = require("../models/user");
const Card = require("../models/card");
const ParsedBill = require("../models/parsedBill");
const {
  getConnectUrl,
  exchangeCodeForTokens,
  exchangeAuthCodeFromMobile,
  getGoogleEmail,
  buildGmailConnection,
  revokeTokens,
} = require("../services/gmailAuthService");
const { syncUser } = require("../services/gmailSyncService");

async function saveTokensForUser(userId, tokens) {
  const user = await User.findById(userId);
  if (!user) {
    throw new Error("User not found");
  }

  const connection = buildGmailConnection(tokens);
  connection.googleEmail = await getGoogleEmail(tokens.access_token);

  user.gmailConnection = connection;
  await user.save();
  return user;
}

exports.getConnectUrl = async (req, res) => {
  try {
    const { userId } = req.query;
    if (!userId || !mongoose.Types.ObjectId.isValid(userId)) {
      return res.status(400).json({ success: false, message: "Valid userId required" });
    }

    const url = getConnectUrl(userId);
    return res.status(200).json({ success: true, url });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
};

exports.oauthCallback = async (req, res) => {
  try {
    const { code, state: userId, error } = req.query;
    const successUrl = process.env.APP_OAUTH_SUCCESS_URL || "fintrack://oauth/success";
    const errorUrl = process.env.APP_OAUTH_ERROR_URL || "fintrack://oauth/error";

    if (error) {
      return res.redirect(`${errorUrl}?reason=${encodeURIComponent(error)}`);
    }

    if (!code || !userId) {
      return res.redirect(`${errorUrl}?reason=missing_code_or_user`);
    }

    const tokens = await exchangeCodeForTokens(code);
    await saveTokensForUser(userId, tokens);

    return res.redirect(`${successUrl}?connected=true`);
  } catch (err) {
    const errorUrl = process.env.APP_OAUTH_ERROR_URL || "fintrack://oauth/error";
    return res.redirect(`${errorUrl}?reason=${encodeURIComponent(err.message)}`);
  }
};

exports.connectWithAuthCode = async (req, res) => {
  try {
    const { userId, authCode } = req.body;

    if (!userId || !authCode) {
      return res.status(400).json({
        success: false,
        message: "userId and authCode are required",
      });
    }

    if (!mongoose.Types.ObjectId.isValid(userId)) {
      return res.status(400).json({ success: false, message: "Invalid userId" });
    }

    const tokens = await exchangeAuthCodeFromMobile(authCode);
    const user = await saveTokensForUser(userId, tokens);

    return res.status(200).json({
      success: true,
      message: "Gmail connected successfully",
      googleEmail: user.gmailConnection.googleEmail,
      connectedAt: user.gmailConnection.connectedAt,
    });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
};

exports.getStatus = async (req, res) => {
  try {
    const { userId } = req.query;

    if (!userId || !mongoose.Types.ObjectId.isValid(userId)) {
      return res.status(400).json({ success: false, message: "Valid userId required" });
    }

    const user = await User.findById(userId).select("gmailConnection");
    if (!user) {
      return res.status(404).json({ success: false, message: "User not found" });
    }

    const connected = Boolean(user.gmailConnection?.refreshTokenEnc);

    return res.status(200).json({
      success: true,
      connected,
      googleEmail: user.gmailConnection?.googleEmail || null,
      connectedAt: user.gmailConnection?.connectedAt || null,
      lastSyncAt: user.gmailConnection?.lastSyncAt || null,
      syncEnabled: user.gmailConnection?.syncEnabled ?? false,
    });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
};

exports.syncEmails = async (req, res) => {
  try {
    const { userId } = req.body;

    if (!userId || !mongoose.Types.ObjectId.isValid(userId)) {
      return res.status(400).json({ success: false, message: "Valid userId required" });
    }

    const result = await syncUser(userId);

    return res.status(200).json({
      success: true,
      message: "Gmail sync completed",
      ...result,
    });
  } catch (err) {
    const status = err.message.includes("wait") ? 429 : 500;
    return res.status(status).json({ success: false, message: err.message });
  }
};

exports.getSuggestions = async (req, res) => {
  try {
    const { userId } = req.query;

    if (!userId || !mongoose.Types.ObjectId.isValid(userId)) {
      return res.status(400).json({ success: false, message: "Valid userId required" });
    }

    const Reminder = require("../models/reminder");
    const activeReminders = await Reminder.find({ userId });

    const allBills = await ParsedBill.find({
      userId,
      status: { $ne: "dismissed" },
    })
      .populate("cardId")
      .sort({ createdAt: -1 })
      .limit(50);

    const uniqueBills = [];
    const seenKeys = new Set();
    for (const bill of allBills) {
      const dueKey = bill.paymentDueDate ? new Date(bill.paymentDueDate).toISOString().split('T')[0] : 'no_due';
      const key = `${bill.bankName || 'bank'}_${bill.last4Digits || 'last4'}_${bill.amount || 0}_${dueKey}`;
      if (!seenKeys.has(key)) {
        seenKeys.add(key);
        uniqueBills.push(bill);
      } else {
        await ParsedBill.deleteOne({ _id: bill._id });
      }
    }

    const pendingSuggestions = uniqueBills.filter((bill) => {
      const isReminderSet = activeReminders.some((rem) => {
        const remCardId = rem.cardId?._id ? rem.cardId._id.toString() : rem.cardId?.toString();
        const billCardId = bill.cardId?._id ? bill.cardId._id.toString() : bill.cardId?.toString();
        const sameCard = remCardId && billCardId && remCardId === billCardId;
        const sameAmount = Number(rem.amount) === Number(bill.amount);
        return sameCard || sameAmount;
      });
      return !isReminderSet;
    });

    return res.status(200).json({
      success: true,
      data: pendingSuggestions,
    });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
};

exports.applyBill = async (req, res) => {
  try {
    const { userId, parsedBillId, cardId } = req.body;

    if (!userId || !parsedBillId) {
      return res.status(400).json({
        success: false,
        message: "userId and parsedBillId are required",
      });
    }

    const bill = await ParsedBill.findOne({ _id: parsedBillId, userId });
    if (!bill) {
      return res.status(404).json({ success: false, message: "Bill not found" });
    }

    let card = null;
    const targetCardId = cardId || bill.cardId;

    if (targetCardId) {
      card = await Card.findOne({ _id: targetCardId, userId });
      if (card) {
        if (bill.statementDate) card.statementDate = bill.statementDate;
        if (bill.paymentDueDate) card.paymentDueDate = bill.paymentDueDate;
        await card.save();
        bill.cardId = card._id;
      }
    }

    bill.status = "applied";
    await bill.save();

    return res.status(200).json({
      success: true,
      message: "Bill applied to card",
      data: {
        parsedBill: bill,
        card,
        prefill: {
          bankName: bill.bankName,
          cardId: bill.cardId,
          amount: bill.amount,
          totalDue: bill.totalDue,
          statementDate: bill.statementDate,
          paymentDate: bill.paymentDueDate,
        },
      },
    });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
};

exports.dismissBill = async (req, res) => {
  try {
    const { userId, parsedBillId } = req.body;

    const bill = await ParsedBill.findOneAndUpdate(
      { _id: parsedBillId, userId },
      { status: "dismissed" },
      { new: true }
    );

    if (!bill) {
      return res.status(404).json({ success: false, message: "Bill not found" });
    }

    return res.status(200).json({ success: true, data: bill });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
};

exports.disconnect = async (req, res) => {
  try {
    const { userId } = req.query;

    if (!userId || !mongoose.Types.ObjectId.isValid(userId)) {
      return res.status(400).json({ success: false, message: "Valid userId required" });
    }

    const user = await User.findById(userId);
    if (!user) {
      return res.status(404).json({ success: false, message: "User not found" });
    }

    await revokeTokens(user);

    user.gmailConnection = {
      googleEmail: null,
      refreshTokenEnc: null,
      accessToken: null,
      accessTokenExpiry: null,
      connectedAt: null,
      lastSyncAt: null,
      syncEnabled: false,
    };
    await user.save();

    await ParsedBill.deleteMany({ userId, status: "pending" });

    return res.status(200).json({
      success: true,
      message: "Gmail disconnected",
    });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
};
