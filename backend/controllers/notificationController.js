const mongoose = require("mongoose");
const User = require("../models/user");
const {
  sendTestNotification,
  sendBroadcastNotification,
} = require("../services/notificationService");

exports.sendBroadcastNotification = async (req, res) => {
  try {
    const title = String(req.body.title || "").trim();
    const body = String(req.body.body || "").trim();

    const result = await sendBroadcastNotification({
      title: title || undefined,
      body: body || undefined,
    });

    if (result.sentCount === 0) {
      return res.status(400).json({
        success: false,
        ...result,
      });
    }

    return res.json({
      success: true,
      ...result,
    });
  } catch (error) {
    return res.status(500).json({
      success: false,
      message: error.message,
    });
  }
};

exports.sendTestNotification = async (req, res) => {
  try {
    const userId = String(req.body.userId || "").trim();
    const title = String(req.body.title || "").trim();
    const body = String(req.body.body || "").trim();

    if (!userId) {
      return res.status(400).json({
        success: false,
        message: "userId is required",
      });
    }

    if (!mongoose.Types.ObjectId.isValid(userId)) {
      return res.status(400).json({
        success: false,
        message: "Invalid userId",
      });
    }

    const user = await User.findById(userId);
    if (!user) {
      return res.status(404).json({
        success: false,
        message: "User not found",
      });
    }

    const result = await sendTestNotification(user, {
      title: title || undefined,
      body: body || undefined,
    });

    if (result.sentCount === 0) {
      return res.status(400).json({
        success: false,
        ...result,
      });
    }

    return res.json({
      success: true,
      userId: user._id,
      email: user.email,
      ...result,
    });
  } catch (error) {
    return res.status(500).json({
      success: false,
      message: error.message,
    });
  }
};
