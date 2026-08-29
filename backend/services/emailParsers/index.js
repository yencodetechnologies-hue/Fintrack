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

module.exports = { parseEmail, GMAIL_SEARCH_QUERY };
