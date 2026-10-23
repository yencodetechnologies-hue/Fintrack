import { useState } from "react";
import { createCustomRole, deleteCustomRole, setMemberCustomRole, updateCustomRole } from "../api.js";
import { useToast } from "../context/ToastContext.jsx";
import ConfirmDialog from "./ConfirmDialog.jsx";
import Modal from "./Modal.jsx";

const BASE_LABEL = { manager: "Manager-like", staff: "Staff-like" };

// Primary admin only: roles on top of Manager/Staff. Each role has a base (how its members behave: manager-like
// see everything and are auto-approved, staff-like post for approval), its own switches (all start OFF), and
// members. Deleting a role removes its members from the company.
export default function CustomRoles({ companyId, company, user, members, definitions, roles, onChanged }) {
  const { showToast } = useToast();
  const [adding, setAdding] = useState(false);
  const [renaming, setRenaming] = useState(null);
  const [deleting, setDeleting] = useState(null);
  const [busy, setBusy] = useState("");
  const [local, setLocal] = useState({}); // optimistic switch values per role id

  const creatorId = String(company?.createdBy?._id || company?.createdBy || "");
  const roleOf = (userId) => roles.find((r) => r.members.some((m) => String(m.userId) === String(userId)));

  async function toggle(role, key, on) {
    setLocal((cur) => ({ ...cur, [role._id]: { ...(cur[role._id] || role.permissions), [key]: on } }));
    setBusy(`${role._id}.${key}`);
    const res = await updateCustomRole(companyId, role._id, user.id, { permissions: { [key]: on } });
    setBusy("");
    if (!res.success) {
      setLocal((cur) => ({ ...cur, [role._id]: role.permissions }));
      showToast(res.message || "Could not save", "error");
    } else {
      setLocal((cur) => ({ ...cur, [role._id]: res.role.permissions }));
      onChanged();
    }
  }

  async function setAll(role, on) {
    const next = Object.fromEntries(definitions.map((d) => [d.key, on && !(d.only && d.only !== role.base)]));
    setBusy(`${role._id}.*`);
    const res = await updateCustomRole(companyId, role._id, user.id, { permissions: next });
    setBusy("");
    if (!res.success) return showToast(res.message || "Could not save", "error");
    setLocal((cur) => ({ ...cur, [role._id]: res.role.permissions }));
    onChanged();
  }

  async function assign(role, memberUserId) {
    if (!memberUserId) return;
    setBusy(`${role._id}.member`);
    const res = await setMemberCustomRole(companyId, memberUserId, user.id, role._id);
    setBusy("");
    if (!res.success) return showToast(res.message || "Could not add to role", "error");
    showToast(`Added to ${role.name}`);
    onChanged();
  }

  async function unassign(role, member) {
    setBusy(`${role._id}.member`);
    const res = await setMemberCustomRole(companyId, member.userId, user.id, null);
    setBusy("");
    if (!res.success) return showToast(res.message || "Could not update", "error");
    showToast(`${member.name} is now staff`);
    onChanged();
  }

  async function confirmDelete() {
    const role = deleting;
    setDeleting(null);
    const res = await deleteCustomRole(companyId, role._id, user.id);
    if (!res.success) return showToast(res.message || "Could not delete role", "error");
    showToast(res.removed ? `"${role.name}" deleted · ${res.removed} member${res.removed === 1 ? "" : "s"} removed from ${company?.name || "the company"}` : `"${role.name}" deleted`);
    onChanged();
  }

  return (
    <section style={{ marginTop: 28 }}>
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 10, flexWrap: "wrap", marginBottom: 6 }}>
        <h2 style={{ margin: 0, fontSize: 20 }}>Custom roles</h2>
        <button type="button" className="btn btn-primary" onClick={() => setAdding(true)}>+ Add role</button>
      </div>
      <p style={{ color: "var(--muted)", fontSize: 13, margin: "0 0 16px", maxWidth: 680 }}>
        Make your own roles, like Accountant or Site supervisor. Every switch starts off — turn on only what the role needs. Only you can change roles or put people in them.
      </p>

      {roles.length === 0 ? (
        <div className="card" style={{ color: "var(--muted)", textAlign: "center", padding: 24 }}>No custom roles yet.</div>
      ) : (
        <div className="perm-grid">
          {roles.map((role) => {
            const values = local[role._id] || role.permissions;
            const usable = definitions.filter((d) => !(d.only && d.only !== role.base));
            const onCount = usable.filter((d) => values[d.key]).length;
            const candidates = members.filter((m) => String(m.userId) !== creatorId && !role.members.some((x) => String(x.userId) === String(m.userId)));
            return (
              <div key={role._id} className="card perm-card">
                <div className="perm-card-head">
                  <div style={{ minWidth: 0 }}>
                    <h2 style={{ margin: 0, fontSize: 18, overflowWrap: "anywhere" }}>{role.name}</h2>
                    <div style={{ display: "flex", gap: 6, alignItems: "center", marginTop: 4, flexWrap: "wrap" }}>
                      <span className={`role-base ${role.base}`}>{BASE_LABEL[role.base]}</span>
                      <span style={{ color: "var(--muted)", fontSize: 12 }}>{role.members.length} member{role.members.length === 1 ? "" : "s"}</span>
                    </div>
                  </div>
                  <span className="perm-count">{onCount}/{usable.length} on</span>
                </div>

                <div className="perm-bulk">
                  <button type="button" className="voucher-ticket-link" disabled={Boolean(busy)} onClick={() => setAll(role, true)}>Turn all on</button>
                  <span aria-hidden="true">·</span>
                  <button type="button" className="voucher-ticket-link" disabled={Boolean(busy)} onClick={() => setAll(role, false)}>Turn all off</button>
                  <span aria-hidden="true">·</span>
                  <button type="button" className="voucher-ticket-link" onClick={() => setRenaming({ role, name: role.name })}>Rename</button>
                  <span aria-hidden="true">·</span>
                  <button type="button" className="voucher-ticket-link" style={{ color: "var(--terracotta)" }} onClick={() => setDeleting(role)}>Delete</button>
                </div>

                <div className="role-members">
                  <div className="role-members-head">Members</div>
                  {role.members.length === 0 && <div style={{ color: "var(--muted)", fontSize: 12.5 }}>Nobody in this role yet.</div>}
                  <div style={{ display: "flex", flexWrap: "wrap", gap: 6 }}>
                    {role.members.map((m) => (
                      <span key={m.userId} className="role-member-chip">
                        {m.name}
                        <button type="button" title="Take out of this role (becomes staff)" disabled={Boolean(busy)} onClick={() => unassign(role, m)}>✕</button>
                      </span>
                    ))}
                  </div>
                  {candidates.length > 0 && (
                    <select className="field-select role-add-member" value="" disabled={Boolean(busy)} onChange={(e) => assign(role, e.target.value)}>
                      <option value="">+ Add a member…</option>
                      {candidates.map((m) => {
                        const current = roleOf(m.userId);
                        return (
                          <option key={m.userId} value={m.userId}>
                            {m.name} · {current ? current.name : m.role === "admin" ? "Manager" : "Staff"}
                          </option>
                        );
                      })}
                    </select>
                  )}
                </div>

                <ul className="perm-list">
                  {definitions.map((def) => {
                    const blocked = Boolean(def.only && def.only !== role.base);
                    const on = !blocked && Boolean(values[def.key]);
                    const id = `role-${role._id}-${def.key}`;
                    return (
                      <li key={def.key} className={`perm-row ${on ? "" : "off"}`}>
                        <label htmlFor={id} className="perm-text">
                          <span className="perm-label">{def.label}</span>
                          {(blocked || def.hint) && (
                            <span className="perm-hint">{blocked ? `Only for ${def.only}-like roles` : def.hint}</span>
                          )}
                        </label>
                        <button
                          id={id}
                          type="button"
                          role="switch"
                          aria-checked={on}
                          className={`perm-switch ${on ? "on" : ""}`}
                          disabled={blocked || Boolean(busy)}
                          onClick={() => toggle(role, def.key, !on)}
                        >
                          <span className="perm-knob" />
                        </button>
                      </li>
                    );
                  })}
                </ul>
              </div>
            );
          })}
        </div>
      )}

      {adding && <AddRoleModal companyId={companyId} user={user} onClose={() => setAdding(false)} onDone={() => { setAdding(false); onChanged(); }} />}

      {renaming && (
        <Modal onClose={() => setRenaming(null)} maxWidth={420}>
          <h2 style={{ marginTop: 0 }}>Rename role</h2>
          <form
            onSubmit={async (e) => {
              e.preventDefault();
              const res = await updateCustomRole(companyId, renaming.role._id, user.id, { name: renaming.name });
              if (!res.success) return showToast(res.message || "Could not rename", "error");
              setRenaming(null);
              onChanged();
            }}
          >
            <label className="field-label">Role name</label>
            <input className="field-input" maxLength={40} autoFocus value={renaming.name} onChange={(e) => setRenaming({ ...renaming, name: e.target.value })} />
            <div style={{ display: "flex", gap: 10, marginTop: 18 }}>
              <button type="button" className="btn btn-outline" style={{ flex: 1 }} onClick={() => setRenaming(null)}>Cancel</button>
              <button className="btn btn-primary" style={{ flex: 1 }} disabled={!renaming.name.trim()}>Save</button>
            </div>
          </form>
        </Modal>
      )}

      {deleting && (
        <ConfirmDialog
          title={`Delete "${deleting.name}"?`}
          message={
            deleting.members.length
              ? `These ${deleting.members.length} member${deleting.members.length === 1 ? "" : "s"} will also be removed from ${company?.name || "the company"}: ${deleting.members.map((m) => m.name).join(", ")}. This can't be undone.`
              : "Nobody is in this role, so no one is removed. This can't be undone."
          }
          confirmLabel={deleting.members.length ? "Delete role and remove members" : "Delete role"}
          danger
          onConfirm={confirmDelete}
          onCancel={() => setDeleting(null)}
        />
      )}
    </section>
  );
}

