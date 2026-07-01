const NotificationLog = require("../models/NotificationLog");

exports.getNotificationLogs = async (req, res) => {
  try {
    const logs = await NotificationLog.find().sort({
      createdAt: -1,
    });

    res.status(200).json({
      success: true,
      count: logs.length,
      data: logs,
    });
  } catch (err) {
    res.status(500).json({
      success: false,
      message: err.message,
    });
  }
};