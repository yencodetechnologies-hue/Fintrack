require("dotenv").config();

const express = require("express");
const cors = require("cors");
const connectDB = require("./config/db");

const app = express();

connectDB();


app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));


const authRoutes = require("./routes/authRoutes");
app.use("/api/auth", authRoutes);



const cardRoutes = require("./routes/cardRoutes");
app.use("/api/cards", cardRoutes);

const reminderRoutes = require("./routes/reminderRoutes");

app.use("/reminder", reminderRoutes);
require("./jobs/reminderCron");
const lendRoutes = require("./routes/lendRoutes");
const liabilityRoutes = require("./routes/liabilityRoutes");
app.use("/api/lend", lendRoutes);
app.use("/api/liability", liabilityRoutes);
const cronReminderRoutes = require("./routes/cronReminderRoutes");

app.use("/api/cron", cronReminderRoutes);

app.listen(3009, "0.0.0.0", () => {
  console.log("Server running on port 3009");
});