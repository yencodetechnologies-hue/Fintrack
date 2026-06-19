const Card = require("../models/card");



exports.addCard = async (req, res) => {
  try {
    const {
      userId,
      bankName,
      cardName,
      last4digits,
      statementDate,
     paymentDueDate
    } = req.body;

    if (!userId) {
      return res.status(400).json({
        success: false,
        message: "userId is required"
      });
    }

    const newCard = await Card.create({
      userId,
      bankName,
      cardName,
      last4digits,
      statementDate,
      paymentDueDate
    });

    res.status(201).json({
      success: true,
      data: newCard
    });

  } catch (error) {
    res.status(500).json({
      success: false,
      message: error.message
    });
  }
};



exports.getCards = async (req, res) => {
  try {
    const { userId } = req.query;

    if (!userId) {
      return res.status(400).json({
        success: false,
        message: "userId is required"
      });
    }

    const cards = await Card.find({ userId });

    res.json({
      success: true,
      data: cards
    });

  } catch (error) {
    res.status(500).json({
      success: false,
      message: error.message
    });
  }
};


exports.updateCard = async (req, res) => {
  try {
    const { userId } = req.body;

    const updated = await Card.findOneAndUpdate(
      { _id: req.params.id, userId },
      req.body,
      { new: true }
    );

    if (!updated) {
      return res.status(404).json({
        success: false,
        message: "Card not found or unauthorized"
      });
    }

    res.json({
      success: true,
      data: updated
    });

  } catch (error) {
    res.status(500).json({
      success: false,
      message: error.message
    });
  }
};


exports.deleteCard = async (req, res) => {
  try {
    const { userId } = req.body;

    const deleted = await Card.findOneAndDelete({
      _id: req.params.id,
      userId
    });

    if (!deleted) {
      return res.status(404).json({
        success: false,
        message: "Card not found or unauthorized"
      });
    }

    res.json({
      success: true,
      message: "Card deleted"
    });

  } catch (error) {
    res.status(500).json({
      success: false,
      message: error.message
    });
  }
};