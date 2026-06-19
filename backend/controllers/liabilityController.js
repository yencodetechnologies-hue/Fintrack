const Liability = require("../models/liability");


// CREATE LIABILITY
exports.createLiability = async (req, res) => {

  try {

    const newLiability = new Liability(req.body);

    await newLiability.save();

    res.status(201).json({
      success: true,
      message: "Liability entry created",
      data: newLiability,
    });

  } catch (error) {

    res.status(500).json({
      success: false,
      message: error.message,
    });

  }
};


// GET USER LIABILITIES
exports.getUserLiabilities = async (req, res) => {

  try {

    const liabilities = await Liability.find({
      userId: req.params.userId,
    }).sort({ createdAt: -1 });

    res.status(200).json({
      success: true,
      data: liabilities,
    });

  } catch (error) {

    res.status(500).json({
      success: false,
      message: error.message,
    });

  }
};


// MARK PAID
exports.markPaid = async (req, res) => {

  try {

    const updated = await Liability.findByIdAndUpdate(
      req.params.id,
      {
        isPaid: true,
      },
      { new: true }
    );

    res.status(200).json({
      success: true,
      data: updated,
    });

  } catch (error) {

    res.status(500).json({
      success: false,
      message: error.message,
    });

  }
};


// DELETE
exports.deleteLiability = async (req, res) => {

  try {

    await Liability.findByIdAndDelete(req.params.id);

    res.status(200).json({
      success: true,
      message: "Deleted successfully",
    });

  } catch (error) {

    res.status(500).json({
      success: false,
      message: error.message,
    });

  }
};