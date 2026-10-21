export function fileToBase64(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result);
    reader.onerror = reject;
    reader.readAsDataURL(file);
  });
}

export function money(v) {
  const n = Number(v) || 0;
  return `₹${n.toFixed(2)}`;
}

export function formatDate(d) {
  if (!d) return "";
  const date = new Date(d);
  if (Number.isNaN(date.getTime())) return "";
  return date.toLocaleDateString("en-IN", { day: "2-digit", month: "short", year: "numeric" });
}

export function formatDateTime(d) {
  if (!d) return "";
  const date = new Date(d);
  if (Number.isNaN(date.getTime())) return "";
  return date.toLocaleString("en-IN", {
    day: "2-digit",
    month: "short",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

export function personName(ref, fallback = "Staff") {
  if (!ref) return fallback;
  if (typeof ref === "object") return ref.name || fallback;
  return fallback;
}

export function personId(ref) {
  if (!ref) return "";
  if (typeof ref === "object") return ref._id?.toString() || "";
  return ref.toString();
}

// The categories a company offers: built-ins + its own, minus the ones a manager removed.
export function companyCategories(company, extra = []) {
  const hidden = new Set((company?.hiddenCategories || []).map((c) => c.toLowerCase()));
  const seen = new Set();
  return [...BASE_CATEGORIES, ...(company?.customCategories || []), ...extra].filter((c) => {
    const key = String(c || "").trim().toLowerCase();
    if (!key || hidden.has(key) || seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

// Who an expense is shown as posted by: the company for company-posted expenses, otherwise the person.
export function isCompanyPosted(expense) {
  return expense?.logAs === "company" || expense?.postedAs === "company";
}

export function postedByName(expense, company) {
  if (isCompanyPosted(expense)) return expense.companyId?.name || company?.name || "Company";
  return expense?.createdBy?.name || "Staff";
}

// Status text shown on expenses, naming who actually paid:
// "Paid by OtherCo" when another company paid (borrowed), "Paid by TestCo" for the company itself, "Paid by Meera" for a person.
export function expenseStatusLabel(expense, company) {
  const lifecycle = expense?.lifecycle || "submitted";
  const nameOf = (ref) => (ref && typeof ref === "object" ? ref.name : "");
  if (lifecycle === "paid_by_company") {
    if (expense.payerType === "other_company") return `Paid by ${nameOf(expense.payerCompanyId) || "another company"}`;
    return `Paid by ${expense.companyId?.name || company?.name || "company"}`;
  }
  if (lifecycle === "paid_by_admin" || lifecycle === "paid_by_person") {
    const who = nameOf(expense.paidByUserId) || nameOf(expense.paidByAdminId);
    return who ? `Paid by ${who}` : lifecycle === "paid_by_admin" ? "Paid by manager" : "Paid by staff";
  }
  if (lifecycle === "awaiting_confirmation") return `Awaiting ${nameOf(expense.payerCompanyId) || "payer"} confirmation`;
  return {
    submitted: "Awaiting approval",
    approved: "Approved · unpaid",
    rejected: "Rejected",
    reimbursed: "Reimbursed",
  }[lifecycle] || lifecycle.replaceAll("_", " ");
}

// "Bank of India – Acme Pvt Ltd (…1234)": tells apart accounts at the same bank.
export function bankAccountLabel(b) {
  if (!b) return "";
  const holder = b.accountHolder ? ` – ${b.accountHolder}` : "";
  const last4 = b.accountNumber ? ` (…${String(b.accountNumber).slice(-4)})` : "";
  return `${b.bankName}${holder}${last4}`;
}

export const PAYMENT_MODES = {
  cash: "Cash 💵",
  card: "Card 💳",
  upi: "UPI 📲",
};

export const PAYMENT_METHODS = ["UPI", "Bank", "Cash", "Card"];

export const LEGACY_PAYMENT_MODES = {
  cash: "Cash 💵",
  upi: "UPI / GPay / PhonePe 📲",
  bank_transfer: "Bank Transfer 🏦",
  other: "Other 💳",
};

export const BASE_CATEGORIES = [
  "General",
  "Food & Dining",
  "Travel & Transport",
  "Office Supplies",
  "Utilities",
  "Software & Tech",
  "Other",
];
