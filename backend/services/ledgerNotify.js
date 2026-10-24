const User = require("../models/user");
const Company = require("../models/company");
const CompanyMember = require("../models/companyMember");
const { buildPushMessage, sendPushToTokens } = require("./notificationService");

const STALE_CODES = new Set(["messaging/registration-token-not-registered", "messaging/invalid-registration-token"]);

async function companyAdminIds(companyId) {
  const company = await Company.findById(companyId).select("createdBy external");
  if (!company || company.external) return [];
  const ids = new Set((await CompanyMember.find({ companyId, role: "admin" })).map((m) => m.userId.toString()));
  if (company.createdBy) ids.add(company.createdBy.toString());
  return [...ids];
}

// Fire-and-forget: a failed push must never fail the ledger action that triggered it.
function notifyUsers(userIds, { title, body, data = {} }, exceptUserId) {
  const ids = [...new Set(userIds.map(String))].filter((id) => id !== String(exceptUserId || ""));
  if (!ids.length) return;
  (async () => {
    const users = await User.find({ _id: { $in: ids } }).select("fcmTokens");
    const tokens = users.flatMap((u) => u.fcmTokens || []).filter(Boolean);
    if (!tokens.length) return;
    const stringData = Object.fromEntries(Object.entries(data).map(([k, v]) => [k, String(v ?? "")]));
    const results = await sendPushToTokens(tokens, buildPushMessage({ title, body, data: stringData, type: "ledger", channelId: "company_updates" }));
    // phones that uninstalled the app or logged out elsewhere: drop their tokens so we stop sending to them
    const stale = tokens.filter((_, i) => !results[i]?.success && STALE_CODES.has(results[i]?.code));
    if (stale.length) await User.updateMany({ _id: { $in: ids } }, { $pull: { fcmTokens: { $in: stale } } });
  })().catch((e) => console.error("ledger notify failed:", e.message));
}

async function notifyCompanyAdmins(companyIds, message, exceptUserId) {
  const lists = await Promise.all([].concat(companyIds).filter(Boolean).map(companyAdminIds));
  notifyUsers(lists.flat(), message, exceptUserId);
}

module.exports = { notifyUsers, notifyCompanyAdmins, companyAdminIds };
