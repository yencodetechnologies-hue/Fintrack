const mongoose = require("mongoose");
const Vehicle = require("../models/vehicle");

// The vehicle, only if it belongs to the userId sent with the request (query for GET/DELETE, body otherwise).
// A wrong id, a missing userId or someone else's vehicle all answer 404, so ids can't be probed.
async function ownVehicle(req, res) {
  const { id } = req.params;
  const userId = req.query.userId || req.body?.userId;
  if (!userId) {
    res.status(400).json({ success: false, message: "userId is required" });
    return null;
  }
  if (!mongoose.isValidObjectId(id) || !mongoose.isValidObjectId(userId)) {
    res.status(404).json({ success: false, message: "Vehicle not found" });
    return null;
  }
  const vehicle = await Vehicle.findOne({ _id: id, userId });
  if (!vehicle) {
    res.status(404).json({ success: false, message: "Vehicle not found" });
    return null;
  }
  return vehicle;
}

// a number from the request, or undefined when not sent; NaN when sent but not a number
const num = (v) => (v === undefined || v === null || v === "" ? undefined : Number(v));
const bad = (res, message) => res.status(400).json({ success: false, message });

// Checks the vehicle numbers (any that are sent); returns an error message or null.
function vehicleNumbersProblem({ averageMileage, tankCapacity, currentFuelLevel, lowRangeThresholdKm, odometerKm }) {
  if (averageMileage !== undefined && !(averageMileage > 0 && averageMileage <= 500)) return "Mileage must be more than 0";
  if (tankCapacity !== undefined && !(tankCapacity > 0 && tankCapacity <= 1000)) return "Tank / battery size must be more than 0";
  if (currentFuelLevel !== undefined && !(currentFuelLevel >= 0)) return "Current fuel can't be negative";
  if (currentFuelLevel !== undefined && tankCapacity !== undefined && currentFuelLevel > tankCapacity) return "Current fuel can't be more than the tank size";
  if (lowRangeThresholdKm !== undefined && !(lowRangeThresholdKm >= 0)) return "Low-range alert can't be negative";
  if (odometerKm !== undefined && !(odometerKm >= 0)) return "Odometer can't be negative";
  return null;
}

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

    if (!mongoose.isValidObjectId(userId)) return bad(res, "Invalid userId");
    const numbers = {
      averageMileage: num(averageMileage),
      tankCapacity: num(tankCapacity) ?? 40,
      currentFuelLevel: num(currentFuelLevel),
      lowRangeThresholdKm: num(lowRangeThresholdKm) ?? 25,
      odometerKm: num(odometerKm) ?? 0,
    };
    if (numbers.currentFuelLevel === undefined) numbers.currentFuelLevel = numbers.tankCapacity * 0.75;
    const problem = vehicleNumbersProblem(numbers);
    if (problem) return bad(res, problem);

    const newVehicle = new Vehicle({
      userId,
      name: String(name).trim(),
      vehicleType,
      fuelType,
      brand: String(brand).trim(),
      model: String(model).trim(),
      isManualModel: Boolean(isManualModel),
      ...numbers,
    });

    await newVehicle.save();

    return res.status(201).json({
      success: true,
      message: "Vehicle created successfully",
      vehicle: newVehicle,
    });
  } catch (error) {
    if (error.name === "ValidationError") return bad(res, Object.values(error.errors)[0]?.message || "Invalid vehicle details");
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
    if (!userId || !mongoose.isValidObjectId(userId)) {
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
    const vehicle = await ownVehicle(req, res);
    if (!vehicle) return;
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
    const vehicle = await ownVehicle(req, res);
    if (!vehicle) return;

    // only these can be edited; owner, ride history and refuel logs never change here
    const TEXT = ["name", "vehicleType", "fuelType", "brand", "model"];
    const NUMBERS = ["averageMileage", "tankCapacity", "currentFuelLevel", "lowRangeThresholdKm", "odometerKm"];
    for (const key of TEXT) {
      if (req.body[key] === undefined) continue;
      const value = String(req.body[key]).trim();
      if (!value) return bad(res, `${key} can't be empty`);
      vehicle[key] = value;
    }
    if (req.body.isManualModel !== undefined) vehicle.isManualModel = Boolean(req.body.isManualModel);
    for (const key of NUMBERS) {
      const value = num(req.body[key]);
      if (value === undefined) continue;
      if (Number.isNaN(value)) return bad(res, `${key} must be a number`);
      vehicle[key] = value;
    }
    // check the result as a whole (e.g. a smaller tank with the old fuel level)
    const problem = vehicleNumbersProblem({
      averageMileage: vehicle.averageMileage,
      tankCapacity: vehicle.tankCapacity,
      currentFuelLevel: vehicle.currentFuelLevel,
      lowRangeThresholdKm: vehicle.lowRangeThresholdKm,
      odometerKm: vehicle.odometerKm,
    });
    if (problem) return bad(res, problem);
    await vehicle.save();

    return res.status(200).json({
      success: true,
      message: "Vehicle updated successfully",
      vehicle,
    });
  } catch (error) {
    if (error.name === "ValidationError") return bad(res, Object.values(error.errors)[0]?.message || "Invalid vehicle details");
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
    const vehicle = await ownVehicle(req, res);
    if (!vehicle) return;
    await vehicle.deleteOne();

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
    const vehicle = await ownVehicle(req, res);
    if (!vehicle) return;

    const added = num(req.body.fuelAdded);
    const cost = num(req.body.cost) ?? 0;
    const odometer = num(req.body.odometer);
    if (!(added > 0)) return bad(res, "Enter how much fuel was added (more than 0)");
    if (added > vehicle.tankCapacity) return bad(res, `That's more than the tank holds (${vehicle.tankCapacity})`);
    if (!(cost >= 0)) return bad(res, "Cost can't be negative");
    if (odometer !== undefined && !(odometer >= 0)) return bad(res, "Odometer can't be negative");

    vehicle.currentFuelLevel = Math.min(vehicle.tankCapacity, vehicle.currentFuelLevel + added);
    if (odometer !== undefined && odometer > vehicle.odometerKm) vehicle.odometerKm = odometer;

    vehicle.refuelLogs.push({
      date: new Date(),
      fuelAdded: added,
      cost,
      odometer: odometer ?? vehicle.odometerKm,
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
    const vehicle = await ownVehicle(req, res);
    if (!vehicle) return;
    const { startTime, endTime } = req.body;

    const dist = num(req.body.distanceKm) ?? 0;
    const sentUsed = num(req.body.fuelUsed);
    const avgSpeed = num(req.body.avgSpeedKmh) ?? 0;
    if (!(dist >= 0 && dist <= 3000)) return bad(res, "Ride distance must be between 0 and 3000 km");
    if (sentUsed !== undefined && !(sentUsed >= 0)) return bad(res, "Fuel used can't be negative");
    if (!(avgSpeed >= 0 && avgSpeed <= 400)) return bad(res, "Average speed must be between 0 and 400 km/h");
    const start = startTime ? new Date(startTime) : new Date();
    const end = endTime ? new Date(endTime) : new Date();
    if (isNaN(start.getTime()) || isNaN(end.getTime()) || end < start) return bad(res, "Ride times aren't valid");
    const used = sentUsed || (vehicle.averageMileage > 0 ? dist / vehicle.averageMileage : 0);

    // Subtract fuel used from vehicle's current level
    vehicle.currentFuelLevel = Math.max(0, vehicle.currentFuelLevel - used);
    vehicle.odometerKm += dist;

    vehicle.rideHistory.push({
      startTime: start,
      endTime: end,
      distanceKm: dist,
      fuelUsed: used,
      avgSpeedKmh: avgSpeed,
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
