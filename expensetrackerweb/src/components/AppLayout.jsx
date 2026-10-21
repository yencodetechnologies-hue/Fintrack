import { useEffect, useState } from "react";
import { Link, useLocation, useNavigate } from "react-router-dom";
import { useAuth } from "../context/AuthContext.jsx";
import { getUserCompanies } from "../api.js";
import ConfirmDialog from "./ConfirmDialog.jsx";

const LAST_COMPANY_KEY = "et_selected_company";

export function rememberCompany(companyId) {
  try {
    localStorage.setItem(LAST_COMPANY_KEY, companyId);
  } catch {
    // storage unavailable: the sidebar just falls back to the first company
  }
}

function lastCompany() {
  try {
    return localStorage.getItem(LAST_COMPANY_KEY) || "";
  } catch {
    return "";
  }
}

const Icon = ({ d }) => (
  <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" style={{ flexShrink: 0 }}>
    {d.map((path) => <path key={path} d={path} />)}
  </svg>
);

const ICONS = {
  home: ["m3 9 9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z", "M9 22V12h6v10"],
  expenses: ["M4 2v20l2-1 2 1 2-1 2 1 2-1 2 1 2-1 2 1V2l-2 1-2-1-2 1-2-1-2 1-2-1-2 1Z", "M8 7h8", "M8 12h8", "M8 17h5"],
  interco: ["m17 2 4 4-4 4", "M3 6h18", "m7 22-4-4 4-4", "M21 18H3"],
  reports: ["M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z", "M14 2v6h6", "M16 13H8", "M16 17H8"],
  analysis: ["M3 3v18h18", "m19 9-5 5-4-4-3 3"],
  more: ["M5 12h.01", "M12 12h.01", "M19 12h.01"],
  companies: ["M3 21h18", "M5 21V7l7-4 7 4v14", "M9 21v-6h6v6"],
  groups: ["M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2", "M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8z", "M22 21v-2a4 4 0 0 0-3-3.87", "M16 3.13a4 4 0 0 1 0 7.75"],
  profile: ["M19 21v-2a4 4 0 0 0-4-4H9a4 4 0 0 0-4 4v2", "M12 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8z"],
  logout: ["M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4", "m16 17 5-5-5-5", "M21 12H9"],
};

const WORKSPACE = [
  { tab: "home", label: "Home" },
  { tab: "expenses", label: "Expenses" },
  { tab: "interco", label: "Inter-co" },
  { tab: "reports", label: "Reports", adminOnly: true },
  { tab: "analysis", label: "Analysis", adminOnly: true },
  { tab: "more", label: "More" },
];

// Every signed-in page: full-height sidebar on the left, the opened page on the right.
// On the company workspace, pass activeTab/onTabChange; elsewhere the workspace links open the last-used company.
export default function AppLayout({ children, companyId, isAdmin, activeTab, onTabChange, title }) {
  const { user, logout } = useAuth();
  const navigate = useNavigate();
  const location = useLocation();
  const [companies, setCompanies] = useState([]);
  const [menuOpen, setMenuOpen] = useState(false);
  const [confirmingLogout, setConfirmingLogout] = useState(false);

  useEffect(() => {
    let active = true;
    getUserCompanies(user.id).then((res) => {
      if (active) setCompanies(Array.isArray(res) ? res : res.companies || []);
    });
    return () => {
      active = false;
    };
  }, [user.id]);

  // close the phone menu whenever the page changes
  useEffect(() => {
    setMenuOpen(false);
  }, [location.pathname, location.search]);

  const currentId = companyId || lastCompany() || companies[0]?._id || "";
  const current = companies.find((c) => String(c._id) === String(currentId));
  const admin = isAdmin ?? current?.userRole === "admin";
  const onWorkspace = Boolean(onTabChange);

  function openTab(tab) {
    if (onWorkspace) onTabChange(tab);
    else if (currentId) navigate(`/company/${currentId}?tab=${tab}`);
    else navigate("/companies");
    setMenuOpen(false);
  }

  const view = new URLSearchParams(location.search).get("view");
  const generalActive = (key) =>
    (key === "companies" && location.pathname === "/companies" && view !== "groups") ||
    (key === "groups" && ((location.pathname === "/companies" && view === "groups") || location.pathname.startsWith("/group/"))) ||
    (key === "profile" && location.pathname === "/profile");

  return (
    <div className="layout">
      <header className="layout-topbar">
        <button type="button" className="layout-menu-btn" aria-label="Open menu" onClick={() => setMenuOpen(true)}>☰</button>
        <span className="layout-brand-mark">Q</span>
        <span className="layout-topbar-title">{title || current?.name || "Q Fin"}</span>
      </header>

      {menuOpen && <div className="layout-scrim" onClick={() => setMenuOpen(false)} />}

      <aside className={`layout-sidebar ${menuOpen ? "open" : ""}`}>
        <Link to="/companies" className="layout-brand">
          <span className="layout-brand-mark">Q</span>
          <span>Q Fin</span>
        </Link>

        {companies.length > 0 && (
          <div className="layout-company">
            <select
              className="sidebar-company-select"
              value={current ? String(current._id) : ""}
              onChange={(e) => navigate(`/company/${e.target.value}${onWorkspace && activeTab ? `?tab=${activeTab}` : ""}`)}
              aria-label="Select company"
            >
              {!current && <option value="">Choose company</option>}
              {companies.map((c) => <option key={c._id} value={String(c._id)}>{c.name}</option>)}
            </select>
            <span className="sidebar-company-chevron" aria-hidden="true" />
            {current && <small>{admin ? "You're a manager" : "Staff"}</small>}
          </div>
        )}

        {current && (
          <>
            <div className="sidebar-section-label">Workspace</div>
            {WORKSPACE.filter((item) => !item.adminOnly || admin).map((item) => (
              <button
                key={item.tab}
                type="button"
                className={`sidebar-item ${onWorkspace && activeTab === item.tab ? "active" : ""}`}
                onClick={() => openTab(item.tab)}
              >
                <Icon d={ICONS[item.tab]} />
                <span>{item.label}</span>
              </button>
            ))}
          </>
        )}

        <div className="sidebar-section-label">General</div>
        <Link to="/companies" className={`sidebar-item ${generalActive("companies") ? "active" : ""}`}>
          <Icon d={ICONS.companies} />
          <span>Companies</span>
        </Link>
        <Link to="/companies?view=groups" className={`sidebar-item ${generalActive("groups") ? "active" : ""}`}>
          <Icon d={ICONS.groups} />
          <span>Groups</span>
        </Link>
        <Link to="/profile" className={`sidebar-item ${generalActive("profile") ? "active" : ""}`}>
          <Icon d={ICONS.profile} />
          <span>Profile</span>
        </Link>

        <div className="layout-user">
          <span className="layout-avatar" aria-hidden="true">{(user.name || user.email || "U").trim()[0]?.toUpperCase()}</span>
          <span className="layout-user-name">{user.name || user.email}</span>
          <button type="button" className="layout-logout" onClick={() => setConfirmingLogout(true)} title="Log out" aria-label="Log out">
            <Icon d={ICONS.logout} />
          </button>
        </div>
      </aside>

      <main className="layout-main">{children}</main>

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
