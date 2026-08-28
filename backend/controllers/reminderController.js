const Reminder = require("../models/reminder");
const mongoose = require("mongoose");


const createReminder = async (req, res) => {
  try {
    const {
      userId,
      cardId,
      bankName,
      amount,
      statementDate,
      paymentDate,
      paymentDueDate,
      reminders,
      status,
    } = req.body;

    if (!userId || !cardId || !amount) {
      return res.status(400).json({
        message: "userId, cardId, amount are required",
      });
    }

    let resolvedBankName = bankName;
    if (!resolvedBankName && cardId && mongoose.Types.ObjectId.isValid(cardId)) {
      const Card = require("../models/card");
      const card = await Card.findById(cardId);
      if (card) resolvedBankName = card.bankName;
    }
    if (!resolvedBankName) resolvedBankName = "Bank";

    let remindersArray = [];
    if (Array.isArray(reminders)) {
      remindersArray = reminders;
    } else if (reminders && typeof reminders === "object") {
      remindersArray = Object.keys(reminders).map((key) => ({
        key,
        count: reminders[key].count || 1,
        times: reminders[key].times || [],
      }));
    }

    const newReminder = new Reminder({
      userId,
      cardId,
      bankName: resolvedBankName,
      amount: parseFloat(amount),
      statementDate: statementDate ? new Date(statementDate) : null,
      paymentDate: paymentDate
        ? new Date(paymentDate)
        : paymentDueDate
        ? new Date(paymentDueDate)
        : null,
      reminders: remindersArray,
      status: status || "unpaid",
    });

    await newReminder.save();

    return res.status(201).json({
      message: "Reminder created successfully",
      data: newReminder,
    });
  } catch (error) {
    return res.status(500).json({
      message: "Server error while creating reminder",
      error: error.message,
    });
  }
};



const getReminders = async (req, res) => {
  try {
    const { userId } = req.query;

    const query = userId ? { userId } : {};

    const reminders = await Reminder.find(query)
      .populate("userId")
      .populate("cardId")
      .sort({ createdAt: -1 });

    return res.status(200).json({
      message: "Reminders fetched successfully",
      data: reminders, // ✅ includes status
    });
  } catch (error) {
    return res.status(500).json({
      message: "Error fetching reminders",
      error: error.message,
    });
  }
};
const deleteReminder = async (req, res) => {
  try {
    const { id } = req.query;

    if (!id) {
      return res.status(400).json({
        message: "Reminder id is required",
      });
    }

    if (!mongoose.Types.ObjectId.isValid(id)) {
      return res.status(400).json({
        message: "Invalid reminder id",
      });
    }

    const deleted = await Reminder.findByIdAndDelete(id);

    if (!deleted) {
      return res.status(404).json({
        message: "Reminder not found",
      });
    }

    return res.status(200).json({
      message: "Reminder deleted successfully",
    });

  } catch (error) {
    return res.status(500).json({
      message: "Error deleting reminder",
      error: error.message,
    });
  }
};




const updateReminder = async (req, res) => {
  try {
    const { id } = req.params;

    if (!mongoose.Types.ObjectId.isValid(id)) {
      return res.status(400).json({
        message: "Invalid reminder ID",
      });
    }

    const {
      bankName,
      userId,
      cardId,
      amount,
      statementDate,
      paymentDate,
      reminders,
    } = req.body;

    // ✅ VALIDATION BLOCK
    if (!userId || !cardId) {
      return res.status(400).json({
        message: "userId and cardId are required",
      });
    }

    if (!mongoose.Types.ObjectId.isValid(cardId)) {
      return res.status(400).json({
        message: "Invalid cardId",
      });
    }

    const updated = await Reminder.findByIdAndUpdate(
      id,
      {
        $set: {
          bankName,
          userId,
          cardId,
          amount,
          statementDate,
          paymentDate,
          reminders: Array.isArray(reminders) ? reminders : [],
        },
      },
      { new: true, runValidators: true }
    );

    if (!updated) {
      return res.status(404).json({
        message: "Reminder not found",
      });
    }

    return res.status(200).json({
      message: "Reminder updated successfully",
      data: updated,
    });
  } catch (error) {
    return res.status(500).json({
      message: "Error updating reminder",
      error: error.message,
    });
  }
};





const updateStatus = async (req, res) => {
  try {
    const { userId, cardId, status, reminders } = req.body;

    if (!userId || !cardId) {
      return res.status(400).json({
        message: "userId and cardId required",
      });
    }

    const updated = await Reminder.updateMany(
      { userId, cardId },
      {
        $set: {
          status,
          reminders,
        },
      }
    );

    return res.status(200).json({
      message: "Status updated successfully",
      data: updated,
    });
  } catch (error) {
    return res.status(500).json({
      message: "Error updating status",
      error: error.message,
    });
  }
};



/// ✅ EXPORT (FIXED)
module.exports = {
  createReminder,
  getReminders,
  updateReminder,
  deleteReminder,
  updateStatus, // 🔥 IMPORTANT
};