function AddRoleModal({ companyId, user, onClose, onDone }) {
  const { showToast } = useToast();
  const [name, setName] = useState("");
  const [base, setBase] = useState("staff");
  const [saving, setSaving] = useState(false);

  async function submit(e) {
    e.preventDefault();
    setSaving(true);
    const res = await createCustomRole(companyId, user.id, name.trim(), base);
    setSaving(false);
    if (!res.success) return showToast(res.message || "Could not create role", "error");
    showToast(`"${res.role.name}" created · all switches are off`);
    onDone();
  }

  return (
    <Modal onClose={onClose} maxWidth={460}>
      <h2 style={{ marginTop: 0, marginBottom: 4 }}>Add role</h2>
      <p style={{ margin: "0 0 14px", color: "var(--muted)", fontSize: 13 }}>Every switch starts off; you turn on what this role may do.</p>
      <form onSubmit={submit}>
        <label className="field-label">Role name</label>
        <input className="field-input" maxLength={40} autoFocus placeholder="e.g. Accountant" value={name} onChange={(e) => setName(e.target.value)} required />
        <label className="field-label" style={{ display: "block", marginTop: 14 }}>Works like</label>
        <div className="payments-choice">
          <button type="button" className={base === "manager" ? "on" : ""} onClick={() => setBase("manager")}>
            <strong>Manager-like</strong>
            <span>Sees all company expenses; their own posts are approved straight away</span>
          </button>
          <button type="button" className={base === "staff" ? "on" : ""} onClick={() => setBase("staff")}>
            <strong>Staff-like</strong>
            <span>Sees their own expenses; their posts wait for a manager's approval</span>
          </button>
        </div>
        <div style={{ display: "flex", gap: 10, marginTop: 20 }}>
          <button type="button" className="btn btn-outline" style={{ flex: 1 }} onClick={onClose}>Cancel</button>
          <button className="btn btn-primary" style={{ flex: 1 }} disabled={saving || !name.trim()}>{saving ? "Creating…" : "Create role"}</button>
        </div>
      </form>
    </Modal>
  );
}
