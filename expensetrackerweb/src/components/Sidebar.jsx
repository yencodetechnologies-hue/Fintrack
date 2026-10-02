export default function Sidebar({ company, isAdmin, viewMode, onViewModeChange, active, onNavigate, userName }) {
  return (
    <aside className="sidebar">
      <div style={{ padding: "6px 10px 14px" }}>
        <div
          style={{
            width: 42,
            height: 42,
            borderRadius: 11,
            background: "rgba(255,255,255,0.1)",
            color: "#fff",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            fontWeight: 700,
            fontSize: 17,
            marginBottom: 10,
          }}
        >
          {company.name?.[0]?.toUpperCase() || "C"}
        </div>
        <div style={{ color: "#fff", fontWeight: 700, fontSize: 15, lineHeight: 1.3 }}>{company.name}</div>
        <div style={{ color: "rgba(255,255,255,0.45)", fontSize: 11.5, marginTop: 2 }}>
          {isAdmin ? "You're an admin" : "Member"}
        </div>
      </div>

      {isAdmin && (
        <>
          <div className="sidebar-section-label">View as</div>
          <button
            className={`sidebar-item ${viewMode === "company" ? "active" : ""}`}
            onClick={() => onViewModeChange("company")}
          >
            🏢 Company
          </button>
          <button
            className={`sidebar-item ${viewMode === "self" ? "active" : ""}`}
            onClick={() => onViewModeChange("self")}
          >
            👤 Self ({userName.split(" ")[0]})
          </button>
        </>
      )}

      <div className="sidebar-section-label">Workspace</div>
      <button className={`sidebar-item ${active === "ledger" ? "active" : ""}`} onClick={() => onNavigate("ledger")}>
        📒 Ledger
      </button>
      {isAdmin && viewMode === "company" && (
        <button className={`sidebar-item ${active === "funds" ? "active" : ""}`} onClick={() => onNavigate("funds")}>
          🏦 Company Funds
        </button>
      )}
      <button className={`sidebar-item ${active === "settings" ? "active" : ""}`} onClick={() => onNavigate("settings")}>
        ⚙ Settings
      </button>
    </aside>
  );
}
