const express = require("express");

const router = express.Router();

const {
  createLend,
  getUserLends,
  markReceived,
  deleteLend,
} = require("../controllers/lendController");


// CREATE
router.post("/create", createLend);

// GET USER LENDS
router.get("/user/:userId", getUserLends);

// MARK RECEIVED
router.put("/received/:id", markReceived);

// DELETE
router.delete("/delete/:id", deleteLend);

module.exports = router;