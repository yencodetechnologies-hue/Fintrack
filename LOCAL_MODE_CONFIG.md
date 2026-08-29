# Local Development vs Live Production Code Reference 🟡🟢

This document provides a side-by-side comparison of the **Local Development Code** and **Live Production Code** across all files in the Fintrack project.

---

## 📊 Environment Comparison Matrix

| File / Component | Local Development Code 🟡 | Live Production Code 🟢 |
| :--- | :--- | :--- |
| **Flutter App Base URL** (`lib/config/app_config.dart`) | `http://10.0.2.2:3009` | `https://fintrack.yencodetechnologies.in` |
| **MongoDB URI** (`backend/.env`) | `mongodb://localhost:27017/fintrack` | MongoDB Atlas Cloud Cluster |
| **Yahoo Redirect URI** (`backend/.env`) | `http://localhost:3009/api/email/oauth/callback` | `https://fintrack.yencodetechnologies.in/api/email/oauth/callback` |
| **Sync Rate Limiting** (`backend/services/gmailSyncService.js`) | Rate limit disabled (`return;`) | 5-minute cooldown enforced |
| **Bank Email Parsers** (`backend/services/emailParsers/index.js`) | Subject matching + Fallback enabled | Strict bank domain matching |
| **Gmail Search Query** (`backend/services/emailParsers/index.js`) | Relaxed subject-only search | Strict `from:` sender bank filter |

---

## 🔍 Detailed Code Snippets

### 1. Flutter Base URL (`lib/config/app_config.dart`)

#### 🟡 Local Development Code
```dart
class AppConfig {
  static const String baseUrl = "http://10.0.2.2:3009";
```

#### 🟢 Live Production Code
```dart
class AppConfig {
  static const String baseUrl = "https://fintrack.yencodetechnologies.in";
```

---

### 2. Database & OAuth Environment Variables (`backend/.env`)

#### 🟡 Local Development Code
```env
MONGO_URI=mongodb://localhost:27017/fintrack
PORT=3009
YAHOO_REDIRECT_URI=http://localhost:3009/api/email/oauth/callback
GOOGLE_REDIRECT_URI=http://localhost:3009/api/email/oauth/callback
```

#### 🟢 Live Production Code
```env
MONGO_URI=mongodb://mycard:mycard@ac-7tksjgy-shard-00-00.p4cmrso.mongodb.net:27017,ac-7tksjgy-shard-00-01.p4cmrso.mongodb.net:27017,ac-7tksjgy-shard-00-02.p4cmrso.mongodb.net:27017/fintrack?ssl=true&replicaSet=atlas-z05aq3-shard-0&authSource=admin
PORT=3009
YAHOO_REDIRECT_URI=https://fintrack.yencodetechnologies.in/api/email/oauth/callback
GOOGLE_REDIRECT_URI=https://fintrack.yencodetechnologies.in/api/email/oauth/callback
```

---

### 3. Rate Limit Cooldown (`backend/services/gmailSyncService.js`)

#### 🟡 Local Development Code
```javascript
function checkRateLimit(userId) {
  // Disabled rate limiting for local testing
  return;
}
```

#### 🟢 Live Production Code
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

### 4. Bank Email Parsers (`backend/services/emailParsers/index.js`)

#### 🟡 Local Development Code
```javascript
const PARSERS = [
  { match: (from, body, subject) => from.includes("hdfcbank.com") || subject.toLowerCase().includes("hdfc"), parse: parseHdfc },
  { match: (from, body, subject) => from.includes("icicibank.com") || subject.toLowerCase().includes("icici"), parse: parseIcici },
  { match: (from, body, subject) => from.includes("axisbank.com") || subject.toLowerCase().includes("axis"), parse: parseAxis },
  { match: (from, body, subject) => from.includes("paytm.com") || subject.toLowerCase().includes("paytm"), parse: parsePaytm },
  { match: (from, body, subject) => from.includes("sbicard.com") || subject.toLowerCase().includes("sbi"), parse: parseSbi },
  { match: (from, body, subject) => from.includes("kotak.com") || subject.toLowerCase().includes("kotak"), parse: parseKotak },
  { match: (from, body, subject) => true, parse: parseHdfc }, // Fallback parser for testing
];
```

#### 🟢 Live Production Code
```javascript
const PARSERS = [
  { match: (from) => from.includes("hdfcbank.com"), parse: parseHdfc },
  { match: (from) => from.includes("icicibank.com"), parse: parseIcici },
  { match: (from) => from.includes("axisbank.com"), parse: parseAxis },
  { match: (from) => from.includes("paytm.com"), parse: parsePaytm },
  { match: (from) => from.includes("sbicard.com"), parse: parseSbi },
  { match: (from) => from.includes("kotak.com"), parse: parseKotak },
];
```

---

### 5. Gmail Search Query Filter (`backend/services/emailParsers/index.js`)

#### 🟡 Local Development Code
```javascript
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
```

#### 🟢 Live Production Code
```javascript
const GMAIL_SEARCH_QUERY = [
  "newer_than:45d",
  "(",
  "from:alerts@hdfcbank.com OR",
  "from:credit_cards@icicibank.com OR",
  "from:axisbank.com OR",
  "from:paytm.com OR",
  "from:sbicard.com OR",
  "from:kotak.com",
  ")",
  "(",
  'subject:"credit card" OR',
  'subject:"statement" OR',
  'subject:"payment due" OR',
  'subject:"bill generated" OR',
  'subject:"e-statement"',
  ")",
].join(" ");
```

---

### 🔄 How to Switch Between Modes

1. **To run locally**: Ensure the 🟡 **Local Development Code** snippets above are active in your workspace.
2. **To deploy to production**: Replace the snippets above with the 🟢 **Live Production Code** snippets, commit to Git, and run `git pull && pm2 restart all` on your server.
