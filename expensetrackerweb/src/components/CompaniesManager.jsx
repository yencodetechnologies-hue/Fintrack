import { useCallback, useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { createCompany, getHiddenCompanies, getUserCompanies, setCompanyHidden } from "../api.js";
import { useToast } from "../context/ToastContext.jsx";
import { roleLabel, roleNames } from "../utils.js";
import ConfirmDialog from "./ConfirmDialog.jsx";
import { CompanyAvatar } from "./CompanyLogo.jsx";

// Settings → Your companies (the Admin): add a company, remove one from MY list (nothing is deleted), and restore
// removed ones. Same rules as the Companies page.
export default function CompaniesManager({ user, currentCompanyId }) {
  const { showToast } = useToast();
  const navigate = useNavigate();
  const [companies, setCompanies] = useState(null);
  const [removed, setRemoved] = useState([]);
  const [showRemoved, setShowRemoved] = useState(false);
  const [removing, setRemoving] = useState(null);
  const [adding, setAdding] = useState(false);
  const [name, setName] = useState("");
  const [details, setDetails] = useState("");
  const [saving, setSaving] = useState(false);

  const isAdminOf = (c) => Boolean(c.isCompanyAdmin) || String(c.createdBy?._id || c.createdBy) === String(user.id);

  const load = useCallback(async () => {
    const [list, all] = await Promise.all([getUserCompanies(user.id), getHiddenCompanies(user.id)]);
    setCompanies((Array.isArray(list) ? list : list.companies || []).filter((c) => !c.external));
    setRemoved((Array.isArray(all) ? all : all.companies || []).filter((c) => c.hiddenFromList));
  }, [user.id]);

  useEffect(() => {
    load();
  }, [load]);

  async function add(e) {
    e.preventDefault();
    if (!name.trim()) return showToast("Enter the company name", "error");
    setSaving(true);
    const res = await createCompany(user.id, name.trim(), details.trim(), user.name);
    setSaving(false);
    if (!res.success) return showToast(res.message || "Could not create the company", "error");
    showToast(`${name.trim()} created · join code ${res.joinCode}`);
    setName("");
    setDetails("");
    setAdding(false);
    load();
  }

  async function confirmRemove() {
    const c = removing;
    setRemoving(null);
    const res = await setCompanyHidden(c._id, user.id, true);
    if (!res.success) return showToast(res.message || "Could not remove it from your list", "error");
    showToast(`${c.name} removed from your list`);
    load();
    // removing the company you're in: go to the Companies page
    if (String(c._id) === String(currentCompanyId)) navigate("/companies");
  }

  async function restore(c) {
    const res = await setCompanyHidden(c._id, user.id, false);
    if (!res.success) return showToast(res.message || "Could not restore it", "error");
    showToast(`${c.name} is back in your list`);
    load();
  }

  return (
    <div className="card" style={{ maxWidth: 560, marginBottom: 28 }}>
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 10, marginBottom: 4 }}>
        <h3 style={{ fontSize: 16, margin: 0 }}>Your companies</h3>
        <button type="button" className="btn btn-outline btn-sm" onClick={() => setAdding((v) => !v)}>
          {adding ? "Cancel" : "+ Add company"}
        </button>
      </div>
      <p style={{ color: "var(--muted)", fontSize: 12, margin: "0 0 10px" }}>
        Removing a company only hides it from your own list. Nothing is deleted and others still see it.
      </p>

      {adding && (
        <form onSubmit={add} style={{ display: "grid", gap: 8, padding: "10px 0 12px", borderBottom: "1px solid var(--slate-border-2)" }}>
          <input className="field-input" placeholder="Company name *" value={name} onChange={(e) => setName(e.target.value)} autoFocus />
          <input className="field-input" placeholder="Details (optional)" value={details} onChange={(e) => setDetails(e.target.value)} />
          <button className="btn btn-primary" disabled={saving}>{saving ? "Creating…" : "Create company"}</button>
        </form>
      )}

      {!companies ? (
        <div style={{ display: "flex", justifyContent: "center", padding: 16 }}><div className="spinner dark" /></div>
      ) : (
        <div className="dt-card" style={{ marginBottom: 0 }}>
          <div className="dt-scroll">
            <table className="dt">
              <thead>
                <tr><th>Company</th><th>Your role</th><th className="num">Action</th></tr>
              </thead>
              <tbody>
                {companies.map((c) => (
                  <tr key={c._id}>
                    <td className="dt-strong">
                      <span style={{ display: "inline-flex", alignItems: "center", gap: 10 }}>
                        <CompanyAvatar company={c} size={28} radius={7} style={{ border: "1px solid var(--slate-border)", flexShrink: 0 }} />
                        {c.name}{String(c._id) === String(currentCompanyId) ? " · this company" : ""}
                      </span>
                    </td>
                    <td>{isAdminOf(c) ? roleNames(c).admin : c.customRoleName || roleLabel(c, c.userRole)}</td>
                    <td>
                      <span className="dt-actions">
                        {isAdminOf(c) ? (
                          <button type="button" className="btn btn-outline-danger btn-sm" onClick={() => setRemoving(c)}>Remove</button>
                        ) : (
                          <span className="dt-sub">Only its Admin can remove</span>
                        )}
                      </span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      <button type="button" className="report-link" style={{ marginTop: 8 }} onClick={() => setShowRemoved((v) => !v)}>
        {showRemoved ? "Hide removed companies" : `Removed companies (${removed.length})`}
      </button>
      {showRemoved && (
        removed.length === 0 ? (
          <p style={{ color: "var(--muted)", fontSize: 12, margin: "6px 0 0" }}>You haven't removed any companies.</p>
        ) : (
          <div className="report-list" style={{ padding: 0 }}>
            {removed.map((c) => (
              <div key={c._id} className="report-row">
                <span>
                  <strong>{c.name}</strong>
                  <small>Removed from your list · still active for its members</small>
                </span>
                <button type="button" className="btn btn-outline btn-sm" onClick={() => restore(c)}>Restore</button>
              </div>
            ))}
          </div>
        )
      )}

      {removing && (
        <ConfirmDialog
          title={`Remove ${removing.name} from your list?`}
          message="It only disappears from your own company list. The company, its members, expenses and money are not deleted, and everyone else still sees it. You can restore it from Removed companies."
          confirmLabel="Remove from list"
          danger
          onCancel={() => setRemoving(null)}
          onConfirm={confirmRemove}
        />
      )}
    </div>
  );
}
