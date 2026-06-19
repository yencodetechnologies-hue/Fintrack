const express = require("express");
const router = express.Router();



const {
  addCard,
  getCards,
  getCardById,
  updateCard,
  deleteCard
} = require("../controllers/cardController");


router.post("/", addCard);


router.get("/", getCards);


router.put("/:id", updateCard);


router.delete("/:id", deleteCard);


module.exports = router;