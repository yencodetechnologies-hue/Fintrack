import { useState } from "react";
import ConfirmDialog from "./ConfirmDialog.jsx";
import { deleteCompany, regenerateJoinCode, removeMember } from "../api.js";
import { useToast } from "../context/ToastContext.jsx";
import { useNavigate } from "react-router-dom";

export default function SettingsPanel({ company, members, user, isAdmin, onChanged }) {
  const { showToast } = useToast();
  const navigate = useNavigate();
  const [joinCode, setJoinCode] = useState(company.joinCode);
  const [removing, setRemoving] = useState(null);
  const [deleting, setDeleting] = useState(false);

  async function handleRegenerate() {
    const res = await regenerateJoinCode(company._id, user.id);
    if (res.success) {
      setJoinCode(res.joinCode);
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

  async function confirmRemove() {
    const res = await removeMember(company._id, removing.userId, user.id);
    setRemoving(null);
    if (res.success) {
      showToast("Member removed");
      onChanged();
    } else {
      showToast(res.message || "Failed to remove member", "error");
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

  return (
    <div>
      <h1 style={{ fontSize: 26, margin: "0 0 6px" }}>Company Settings</h1>
      <p style={{ color: "var(--muted)", fontSize: 13.5, margin: "0 0 28px" }}>
        Manage the join code, members, and company lifecycle.
      </p>

      {isAdmin && (
        <div className="card" style={{ maxWidth: 480, marginBottom: 28 }}>
          <div className="field-label">Join code (valid 5 minutes after regenerating)</div>
          <div style={{ display: "flex", alignItems: "center", gap: 10, flexWrap: "wrap" }}>
            <div style={{ fontSize: 30, fontWeight: 800, letterSpacing: 5, fontFamily: "Fraunces, serif", color: "var(--forest)" }}>
              {joinCode}
            </div>
            <button className="btn btn-outline" onClick={copyCode}>Copy</button>
            <button className="btn btn-dark" onClick={handleRegenerate}>Regenerate</button>
          </div>
        </div>
      )}

      <h3 style={{ fontSize: 16, marginBottom: 10 }}>Members ({members.length})</h3>
      <div className="card" style={{ maxWidth: 560, padding: 6, marginBottom: 28 }}>
        {members.map((m, idx) => (
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
            <div style={{ width: 36, height: 36, borderRadius: "50%", background: "var(--forest)", color: "#fff", display: "flex", alignItems: "center", justifyContent: "center", fontWeight: 700, flexShrink: 0 }}>
              {m.name?.[0]?.toUpperCase() || "M"}
            </div>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ fontWeight: 700, fontSize: 13.5 }}>{m.name}</div>
              <div style={{ fontSize: 11.5, color: "var(--muted)" }}>{m.role === "admin" ? "Admin" : "Member"}</div>
            </div>
            {isAdmin && m.role !== "admin" && (
              <button className="btn btn-outline-danger" style={{ padding: "6px 10px", fontSize: 12 }} onClick={() => setRemoving(m)}>
                Remove
              </button>
            )}
          </div>
        ))}
      </div>

      {isAdmin && (
        <>
          <h3 style={{ fontSize: 16, marginBottom: 10, color: "var(--terracotta)" }}>Danger zone</h3>
          <div className="card" style={{ maxWidth: 480, borderColor: "var(--terracotta-soft)" }}>
            <div style={{ fontWeight: 700, fontSize: 13.5, marginBottom: 4 }}>Delete this company</div>
            <p style={{ color: "var(--muted)", fontSize: 12.5, marginTop: 0 }}>
              Permanently deletes {company.name} and all its expenses for everyone. This cannot be undone.
            </p>
            <button className="btn btn-outline-danger" onClick={() => setDeleting(true)}>Delete Company</button>
          </div>
        </>
      )}

      {removing && (
        <ConfirmDialog
          title="Remove member?"
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
