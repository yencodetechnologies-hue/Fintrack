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
const cronReminderRoutes = require("./routes/cronreminderRoutes");

app.use("/api/cron", cronReminderRoutes);

const emailSyncRoutes = require("./routes/emailSyncRoutes");
app.use("/api/email", emailSyncRoutes);

const notificationRoutes = require("./routes/notificationRoutes");
app.use("/api/notifications", notificationRoutes);

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

const PORT = process.env.PORT || 3009;

require("./jobs/emailSyncCron");

app.listen(3009, "0.0.0.0", () => {
  console.log("Server running on port 3009");
});