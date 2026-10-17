import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { useAuth } from "../context/AuthContext.jsx";
import { useToast } from "../context/ToastContext.jsx";
import { createCompany, getCompanyMemberCandidates, getUserCompanies, getUserExpenseGroups, joinCompany } from "../api.js";
import Navbar from "../components/Navbar.jsx";
import Modal from "../components/Modal.jsx";
import CreateGroupModal from "../components/CreateGroupModal.jsx";

export default function CompaniesPage() {
  const { user } = useAuth();
  const { showToast } = useToast();
  const navigate = useNavigate();

  const [companies, setCompanies] = useState([]);
  const [loading, setLoading] = useState(true);
  const [modal, setModal] = useState(""); // "", "create", "join"
  const [saving, setSaving] = useState(false);
  const [activeView, setActiveView] = useState("companies");
  const [groups, setGroups] = useState([]);
  const [groupsLoading, setGroupsLoading] = useState(false);
  const [groupsError, setGroupsError] = useState("");
  const [showCreateGroup, setShowCreateGroup] = useState(false);

  const [name, setName] = useState("");
  const [details, setDetails] = useState("");
  const [joinCode, setJoinCode] = useState("");

  const [candidateMembers, setCandidateMembers] = useState([]);
  const [loadingCandidates, setLoadingCandidates] = useState(false);
  const [selectedMembers, setSelectedMembers] = useState(new Set());
  const [memberSearch, setMemberSearch] = useState("");
  const [memberRoles, setMemberRoles] = useState({});

  async function load() {
    setLoading(true);
    const list = await getUserCompanies(user.id);
    setCompanies(Array.isArray(list) ? list : list.companies || []);
    setLoading(false);
  }

  async function loadGroups() {
    setGroupsLoading(true);
    setGroupsError("");
    const res = await getUserExpenseGroups(user.id);
    if (res.success) setGroups(res.groups || []);
    else setGroupsError(res.message || "Could not load groups");
    setGroupsLoading(false);
  }

  useEffect(() => {
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    if (modal === "create") {
      setLoadingCandidates(true);
      getCompanyMemberCandidates(user.id)
        .then((res) => {
          if (res.success) setCandidateMembers(res.candidates || []);
          else setCandidateMembers([]);
        })
        .finally(() => setLoadingCandidates(false));
    }
  }, [modal, user.id]);

  const filteredCandidates = candidateMembers.filter((c) => {
    if (!memberSearch.trim()) return true;
    const q = memberSearch.toLowerCase();
    return (
      (c.name || "").toLowerCase().includes(q) ||
      (c.email || "").toLowerCase().includes(q) ||
      (c.companies || []).some((comp) => comp.toLowerCase().includes(q))
    );
  });

  function toggleCandidateMember(userId) {
    setSelectedMembers((prev) => {
      const next = new Set(prev);
      if (next.has(userId)) next.delete(userId);
      else next.add(userId);
      return next;
    });
  }

  async function handleCreate(e) {
    e.preventDefault();
    if (!name.trim()) {
      showToast("Enter a company name", "error");
      return;
    }
    setSaving(true);
    const memberUserIds = Array.from(selectedMembers).map((userId) => ({
      userId,
      role: memberRoles[userId] || "member",
    }));
    const res = await createCompany(user.id, name.trim(), details.trim(), user.name, memberUserIds);
    setSaving(false);
    if (res.success) {
      const addedCount = memberUserIds.length;
      showToast(
        addedCount > 0
          ? `Company created with ${addedCount} staff. Join code: ${res.joinCode}`
          : `Company created. Join code: ${res.joinCode}`
      );
      setName("");
      setDetails("");
      setSelectedMembers(new Set());
      setMemberRoles({});
      setMemberSearch("");
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
      </Navbar>

      <div className="container" style={{ padding: "52px 32px 70px" }}>
        <div style={{ marginBottom: 36 }}>
          <div className="eyebrow" style={{ marginBottom: 10 }}>Workspace</div>
          <div style={{ display: "flex", alignItems: "flex-end", justifyContent: "space-between", flexWrap: "wrap", gap: 20 }}>
            <h1 style={{ color: "#fff", fontSize: 36, margin: 0, lineHeight: 1.15 }}>
              {activeView === "companies" ? "Your companies" : "Your groups"}
            </h1>
          </div>
          <p style={{ color: "rgba(255,255,255,0.65)", fontSize: 14.5, marginTop: 12, maxWidth: 520 }}>
            {activeView === "companies" ? "Pick a company to open its ledger, or create a new one to start tracking shared expenses." : "Create a group inside a company and track shared group expenses together."}
          </p>
        </div>

        <div className={`landing-toggle ${activeView}`} role="tablist" aria-label="Expense workspaces">
          <div className="landing-toggle-thumb" aria-hidden="true" />
          <button type="button" role="tab" aria-selected={activeView === "companies"} className={activeView === "companies" ? "active" : ""} onClick={() => setActiveView("companies")}>Company</button>
          <button type="button" role="tab" aria-selected={activeView === "groups"} className={activeView === "groups" ? "active" : ""} onClick={() => { setActiveView("groups"); if (!groups.length && !groupsLoading) loadGroups(); }}>Group</button>
        </div>

        {activeView === "companies" && <>
        <div className="landing-actions">
          <button className="btn btn-dark" onClick={() => setModal("create")}>+ Create Company</button>
          <button className="btn btn-primary" onClick={() => setModal("join")}>Join Company</button>
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
                    {c.userRole === "admin" ? "Manager" : "Staff"}
                  </span>
                  {c.details ? <span>{c.details}</span> : null}
                </div>
              </button>
            ))}
          </div>
        )}
        </>}

        {activeView === "groups" && <>
          <div className="landing-actions">
            <button className="btn btn-dark" onClick={() => setShowCreateGroup(true)} disabled={!companies.length}>+ Create Group</button>
            {!companies.length && <span style={{ color: "rgba(255,255,255,0.68)", fontSize: 13 }}>Create or join a company first.</span>}
          </div>
          {groupsLoading ? <div style={{ display: "flex", justifyContent: "center", padding: 70 }}><div className="spinner" /></div> : groupsError ? (
            <div className="card" style={{ maxWidth: 560 }}><p>{groupsError}</p><button className="btn btn-outline" onClick={loadGroups}>Retry</button></div>
          ) : groups.length === 0 ? (
            <div className="card" style={{ textAlign: "center", color: "var(--muted)", padding: 48, maxWidth: 560 }}>{companies.length ? "No groups yet. Create a group to start recording shared expenses." : "Join or create a company before creating a group."}</div>
          ) : (
            <>
              <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", margin: "26px 0 14px" }}>
                <h2 style={{ color: "#fff", fontSize: 23, margin: 0 }}>My Groups</h2>
                <span style={{ color: "rgba(255,255,255,0.7)", fontSize: 12 }}>{groups.length} groups</span>
              </div>
              <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(260px, 1fr))", gap: 14 }}>
                {groups.map((group) => (
                  <button key={group._id} className="list-row group-row" onClick={() => navigate(`/group/${group._id}`)}>
                    <span className="group-avatar">{group.name?.[0]?.toUpperCase() || "G"}</span>
                    <span className="group-row-copy"><strong>{group.name}</strong><small>{group.companyId?.name || "Company"} · {group.createdBy?.name ? `Created by ${group.createdBy.name}` : "Shared expenses"}</small></span>
                    <span className={`pill ${group.settlementStatus === "settled" ? "pill-paid" : "pill-outstanding"}`}>{group.settlementStatus === "settled" ? "Settled" : "Active"}</span>
                    <span aria-hidden="true" style={{ color: "var(--muted)", fontSize: 20 }}>›</span>
                  </button>
                ))}
              </div>
            </>
          )}
        </>}
      </div>

      {modal === "create" && (
        <Modal onClose={() => setModal("")} maxWidth={520}>
          <h2 style={{ marginTop: 0, fontSize: 20 }}>Create a company</h2>
          <form onSubmit={handleCreate}>
            <label className="field-label">Company name *</label>
            <input
              className="field-input"
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="e.g. YD Productions"
              required
              autoFocus
            />
            <div style={{ height: 12 }} />
            <label className="field-label">Details (optional)</label>
            <input
              className="field-input"
              value={details}
              onChange={(e) => setDetails(e.target.value)}
              placeholder="Short description"
            />

            <div style={{ marginTop: 18, borderTop: "1px solid var(--slate-border-2)", paddingTop: 14 }}>
              <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 8 }}>
                <label className="field-label" style={{ margin: 0 }}>
                  Add staff from existing companies {candidateMembers.length > 0 && `(${selectedMembers.size}/${candidateMembers.length} selected)`}
                </label>
                {filteredCandidates.length > 0 && (
                  <button
                    type="button"
                    style={{
                      background: "none",
                      border: "none",
                      color: "var(--forest)",
                      fontSize: 12,
                      fontWeight: 700,
                      cursor: "pointer",
                      padding: 0,
                    }}
                    onClick={() => {
                      if (selectedMembers.size >= filteredCandidates.length) {
                        setSelectedMembers(new Set());
                      } else {
                        setSelectedMembers(new Set(filteredCandidates.map((c) => c.userId)));
                      }
                    }}
                  >
                    {selectedMembers.size >= filteredCandidates.length ? "Deselect all" : "Select all"}
                  </button>
                )}
              </div>

              {loadingCandidates ? (
                <div style={{ display: "flex", alignItems: "center", gap: 8, padding: "16px 0", color: "var(--muted)", fontSize: 13 }}>
                  <div className="spinner" style={{ width: 18, height: 18, borderWidth: 2 }} />
                  <span>Loading staff from your companies…</span>
                </div>
              ) : candidateMembers.length === 0 ? (
                <p style={{ color: "var(--muted)", fontSize: 13, margin: "6px 0 0", lineHeight: 1.4 }}>
                  No staff found in other companies yet. You will be the admin and can invite staff with the 6-digit join code after creation.
                </p>
              ) : (
                <>
                  {candidateMembers.length > 3 && (
                    <input
                      className="field-input"
                      style={{ padding: "8px 12px", fontSize: 13, marginBottom: 8 }}
                      placeholder="Search staff name, email or company..."
                      value={memberSearch}
                      onChange={(e) => setMemberSearch(e.target.value)}
                    />
                  )}
                  <div
                    style={{
                      display: "flex",
                      flexDirection: "column",
                      gap: 6,
                      maxHeight: 210,
                      overflowY: "auto",
                      paddingRight: 4,
                      marginTop: 6,
                    }}
                  >
                    {filteredCandidates.length === 0 ? (
                      <p style={{ color: "var(--muted)", fontSize: 13, padding: 8, margin: 0 }}>
                        No staff matching &ldquo;{memberSearch}&rdquo;
                      </p>
                    ) : (
                      filteredCandidates.map((c) => {
                        const isSelected = selectedMembers.has(c.userId);
                        return (
                          <label
                            key={c.userId}
                            className="group-member-option"
                            style={{
                              display: "flex",
                              alignItems: "center",
                              gap: 10,
                              padding: "9px 12px",
                              borderRadius: 8,
                              border: isSelected ? "1.5px solid var(--forest)" : "1px solid var(--slate-border)",
                              background: isSelected ? "#F0FDF4" : "#fff",
                              cursor: "pointer",
                              transition: "all 0.15s ease",
                            }}
                          >
                            <input
                              type="checkbox"
                              checked={isSelected}
                              onChange={() => toggleCandidateMember(c.userId)}
                              style={{ width: 17, height: 17, accentColor: "var(--forest)", cursor: "pointer", flexShrink: 0 }}
                            />
                            <div style={{ flex: 1, minWidth: 0 }}>
                              <div style={{ display: "flex", alignItems: "center", gap: 6, flexWrap: "wrap" }}>
                                <strong style={{ fontSize: 13.5, color: "var(--dark-text)" }}>{c.name}</strong>
                                {c.companies && c.companies.length > 0 && (
                                  <span
                                    style={{
                                      fontSize: 11,
                                      padding: "1px 7px",
                                      borderRadius: 12,
                                      background: "#E2E8F0",
                                      color: "#334155",
                                      fontWeight: 600,
                                    }}
                                  >
                                    {c.companies.join(", ")}
                                  </span>
                                )}
                              </div>
                              {c.email && (
                                <small style={{ color: "var(--muted)", fontSize: 12, display: "block", marginTop: 2 }}>
                                  {c.email}
                                </small>
                              )}
                            </div>
                            {isSelected && (
                              <select
                                value={memberRoles[c.userId] || "member"}
                                onChange={(e) => {
                                  e.stopPropagation();
                                  setMemberRoles((prev) => ({ ...prev, [c.userId]: e.target.value }));
                                }}
                                onClick={(e) => e.stopPropagation()}
                                style={{
                                  padding: "4px 8px",
                                  fontSize: 11.5,
                                  borderRadius: 6,
                                  border: "1px solid var(--slate-border)",
                                  background: "#fff",
                                  color: "var(--dark-text)",
                                  fontWeight: 600,
                                  cursor: "pointer",
                                  flexShrink: 0,
                                }}
                              >
                                <option value="member">Staff</option>
                                <option value="admin">Admin</option>
                              </select>
                            )}
                          </label>
                        );
                      })
                    )}
                  </div>
                </>
              )}
            </div>

            <div style={{ display: "flex", gap: 10, marginTop: 20 }}>
              <button
                type="button"
                className="btn btn-outline"
                style={{ flex: 1 }}
                onClick={() => setModal("")}
              >
                Cancel
              </button>
              <button
                type="submit"
                className="btn btn-primary"
                style={{ flex: 1 }}
                disabled={saving}
              >
                {saving
                  ? "Creating..."
                  : selectedMembers.size > 0
                  ? `Create with ${selectedMembers.size + 1} staff`
                  : "Create Company"}
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

      {showCreateGroup && <CreateGroupModal companies={companies} user={user} onClose={() => setShowCreateGroup(false)} onCreated={loadGroups} />}

    </div>
  );
}
