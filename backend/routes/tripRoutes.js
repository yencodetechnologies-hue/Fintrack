const express = require("express");
const router = express.Router();
const tripController = require("../controllers/tripController");

// Create trip
router.post("/create", tripController.createTrip);

// Get user trips
router.get("/user/:userId", tripController.getUserTrips);

// Get trip by ID
router.get("/:tripId", tripController.getTripById);

// Join trip via 6-digit code or QR code
router.post("/join", tripController.joinTrip);

// Update trip (organizer only)
router.put("/:tripId", tripController.updateTrip);

// Delete trip or remove member
router.delete("/:tripId", tripController.deleteTrip);

module.exports = router;
