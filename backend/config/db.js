const mongoose = require("mongoose");

const connectDB = async () => {
  try {
    await mongoose.connect(process.env.MONGO_URI, {
      maxPoolSize: 10,
      serverSelectionTimeoutMS: 15000,
      socketTimeoutMS: 45000,
      autoIndex: true,
    });
    console.log("MongoDB Connected");
  } catch (error) {
    console.log("DB Error:", error);
    process.exit(1);
  }
};

module.exports = connectDB;