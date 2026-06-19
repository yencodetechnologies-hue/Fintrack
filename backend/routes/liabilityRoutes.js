const express = require("express");

const router = express.Router();

const {
  createLiability,
  getUserLiabilities,
  markPaid,
  deleteLiability,
} = require("../controllers/liabilityController");


// CREATE
router.post("/create", createLiability);

// GET USER LIABILITIES
router.get("/:userId", getUserLiabilities);

// MARK PAID
router.put("/paid/:id", markPaid);

// DELETE
router.delete("/:id", deleteLiability);

module.exports = router;