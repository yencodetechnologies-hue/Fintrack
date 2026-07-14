const crypto = require("crypto");

function stripHtml(html) {
  return html
    .replace(/<style[^>]*>[\s\S]*?<\/style>/gi, " ")
    .replace(/<script[^>]*>[\s\S]*?<\/script>/gi, " ")
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&#8377;/g, "₹")
    .replace(/\s+/g, " ")
    .trim();
}

function parseAmount(text) {
  const patterns = [
    /(?:minimum\s+(?:amount\s+)?due|min(?:imum)?\.?\s+due|amount\s+due|total\s+due|total\s+amount\s+due|payment\s+due)[:\s]*(?:rs\.?|inr|₹)?\s*([\d,]+(?:\.\d{1,2})?)/i,
    /(?:rs\.?|inr|₹)\s*([\d,]+(?:\.\d{1,2})?)/i,
  ];

  for (const pattern of patterns) {
    const match = text.match(pattern);
    if (match) {
      const value = parseFloat(match[1].replace(/,/g, ""));
      if (!Number.isNaN(value) && value > 0) {
        return value;
      }
    }
  }
  return null;
}

function parseTotalDue(text) {
  const match = text.match(
    /total\s+(?:amount\s+)?due[:\s]*(?:rs\.?|inr|₹)?\s*([\d,]+(?:\.\d{1,2})?)/i
  );
  if (match) {
    const value = parseFloat(match[1].replace(/,/g, ""));
    if (!Number.isNaN(value) && value > 0) {
      return value;
    }
  }
  return null;
}

function parseDateFromText(text) {
  const patterns = [
    /(\d{1,2}[-/]\d{1,2}[-/]\d{2,4})/,
    /(\d{1,2}\s+(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\s+\d{2,4})/i,
    /((?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\s+\d{1,2},?\s+\d{2,4})/i,
  ];

  for (const pattern of patterns) {
    const match = text.match(pattern);
    if (match) {
      const parsed = new Date(match[1]);
      if (!Number.isNaN(parsed.getTime())) {
        return parsed;
      }
    }
  }
  return null;
}

function parseDueDate(text) {
  const duePatterns = [
    /payment\s+due\s+(?:date|on|by)[:\s]*(\d{1,2}[-/]\d{1,2}[-/]\d{2,4})/i,
    /payment\s+due\s+(?:date|on|by)[:\s]*(\d{1,2}\s+(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\s+\d{2,4})/i,
    /due\s+(?:date|on|by)[:\s]*(\d{1,2}[-/]\d{1,2}[-/]\d{2,4})/i,
    /due\s+(?:date|on|by)[:\s]*(\d{1,2}\s+(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\s+\d{2,4})/i,
    /pay\s+by[:\s]*(\d{1,2}[-/]\d{1,2}[-/]\d{2,4})/i,
  ];

  for (const pattern of duePatterns) {
    const match = text.match(pattern);
    if (match) {
      const parsed = new Date(match[1]);
      if (!Number.isNaN(parsed.getTime())) {
        return parsed;
      }
    }
  }
  return parseDateFromText(text);
}

function parseStatementDate(text) {
  const patterns = [
    /statement\s+(?:date|period)[:\s]*(\d{1,2}[-/]\d{1,2}[-/]\d{2,4})/i,
    /statement\s+(?:date|period)[:\s]*(\d{1,2}\s+(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\s+\d{2,4})/i,
    /billing\s+(?:date|period)[:\s]*(\d{1,2}[-/]\d{1,2}[-/]\d{2,4})/i,
  ];

  for (const pattern of patterns) {
    const match = text.match(pattern);
    if (match) {
      const parsed = new Date(match[1]);
      if (!Number.isNaN(parsed.getTime())) {
        return parsed;
      }
    }
  }
  return null;
}

function parseLast4Digits(text) {
  const patterns = [
    /(?:card|ending|xx+|x{2,})\s*[- ]*(\d{4})/i,
    /\*{2,}\s*(\d{4})/,
    /(\d{4})\s*(?:is\s+)?(?:your|the)\s+card/i,
  ];

  for (const pattern of patterns) {
    const match = text.match(pattern);
    if (match) {
      return match[1];
    }
  }
  return null;
}

function normalizeBankName(name) {
  return name.toLowerCase().replace(/[^a-z0-9]/g, "");
}

function banksMatch(a, b) {
  if (!a || !b) return false;
  const na = normalizeBankName(a);
  const nb = normalizeBankName(b);
  return na.includes(nb) || nb.includes(na);
}

function hashContent(text) {
  return crypto.createHash("sha256").update(text).digest("hex");
}

module.exports = {
  stripHtml,
  parseAmount,
  parseTotalDue,
  parseDueDate,
  parseStatementDate,
  parseLast4Digits,
  banksMatch,
  hashContent,
};
