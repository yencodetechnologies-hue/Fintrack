const NotificationLog = require("../models/notificationcron");

exports.getNotificationLogs = async (req, res) => {
  try {
    const logs = await NotificationLog.find().sort({
      createdAt: -1,
    });

    const data = logs.map((log) => ({
      _id: log._id,
      message: log.message,
      createdAt: log.createdAt,
      sentAt: log.createdAt,
    }));

    res.status(200).json({
      success: true,
      count: data.length,
      data,
    });
  } catch (err) {
    res.status(500).json({
      success: false,
      message: err.message,
    });
  }
};