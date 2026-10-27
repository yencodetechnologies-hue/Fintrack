import { useState } from "react";
import { createCompany, deleteCompanyGroup, saveCompanyGroup } from "../api.js";
import { useToast } from "../context/ToastContext.jsx";
import ConfirmDialog from "./ConfirmDialog.jsx";
import Modal from "./Modal.jsx";
import { CompanyAvatar } from "./CompanyLogo.jsx";

// Create or edit a company group: a name plus the companies in it. Grouping only changes how the companies list
// is shown; each company keeps its own members, money and books. Only companies I run (Admin / manager) can be picked.
export default function CompanyGroupModal({ group, companies, user, onClose, onSaved, onCompanyCreated }) {
  const { showToast } = useToast();
  const [name, setName] = useState(group?.name || "");
  const [picked, setPicked] = useState(() => new Set(companies.filter((c) => group && String(c.companyGroup?._id) === String(group._id)).map((c) => String(c._id))));
  const [saving, setSaving] = useState(false);
  const [confirmDelete, setConfirmDelete] = useState(false);
  // companies made right here ("+ New company"), added to the list and ticked
  const [created, setCreated] = useState([]);
  const [newName, setNewName] = useState("");
  const [creating, setCreating] = useState(false);
  const fromList = companies.filter((c) => c.userRole === "admin" && !c.external);
  // once the page's list reloads, a company made here is in it already, so it isn't shown twice
  const mine = [...fromList, ...created.filter((c) => !fromList.some((x) => String(x._id) === String(c._id)))];

  async function addCompany() {
    const n = newName.trim();
    if (!n) return showToast("Enter the new company's name", "error");
    setCreating(true);
    const res = await createCompany(user.id, n, "", user.name);
    setCreating(false);
    if (!res.success || !res.company) return showToast(res.message || "Could not create the company", "error");
    const c = { ...res.company, userRole: "admin", isCompanyAdmin: true, companyGroup: null };
    setCreated((list) => [...list, c]);
    setPicked((prev) => new Set([...prev, String(c._id)]));
    setNewName("");
    showToast(`${c.name} created · join code ${res.joinCode}`);
    onCompanyCreated?.();
  }

  function toggle(id) {
    setPicked((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  async function save(e) {
    e.preventDefault();
    if (!name.trim()) return showToast("Enter a group name", "error");
    if (picked.size < 2) return showToast("Pick at least two companies", "error");
    setSaving(true);
    const res = await saveCompanyGroup(group?._id, { userId: user.id, name: name.trim(), companyIds: [...picked] });
    setSaving(false);
    if (!res.success) return showToast(res.message || "Could not save the group", "error");
    showToast(group ? "Company group updated" : "Company group created");
    onSaved();
  }

  async function remove() {
    setConfirmDelete(false);
    setSaving(true);
    const res = await deleteCompanyGroup(group._id, user.id);
    setSaving(false);
    if (!res.success) return showToast(res.message || "Could not remove the group", "error");
    showToast("Company group removed");
    onSaved();
  }

  return (
    <Modal onClose={onClose} maxWidth={480}>
      <h2 style={{ marginTop: 0, marginBottom: 4 }}>{group ? "Edit company group" : "New company group"}</h2>
      <p style={{ margin: "0 0 16px", color: "var(--muted)", fontSize: 13 }}>
        Keep related companies together on your Companies page. Each company stays separate, with its own members, money and books.
      </p>
      <form onSubmit={save}>
        <label className="field-label">Group name *</label>
        <input className="field-input" value={name} onChange={(e) => setName(e.target.value)} placeholder="e.g. YD Group" autoFocus />

        <label className="field-label" style={{ display: "block", marginTop: 14 }}>
          Companies {picked.size > 0 && `(${picked.size} selected)`}
        </label>
        {mine.length < 2 && (
          <p style={{ color: "var(--muted)", fontSize: 13, margin: "4px 0 8px" }}>A group needs at least two companies you run. Add a new one below.</p>
        )}
        {mine.length > 0 && (
          <div style={{ display: "flex", flexDirection: "column", gap: 6, maxHeight: 280, overflowY: "auto" }}>
            {mine.map((c) => {
              const on = picked.has(String(c._id));
              const elsewhere = c.companyGroup && String(c.companyGroup._id) !== String(group?._id) ? c.companyGroup.name : "";
              return (
                <label
                  key={c._id}
                  className="group-member-option"
                  style={{ border: on ? "1.5px solid var(--forest)" : "1px solid var(--slate-border)", background: on ? "#F0FDF4" : "#fff" }}
                >
                  <input type="checkbox" checked={on} onChange={() => toggle(String(c._id))} style={{ width: 17, height: 17, accentColor: "var(--forest)" }} />
                  <CompanyAvatar company={c} size={28} radius={7} style={{ border: "1px solid var(--slate-border)" }} />
                  <span style={{ flex: 1, minWidth: 0 }}>
                    <strong style={{ fontSize: 13.5, color: "var(--dark-text)" }}>{c.name}</strong>
                    {elsewhere && <small style={{ display: "block" }}>Now in “{elsewhere}”; picking it moves it here</small>}
                  </span>
                </label>
              );
            })}
          </div>
        )}

        {/* make a brand-new company straight into this group (you become its Admin; share its join code later from Settings) */}
        <label className="field-label" style={{ display: "block", marginTop: 14 }}>New company</label>
        <div style={{ display: "flex", gap: 8 }}>
          <input
            className="field-input"
            value={newName}
            onChange={(e) => setNewName(e.target.value)}
            onKeyDown={(e) => { if (e.key === "Enter") { e.preventDefault(); addCompany(); } }}
            placeholder="Company name, e.g. YD Kitchen"
          />
          <button type="button" className="btn btn-outline" disabled={creating || !newName.trim()} onClick={addCompany} style={{ flexShrink: 0 }}>
            {creating ? "Adding…" : "+ Add"}
          </button>
        </div>

        <div style={{ display: "flex", gap: 10, marginTop: 20 }}>
          {group && (
            <button type="button" className="btn btn-outline-danger" disabled={saving} onClick={() => setConfirmDelete(true)}>Remove group</button>
          )}
          <button type="button" className="btn btn-outline" style={{ flex: 1 }} onClick={onClose}>Cancel</button>
          <button className="btn btn-primary" style={{ flex: 1 }} disabled={saving || mine.length < 2}>{saving ? "Saving…" : group ? "Save" : "Create group"}</button>
        </div>
      </form>

      {confirmDelete && (
        <ConfirmDialog
          title="Remove this group?"
          message={`“${group.name}” is removed and its companies show on their own again. Nothing inside the companies changes.`}
          confirmLabel="Remove group"
          danger
          onCancel={() => setConfirmDelete(false)}
          onConfirm={remove}
        />
      )}
    </Modal>
  );
}
