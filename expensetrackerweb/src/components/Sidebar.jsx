function HomeIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" style={{ flexShrink: 0 }}>
      <path d="m3 9 9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z" />
      <polyline points="9 22 9 12 15 12 15 22" />
    </svg>
  );
}

function ExpensesIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" style={{ flexShrink: 0 }}>
      <path d="M4 2v20l2-1 2 1 2-1 2 1 2-1 2 1 2-1 2 1V2l-2 1-2-1-2 1-2-1-2 1-2-1-2 1Z" />
      <line x1="8" y1="7" x2="16" y2="7" />
      <line x1="8" y1="12" x2="16" y2="12" />
      <line x1="8" y1="17" x2="13" y2="17" />
    </svg>
  );
}

function IntercoIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" style={{ flexShrink: 0 }}>
      <path d="m17 2 4 4-4 4" />
      <path d="M3 6h18" />
      <path d="m7 22-4-4 4-4" />
      <path d="M21 18H3" />
    </svg>
  );
}

function ReportsIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" style={{ flexShrink: 0 }}>
      <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" />
      <polyline points="14 2 14 8 20 8" />
      <line x1="16" y1="13" x2="8" y2="13" />
      <line x1="16" y1="17" x2="8" y2="17" />
      <polyline points="10 9 9 9 8 9" />
    </svg>
  );
}

function MoreIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" style={{ flexShrink: 0 }}>
      <circle cx="12" cy="12" r="1.5" fill="currentColor" stroke="none" />
      <circle cx="19" cy="12" r="1.5" fill="currentColor" stroke="none" />
      <circle cx="5" cy="12" r="1.5" fill="currentColor" stroke="none" />
    </svg>
  );
}

export default function Sidebar({ company, companies = [], isAdmin, active, onNavigate, onCompanyChange }) {
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
        {companies.length > 1 ? (
          <div className="sidebar-company-picker">
            <select className="sidebar-company-select" value={company._id} onChange={(e) => onCompanyChange(e.target.value)} aria-label="Select company">
              {companies.map((item) => <option key={item._id} value={item._id}>{item.name}</option>)}
            </select>
            <span className="sidebar-company-chevron" aria-hidden="true" />
          </div>
        ) : <div style={{ color: "#fff", fontWeight: 700, fontSize: 15, lineHeight: 1.3 }}>{company.name}</div>}
        <div style={{ color: "rgba(255,255,255,0.45)", fontSize: 11.5, marginTop: 2 }}>
          {isAdmin ? "You're a manager" : "Staff"}
        </div>
      </div>

      <div className="sidebar-section-label">Workspace</div>
      <button className={`sidebar-item ${active === "home" ? "active" : ""}`} onClick={() => onNavigate("home")}>
        <HomeIcon />
        <span>Home</span>
      </button>
      <button className={`sidebar-item ${active === "expenses" ? "active" : ""}`} onClick={() => onNavigate("expenses")}>
        <ExpensesIcon />
        <span>Expenses</span>
      </button>
      <button className={`sidebar-item ${active === "interco" ? "active" : ""}`} onClick={() => onNavigate("interco")}>
        <IntercoIcon />
        <span>Inter-co</span>
      </button>
      {isAdmin && (
        <button className={`sidebar-item ${active === "reports" ? "active" : ""}`} onClick={() => onNavigate("reports")}>
          <ReportsIcon />
          <span>Reports</span>
        </button>
      )}
      <button className={`sidebar-item ${active === "more" ? "active" : ""}`} onClick={() => onNavigate("more")}>
        <MoreIcon />
        <span>More</span>
      </button>
    </aside>
  );
}
