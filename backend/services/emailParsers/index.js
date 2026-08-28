const parseHdfc = require("./hdfcParser");
const parseIcici = require("./iciciParser");
const parseAxis = require("./axisParser");
const parsePaytm = require("./paytmParser");
const parseSbi = require("./sbiParser");
const parseKotak = require("./kotakParser");

const PARSERS = [
  { match: (from, body, subject) => from.includes("hdfcbank.com") || subject.toLowerCase().includes("hdfc"), parse: parseHdfc },
  { match: (from, body, subject) => from.includes("icicibank.com") || subject.toLowerCase().includes("icici"), parse: parseIcici },
  { match: (from, body, subject) => from.includes("axisbank.com") || subject.toLowerCase().includes("axis"), parse: parseAxis },
  { match: (from, body, subject) => from.includes("paytm.com") || subject.toLowerCase().includes("paytm"), parse: parsePaytm },
  { match: (from, body, subject) => from.includes("sbicard.com") || subject.toLowerCase().includes("sbi"), parse: parseSbi },
  { match: (from, body, subject) => from.includes("kotak.com") || subject.toLowerCase().includes("kotak"), parse: parseKotak },
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
