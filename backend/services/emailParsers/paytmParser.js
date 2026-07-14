const {
  stripHtml,
  parseAmount,
  parseTotalDue,
  parseDueDate,
  parseStatementDate,
  parseLast4Digits,
} = require("./helpers");

function parsePaytmEmail({ subject, body, messageId }) {
  const text = `${subject} ${stripHtml(body)}`;
  const amount = parseAmount(text);
  const totalDue = parseTotalDue(text);
  let paymentDueDate = parseDueDate(text);
  const statementDate = parseStatementDate(text);
  const last4Digits = parseLast4Digits(text);

  if (!paymentDueDate) {
    const paytmDue = text.match(
      /due\s+(?:on|by|date)[:\s]*(\d{1,2}\s+(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*)/i
    );
    if (paytmDue) {
      paymentDueDate = new Date(`${paytmDue[1]} ${new Date().getFullYear()}`);
    }
  }

  if (!amount && !paymentDueDate) {
    return null;
  }

  return {
    bankName: "Paytm",
    last4Digits,
    amount: amount || totalDue,
    totalDue: totalDue || amount,
    paymentDueDate,
    statementDate,
    sourceMessageId: messageId,
    confidence: paymentDueDate && amount ? "high" : "medium",
  };
}

module.exports = parsePaytmEmail;
