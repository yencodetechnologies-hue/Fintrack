# Email Sync Testing Changes & Revert Guide

This document records temporary testing changes made to the backend, MongoDB database config, and Flutter app.

---

## 1. Modified File: Local MongoDB URI Config
- File: [backend/.env](file:///e:/Yencode/Fintrack/backend/.env)

### Currently Active Testing Code (Local MongoDB Server):
```env
MONGO_URI=mongodb://localhost:27017/fintrack
```

### Production Code to Revert To (Atlas Cluster):
```env
MONGO_URI=mongodb://mycard:mycard@ac-7tksjgy-shard-00-00.p4cmrso.mongodb.net:27017,ac-7tksjgy-shard-00-01.p4cmrso.mongodb.net:27017,ac-7tksjgy-shard-00-02.p4cmrso.mongodb.net:27017/fintrack?ssl=true&replicaSet=atlas-z05aq3-shard-0&authSource=admin
```

---

## 2. Modified File: Flutter App Local Backend Config
- File: [lib/config/app_config.dart](file:///e:/Yencode/Fintrack/lib/config/app_config.dart)

### Currently Active Testing Code (Local Android Emulator Backend):
```dart
class AppConfig {
  static const String baseUrl = "http://10.0.2.2:3009";
```

### Production Code to Revert To:
```dart
class AppConfig {
  static const String baseUrl = "https://fintrack.yencodetechnologies.in";
```

---

## 3. Modified File: Backend Rate Limit Bypass
- File: [backend/services/gmailSyncService.js](file:///e:/Yencode/Fintrack/backend/services/gmailSyncService.js)

### Currently Active Testing Code:
```javascript
function checkRateLimit(userId) {
  // Disabled rate limiting for testing
  return;
}
```

### Production Code to Revert To:
```javascript
function checkRateLimit(userId) {
  const last = syncRateLimit.get(userId);
  if (last && Date.now() - last < SYNC_COOLDOWN_MS) {
    const waitSec = Math.ceil((SYNC_COOLDOWN_MS - (Date.now() - last)) / 1000);
    throw new Error(`Please wait ${waitSec}s before syncing again`);
  }
  syncRateLimit.set(userId, Date.now());
}
```

---

## 4. Modified File: Sender & Query Rule Bypass
- File: [backend/services/emailParsers/index.js](file:///e:/Yencode/Fintrack/backend/services/emailParsers/index.js)

### Currently Active Testing Code:
```javascript
const parseHdfc = require("./hdfcParser");
const parseIcici = require("./iciciParser");
const parseAxis = require("./axisParser");
const parsePaytm = require("./paytmParser");

const PARSERS = [
  { match: (from, body, subject) => from.includes("hdfcbank.com") || subject.toLowerCase().includes("hdfc"), parse: parseHdfc },
  { match: (from, body, subject) => from.includes("icicibank.com") || subject.toLowerCase().includes("icici"), parse: parseIcici },
  { match: (from, body, subject) => from.includes("axisbank.com") || subject.toLowerCase().includes("axis"), parse: parseAxis },
  { match: (from, body, subject) => from.includes("paytm.com") || subject.toLowerCase().includes("paytm"), parse: parsePaytm },
  { match: (from, body, subject) => true, parse: parseHdfc }, // Fallback parser for testing
];

function parseEmail({ from, subject, body, messageId }) {
  const fromLower = (from || "").toLowerCase();
  const subjLower = (subject || "").toLowerCase();

  for (const parser of PARSERS) {
    if (parser.match(fromLower, body, subjLower)) {
      const res = parser.parse({ subject, body, messageId });
      if (res) return res;
    }
  }

  return null;
}

const GMAIL_SEARCH_QUERY = [
  "newer_than:45d",
  "(",
  'subject:"credit card" OR',
  'subject:"statement" OR',
  'subject:"payment due" OR',
  'subject:"bill generated" OR',
  'subject:"e-statement"',
  ")",
].join(" ");

module.exports = { parseEmail, GMAIL_SEARCH_QUERY };
```

### Production Code to Revert To:
```javascript
const parseHdfc = require("./hdfcParser");
const parseIcici = require("./iciciParser");
const parseAxis = require("./axisParser");
const parsePaytm = require("./paytmParser");

const PARSERS = [
  { match: (from) => from.includes("hdfcbank.com"), parse: parseHdfc },
  { match: (from) => from.includes("icicibank.com"), parse: parseIcici },
  { match: (from) => from.includes("axisbank.com"), parse: parseAxis },
  { match: (from) => from.includes("paytm.com"), parse: parsePaytm },
];

function parseEmail({ from, subject, body, messageId }) {
  const fromLower = (from || "").toLowerCase();

  for (const parser of PARSERS) {
    if (parser.match(fromLower)) {
      return parser.parse({ subject, body, messageId });
    }
  }

  return null;
}

const GMAIL_SEARCH_QUERY = [
  "newer_than:45d",
  "(",
  "from:alerts@hdfcbank.com OR",
  "from:credit_cards@icicibank.com OR",
  "from:axisbank.com OR",
  "from:paytm.com",
  ")",
  "(",
  'subject:"credit card" OR',
  'subject:"statement" OR',
  'subject:"payment due" OR',
  'subject:"bill generated" OR',
  'subject:"e-statement"',
  ")",
].join(" ");

module.exports = { parseEmail, GMAIL_SEARCH_QUERY };
```
