import { useEffect, useState } from "react";
import Modal from "./Modal.jsx";
import { createExpenseGroup, getCompanyDetails } from "../api.js";
import { useToast } from "../context/ToastContext.jsx";

export default function CreateGroupModal({ companies, user, onClose, onCreated }) {
  const { showToast } = useToast();
  const [name, setName] = useState("");
  const [companyId, setCompanyId] = useState(companies[0]?._id || "");
  const [members, setMembers] = useState([]);
  const [selected, setSelected] = useState(new Set());
  const [loadingMembers, setLoadingMembers] = useState(false);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    let active = true;
    if (!companyId) {
      setMembers([]);
      return () => { active = false; };
    }
    setLoadingMembers(true);
    getCompanyDetails(companyId, user.id).then((res) => {
      if (!active) return;
      const list = res.success ? (res.members || []) : [];
      setMembers(list.filter((member) => member.userId !== user.id));
      setSelected(new Set());
      setLoadingMembers(false);
    });
    return () => { active = false; };
  }, [companyId, user.id]);

  function toggleMember(id) {
    setSelected((current) => {
      const next = new Set(current);
      next.has(id) ? next.delete(id) : next.add(id);
      return next;
    });
  }

  async function handleSubmit(e) {
    e.preventDefault();
    if (!companyId) {
      showToast("Choose a company for this group", "error");
      return;
    }
    if (!name.trim()) {
      showToast("Enter a group name", "error");
      return;
    }
    setSaving(true);
    const res = await createExpenseGroup(companyId, user.id, name.trim(), [...selected]);
    setSaving(false);
    if (res.success) {
      showToast("Group created");
      onCreated();
      onClose();
    } else {
      showToast(res.message || "Could not create group", "error");
    }
  }

  return (
    <Modal onClose={onClose} maxWidth={480}>
      <h2 style={{ marginTop: 0, fontSize: 20 }}>Create a group</h2>
      <form onSubmit={handleSubmit}>
        <label className="field-label">Group name</label>
        <input className="field-input" value={name} onChange={(e) => setName(e.target.value)} placeholder="e.g. Project team" autoFocus />
        <div style={{ height: 14 }} />
        <label className="field-label">Company</label>
        <select className="field-select" value={companyId} onChange={(e) => setCompanyId(e.target.value)}>
          {companies.map((company) => <option key={company._id} value={company._id}>{company.name}</option>)}
        </select>
        <div style={{ marginTop: 16 }}>
          <label className="field-label">Add company staff</label>
          {loadingMembers ? <p style={{ color: "var(--muted)", fontSize: 13 }}>Loading staff…</p> : members.length === 0 ? (
            <p style={{ color: "var(--muted)", fontSize: 13 }}>You can add other company staff to the group later.</p>
          ) : (
            <div style={{ display: "grid", gap: 8, maxHeight: 190, overflowY: "auto" }}>
              {members.map((member) => (
                <label key={member.userId} className="group-member-option">
                  <input type="checkbox" checked={selected.has(member.userId)} onChange={() => toggleMember(member.userId)} />
                  <span><strong>{member.name}</strong><small>{member.email}</small></span>
                </label>
              ))}
            </div>
          )}
        </div>
        <div style={{ display: "flex", gap: 10, marginTop: 20 }}>
          <button type="button" className="btn btn-outline" style={{ flex: 1 }} onClick={onClose}>Cancel</button>
          <button type="submit" className="btn btn-primary" style={{ flex: 1 }} disabled={saving || !companies.length}>
            {saving ? "Creating…" : "Create Group"}
          </button>
        </div>
      </form>
    </Modal>
  );
}
