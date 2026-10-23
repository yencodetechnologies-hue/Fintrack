// Per-role feature switches for a company. The primary admin (company creator) sets the managers' list and the
// staff list; other managers may change the staff list, but only for features they have themselves.
// Stored on Company.permissions as { manager: { key: false }, staff: { key: false } } — a missing key means ON.
const Company = require("../models/company");
const CompanyMember = require("../models/companyMember");
const User = require("../models/user");

const MANAGER_PERMISSIONS = [
  { key: "post_expenses", label: "Post expenses" },
  { key: "post_as_company", label: "Post as company", hint: "Pay straight from company Cash/Bank" },
  { key: "approve_expenses", label: "Approve / reject staff expenses" },
  { key: "edit_expenses", label: "Edit / delete expenses" },
  { key: "record_payments", label: "Record payment on bills", hint: "Includes changing who paid" },
  { key: "verify", label: "Verify transactions", hint: "Amounts above the verification threshold" },
  { key: "reimburse", label: "Reimburse people & Payments page", hint: "Also Lend to company" },
  { key: "intercompany", label: "Inter-company", hint: "Lend, borrow, routed payment, repay, mark received" },
  { key: "vouchers", label: "Vouchers", hint: "Create, close, cancel, delete, approve hand-backs" },
  { key: "funds", label: "Company Funds", hint: "Bank accounts, add money, cash name" },
  { key: "reports", label: "Reports & CSV export" },
  { key: "analysis", label: "Analysis" },
  { key: "ledger_audit", label: "Ledger & Audit log" },
  { key: "members", label: "Members", hint: "Add, invite, remove, change role" },
  { key: "settings", label: "Company settings", hint: "GSTIN, threshold, categories, join code" },
  { key: "remove_receipts", label: "Remove receipt / proof images" },
  { key: "staff_permissions", label: "Change staff permissions" },
];

// `needs`: the manager switch a (non-primary) manager must have before turning this staff switch on
const STAFF_PERMISSIONS = [
  { key: "post_expenses", label: "Post expenses", needs: "post_expenses" },
  { key: "edit_expenses", label: "Edit / delete their own expenses", hint: "Only before approval", needs: "edit_expenses" },
  { key: "borrow", label: "Borrow from another company to pay their bill", needs: "intercompany" },
  { key: "vouchers", label: "Vouchers", hint: "Claim, hand back balance", needs: "vouchers" },
  { key: "intercompany", label: "See the Inter-co page", needs: "intercompany" },
  { key: "settings", label: "See company settings & join code", needs: "settings" },
];

const LISTS = { manager: MANAGER_PERMISSIONS, staff: STAFF_PERMISSIONS };

function resolved(list, stored) {
  const out = {};
  for (const p of list) out[p.key] = !(stored && stored[p.key] === false);
  return out;
}

const allOn = (list) => resolved(list, null);

// What this person may do in this company: { role: "primary"|"manager"|"staff"|null, perms: { key: bool } }.
// The primary admin and super admins always have everything.
async function permissionsFor(companyId, userId) {
  if (!userId || !companyId) return { role: null, perms: {} };
  const [user, company] = await Promise.all([
    User.findById(userId).select("platformRole").lean(),
    Company.findById(companyId).select("createdBy external permissions").lean(),
  ]);
  if (!company) return { role: null, perms: {} };
  if (user?.platformRole === "super_admin" || (!company.external && String(company.createdBy) === String(userId))) {
    return { role: "primary", perms: allOn(MANAGER_PERMISSIONS) };
  }
  const member = await CompanyMember.findOne({ companyId, userId }).select("role").lean();
  if (!member) return { role: null, perms: {} };
  if (member.role === "admin") return { role: "manager", perms: resolved(MANAGER_PERMISSIONS, company.permissions?.manager) };
  return { role: "staff", perms: resolved(STAFF_PERMISSIONS, company.permissions?.staff) };
}

// null when allowed, otherwise the message to refuse with. A key that has no switch for the person's role is allowed.
async function permissionDenied(companyId, userId, key) {
  const { role, perms } = await permissionsFor(companyId, userId);
  if (!role || role === "primary") return null;
  if (perms[key] !== false) return null;
  const def = LISTS[role === "manager" ? "manager" : "staff"].find((p) => p.key === key);
  return `"${def?.label || key}" is turned off for ${role === "manager" ? "managers" : "staff"} in this company`;
}

module.exports = { MANAGER_PERMISSIONS, STAFF_PERMISSIONS, LISTS, resolved, permissionsFor, permissionDenied };
