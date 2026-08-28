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

  for (const parser of PARSERS) {
    if (parser.match(fromLower)) {
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
