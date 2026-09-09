const express = require("express");
const router = express.Router();
const vehicleController = require("../controllers/vehicleController");

// Create new vehicle
router.post("/", vehicleController.createVehicle);

// Get user's vehicles
router.get("/user/:userId", vehicleController.getUserVehicles);

// Get vehicle by ID
router.get("/:id", vehicleController.getVehicleById);

// Update vehicle
router.put("/:id", vehicleController.updateVehicle);

// Delete vehicle
router.delete("/:id", vehicleController.deleteVehicle);

// Log refuel
router.post("/:id/refuel", vehicleController.addRefuelLog);

// Save ride history
router.post("/:id/ride", vehicleController.saveRide);

module.exports = router;
