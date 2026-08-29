# Email Parser Test Mode Configuration

This document outlines the difference between **Strict Production Mode** (domain filtering) and **Temporary Testing Mode** (keyword matching) for processing bank credit card emails.

---

## 1. File: `backend/services/emailParsers/index.js`

### 🔴 BEFORE (Strict Production Mode - Domain Matching Only)

In production mode, emails are matched strictly by the sender's official bank email domain (`hdfcbank.com`, `icicibank.com`, `axisbank.com`, `sbicard.com`, `kotak.com`, `paytm.com`).

```javascript
const parseHdfc = require("./hdfcParser");
const parseIcici = require("./iciciParser");
const parseAxis = require("./axisParser");
const parsePaytm = require("./paytmParser");
const parseSbi = require("./sbiParser");
const parseKotak = require("./kotakParser");

const PARSERS = [
  { match: (from) => from.includes("hdfcbank.com"), parse: parseHdfc },
  { match: (from) => from.includes("icicibank.com"), parse: parseIcici },
  { match: (from) => from.includes("axisbank.com"), parse: parseAxis },
  { match: (from) => from.includes("paytm.com"), parse: parsePaytm },
  { match: (from) => from.includes("sbicard.com"), parse: parseSbi },
  { match: (from) => from.includes("kotak.com"), parse: parseKotak },
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
```

---

### 🟢 AFTER (Temporary Testing Mode - Keyword Matching Allowed)

In testing mode, emails sent from **any sender address** (personal Gmail, temporary mail, Yahoo) are accepted as long as the email subject or body contains the bank keywords (`hdfc`, `icici`, `axis`, `sbi`, `kotak`, `paytm`).

```javascript
const parseHdfc = require("./hdfcParser");
const parseIcici = require("./iciciParser");
const parseAxis = require("./axisParser");
const parsePaytm = require("./paytmParser");
const parseSbi = require("./sbiParser");
const parseKotak = require("./kotakParser");

const PARSERS = [
  {
    match: (fromLower, body, subjLower) =>
      fromLower.includes("hdfcbank.com") || subjLower.includes("hdfc") || (body && body.toLowerCase().includes("hdfc")),
    parse: parseHdfc,
  },
  {
    match: (fromLower, body, subjLower) =>
      fromLower.includes("icicibank.com") || subjLower.includes("icici") || (body && body.toLowerCase().includes("icici")),
    parse: parseIcici,
  },
  {
    match: (fromLower, body, subjLower) =>
      fromLower.includes("axisbank.com") || subjLower.includes("axis") || (body && body.toLowerCase().includes("axis")),
    parse: parseAxis,
  },
  {
    match: (fromLower, body, subjLower) =>
      fromLower.includes("paytm.com") || subjLower.includes("paytm") || (body && body.toLowerCase().includes("paytm")),
    parse: parsePaytm,
  },
  {
    match: (fromLower, body, subjLower) =>
      fromLower.includes("sbicard.com") || subjLower.includes("sbi") || (body && body.toLowerCase().includes("sbi")),
    parse: parseSbi,
  },
  {
    match: (fromLower, body, subjLower) =>
      fromLower.includes("kotak.com") || subjLower.includes("kotak") || (body && body.toLowerCase().includes("kotak")),
    parse: parseKotak,
  },
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
```

---

## 2. How to Test with Temporary Emails

1. Send an email to your Yahoo or Gmail account from **any email address**.
2. **Subject**: e.g., `HDFC Credit Card Bill Statement` or `SBI Card Due Reminder`
3. **Body Sample**:
   ```text
   Total Amount Due: Rs 12,500
   Minimum Amount Due: Rs 1,250
   Payment Due Date: 15-09-2026
   Credit Card Number: XXXX XXXX XXXX 5678
   ```
4. Perform email sync in Q Fin — the parser will recognize the bank keyword and extract the bill details automatically.
