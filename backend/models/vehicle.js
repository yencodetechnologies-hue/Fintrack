const mongoose = require("mongoose");

const refuelLogSchema = new mongoose.Schema({
  date: {
    type: Date,
    default: Date.now,
  },
  fuelAdded: {
    type: Number, // Liters or kWh
    required: true,
  },
  cost: {
    type: Number,
    default: 0,
  },
  odometer: {
    type: Number,
    default: 0,
  },
});

const rideHistorySchema = new mongoose.Schema({
  startTime: {
    type: Date,
    default: Date.now,
  },
  endTime: {
    type: Date,
    default: Date.now,
  },
  distanceKm: {
    type: Number,
    default: 0,
  },
  fuelUsed: {
    type: Number,
    default: 0,
  },
  avgSpeedKmh: {
    type: Number,
    default: 0,
  },
});

const vehicleSchema = new mongoose.Schema(
  {
    userId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      required: true,
    },
    name: {
      type: String,
      required: true,
      trim: true,
    },
    vehicleType: {
      type: String,
      enum: ["bike", "car"],
      required: true,
    },

    fuelType: {
      type: String,
      enum: ["petrol", "diesel", "cng", "electric", "hybrid"],
      required: true,
    },
    brand: {
      type: String,
      required: true,
      trim: true,
    },
    model: {
      type: String,
      required: true,
      trim: true,
    },
    isManualModel: {
      type: Boolean,
      default: false,
    },
    averageMileage: {
      type: Number, // km/L or km/kWh
      required: true,
      min: 0.1,
    },
    tankCapacity: {
      type: Number, // Liters or kWh
      default: 40,
    },
    currentFuelLevel: {
      type: Number, // Liters or kWh
      default: 20,
    },
    lowRangeThresholdKm: {
      type: Number, // Buffer in km before low range notification
      default: 25,
    },
    odometerKm: {
      type: Number,
      default: 0,
    },
    refuelLogs: [refuelLogSchema],
    rideHistory: [rideHistorySchema],
  },
  { timestamps: true }
);

module.exports = mongoose.model("Vehicle", vehicleSchema);
