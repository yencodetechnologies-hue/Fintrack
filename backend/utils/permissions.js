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

// Custom roles (Company.customRoles) don't start from Manager or Staff: every ability is its own switch, all OFF.
// Behind the scenes a role whose switches go beyond what staff can do gets manager-level access (see roleBase), and
// the "view_all" / "auto_approve" switches decide what managers get automatically.
const mgr = (key) => MANAGER_PERMISSIONS.find((p) => p.key === key);
const CUSTOM_PERMISSIONS = [
  { key: "view_all", label: "See all company expenses", hint: "Otherwise: staff expenses, their own, and ones shared with them", group: "Access" },
  { key: "auto_approve", label: "Their own expenses are approved automatically", hint: "Otherwise they wait for approval", group: "Access" },
  { ...mgr("post_expenses"), group: "Expenses" },
  { ...mgr("post_as_company"), group: "Expenses" },
  { ...mgr("approve_expenses"), label: "Approve / reject expenses", group: "Expenses" },
  { ...mgr("edit_expenses"), group: "Expenses" },
  { ...mgr("record_payments"), group: "Expenses" },
  { ...mgr("verify"), group: "Expenses" },
  { ...mgr("remove_receipts"), group: "Expenses" },
  { key: "borrow", label: "Borrow from another company to pay their own bill", group: "Expenses" },
  { ...mgr("reimburse"), group: "Money" },
  { ...mgr("intercompany"), group: "Money" },
  { ...mgr("vouchers"), group: "Money" },
  { ...mgr("funds"), group: "Money" },
  { ...mgr("reports"), group: "Reports" },
  { ...mgr("analysis"), group: "Reports" },
  { ...mgr("ledger_audit"), group: "Reports" },
  { ...mgr("members"), group: "Company" },
  { ...mgr("settings"), group: "Company" },
  { ...mgr("staff_permissions"), group: "Company" },
  { key: "manager_permissions", label: "Change manager permissions", group: "Admin powers" },
  { key: "manage_roles", label: "Manage custom roles", hint: "Create, change and delete roles, and put people in them", group: "Admin powers" },
  { key: "reverse_transactions", label: "Reverse ledger transactions", group: "Admin powers" },
  { key: "delete_company", label: "Delete the company", group: "Admin powers" },
  { key: "full_admin", label: "All admin access", hint: "Everything the primary admin can do — turns every switch on", group: "Admin powers" },
];

// Switches a plain staff member can already use; turning on anything else gives the role manager-level access.
const STAFF_SAFE = new Set(["post_expenses", "edit_expenses", "record_payments", "intercompany", "vouchers", "settings", "borrow"]);

const LISTS = { manager: MANAGER_PERMISSIONS, staff: STAFF_PERMISSIONS, custom: CUSTOM_PERMISSIONS };

// A custom role's switches: ON only where saved ON; "All admin access" turns every one on.
function resolvedCustom(role) {
  const full = role?.permissions?.full_admin === true;
  const out = {};
  for (const p of CUSTOM_PERMISSIONS) out[p.key] = full || role?.permissions?.[p.key] === true;
  return out;
}

// "manager" when any switch beyond staff abilities is on (its members are stored as admin so those features work).
function roleBase(role) {
  const perms = resolvedCustom(role);
  return Object.entries(perms).some(([key, on]) => on && !STAFF_SAFE.has(key)) ? "manager" : "staff";
}

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
    Company.findById(companyId).select("createdBy external permissions customRoles").lean(),
  ]);
  if (!company) return { role: null, perms: {} };
  if (user?.platformRole === "super_admin" || (!company.external && String(company.createdBy) === String(userId))) {
    return { role: "primary", perms: allOn(MANAGER_PERMISSIONS) };
  }
  const member = await CompanyMember.findOne({ companyId, userId }).select("role customRoleId isAdmin").lean();
  if (!member) return { role: null, perms: {} };
  // an Admin (made so by an Admin) has full access, same as the creator
  if (member.isAdmin) return { role: "primary", perms: allOn(MANAGER_PERMISSIONS) };
  const custom = member.customRoleId ? (company.customRoles || []).find((r) => String(r._id) === String(member.customRoleId)) : null;
  if (custom) {
    return { role: "custom", roleId: String(custom._id), roleName: custom.name, base: roleBase(custom), perms: resolvedCustom(custom) };
  }
  if (member.role === "admin") return { role: "manager", perms: resolved(MANAGER_PERMISSIONS, company.permissions?.manager) };
  return { role: "staff", perms: resolved(STAFF_PERMISSIONS, company.permissions?.staff) };
}

// null when allowed, otherwise the message to refuse with. A key that has no switch for the person's role is allowed.
async function permissionDenied(companyId, userId, key) {
  const who = await permissionsFor(companyId, userId);
  const { role, perms } = who;
  if (!role || role === "primary") return null;
  if (perms[key] !== false) return null;
  const def = LISTS[role === "custom" ? "custom" : role === "manager" ? "manager" : "staff"].find((p) => p.key === key);
  const group = role === "custom" ? `the "${who.roleName}" role` : role === "manager" ? "managers" : "staff";
  return `"${def?.label || key}" is turned off for ${group} in this company`;
}

// an admin power: the primary admin, or a custom role with that switch (or All admin access)
const hasPower = (mine, key) => mine?.role === "primary" || (mine?.role === "custom" && mine.perms?.[key] === true);

module.exports = { MANAGER_PERMISSIONS, STAFF_PERMISSIONS, CUSTOM_PERMISSIONS, LISTS, resolved, resolvedCustom, roleBase, hasPower, permissionsFor, permissionDenied };
