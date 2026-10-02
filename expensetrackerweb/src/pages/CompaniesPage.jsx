import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { useAuth } from "../context/AuthContext.jsx";
import { useToast } from "../context/ToastContext.jsx";
import { createCompany, getUserCompanies, joinCompany } from "../api.js";
import Navbar from "../components/Navbar.jsx";
import Modal from "../components/Modal.jsx";
import ConfirmDialog from "../components/ConfirmDialog.jsx";

export default function CompaniesPage() {
  const { user, logout } = useAuth();
  const { showToast } = useToast();
  const navigate = useNavigate();

  const [companies, setCompanies] = useState([]);
  const [loading, setLoading] = useState(true);
  const [modal, setModal] = useState(""); // "", "create", "join"
  const [saving, setSaving] = useState(false);
  const [confirmingLogout, setConfirmingLogout] = useState(false);

  const [name, setName] = useState("");
  const [details, setDetails] = useState("");
  const [joinCode, setJoinCode] = useState("");

  async function load() {
    setLoading(true);
    const list = await getUserCompanies(user.id);
    setCompanies(Array.isArray(list) ? list : list.companies || []);
    setLoading(false);
  }

  useEffect(() => {
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function handleCreate(e) {
    e.preventDefault();
    if (!name.trim()) {
      showToast("Enter a company name", "error");
      return;
    }
    setSaving(true);
    const res = await createCompany(user.id, name.trim(), details.trim(), user.name);
    setSaving(false);
    if (res.success) {
      showToast(`Company created. Join code: ${res.joinCode}`);
      setName("");
      setDetails("");
      setModal("");
      load();
    } else {
      showToast(res.message || "Failed to create company", "error");
    }
  }

  async function handleJoin(e) {
    e.preventDefault();
    if (!joinCode.trim()) {
      showToast("Enter the 6-digit join code", "error");
      return;
    }
    setSaving(true);
    const res = await joinCompany(user.id, joinCode.trim(), user.name);
    setSaving(false);
    if (res.success) {
      showToast(res.message || "Joined company");
      setJoinCode("");
      setModal("");
      load();
    } else {
      showToast(res.message || "Failed to join company", "error");
    }
  }

  return (
    <div style={{ minHeight: "100vh" }}>
      <Navbar>
        <span style={{ color: "rgba(255,255,255,0.75)", fontSize: 13, marginRight: 4 }}>{user.name}</span>
        <button className="nav-text-btn" onClick={() => setConfirmingLogout(true)}>⎋ Log out</button>
      </Navbar>

      <div className="container" style={{ padding: "52px 32px 70px" }}>
        <div style={{ marginBottom: 36 }}>
          <div className="eyebrow" style={{ marginBottom: 10 }}>Workspace</div>
          <div style={{ display: "flex", alignItems: "flex-end", justifyContent: "space-between", flexWrap: "wrap", gap: 20 }}>
            <h1 style={{ color: "#fff", fontSize: 36, margin: 0, lineHeight: 1.15 }}>
              Your companies
            </h1>
            <div style={{ display: "flex", gap: 10 }}>
              <button className="nav-text-btn" onClick={() => setModal("join")}>Join with Code</button>
              <button className="btn btn-primary" style={{ background: "#fff", color: "var(--forest)" }} onClick={() => setModal("create")}>
                + New Company
              </button>
            </div>
          </div>
          <p style={{ color: "rgba(255,255,255,0.65)", fontSize: 14.5, marginTop: 12, maxWidth: 520 }}>
            Pick a company to open its ledger, or create a new one to start tracking shared expenses.
          </p>
        </div>

        {loading ? (
          <div style={{ display: "flex", justifyContent: "center", padding: 70 }}>
            <div className="spinner" />
          </div>
        ) : companies.length === 0 ? (
          <div className="card" style={{ textAlign: "center", color: "var(--muted)", padding: 56, maxWidth: 480 }}>
            No companies yet. Create one or join with a code to get started.
          </div>
        ) : (
          <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(260px, 1fr))", gap: 16 }}>
            {companies.map((c) => (
              <button
                key={c._id}
                className="list-row"
                style={{ textAlign: "left", border: "1px solid var(--slate-border)", cursor: "pointer", padding: 20 }}
                onClick={() => navigate(`/company/${c._id}`)}
              >
                <div
                  style={{
                    width: 44,
                    height: 44,
                    borderRadius: 11,
                    background: "var(--forest)",
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                    color: "#fff",
                    fontWeight: 700,
                    fontSize: 17,
                    marginBottom: 14,
                  }}
                >
                  {c.name?.[0]?.toUpperCase() || "C"}
                </div>
                <div style={{ fontWeight: 700, fontSize: 16, marginBottom: 6 }}>{c.name}</div>
                <div style={{ fontSize: 12.5, color: "var(--muted)", display: "flex", alignItems: "center", gap: 8, flexWrap: "wrap" }}>
                  <span className="pill" style={{ background: c.userRole === "admin" ? "rgba(12,95,65,0.1)" : "var(--slate-border-2)", color: c.userRole === "admin" ? "var(--forest)" : "var(--dark-text)" }}>
                    {c.userRole === "admin" ? "Admin" : "Member"}
                  </span>
                  {c.details ? <span>{c.details}</span> : null}
                </div>
              </button>
            ))}
          </div>
        )}
      </div>

      {modal === "create" && (
        <Modal onClose={() => setModal("")} maxWidth={420}>
          <h2 style={{ marginTop: 0, fontSize: 20 }}>Create a company</h2>
          <form onSubmit={handleCreate}>
            <label className="field-label">Company name</label>
            <input className="field-input" value={name} onChange={(e) => setName(e.target.value)} placeholder="e.g. YD Productions" />
            <div style={{ height: 12 }} />
            <label className="field-label">Details (optional)</label>
            <input className="field-input" value={details} onChange={(e) => setDetails(e.target.value)} placeholder="Short description" />
            <div style={{ display: "flex", gap: 10, marginTop: 18 }}>
              <button type="button" className="btn btn-outline" style={{ flex: 1 }} onClick={() => setModal("")}>
                Cancel
              </button>
              <button type="submit" className="btn btn-primary" style={{ flex: 1 }} disabled={saving}>
                {saving ? "Creating..." : "Create"}
              </button>
            </div>
          </form>
        </Modal>
      )}

      {modal === "join" && (
        <Modal onClose={() => setModal("")} maxWidth={380}>
          <h2 style={{ marginTop: 0, fontSize: 20 }}>Join a company</h2>
          <form onSubmit={handleJoin}>
            <label className="field-label">6-digit join code</label>
            <input
              className="field-input"
              value={joinCode}
              onChange={(e) => setJoinCode(e.target.value)}
              placeholder="123456"
              maxLength={6}
            />
            <div style={{ display: "flex", gap: 10, marginTop: 18 }}>
              <button type="button" className="btn btn-outline" style={{ flex: 1 }} onClick={() => setModal("")}>
                Cancel
              </button>
              <button type="submit" className="btn btn-primary" style={{ flex: 1 }} disabled={saving}>
                {saving ? "Joining..." : "Join"}
              </button>
            </div>
          </form>
        </Modal>
      )}

      {confirmingLogout && (
        <ConfirmDialog
          title="Log out?"
          message="You'll need to sign in again to access your companies."
          confirmLabel="Log out"
          danger
          onConfirm={logout}
          onCancel={() => setConfirmingLogout(false)}
        />
      )}
    </div>
  );
}
