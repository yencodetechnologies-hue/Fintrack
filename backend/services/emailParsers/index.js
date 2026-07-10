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
