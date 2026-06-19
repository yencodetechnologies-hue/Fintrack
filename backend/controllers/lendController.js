const Lend = require("../models/lend");


// CREATE LEND
exports.createLend = async (req, res) => {

  try {

    const newLend = new Lend(req.body);

    await newLend.save();

    res.status(201).json({
      success: true,
      message: "Lend entry created",
      data: newLend,
    });

  } catch (error) {

    res.status(500).json({
      success: false,
      message: error.message,
    });

  }
};


// GET USER LENDS
exports.getUserLends = async (req, res) => {

  try {

    const lends = await Lend.find({
      userId: req.params.userId,
    }).sort({ createdAt: -1 });

    res.status(200).json({
      success: true,
      data: lends,
    });

  } catch (error) {

    res.status(500).json({
      success: false,
      message: error.message,
    });

  }
};


// MARK RECEIVED
exports.markReceived = async (req, res) => {

  try {

    const updated = await Lend.findByIdAndUpdate(
      req.params.id,
      {
        isReceived: true,
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
exports.deleteLend = async (req, res) => {

  try {

    await Lend.findByIdAndDelete(req.params.id);

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