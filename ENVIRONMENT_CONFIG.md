# 🛠️ Fintrack Environment Configuration Guide

This document outlines all current configuration settings for **Local Testing Mode** versus **Live Production Mode**.

---

## 📌 Current Mode: **LIVE PRODUCTION MODE** 🟢

The application is currently pointed to the **Live Production Backend** (`https://fintrack.yencodetechnologies.in`).

| Setting / Component | Local Value | Live Production Value |
| :--- | :--- | :--- |
| **Flutter Base URL** ([app_config.dart](file:///e:/Yencode/Fintrack/lib/config/app_config.dart#L4)) | `"http://10.0.2.2:3009"` | `"https://fintrack.yencodetechnologies.in"` |
| **MongoDB Connection** ([backend/.env](file:///e:/Yencode/Fintrack/backend/.env#L1)) | `mongodb://localhost:27017/fintrack` | `mongodb://mycard:mycard@ac-7tksjgy-shard-00-00.../fintrack?ssl=true&...` |
| **Yahoo Redirect URI** ([backend/.env](file:///e:/Yencode/Fintrack/backend/.env#L26)) | `https://fintrack.yencodetechnologies.in/api/email/oauth/callback` | `https://fintrack.yencodetechnologies.in/api/email/oauth/callback` |
| **Gmail Sync Rate Limiter** ([gmailSyncService.js](file:///e:/Yencode/Fintrack/backend/services/gmailSyncService.js#L17)) | Disabled (`return;`) | 5-Minute Cooldown (`checkRateLimit`) |
| **Bank Email Parsers** ([emailParsers/index.js](file:///e:/Yencode/Fintrack/backend/services/emailParsers/index.js#L8)) | Relaxed matching + Fallback | Strict domain match (`hdfcbank.com`, etc.) |
| **Gmail Search Query** ([emailParsers/index.js](file:///e:/Yencode/Fintrack/backend/services/emailParsers/index.js#L30)) | Subject-only matching | Strict `from:alerts@hdfcbank.com OR ...` |

---

## 🔄 How to Switch Back to LIVE PRODUCTION MODE

When you are ready to build the release APK or deploy to production, update these 4 files:

### 1. `lib/config/app_config.dart`
```dart
static const String baseUrl = "https://fintrack.yencodetechnologies.in";
```

### 2. `backend/.env`
```env
MONGO_URI=mongodb://mycard:mycard@ac-7tksjgy-shard-00-00.p4cmrso.mongodb.net:27017,ac-7tksjgy-shard-00-01.p4cmrso.mongodb.net:27017,ac-7tksjgy-shard-00-02.p4cmrso.mongodb.net:27017/fintrack?ssl=true&replicaSet=atlas-z05aq3-shard-0&authSource=admin
YAHOO_REDIRECT_URI=https://fintrack.yencodetechnologies.in/api/email/oauth/callback
```

### 3. `backend/services/gmailSyncService.js`
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

### 4. `backend/services/emailParsers/index.js`
```javascript
const PARSERS = [
  { match: (from) => from.includes("hdfcbank.com"), parse: parseHdfc },
  { match: (from) => from.includes("icicibank.com"), parse: parseIcici },
  { match: (from) => from.includes("axisbank.com"), parse: parseAxis },
  { match: (from) => from.includes("paytm.com"), parse: parsePaytm },
  { match: (from) => from.includes("sbicard.com"), parse: parseSbi },
  { match: (from) => from.includes("kotak.com"), parse: parseKotak },
];

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

## 🌐 Yahoo OAuth Live Shared Callback Path
Both Gmail and Yahoo share the exact same OAuth callback endpoint:
```text
https://fintrack.yencodetechnologies.in/api/email/oauth/callback
```
