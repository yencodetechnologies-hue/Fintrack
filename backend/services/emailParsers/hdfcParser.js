const {
  stripHtml,
  parseAmount,
  parseTotalDue,
  parseDueDate,
  parseStatementDate,
  parseLast4Digits,
} = require("./helpers");

function parseHdfcEmail({ subject, body, messageId }) {
  const text = `${subject} ${stripHtml(body)}`;
  const amount = parseAmount(text);
  const totalDue = parseTotalDue(text);
  const paymentDueDate = parseDueDate(text);
  const statementDate = parseStatementDate(text);
  const last4Digits = parseLast4Digits(text);

  if (!amount && !paymentDueDate) {
    return null;
  }

  return {
    bankName: "HDFC",
    last4Digits,
    amount: amount || totalDue,
    totalDue: totalDue || amount,
    paymentDueDate,
    statementDate,
    sourceMessageId: messageId,
    confidence: paymentDueDate && amount ? "high" : "medium",
  };
}

module.exports = parseHdfcEmail;
