import { useState } from "react";
import { roleLabel } from "../utils.js";
import { createCustomRole, deleteCustomRole, setMemberCustomRole, updateCustomRole } from "../api.js";
import { useToast } from "../context/ToastContext.jsx";
import ConfirmDialog from "./ConfirmDialog.jsx";
import Modal from "./Modal.jsx";

// Roles made by the primary admin (or anyone with "Manage custom roles"). A role is just a name: every ability —
// staff, manager and admin powers — is its own switch, all OFF to start. "All admin access" turns them all on.
// Deleting a role removes its members from the company.
export default function CustomRoles({ companyId, company, user, members, definitions, roles, onChanged }) {
  const { showToast } = useToast();
  const [adding, setAdding] = useState(false);
  const [renaming, setRenaming] = useState(null);
  const [deleting, setDeleting] = useState(null);
  const [busy, setBusy] = useState("");
  const [local, setLocal] = useState({}); // optimistic switch values per role id

  const creatorId = String(company?.createdBy?._id || company?.createdBy || "");
  const roleOf = (userId) => roles.find((r) => r.members.some((m) => String(m.userId) === String(userId)));
  const groups = definitions.reduce((acc, d) => {
    const g = d.group || "Other";
    (acc[g] = acc[g] || []).push(d);
    return acc;
  }, {});

  async function save(role, permissions) {
    setBusy(`${role._id}`);
    const res = await updateCustomRole(companyId, role._id, user.id, { permissions });
    setBusy("");
    if (!res.success) {
      setLocal((cur) => ({ ...cur, [role._id]: role.permissions }));
      return showToast(res.message || "Could not save", "error");
    }
    setLocal((cur) => ({ ...cur, [role._id]: res.role.permissions }));
    onChanged();
  }

  function toggle(role, key, on) {
    setLocal((cur) => ({ ...cur, [role._id]: { ...(cur[role._id] || role.permissions), [key]: on } }));
    save(role, { [key]: on });
  }

  function setAll(role, on) {
    save(role, Object.fromEntries(definitions.map((d) => [d.key, on && d.key !== "full_admin"])));
  }

  async function assign(role, memberUserId) {
    if (!memberUserId) return;
    setBusy(`${role._id}`);
    const res = await setMemberCustomRole(companyId, memberUserId, user.id, role._id);
    setBusy("");
    if (!res.success) return showToast(res.message || "Could not add to role", "error");
    showToast(`Added to ${role.name}`);
    onChanged();
  }

  async function unassign(role, member) {
    setBusy(`${role._id}`);
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
        Make your own roles, like Accountant or Site supervisor. Every ability — staff, manager and admin — is a switch, and all start off. Turn on only what the role needs.
      </p>

      {roles.length === 0 ? (
        <div className="card" style={{ color: "var(--muted)", textAlign: "center", padding: 24 }}>No custom roles yet.</div>
      ) : (
        <div className="perm-grid">
          {roles.map((role) => {
            const values = local[role._id] || role.permissions;
            const full = Boolean(values.full_admin);
            const onCount = definitions.filter((d) => full || values[d.key]).length;
            const candidates = members.filter((m) => String(m.userId) !== creatorId && !role.members.some((x) => String(x.userId) === String(m.userId)));
            return (
              <div key={role._id} className="card perm-card">
                <div className="perm-card-head">
                  <div style={{ minWidth: 0 }}>
                    <h2 style={{ margin: 0, fontSize: 18, overflowWrap: "anywhere" }}>{role.name}</h2>
                    <div style={{ color: "var(--muted)", fontSize: 12, marginTop: 4 }}>
                      {role.members.length} member{role.members.length === 1 ? "" : "s"}
                      {full ? " · all admin access" : role.base === "manager" ? " · manager-level access" : ""}
                    </div>
                  </div>
                  <span className="perm-count">{onCount}/{definitions.length} on</span>
                </div>

                <div className="perm-bulk">
                  <button type="button" className="voucher-ticket-link" disabled={Boolean(busy) || full} onClick={() => setAll(role, true)}>Turn all on</button>
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
                            {m.name} · {current ? current.name : m.isAdmin ? "Admin" : roleLabel(company, m.role)}
                          </option>
                        );
                      })}
                    </select>
                  )}
                </div>

                {Object.entries(groups).map(([group, defs]) => (
                  <div key={group}>
                    <div className="perm-group-head">{group}</div>
                    <ul className="perm-list">
                      {defs.map((def) => {
                        const included = full && def.key !== "full_admin";
                        const on = included || Boolean(values[def.key]);
                        const id = `role-${role._id}-${def.key}`;
                        return (
                          <li key={def.key} className={`perm-row ${on ? "" : "off"}`}>
                            <label htmlFor={id} className="perm-text">
                              <span className="perm-label">{def.label}</span>
                              {(included || def.hint) && <span className="perm-hint">{included ? "Included in All admin access" : def.hint}</span>}
                            </label>
                            <button
                              id={id}
                              type="button"
                              role="switch"
                              aria-checked={on}
                              className={`perm-switch ${on ? "on" : ""}`}
                              disabled={included || Boolean(busy)}
                              onClick={() => toggle(role, def.key, !on)}
                            >
                              <span className="perm-knob" />
                            </button>
                          </li>
                        );
                      })}
                    </ul>
                  </div>
                ))}
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

// A role is just a name; its switches are set on its card afterwards.
function AddRoleModal({ companyId, user, onClose, onDone }) {
  const { showToast } = useToast();
  const [name, setName] = useState("");
  const [saving, setSaving] = useState(false);

  async function submit(e) {
    e.preventDefault();
    setSaving(true);
    const res = await createCustomRole(companyId, user.id, name.trim());
    setSaving(false);
    if (!res.success) return showToast(res.message || "Could not create role", "error");
    showToast(`"${res.role.name}" created · turn on what it can do`);
    onDone();
  }

  return (
    <Modal onClose={onClose} maxWidth={420}>
      <h2 style={{ marginTop: 0, marginBottom: 4 }}>Add role</h2>
      <p style={{ margin: "0 0 14px", color: "var(--muted)", fontSize: 13 }}>Every switch starts off; you turn on what this role may do.</p>
      <form onSubmit={submit}>
        <label className="field-label">Role name</label>
        <input className="field-input" maxLength={40} autoFocus placeholder="e.g. Accountant" value={name} onChange={(e) => setName(e.target.value)} required />
        <div style={{ display: "flex", gap: 10, marginTop: 20 }}>
          <button type="button" className="btn btn-outline" style={{ flex: 1 }} onClick={onClose}>Cancel</button>
          <button className="btn btn-primary" style={{ flex: 1 }} disabled={saving || !name.trim()}>{saving ? "Creating…" : "Create role"}</button>
        </div>
      </form>
    </Modal>
  );
}
