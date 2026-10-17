const Vehicle = require("../models/vehicle");

// 1. Create a new Vehicle
exports.createVehicle = async (req, res) => {
  try {
    const {
      userId,
      name,
      vehicleType,
      fuelType,
      brand,
      model,
      isManualModel,
      averageMileage,
      tankCapacity,
      currentFuelLevel,
      lowRangeThresholdKm,
      odometerKm,
    } = req.body;

    if (!userId || !name || !vehicleType || !fuelType || !brand || !model || !averageMileage) {
      return res.status(400).json({
        success: false,
        message: "Missing required fields: userId, name, vehicleType, fuelType, brand, model, averageMileage",
      });
    }

    const newVehicle = new Vehicle({
      userId,
      name,
      vehicleType,
      fuelType,
      brand,
      model,
      isManualModel: isManualModel || false,
      averageMileage: parseFloat(averageMileage),
      tankCapacity: tankCapacity ? parseFloat(tankCapacity) : 40,
      currentFuelLevel: currentFuelLevel ? parseFloat(currentFuelLevel) : (tankCapacity ? parseFloat(tankCapacity) * 0.75 : 30),
      lowRangeThresholdKm: lowRangeThresholdKm ? parseFloat(lowRangeThresholdKm) : 25,
      odometerKm: odometerKm ? parseFloat(odometerKm) : 0,
    });

    await newVehicle.save();

    return res.status(201).json({
      success: true,
      message: "Vehicle created successfully",
      vehicle: newVehicle,
    });
  } catch (error) {
    console.error("Error creating vehicle:", error);
    return res.status(500).json({
      success: false,
      message: "Server error creating vehicle",
      error: error.message,
    });
  }
};

// 2. Get User's Vehicles
exports.getUserVehicles = async (req, res) => {
  try {
    const { userId } = req.params;
    if (!userId) {
      return res.status(400).json({ success: false, message: "User ID is required" });
    }

    const vehicles = await Vehicle.find({ userId }).sort({ createdAt: -1 });

    return res.status(200).json({
      success: true,
      count: vehicles.length,
      vehicles,
    });
  } catch (error) {
    console.error("Error fetching vehicles:", error);
    return res.status(500).json({
      success: false,
      message: "Server error fetching vehicles",
      error: error.message,
    });
  }
};

// 3. Get Vehicle by ID
exports.getVehicleById = async (req, res) => {
  try {
    const { id } = req.params;
    const vehicle = await Vehicle.findById(id);

    if (!vehicle) {
      return res.status(404).json({ success: false, message: "Vehicle not found" });
    }

    return res.status(200).json({ success: true, vehicle });
  } catch (error) {
    console.error("Error fetching vehicle by ID:", error);
    return res.status(500).json({
      success: false,
      message: "Server error fetching vehicle",
      error: error.message,
    });
  }
};

// 4. Update Vehicle
exports.updateVehicle = async (req, res) => {
  try {
    const { id } = req.params;
    const updateData = req.body;

    const updatedVehicle = await Vehicle.findByIdAndUpdate(id, updateData, {
      returnDocument: "after",
      runValidators: true,
    });

    if (!updatedVehicle) {
      return res.status(404).json({ success: false, message: "Vehicle not found" });
    }

    return res.status(200).json({
      success: true,
      message: "Vehicle updated successfully",
      vehicle: updatedVehicle,
    });
  } catch (error) {
    console.error("Error updating vehicle:", error);
    return res.status(500).json({
      success: false,
      message: "Server error updating vehicle",
      error: error.message,
    });
  }
};

// 5. Delete Vehicle
exports.deleteVehicle = async (req, res) => {
  try {
    const { id } = req.params;
    const deleted = await Vehicle.findByIdAndDelete(id);

    if (!deleted) {
      return res.status(404).json({ success: false, message: "Vehicle not found" });
    }

    return res.status(200).json({ success: true, message: "Vehicle deleted successfully" });
  } catch (error) {
    console.error("Error deleting vehicle:", error);
    return res.status(500).json({
      success: false,
      message: "Server error deleting vehicle",
      error: error.message,
    });
  }
};

// 6. Log Refuel / Recharge
exports.addRefuelLog = async (req, res) => {
  try {
    const { id } = req.params;
    const { fuelAdded, cost, odometer } = req.body;

    if (!fuelAdded) {
      return res.status(400).json({ success: false, message: "fuelAdded is required" });
    }

    const vehicle = await Vehicle.findById(id);
    if (!vehicle) {
      return res.status(404).json({ success: false, message: "Vehicle not found" });
    }

    const added = parseFloat(fuelAdded);
    vehicle.currentFuelLevel = Math.min(vehicle.tankCapacity, vehicle.currentFuelLevel + added);
    
    if (odometer && parseFloat(odometer) > vehicle.odometerKm) {
      vehicle.odometerKm = parseFloat(odometer);
    }

    vehicle.refuelLogs.push({
      date: new Date(),
      fuelAdded: added,
      cost: cost ? parseFloat(cost) : 0,
      odometer: odometer ? parseFloat(odometer) : vehicle.odometerKm,
    });

    await vehicle.save();

    return res.status(200).json({
      success: true,
      message: "Refuel log recorded successfully",
      vehicle,
    });
  } catch (error) {
    console.error("Error logging refuel:", error);
    return res.status(500).json({
      success: false,
      message: "Server error recording refuel",
      error: error.message,
    });
  }
};

// 7. Save Completed Ride
exports.saveRide = async (req, res) => {
  try {
    const { id } = req.params;
    const { startTime, endTime, distanceKm, fuelUsed, avgSpeedKmh } = req.body;

    const vehicle = await Vehicle.findById(id);
    if (!vehicle) {
      return res.status(404).json({ success: false, message: "Vehicle not found" });
    }

    const dist = parseFloat(distanceKm) || 0;
    const used = parseFloat(fuelUsed) || (vehicle.averageMileage > 0 ? dist / vehicle.averageMileage : 0);

    // Subtract fuel used from vehicle's current level
    vehicle.currentFuelLevel = Math.max(0, vehicle.currentFuelLevel - used);
    vehicle.odometerKm += dist;

    vehicle.rideHistory.push({
      startTime: startTime || new Date(),
      endTime: endTime || new Date(),
      distanceKm: dist,
      fuelUsed: used,
      avgSpeedKmh: parseFloat(avgSpeedKmh) || 0,
    });

    await vehicle.save();

    return res.status(200).json({
      success: true,
      message: "Ride recorded successfully",
      vehicle,
    });
  } catch (error) {
    console.error("Error saving ride:", error);
    return res.status(500).json({
      success: false,
      message: "Server error saving ride",
      error: error.message,
    });
  }
};
