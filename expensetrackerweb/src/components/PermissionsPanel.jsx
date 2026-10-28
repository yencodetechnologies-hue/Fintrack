import { useEffect, useState } from "react";
import { getPermissions, renameBuiltInRoles, updatePermissions } from "../api.js";
import { roleNames } from "../utils.js";
import Modal from "./Modal.jsx";
import { useToast } from "../context/ToastContext.jsx";
import CustomRoles from "./CustomRoles.jsx";

// Feature switches per role. The primary admin edits Managers and Staff; other managers (with
// "Change staff permissions") edit Staff, and can't switch on a staff feature that's off for managers.
// Each switch saves on its own; whatever was saved last wins.
export default function PermissionsPanel({ companyId, company, members = [], user, refreshKey, onChanged }) {
  const { showToast } = useToast();
  const [data, setData] = useState(null);
  const [error, setError] = useState("");
  const [saving, setSaving] = useState("");
  const [reloadKey, setReloadKey] = useState(0);
  const [renaming, setRenaming] = useState(null); // { role: "manager"|"staff", name }

  useEffect(() => {
    let active = true;
    getPermissions(companyId, user.id).then((res) => {
      if (!active) return;
      if (res.success) setData(res);
      else setError(res.message || "Could not load permissions");
    });
    return () => {
      active = false;
    };
  }, [companyId, user.id, refreshKey, reloadKey]);

  async function toggle(role, key, on) {
    const before = data[role];
    setData((d) => ({ ...d, [role]: { ...d[role], [key]: on } }));
    setSaving(`${role}.${key}`);
    const res = await updatePermissions(companyId, user.id, role, { [key]: on });
    setSaving("");
    if (res.success) {
      setData((d) => ({ ...d, [role]: res[role] }));
    } else {
      setData((d) => ({ ...d, [role]: before }));
      showToast(res.message || "Could not save", "error");
    }
  }

  async function setAll(role, on) {
    const before = data[role];
    const blocked = (def) => role === "staff" && on && lockedForStaff(def);
    const next = Object.fromEntries(data.definitions[role].map((def) => [def.key, blocked(def) ? before[def.key] : on]));
    setData((d) => ({ ...d, [role]: next }));
    setSaving(`${role}.*`);
    const res = await updatePermissions(companyId, user.id, role, next);
    setSaving("");
    if (res.success) setData((d) => ({ ...d, [role]: res[role] }));
    else {
      setData((d) => ({ ...d, [role]: before }));
      showToast(res.message || "Could not save", "error");
    }
  }

  // a non-primary manager can't switch on what managers themselves don't have
  const lockedForStaff = (def) => data.role !== "primary" && def.needs && data.mine[def.needs] === false;

  if (error) return <div className="card" style={{ color: "var(--terracotta)" }}>{error}</div>;
  if (!data) return <div style={{ display: "flex", justifyContent: "center", padding: 40 }}><div className="spinner" /></div>;
  if (!data.canEditStaff) return <div className="card" style={{ color: "var(--muted)" }}>You can't change permissions in this company.</div>;

  const names = roleNames(company);

  const section = (role, title, subtitle) => {
    const defs = data.definitions[role];
    const values = data[role];
    const onCount = defs.filter((d) => values[d.key]).length;
    return (
      <div className="card perm-card">
        <div className="perm-card-head">
          <div>
            <h2 style={{ margin: 0, fontSize: 20 }}>{title}</h2>
            <div style={{ color: "var(--muted)", fontSize: 13, marginTop: 2 }}>{subtitle}</div>
          </div>
          <span className="perm-count">{onCount}/{defs.length} on</span>
        </div>
        <div className="perm-bulk">
          <button type="button" className="voucher-ticket-link" disabled={Boolean(saving)} onClick={() => setAll(role, true)}>Turn all on</button>
          <span aria-hidden="true">·</span>
          <button type="button" className="voucher-ticket-link" disabled={Boolean(saving)} onClick={() => setAll(role, false)}>Turn all off</button>
          {data.canManageRoles && (
            <>
              <span aria-hidden="true">·</span>
              <button type="button" className="voucher-ticket-link" onClick={() => setRenaming({ role, name: names[role] })}>Rename</button>
            </>
          )}
        </div>
        <ul className="perm-list">
          {defs.map((def) => {
            const on = values[def.key];
            const locked = role === "staff" && !on && lockedForStaff(def);
            const id = `perm-${role}-${def.key}`;
            return (
              <li key={def.key} className={`perm-row ${on ? "" : "off"}`}>
                <label htmlFor={id} className="perm-text">
                  <span className="perm-label">{def.label}</span>
                  {(def.hint || locked) && (
                    <span className="perm-hint">{locked ? "Off for managers, so you can't turn it on" : def.hint}</span>
                  )}
                </label>
                <button
                  id={id}
                  type="button"
                  role="switch"
                  aria-checked={on}
                  className={`perm-switch ${on ? "on" : ""}`}
                  disabled={locked || Boolean(saving)}
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
  };

  return (
    <>
      <h1 style={{ fontSize: 22, margin: "0 0 6px" }}>Permissions</h1>
      <p style={{ color: "var(--muted)", fontSize: 14, margin: "0 0 22px", maxWidth: 680 }}>
        Turn features on or off for everyone in a role. Switched-off features are hidden for them and refused by the server.
        {data.role === "primary" ? " As the primary admin, these never apply to you." : " You can change staff permissions, but only for features managers have."}
      </p>
      <div className="perm-grid">
        {data.canEditManagers && section("manager", names.managers, `Every ${names.manager.toLowerCase()} except the primary admin`)}
        {section("staff", names.staffs, `Every ${names.staff.toLowerCase()}`)}
      </div>
      {renaming && (
        <Modal onClose={() => setRenaming(null)} maxWidth={420}>
          <h2 style={{ marginTop: 0, marginBottom: 4 }}>Rename {renaming.role === "manager" ? "Manager" : "Staff"} role</h2>
          <p style={{ margin: "0 0 12px", color: "var(--muted)", fontSize: 13 }}>Shown everywhere in this company, on the web and in the app. Leave it empty to go back to "{renaming.role === "manager" ? "Manager" : "Staff"}".</p>
          <form
            onSubmit={async (e) => {
              e.preventDefault();
              const res = await renameBuiltInRoles(companyId, user.id, { [renaming.role]: renaming.name.trim() });
              if (!res.success) return showToast(res.message || "Could not rename", "error");
              setRenaming(null);
              showToast("Role renamed");
              setReloadKey((k) => k + 1);
              onChanged?.();
            }}
          >
            <label className="field-label">Role name</label>
            <input className="field-input" maxLength={30} autoFocus value={renaming.name} onChange={(e) => setRenaming({ ...renaming, name: e.target.value })} />
            <div style={{ display: "flex", gap: 10, marginTop: 18 }}>
              <button type="button" className="btn btn-outline" style={{ flex: 1 }} onClick={() => setRenaming(null)}>Cancel</button>
              <button className="btn btn-primary" style={{ flex: 1 }}>Save</button>
            </div>
          </form>
        </Modal>
      )}
      {data.customRoles && (
        <CustomRoles
          companyId={companyId}
          company={company}
          user={user}
          members={members}
          definitions={data.definitions.custom || []}
          roles={data.customRoles}
          onChanged={() => {
            setReloadKey((k) => k + 1);
            onChanged?.();
          }}
        />
      )}
    </>
  );
}
