import { useCallback, useEffect, useState } from "react";
import { cancelCompanyInvite, getCompanyInvites, inviteCompanyMember } from "../api.js";
import { useToast } from "../context/ToastContext.jsx";
import { formatDate, roleLabel } from "../utils.js";
import ConfirmDialog from "./ConfirmDialog.jsx";

// People invited by email and where they are: invite sent (waiting to sign up), email failed, or joined.
// Pending ones can be resent or cancelled. refreshKey changes after a new invite is sent.
export default function InvitesList({ company, user, refreshKey }) {
  const { showToast } = useToast();
  const [invites, setInvites] = useState(null);
  const [busy, setBusy] = useState("");
  const [cancelling, setCancelling] = useState(null);

  const load = useCallback(() => {
    getCompanyInvites(company._id, user.id).then((res) => setInvites(res.success ? res.invites || [] : []));
  }, [company._id, user.id]);
  useEffect(load, [load, refreshKey]);

  async function resend(inv) {
    setBusy(inv._id);
    const res = await inviteCompanyMember(company._id, user.id, inv.email, inv.role, inv.customRoleId);
    setBusy("");
    showToast(res.success ? `Invite sent again to ${inv.email}` : res.message || "Could not resend", res.success ? undefined : "error");
    load();
  }

  async function cancel() {
    const inv = cancelling;
    setCancelling(null);
    setBusy(inv._id);
    const res = await cancelCompanyInvite(company._id, inv._id, user.id);
    setBusy("");
    showToast(res.success ? `Invite to ${inv.email} cancelled` : res.message || "Could not cancel", res.success ? undefined : "error");
    load();
  }

  if (!invites || invites.length === 0) return null;
  const waiting = invites.filter((i) => i.status !== "accepted").length;

  return (
    <div className="card" style={{ maxWidth: 560, marginBottom: 28, padding: 0 }}>
      <div style={{ padding: "14px 16px 6px" }}>
        <h3 style={{ fontSize: 16, margin: 0 }}>Invites</h3>
        <p style={{ color: "var(--muted)", fontSize: 13, margin: "4px 0 0" }}>
          {waiting ? `${waiting} waiting to sign up · ` : ""}{invites.length - waiting} joined
        </p>
      </div>
      {invites.map((inv) => {
        const joined = inv.status === "accepted";
        const status = joined
          ? { text: `Joined${inv.acceptedAt ? ` · ${formatDate(inv.acceptedAt)}` : ""}`, color: "var(--forest)", bg: "#E8F7EF", icon: "✓" }
          : inv.emailSent
          ? { text: `Invite sent${inv.sentAt ? ` · ${formatDate(inv.sentAt)}` : ""} · waiting to sign up`, color: "#B45309", bg: "#FFF7ED", icon: "✉" }
          : { text: "Email not sent · resend it", color: "var(--terracotta)", bg: "#FEF2F2", icon: "!" };
        return (
          <div key={inv._id} style={{ display: "flex", alignItems: "center", gap: 10, padding: "10px 16px", borderTop: "1px solid var(--slate-border-2)", flexWrap: "wrap" }}>
            <div style={{ flex: 1, minWidth: 180 }}>
              <div style={{ fontWeight: 600, fontSize: 14, overflow: "hidden", textOverflow: "ellipsis" }}>{inv.email}</div>
              <div style={{ fontSize: 12, color: "var(--muted)" }}>
                as {inv.roleName || roleLabel(company, inv.role)}{inv.invitedBy ? ` · by ${inv.invitedBy}` : ""}
              </div>
            </div>
            <span style={{ fontSize: 12, fontWeight: 700, color: status.color, background: status.bg, padding: "4px 10px", borderRadius: 99, whiteSpace: "nowrap" }}>
              {status.icon} {status.text}
            </span>
            {!joined && (
              <span style={{ display: "flex", gap: 6 }}>
                <button type="button" className="btn btn-outline btn-sm" disabled={busy === inv._id} onClick={() => resend(inv)}>Resend</button>
                <button type="button" className="btn btn-outline-danger btn-sm" disabled={busy === inv._id} onClick={() => setCancelling(inv)}>Cancel</button>
              </span>
            )}
          </div>
        );
      })}
      {cancelling && (
        <ConfirmDialog
          title="Cancel this invite?"
          message={`${cancelling.email} won't be added to ${company.name} when they sign up. You can invite them again later.`}
          confirmLabel="Cancel invite"
          danger
          onCancel={() => setCancelling(null)}
          onConfirm={cancel}
        />
      )}
    </div>
  );
}
