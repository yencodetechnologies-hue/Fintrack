// Feature switches (backend/utils/permissions.js). `can(key)` is true unless the switch is off for this person's
// role; the primary admin always has everything. Switched-off features are hidden, and the backend refuses them too.
export function makeCan(myPermissions) {
  return (key) => !myPermissions || myPermissions[key] !== false;
}

// workspace page -> the switch that opens it
const TAB_PERMISSION = {
  interco: "intercompany",
  reports: "reports",
  analysis: "analysis",
  vouchers: "vouchers",
  payments: "reimburse",
  funds: "funds",
  accounts: "funds",
  transactions: "ledger_audit",
  audit: "ledger_audit",
};

export function tabAllowed(tab, { admin, can, permissionRole }) {
  if (tab === "permissions") {
    if (permissionRole === "primary") return true;
    if (permissionRole === "custom" && (can("manager_permissions") || can("manage_roles"))) return true;
    return (permissionRole === "manager" || (permissionRole === "custom" && admin)) && can("staff_permissions");
  }
  // managers: the Settings page holds both members and company settings
  if (tab === "settings") return admin ? can("settings") || can("members") || permissionRole === "primary" : can("settings");
  const key = TAB_PERMISSION[tab];
  return !key || can(key);
}
