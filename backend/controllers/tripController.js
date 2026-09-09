const Trip = require("../models/trip");
const User = require("../models/user");
const crypto = require("crypto");

// Helper: Generate unique 6-character alphanumeric code (e.g. TRP892)
function generateJoinCode() {
  const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
  let code = "";
  for (let i = 0; i < 6; i++) {
    code += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return code;
}

// Helper: Recalculate member budget shares
function recalculateShares(trip) {
  if (!trip.members || trip.members.length === 0) return;

  if (trip.splitType === "equal") {
    const memberCount = trip.members.length;
    const equalShare = parseFloat((trip.budget / memberCount).toFixed(2));
    const equalPercentage = parseFloat((100 / memberCount).toFixed(2));

    trip.members.forEach((m) => {
      m.shareAmount = equalShare;
      m.sharePercentage = equalPercentage;
    });
  }
}

// Helper: Get Currency Symbol from Code
function getCurrencySymbol(code) {
  const map = {
    INR: "₹",
    USD: "$",
    EUR: "€",
    GBP: "£",
    JPY: "¥",
    AED: "AED ",
    SGD: "S$",
    CAD: "CA$",
    AUD: "A$",
  };
  return map[code] || "₹";
}

// 1. Create a new Trip
exports.createTrip = async (req, res) => {
  try {
    const {
      userId,
      name,
      fromLocation,
      toLocation,
      startDate,
      endDate,
      budget,
      currency,
      splitType,
      customShares,
    } = req.body;

    if (!userId || !name || !fromLocation || !toLocation || !budget) {
      return res.status(400).json({
        success: false,
        message: "Missing required fields: userId, name, fromLocation, toLocation, budget",
      });
    }

    const organizerUser = await User.findById(userId);
    if (!organizerUser) {
      return res.status(404).json({
        success: false,
        message: "Organizer user not found",
      });
    }

    // Generate unique join code
    let joinCode = generateJoinCode();
    let existingTrip = await Trip.findOne({ joinCode });
    while (existingTrip) {
      joinCode = generateJoinCode();
      existingTrip = await Trip.findOne({ joinCode });
    }

    const parsedBudget = parseFloat(budget);

    // Initial member (Organizer)
    const organizerMember = {
      userId: organizerUser._id,
      name: organizerUser.name || "Organizer",
      email: organizerUser.email || "",
      shareAmount: parsedBudget,
      sharePercentage: 100,
      joinedAt: new Date(),
    };

    const selectedCurrency = currency || "INR";
    const selectedSymbol = getCurrencySymbol(selectedCurrency);

    const newTrip = new Trip({
      name,
      fromLocation,
      toLocation,
      startDate: startDate ? new Date(startDate) : null,
      endDate: endDate ? new Date(endDate) : null,
      budget: parsedBudget,
      currency: selectedCurrency,
      currencySymbol: selectedSymbol,
      splitType: splitType || "equal",
      organizer: organizerUser._id,
      joinCode,
      members: [organizerMember],
    });

    if (splitType === "custom" && Array.isArray(customShares)) {
      // Custom split initial processing if additional members provided
    } else {
      recalculateShares(newTrip);
    }

    await newTrip.save();

    return res.status(201).json({
      success: true,
      message: "Trip created successfully",
      trip: newTrip,
    });
  } catch (error) {
    console.error("Create Trip Error:", error);
    return res.status(500).json({
      success: false,
      message: "Server error creating trip: " + error.message,
    });
  }
};

// 2. Fetch User Trips (where user is organizer or member)
exports.getUserTrips = async (req, res) => {
  try {
    const { userId } = req.params;

    if (!userId) {
      return res.status(400).json({
        success: false,
        message: "userId is required",
      });
    }

    const trips = await Trip.find({
      $or: [{ organizer: userId }, { "members.userId": userId }],
    })
      .sort({ createdAt: -1 })
      .populate("organizer", "name email");

    return res.status(200).json({
      success: true,
      count: trips.length,
      trips,
    });
  } catch (error) {
    console.error("Get User Trips Error:", error);
    return res.status(500).json({
      success: false,
      message: "Server error fetching trips: " + error.message,
    });
  }
};

// 3. Fetch Single Trip Details
exports.getTripById = async (req, res) => {
  try {
    const { tripId } = req.params;

    const trip = await Trip.findById(tripId).populate("organizer", "name email");
    if (!trip) {
      return res.status(404).json({
        success: false,
        message: "Trip not found",
      });
    }

    return res.status(200).json({
      success: true,
      trip,
    });
  } catch (error) {
    console.error("Get Trip Details Error:", error);
    return res.status(500).json({
      success: false,
      message: "Server error fetching trip details: " + error.message,
    });
  }
};

// 4. Join Trip via 6-digit code or QR code payload
exports.joinTrip = async (req, res) => {
  try {
    const { userId, joinCode } = req.body;

    if (!userId || !joinCode) {
      return res.status(400).json({
        success: false,
        message: "userId and joinCode are required",
      });
    }

    const formattedCode = joinCode.trim().toUpperCase();

    const trip = await Trip.findOne({ joinCode: formattedCode });
    if (!trip) {
      return res.status(404).json({
        success: false,
        message: "Invalid Trip Code. No matching trip found.",
      });
    }

    const joiningUser = await User.findById(userId);
    if (!joiningUser) {
      return res.status(404).json({
        success: false,
        message: "User not found",
      });
    }

    // Check if user is already a member
    const alreadyMember = trip.members.some(
      (m) => m.userId.toString() === joiningUser._id.toString()
    );

    if (alreadyMember) {
      return res.status(200).json({
        success: true,
        message: "You are already a member of this trip!",
        trip,
      });
    }

    // Add user as member
    const newMember = {
      userId: joiningUser._id,
      name: joiningUser.name || "Member",
      email: joiningUser.email || "",
      shareAmount: 0,
      sharePercentage: 0,
      joinedAt: new Date(),
    };

    trip.members.push(newMember);

    // Recalculate shares
    recalculateShares(trip);

    await trip.save();

    return res.status(200).json({
      success: true,
      message: `Successfully joined trip "${trip.name}"!`,
      trip,
    });
  } catch (error) {
    console.error("Join Trip Error:", error);
    return res.status(500).json({
      success: false,
      message: "Server error joining trip: " + error.message,
    });
  }
};

// 5. Update Trip Details / Custom Split (Organizer only)
exports.updateTrip = async (req, res) => {
  try {
    const { tripId } = req.params;
    const {
      userId,
      name,
      fromLocation,
      toLocation,
      startDate,
      endDate,
      budget,
      currency,
      splitType,
      status,
      customShares,
    } = req.body;

    const trip = await Trip.findById(tripId);
    if (!trip) {
      return res.status(404).json({
        success: false,
        message: "Trip not found",
      });
    }

    if (trip.organizer.toString() !== userId) {
      return res.status(403).json({
        success: false,
        message: "Only the trip organizer can update trip details.",
      });
    }

    if (name) trip.name = name;
    if (fromLocation) trip.fromLocation = fromLocation;
    if (toLocation) trip.toLocation = toLocation;
    if (startDate) trip.startDate = new Date(startDate);
    if (endDate) trip.endDate = new Date(endDate);
    if (budget) trip.budget = parseFloat(budget);
    if (currency) {
      trip.currency = currency;
      trip.currencySymbol = getCurrencySymbol(currency);
    }
    if (splitType) trip.splitType = splitType;
    if (status) trip.status = status;

    if (trip.splitType === "custom" && Array.isArray(customShares)) {
      // customShares: [{ userId, shareAmount }]
      const shareMap = new Map(customShares.map((cs) => [cs.userId.toString(), parseFloat(cs.shareAmount)]));
      trip.members.forEach((m) => {
        if (shareMap.has(m.userId.toString())) {
          m.shareAmount = shareMap.get(m.userId.toString());
          m.sharePercentage = trip.budget > 0 ? parseFloat(((m.shareAmount / trip.budget) * 100).toFixed(2)) : 0;
        }
      });
    } else {
      recalculateShares(trip);
    }

    await trip.save();

    return res.status(200).json({
      success: true,
      message: "Trip updated successfully",
      trip,
    });
  } catch (error) {
    console.error("Update Trip Error:", error);
    return res.status(500).json({
      success: false,
      message: "Server error updating trip: " + error.message,
    });
  }
};

// 6. Delete Trip or Remove Member
exports.deleteTrip = async (req, res) => {
  try {
    const { tripId } = req.params;
    const { userId, removeMemberId } = req.body;

    const trip = await Trip.findById(tripId);
    if (!trip) {
      return res.status(404).json({
        success: false,
        message: "Trip not found",
      });
    }

    const isOrganizer = trip.organizer.toString() === userId;

    // Case A: Organizer removing specific member
    if (removeMemberId && isOrganizer) {
      if (removeMemberId === trip.organizer.toString()) {
        return res.status(400).json({
          success: false,
          message: "Organizer cannot be removed from the trip. Delete the trip instead.",
        });
      }
      trip.members = trip.members.filter((m) => m.userId.toString() !== removeMemberId);
      recalculateShares(trip);
      await trip.save();
      return res.status(200).json({
        success: true,
        message: "Member removed from trip",
        trip,
      });
    }

    // Case B: Member leaving trip
    if (!isOrganizer) {
      trip.members = trip.members.filter((m) => m.userId.toString() !== userId);
      recalculateShares(trip);
      await trip.save();
      return res.status(200).json({
        success: true,
        message: "You left the trip successfully",
      });
    }

    // Case C: Organizer deleting entire trip
    await Trip.findByIdAndDelete(tripId);

    return res.status(200).json({
      success: true,
      message: "Trip deleted successfully",
    });
  } catch (error) {
    console.error("Delete Trip Error:", error);
    return res.status(500).json({
      success: false,
      message: "Server error deleting trip: " + error.message,
    });
  }
};
