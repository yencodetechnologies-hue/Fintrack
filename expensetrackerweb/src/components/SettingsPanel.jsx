import { useEffect, useState } from "react";
import { changeCreatorRole, setMemberAdmin, setMemberCustomRole } from "../api.js";
import ConfirmDialog from "./ConfirmDialog.jsx";
import ManageCategoriesModal from "./ManageCategoriesModal.jsx";
import { CompanyLogoCard } from "./CompanyLogo.jsx";
import CompaniesManager from "./CompaniesManager.jsx";
import InvitesList from "./InvitesList.jsx";
import { companyCategories, roleLabel, roleNames } from "../utils.js";
import {
  addCompanyMember,
  deleteCompany,
  inviteCompanyMember,
  regenerateJoinCode,
  removeMember,
  setCompanyMemberRole,
  updateCompanySettings,
} from "../api.js";
import { useToast } from "../context/ToastContext.jsx";
import { useNavigate } from "react-router-dom";
import { TableCard } from "./DataTable.jsx";
import TextSizeCard from "./TextSize.jsx";

export default function SettingsPanel({ company, members, user, isAdmin, can = () => true, powers = {}, onChanged }) {
  const { showToast } = useToast();
  const navigate = useNavigate();

  const [joinCode, setJoinCode] = useState(company.joinCode);
  const [secondsLeft, setSecondsLeft] = useState(() => {
    const rawDate = company.joinCodeCreatedAt || company.updatedAt;
    if (!rawDate) return 300;
    const elapsed = Math.floor((Date.now() - new Date(rawDate).getTime()) / 1000);
    return Math.max(0, 300 - elapsed);
  });

  const [inviteEmail, setInviteEmail] = useState("");
  const [inviteRole, setInviteRole] = useState("member");
  const [inviting, setInviting] = useState(false);
  const [pendingInvite, setPendingInvite] = useState(null); // {email, role} for an email with no account

  const [gstin, setGstin] = useState(company.gstin || "");
  const [currency, setCurrency] = useState(company.currency || "INR");
  const [threshold, setThreshold] = useState(
    company.verificationThreshold !== null && company.verificationThreshold !== undefined
      ? String(company.verificationThreshold)
      : ""
  );
  const [savingSettings, setSavingSettings] = useState(false);

  const [removing, setRemoving] = useState(null);
  const [managingCategories, setManagingCategories] = useState(false);
  const [deleting, setDeleting] = useState(false);

  useEffect(() => {
    if (secondsLeft <= 0) return;
    const interval = setInterval(() => {
      setSecondsLeft((s) => Math.max(0, s - 1));
    }, 1000);
    return () => clearInterval(interval);
  }, [secondsLeft]);

  async function handleRegenerate() {
    const res = await regenerateJoinCode(company._id, user.id);
    if (res.success) {
      setJoinCode(res.joinCode);
      setSecondsLeft(300);
      showToast("Join code regenerated");
    } else {
      showToast(res.message || "Failed to regenerate code", "error");
    }
  }

  async function copyCode() {
    try {
      await navigator.clipboard.writeText(joinCode);
      showToast("Join code copied");
    } catch {
      showToast("Could not copy code", "error");
    }
  }

  const [invitesKey, setInvitesKey] = useState(0);

  async function handleAddMember(e) {
    e.preventDefault();
    if (!inviteEmail.trim()) {
      showToast("Enter the member's email address", "error");
      return;
    }
    setInviting(true);
    const target = inviteTarget(inviteRole);
    const res = await addCompanyMember(company._id, user.id, inviteEmail.trim(), target.role, target.customRoleId);
    setInviting(false);
    if (res.success) {
      showToast(`${res.member?.name || inviteEmail} added as ${target.label}`);
      setInviteEmail("");
      onChanged();
    } else if (res.code === "USER_NOT_FOUND") {
      setPendingInvite({ email: inviteEmail.trim(), role: inviteRole });
    } else {
      showToast(res.message || "Failed to add staff", "error");
    }
  }

  async function confirmSendInvite() {
    const { email, role } = pendingInvite;
    setPendingInvite(null);
    setInviting(true);
    const target = inviteTarget(role);
    const res = await inviteCompanyMember(company._id, user.id, email, target.role, target.customRoleId);
    setInviting(false);
    setInvitesKey((k) => k + 1); // saved even when the email fails, so refresh the Invites list either way
    if (res.success) {
      showToast(`Invite sent to ${email}`);
      setInviteEmail("");
    } else {
      showToast(res.message || "Failed to send invite", "error");
    }
  }

  // primary admin only: puts a member into one of the custom roles (Permissions page)
  const names = roleNames(company);
  // the primary admin, or a custom role with "Manage custom roles"
  const isPrimary = Boolean(powers.manageRoles);
  const iAmAdmin = Boolean(powers.admin); // creator or someone an Admin made Admin
  // another Admin changing the creator's role (asked first): they become the creator
  const [creatorChange, setCreatorChange] = useState(null); // { member, value, label }
  async function confirmCreatorChange() {
    const { member, value } = creatorChange;
    setCreatorChange(null);
    const role = value.startsWith("role:") ? "custom" : value;
    const res = await changeCreatorRole(company._id, member.userId, user.id, role, value.startsWith("role:") ? value.slice(5) : undefined);
    if (!res.success) return showToast(res.message || "Could not change the creator's role", "error");
    showToast(`You're now the creator · ${member.name} is ${creatorChange?.label || "changed"}`);
    onChanged();
  }
  async function handleAdmin(memberUserId, admin) {
    const res = await setMemberAdmin(company._id, memberUserId, user.id, admin);
    if (res.success) {
      showToast(admin ? "Now an Admin" : "No longer an Admin");
      onChanged();
    } else showToast(res.message || "Could not change", "error");
  }
  // the role picker's value: "member" | "admin" | "role:<customRoleId>"
  function inviteTarget(value) {
    if (String(value).startsWith("role:")) {
      const id = value.slice(5);
      const r = (company.customRoles || []).find((x) => String(x._id) === id);
      return { role: r?.base === "manager" ? "admin" : "member", customRoleId: id, label: `"${r?.name || "custom role"}"` };
    }
    return { role: value, customRoleId: null, label: value === "admin" ? "a manager" : "staff" };
  }

  async function handleCustomRole(memberUserId, roleId) {
    const res = await setMemberCustomRole(company._id, memberUserId, user.id, roleId);
    if (res.success) {
      showToast("Role updated");
      onChanged();
    } else {
      showToast(res.message || "Failed to change role", "error");
    }
  }

  async function handleRoleChange(memberUserId, newRole) {
    const res = await setCompanyMemberRole(company._id, user.id, memberUserId, newRole);
    if (res.success) {
      showToast("Role updated");
      onChanged();
    } else {
      showToast(res.message || "Failed to change role", "error");
    }
  }

  async function handleSaveSettings(e) {
    e.preventDefault();
    setSavingSettings(true);
    const res = await updateCompanySettings(company._id, {
      userId: user.id,
      gstin: gstin.trim(),
      currency: currency.trim() || "INR",
      verificationThreshold: threshold.trim() === "" ? null : parseFloat(threshold),
    });
    setSavingSettings(false);
    if (res.success) {
      showToast("Company settings saved");
      onChanged();
    } else {
      showToast(res.message || "Failed to save settings", "error");
    }
  }

  async function confirmRemove() {
    const res = await removeMember(company._id, removing.userId, user.id);
    setRemoving(null);
    if (res.success) {
      showToast(`${names.staff} removed`);
      onChanged();
    } else {
      showToast(res.message || "Failed to remove staff", "error");
    }
  }

  async function confirmDelete() {
    const res = await deleteCompany(company._id, user.id);
    setDeleting(false);
    if (res.success) {
      showToast("Company deleted");
      navigate("/companies", { replace: true });
    } else {
      showToast(res.message || "Failed to delete company", "error");
    }
  }

  const formatTimer = (sec) => {
    const m = String(Math.floor(sec / 60)).padStart(2, "0");
    const s = String(sec % 60).padStart(2, "0");
    return `${m}:${s}`;
  };

  const isExpired = secondsLeft <= 0;

  return (
    <div>
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", flexWrap: "wrap", gap: 10, marginBottom: 6 }}>
        <h1 style={{ fontSize: 22, margin: 0 }}>Settings</h1>
      </div>
      <p style={{ color: "var(--muted)", margin: "0 0 18px" }}>
        Manage the join code, direct invites, staff roles, and company configuration.
      </p>

      {/* everyone: their own text size for the whole web */}
      <TextSizeCard style={{ maxWidth: 560, marginBottom: 28 }} />

      {/* logo first: the primary Admin only */}
      {powers.admin && <CompanyLogoCard company={company} user={user} onChanged={onChanged} />}
      {/* the Admin: add companies, remove one from my list (nothing deleted), restore removed ones */}
      {powers.admin && <CompaniesManager user={user} currentCompanyId={company._id} />}

      {isAdmin && can("settings") && (
        <div className="card" style={{ maxWidth: 560, marginBottom: 28 }}>
          <div className="field-label" style={{ display: "flex", justifyContent: "space-between" }}>
            <span>Join Code</span>
            <span style={{ color: isExpired ? "var(--terracotta)" : "var(--forest)", fontWeight: 700 }}>
              {isExpired ? "Expired" : `Valid for ${formatTimer(secondsLeft)}`}
            </span>
          </div>
          <div style={{ display: "flex", alignItems: "center", gap: 12, flexWrap: "wrap", margin: "10px 0" }}>
            <div
              style={{
                fontSize: 22,
                fontWeight: 800,
                letterSpacing: 6,
                fontFamily: "Helvetica Neue, Helvetica, Arial, sans-serif",
                color: isExpired ? "var(--muted)" : "var(--forest)",
              }}
            >
              {joinCode}
            </div>
            <button className="btn btn-outline" onClick={copyCode} disabled={isExpired}>
              Copy Code
            </button>
            <button className="btn btn-dark" onClick={handleRegenerate}>
              Regenerate Code
            </button>
          </div>
          <small style={{ color: isExpired ? "var(--terracotta)" : "var(--muted)" }}>
            {isExpired
              ? "This join code has expired. Generate a new code to allow colleagues to join."
              : "Share this 6-character code with staff to let them join this workspace."}
          </small>
        </div>
      )}

      {isAdmin && can("members") && (
        <div className="card" style={{ maxWidth: 560, marginBottom: 28 }}>
          <h3 style={{ fontSize: 16, marginTop: 0, marginBottom: 6 }}>Direct Member Invite</h3>
          <p style={{ color: "var(--muted)", fontSize: 13, margin: "0 0 16px" }}>
            Add a registered user directly by email, or invite someone new to sign up and join.
          </p>
          <form onSubmit={handleAddMember} style={{ display: "flex", gap: 10, flexWrap: "wrap" }}>
            <input
              className="field-input"
              type="email"
              placeholder="colleague@example.com"
              value={inviteEmail}
              onChange={(e) => setInviteEmail(e.target.value)}
              style={{ flex: 2, minWidth: 200 }}
              required
            />
            <select
              className="field-select"
              value={inviteRole}
              onChange={(e) => setInviteRole(e.target.value)}
              style={{ flex: 1, minWidth: 110 }}
            >
              <option value="member">{names.staff}</option>
              <option value="admin">{names.manager}</option>
              {/* custom roles: only the primary admin can add people into them */}
              {isPrimary && (company.customRoles || []).map((r) => (
                <option key={r._id} value={`role:${r._id}`}>{r.name}</option>
              ))}
            </select>
            <button className="btn btn-primary" disabled={inviting}>
              {inviting ? "Adding…" : "Add Member"}
            </button>
          </form>
        </div>
      )}

      {/* emailed invites and whether each person has signed up (joined) yet */}
      {isAdmin && can("members") && <InvitesList company={company} user={user} members={members} refreshKey={invitesKey} />}

      {/* the count is staff only; managers (incl. the creator) are listed but not counted */}
      <TableCard
        title="Members"
        meta={memberRoleCounts(members, company, names)}
       items={members}>
        {(rows) => (
          <>
        <table className="dt">
          <thead>
            <tr><th>Name</th><th>Email</th><th>Role</th>{isAdmin && <th className="num">Action</th>}</tr>
          </thead>
          <tbody>
            {rows.map((m) => {
              const isCreator = String(company.createdBy) === String(m.userId);
              const canManage = isAdmin && (can("members") || iAmAdmin) && !isCreator && (!m.isAdmin || iAmAdmin);
              return (
                <tr key={m.userId}>
                  <td className="dt-strong">
                    <span style={{ display: "inline-flex", alignItems: "center", gap: 10 }}>
                      <span className="payments-avatar">{m.name?.[0]?.toUpperCase() || "M"}</span>
                      {m.name}
                    </span>
                  </td>
                  <td className="muted">{m.email || "—"}</td>
                  <td>
                    {isCreator && iAmAdmin && String(m.userId) !== String(user.id) ? (
                      // another Admin can change the creator's role; they then become the creator
                      <select
                        className="field-select"
                        style={{ padding: "4px 8px", fontSize: 13, height: 34, width: "auto" }}
                        value="creator"
                        onChange={(e) => {
                          const v = e.target.value;
                          const label = v === "admin" ? names.admin : v === "manager" ? names.manager : v === "staff" ? names.staff : (company.customRoles || []).find((r) => `role:${r._id}` === v)?.name || "a custom role";
                          setCreatorChange({ member: m, value: v, label });
                        }}
                      >
                        <option value="creator">{names.admin} · Creator</option>
                        <option value="admin">{names.admin}</option>
                        <option value="manager">{names.manager}</option>
                        <option value="staff">{names.staff}</option>
                        {(company.customRoles || []).map((r) => (
                          <option key={r._id} value={`role:${r._id}`}>{r.name}</option>
                        ))}
                      </select>
                    ) : canManage ? (
                      <select
                        className="field-select"
                        style={{ padding: "4px 8px", fontSize: 13, height: 34, width: "auto" }}
                        value={m.isAdmin ? "coadmin" : m.customRoleId ? `role:${m.customRoleId}` : m.role === "admin" ? "admin" : "member"}
                        disabled={Boolean(m.customRoleId) && !isPrimary}
                        title={m.customRoleId && !isPrimary ? "Only the primary admin can change someone in a custom role" : undefined}
                        onChange={(e) => {
                          const v = e.target.value;
                          if (v === "coadmin") return handleAdmin(m.userId, true);
                          if (v.startsWith("role:")) return handleCustomRole(m.userId, v.slice(5));
                          // an Admin back to manager just loses Admin; to staff, the role change clears it too
                          if (m.isAdmin && v === "admin") return handleAdmin(m.userId, false);
                          return handleRoleChange(m.userId, v);
                        }}
                      >
                        <option value="member">{names.staff}</option>
                        <option value="admin">{names.manager}</option>
                        {/* only an Admin can make someone an Admin (full access, like the creator) */}
                        {(iAmAdmin || m.isAdmin) && <option value="coadmin" disabled={!iAmAdmin}>{names.admin}</option>}
                        {(isPrimary || m.customRoleId) && (company.customRoles || []).map((r) => (
                          <option key={r._id} value={`role:${r._id}`} disabled={!isPrimary}>{r.name}</option>
                        ))}
                      </select>
                    ) : (
                      isCreator ? `${names.admin} · Creator` : m.isAdmin ? names.admin : m.customRoleName ? m.customRoleName : roleLabel(company, m.role)
                    )}
                  </td>
                  {isAdmin && (
                    <td>
                      <span className="dt-actions">
                        {canManage && <button className="btn btn-outline-danger btn-sm" onClick={() => setRemoving(m)}>Remove</button>}
                      </span>
                    </td>
                  )}
                </tr>
              );
            })}
          </tbody>
        </table>
      
          </>
        )}
      </TableCard>

      {isAdmin && can("settings") && (
        <div className="card" style={{ maxWidth: 560, marginBottom: 28, display: "flex", alignItems: "center", justifyContent: "space-between", gap: 12, flexWrap: "wrap" }}>
          <div>
            <h3 style={{ fontSize: 16, margin: "0 0 4px" }}>Expense categories</h3>
            <p style={{ color: "var(--muted)", fontSize: 13, margin: 0 }}>
              {companyCategories(company).length} categories offered when posting expenses.
            </p>
          </div>
          <button type="button" className="btn btn-outline" onClick={() => setManagingCategories(true)}>
            Manage categories
          </button>
        </div>
      )}

      {isAdmin && can("settings") && (
        <div className="card" style={{ maxWidth: 560, marginBottom: 28 }}>
          <h3 style={{ fontSize: 16, marginTop: 0, marginBottom: 6 }}>Company Configuration</h3>
          <p style={{ color: "var(--muted)", fontSize: 13, margin: "0 0 16px" }}>
            Configure financial identification, currency and transaction approval threshold.
          </p>
          <form onSubmit={handleSaveSettings}>
            <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(220px, 1fr))", gap: 12 }}>
              <div>
                <label className="field-label">GSTIN / Tax ID</label>
                <input
                  className="field-input"
                  placeholder="e.g. 29ABCDE1234F1Z5"
                  value={gstin}
                  onChange={(e) => setGstin(e.target.value)}
                />
              </div>
              <div>
                <label className="field-label">Currency Code</label>
                <input
                  className="field-input"
                  placeholder="INR"
                  value={currency}
                  onChange={(e) => setCurrency(e.target.value.toUpperCase())}
                />
              </div>
            </div>
            <div style={{ marginTop: 12 }}>
              <label className="field-label">Verification Threshold (₹)</label>
              <input
                className="field-input"
                type="number"
                min="0"
                step="1"
                placeholder="Leave blank for no verification requirement"
                value={threshold}
                onChange={(e) => setThreshold(e.target.value)}
              />
              <small style={{ color: "var(--muted)", display: "block", marginTop: 4 }}>
                Transactions at or above this amount will require secondary manager verification before being settled.
              </small>
            </div>
            <button className="btn btn-primary" style={{ marginTop: 16 }} disabled={savingSettings}>
              {savingSettings ? "Saving…" : "Save Settings"}
            </button>
          </form>
        </div>
      )}

      {/* only the primary admin (company creator) can delete the company */}
      {powers.deleteCompany && (
        <>
          <h3 style={{ fontSize: 16, marginBottom: 10, color: "var(--terracotta)" }}>Danger Zone</h3>
          <div className="card" style={{ maxWidth: 560, borderColor: "var(--terracotta-soft)" }}>
            <div style={{ fontWeight: 700, fontSize: 14, marginBottom: 4 }}>Delete this company</div>
            <p style={{ color: "var(--muted)", fontSize: 13, marginTop: 0 }}>
              Permanently deletes {company.name} and all its expenses and ledger history for everyone.
            </p>
            <button className="btn btn-outline-danger" onClick={() => setDeleting(true)}>
              Delete Company
            </button>
          </div>
        </>
      )}

      {managingCategories && (
        <ManageCategoriesModal company={company} user={user} onClose={() => setManagingCategories(false)} onChanged={onChanged} />
      )}

      {pendingInvite && (
        <ConfirmDialog
          title="Not a Q Fin user yet"
          message={`${pendingInvite.email} is not in the user list. Send an invite link to their email? Once they sign up with this email, they'll join ${company.name} as ${inviteTarget(pendingInvite.role).label}.`}
          confirmLabel="Send invite"
          onConfirm={confirmSendInvite}
          onCancel={() => setPendingInvite(null)}
        />
      )}

      {creatorChange && (
        <ConfirmDialog
          title={`Make ${creatorChange.member.name} ${creatorChange.label}?`}
          message={`${creatorChange.member.name} created ${company.name}. If you change their role, you become the company's creator (${names.admin} · Creator) and ${creatorChange.member.name} becomes ${creatorChange.label}.`}
          confirmLabel="Change role"
          onCancel={() => setCreatorChange(null)}
          onConfirm={confirmCreatorChange}
        />
      )}
      {removing && (
        <ConfirmDialog
          title="Remove staff?"
          message={`Remove ${removing.name} from ${company.name}? They can rejoin later with the join code.`}
          confirmLabel="Remove"
          danger
          onConfirm={confirmRemove}
          onCancel={() => setRemoving(null)}
        />
      )}

      {deleting && (
        <ConfirmDialog
          title="Delete company?"
          message={`This permanently deletes ${company.name} and all its expenses for everyone. This cannot be undone.`}
          confirmLabel="Delete"
          danger
          onConfirm={confirmDelete}
          onCancel={() => setDeleting(false)}
        />
      )}
    </div>
  );
}

// "1 Admin · 3 Partner · 1 Staff": each person counted once, under the role the table shows for them
function memberRoleCounts(members, company, names) {
  const counts = new Map();
  for (const m of members) {
    const label = String(company.createdBy) === String(m.userId) || m.isAdmin
      ? names.admin
      : m.customRoleName || (m.role === "admin" ? names.manager : names.staff);
    counts.set(label, (counts.get(label) || 0) + 1);
  }
  return [...counts].map(([label, n]) => `${n} ${label}`).join(" · ");
}
