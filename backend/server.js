require("dotenv").config();

const express = require("express");
const http = require("http");
const realtime = require("./services/realtime");
const cors = require("cors");
const connectDB = require("./config/db");

const app = express();

const allowedOrigins = [
  "https://fintrack-sooty-eta.vercel.app",
  "https://fintracknet.netlify.app",
  "https://fintrack.yencodetechnologies.in",
  "http://localhost:5173",
  "http://localhost:3000",
  "http://localhost:3009",
];

app.use(
  cors({
    origin: (origin, callback) => {
      // Allow requests with no origin (like mobile apps, curl, Postman)
      if (!origin) return callback(null, true);
      const cleanOrigin = origin.replace(/\/+$/, "");
      if (
        allowedOrigins.includes(cleanOrigin) ||
        cleanOrigin.endsWith(".vercel.app") ||
        /^https:\/\/.*\.vercel\.app$/.test(cleanOrigin)
      ) {
        return callback(null, true);
      }
      return callback(null, true);
    },
    credentials: true,
    methods: ["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"],
    allowedHeaders: ["Content-Type", "Authorization", "X-Requested-With", "Accept", "Origin", "X-Socket-Id"],
    optionsSuccessStatus: 200,
  })
);
app.use(express.json({ limit: "50mb" }));
app.use(express.urlencoded({ limit: "50mb", extended: true }));



const authRoutes = require("./routes/authRoutes");
app.use("/api/auth", authRoutes);



const cardRoutes = require("./routes/cardRoutes");
app.use("/api/cards", cardRoutes);

const reminderRoutes = require("./routes/reminderRoutes");

app.use("/reminder", reminderRoutes);
const lendRoutes = require("./routes/lendRoutes");
const liabilityRoutes = require("./routes/liabilityRoutes");
app.use("/api/lend", lendRoutes);
app.use("/api/liability", liabilityRoutes);
const cronReminderRoutes = require("./routes/cronreminderRoutes");

app.use("/api/cron", cronReminderRoutes);

const emailSyncRoutes = require("./routes/emailSyncRoutes");
app.use("/api/email", emailSyncRoutes);

const notificationRoutes = require("./routes/notificationRoutes");
app.use("/api/notifications", notificationRoutes);

const tripRoutes = require("./routes/tripRoutes");
app.use("/api/trips", tripRoutes);

const vehicleRoutes = require("./routes/vehicleRoutes");
app.use("/api/vehicles", vehicleRoutes);

const companyExpenseRoutes = require("./routes/companyExpenseRoutes");
// writes are announced live to the company's members (services/realtime.js)
app.use("/api/company-expense", realtime.announceWrites("company-expense"), companyExpenseRoutes);

const ledgerRoutes = require("./routes/ledgerRoutes");
app.use("/api/ledger", realtime.announceWrites("ledger"), ledgerRoutes);


// Public Privacy Policy Endpoint
app.get("/privacy", (req, res) => {
  res.send(`
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>Privacy Policy - Q Fin (Fintrack)</title>
      <style>
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; line-height: 1.6; color: #333; max-width: 800px; margin: 0 auto; padding: 30px 20px; background: #fafafa; }
        .card { background: #fff; border-radius: 12px; padding: 40px; box-shadow: 0 4px 15px rgba(0,0,0,0.05); }
        h1 { color: #1a202c; border-bottom: 2px solid #edf2f7; padding-bottom: 12px; }
        h2 { color: #2d3748; margin-top: 28px; }
        ul { padding-left: 20px; }
        li { margin-bottom: 8px; }
        .badge { background: #ebf8ff; color: #2b6cb0; font-weight: 600; padding: 4px 10px; border-radius: 6px; font-size: 14px; }
      </style>
    </head>
    <body>
      <div class="card">
        <h1>Privacy Policy for Q Fin</h1>
        <p><span class="badge">Last Updated: August 31, 2026</span></p>
        <p><strong>Yencode Technologies</strong> ("we", "us", or "our") operates the <strong>Q Fin</strong> application. This policy outlines our commitment to protecting your data.</p>
        
        <h2>1. Information We Collect</h2>
        <ul>
          <li><strong>Account Info:</strong> Name, email address, and profile credentials.</li>
          <li><strong>Statement Email Metadata:</strong> With your permission via Google or Yahoo OAuth, we scan headers and text strictly from recognized financial institutions (HDFC, ICICI, Axis, SBI, Kotak, Paytm) to extract due dates and total bill amounts.</li>
          <li><strong>Zero Unrelated Access:</strong> We do NOT access, read, or store any personal emails, contacts, or calendar data.</li>
        </ul>

        <h2>2. How We Use Information</h2>
        <ul>
          <li>To display credit card statement summaries and schedule automated bill payment reminders.</li>
          <li><strong>We do NOT sell, share, trade, or monetize your personal or financial data.</strong></li>
          <li><strong>We do NOT use your data for advertising or marketing targeting.</strong></li>
        </ul>

        <h2>3. Security & Encryption</h2>
        <ul>
          <li>All stored OAuth tokens are secured using <strong>AES-256 encryption</strong>.</li>
          <li>All server communications use secure <strong>HTTPS / TLS 1.3 encryption</strong>.</li>
        </ul>

        <h2>4. Data Control & Deletion</h2>
        <p>You may disconnect email accounts at any time inside app settings. Disconnecting revokes all tokens and permanently deletes them from our servers. You may also request full data deletion by emailing <strong>yencodedeveloper@yahoo.com</strong>.</p>
        
        <hr style="margin-top:40px; border:none; border-top:1px solid #edf2f7;" />
        <p style="font-size:14px; color:#718096;">&copy; 2026 Yencode Technologies. All rights reserved.</p>
      </div>
    </body>
    </html>
  `);
});

app.get("/api/health", (req, res) => {
  res.status(200).json({ status: "ok", timestamp: new Date().toISOString() });
});

const PORT = process.env.PORT || 3009;

async function startServer() {
  await connectDB();
  require("./jobs/reminderCron");
  require("./jobs/emailSyncCron");
  require("./jobs/ledgerDayCloseCron");
  const server = http.createServer(app);
  realtime.init(server);
  server.listen(PORT, "0.0.0.0", () => {
    console.log(`Server running on port ${PORT}`);
  });
}

startServer().catch((error) => {
  console.error("Server startup failed:", error);
  process.exit(1);
});
