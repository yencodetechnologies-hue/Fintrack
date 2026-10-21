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
