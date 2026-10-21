import { useEffect, useState } from "react";
import ConfirmDialog from "./ConfirmDialog.jsx";
import ManageCategoriesModal from "./ManageCategoriesModal.jsx";
import { companyCategories } from "../utils.js";
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

export default function SettingsPanel({ company, members, user, isAdmin, onChanged }) {
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

  async function handleAddMember(e) {
    e.preventDefault();
    if (!inviteEmail.trim()) {
      showToast("Enter staff email address", "error");
      return;
    }
    setInviting(true);
    const res = await addCompanyMember(company._id, user.id, inviteEmail.trim(), inviteRole);
    setInviting(false);
    if (res.success) {
      showToast(`${res.member?.name || inviteEmail} added as ${inviteRole === "admin" ? "manager" : "staff"}`);
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
    const res = await inviteCompanyMember(company._id, user.id, email, role);
    setInviting(false);
    if (res.success) {
      showToast(`Invite sent to ${email}`);
      setInviteEmail("");
    } else {
      showToast(res.message || "Failed to send invite", "error");
    }
  }

  async function handleRoleChange(memberUserId, newRole) {
    const res = await setCompanyMemberRole(company._id, user.id, memberUserId, newRole);
    if (res.success) {
      showToast("Staff role updated");
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
      showToast("Staff removed");
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
      <h1 style={{ fontSize: 26, margin: "0 0 6px" }}>Company Settings</h1>
      <p style={{ color: "var(--muted)", fontSize: 13.5, margin: "0 0 28px" }}>
        Manage the join code, direct invites, staff roles, and company configuration.
      </p>

      {isAdmin && (
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
                fontSize: 32,
                fontWeight: 800,
                letterSpacing: 6,
                fontFamily: "Fraunces, serif",
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

      {isAdmin && (
        <div className="card" style={{ maxWidth: 560, marginBottom: 28 }}>
          <h3 style={{ fontSize: 16, marginTop: 0, marginBottom: 6 }}>Direct Staff Invite</h3>
          <p style={{ color: "var(--muted)", fontSize: 12.5, margin: "0 0 16px" }}>
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
              <option value="member">Staff</option>
              <option value="admin">Manager</option>
            </select>
            <button className="btn btn-primary" disabled={inviting}>
              {inviting ? "Adding…" : "Add Staff"}
            </button>
          </form>
        </div>
      )}

      <h3 style={{ fontSize: 16, marginBottom: 10 }}>Staff ({members.length})</h3>
      <div className="card" style={{ maxWidth: 560, padding: 6, marginBottom: 28 }}>
        {members.map((m, idx) => {
          const isCreator = String(company.createdBy) === String(m.userId);
          return (
            <div
              key={m.userId}
              style={{
                display: "flex",
                alignItems: "center",
                gap: 12,
                padding: "10px 12px",
                borderBottom: idx < members.length - 1 ? "1px solid var(--slate-border-2)" : "none",
              }}
            >
              <div
                style={{
                  width: 36,
                  height: 36,
                  borderRadius: "50%",
                  background: "var(--forest)",
                  color: "#fff",
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                  fontWeight: 700,
                  flexShrink: 0,
                }}
              >
                {m.name?.[0]?.toUpperCase() || "M"}
              </div>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ fontWeight: 700, fontSize: 13.5 }}>{m.name}</div>
                <div style={{ fontSize: 11.5, color: "var(--muted)" }}>
                  {isCreator ? "Owner / Creator" : m.role === "admin" ? "Manager" : "Staff"}
                </div>
              </div>

              {isAdmin && !isCreator && (
                <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                  <select
                    className="field-select"
                    style={{ padding: "4px 8px", fontSize: 12 }}
                    value={m.role === "admin" ? "admin" : "member"}
                    onChange={(e) => handleRoleChange(m.userId, e.target.value)}
                  >
                    <option value="member">Staff</option>
                    <option value="admin">Manager</option>
                  </select>
                  <button
                    className="btn btn-outline-danger"
                    style={{ padding: "5px 10px", fontSize: 12 }}
                    onClick={() => setRemoving(m)}
                  >
                    Remove
                  </button>
                </div>
              )}
            </div>
          );
        })}
      </div>

      {isAdmin && (
        <div className="card" style={{ maxWidth: 560, marginBottom: 28, display: "flex", alignItems: "center", justifyContent: "space-between", gap: 12, flexWrap: "wrap" }}>
          <div>
            <h3 style={{ fontSize: 16, margin: "0 0 4px" }}>Expense categories</h3>
            <p style={{ color: "var(--muted)", fontSize: 12.5, margin: 0 }}>
              {companyCategories(company).length} categories offered when posting expenses.
            </p>
          </div>
          <button type="button" className="btn btn-outline" onClick={() => setManagingCategories(true)}>
            Manage categories
          </button>
        </div>
      )}

      {isAdmin && (
        <div className="card" style={{ maxWidth: 560, marginBottom: 28 }}>
          <h3 style={{ fontSize: 16, marginTop: 0, marginBottom: 6 }}>Company Configuration</h3>
          <p style={{ color: "var(--muted)", fontSize: 12.5, margin: "0 0 16px" }}>
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

      {isAdmin && (
        <>
          <h3 style={{ fontSize: 16, marginBottom: 10, color: "var(--terracotta)" }}>Danger Zone</h3>
          <div className="card" style={{ maxWidth: 560, borderColor: "var(--terracotta-soft)" }}>
            <div style={{ fontWeight: 700, fontSize: 13.5, marginBottom: 4 }}>Delete this company</div>
            <p style={{ color: "var(--muted)", fontSize: 12.5, marginTop: 0 }}>
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
          message={`${pendingInvite.email} is not in the user list. Send an invite link to their email? Once they sign up with this email, they'll join ${company.name} as ${pendingInvite.role === "admin" ? "a manager" : "staff"}.`}
          confirmLabel="Send invite"
          onConfirm={confirmSendInvite}
          onCancel={() => setPendingInvite(null)}
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
