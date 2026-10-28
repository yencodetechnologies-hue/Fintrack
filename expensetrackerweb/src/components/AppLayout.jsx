import { useEffect, useState } from "react";
import { Link, useLocation, useNavigate } from "react-router-dom";
import { useAuth } from "../context/AuthContext.jsx";
import { getUserCompanies } from "../api.js";
import ConfirmDialog from "./ConfirmDialog.jsx";
import { tabAllowed } from "../permissions.js";
import { roleLabel } from "../utils.js";

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
  payments: ["M12 2v20", "M17 5H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6"],
  vouchers: ["M2 9a3 3 0 0 1 0 6v2a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-2a3 3 0 0 1 0-6V7a2 2 0 0 0-2-2H4a2 2 0 0 0-2 2Z", "M13 5v2", "M13 17v2", "M13 11v2"],
  funds: ["M3 21h18", "M3 10h18", "m5 6 7-3 7 3", "M4 10v11", "M20 10v11", "M8 14v3", "M12 14v3", "M16 14v3"],
  accounts: ["M8 2v4", "M16 2v4", "M3 10h18", "M5 4h14a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2z", "M8 14h3", "M8 18h6"],
  transactions: ["M4 19.5v-15A2.5 2.5 0 0 1 6.5 2H20v20H6.5a2.5 2.5 0 0 1 0-5H20", "M8 7h8", "M8 11h6"],
  audit: ["M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z", "m9 12 2 2 4-4"],
  permissions: ["M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z", "M12 8v4", "M12 16h.01"],
  settings: ["M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6z", "M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 1 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.68 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 1 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 9 4.68a1.65 1.65 0 0 0 1-1.51V3a2 2 0 1 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06A1.65 1.65 0 0 0 19.4 9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 1 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"],
  companies: ["M3 21h18", "M5 21V7l7-4 7 4v14", "M9 21v-6h6v6"],
  groups: ["M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2", "M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8z", "M22 21v-2a4 4 0 0 0-3-3.87", "M16 3.13a4 4 0 0 1 0 7.75"],
  profile: ["M19 21v-2a4 4 0 0 0-4-4H9a4 4 0 0 0-4 4v2", "M12 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8z"],
  logout: ["M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4", "m16 17 5-5-5-5", "M21 12H9"],
};

const WORKSPACE = [
  { tab: "home", label: "Home" },
  { tab: "expenses", label: "Expenses" },
  { tab: "interco", label: "Loans" },
  { tab: "reports", label: "Reports", adminOnly: true },
  { tab: "analysis", label: "Analysis", adminOnly: true },
  { tab: "vouchers", label: "Vouchers", adminOnly: true },
  { tab: "payments", label: "Payments", adminOnly: true },
  { tab: "funds", label: "Company Funds", adminOnly: true },
  { tab: "accounts", label: "Accounts", adminOnly: true },
  { tab: "transactions", label: "Ledger", adminOnly: true },
  { tab: "audit", label: "Audit log", adminOnly: true },
  { tab: "settings", label: "Settings" },
  { tab: "permissions", label: "Permissions", adminOnly: true },
];

// Every signed-in page: full-height sidebar on the left, the opened page on the right.
// On the company workspace, pass activeTab/onTabChange; elsewhere the workspace links open the last-used company.
const ALL_ON = () => true;

export default function AppLayout({ children, companyId, isAdmin, can = ALL_ON, permissionRole, roleName, activeTab, onTabChange, title, light = false }) {
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
        <img src="/logo.png" alt="" className="layout-brand-mark" />
        <span className="layout-topbar-title">{title || current?.name || "Q Fin"}</span>
      </header>

      {menuOpen && <div className="layout-scrim" onClick={() => setMenuOpen(false)} />}

      <aside className={`layout-sidebar ${menuOpen ? "open" : ""}`}>
        {/* the wordmark already reads "Q FIN", so no separate name text */}
        <Link to="/companies" className="layout-brand" aria-label="Q Fin home">
          <img src="/logo-wordmark.png" alt="Q Fin" className="layout-brand-wordmark" />
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
            {/* the company creator (primary admin) is "Admin"; others show their role */}
            {current && <small>{String(current.createdBy?._id || current.createdBy) === String(user.id) || current.isCompanyAdmin || permissionRole === "primary" ? "You're Admin" : (roleName || current.customRoleName) ? `You're ${roleName || current.customRoleName}` : `You're ${roleLabel(current, admin ? "admin" : "member")}`}</small>}
          </div>
        )}

        {/* the company's own pages: only while inside a company (not on Companies / Groups / Profile) */}
        {current && onWorkspace && (
          <>
            <div className="sidebar-section-label">Workspace</div>
            {WORKSPACE.filter((item) => (!item.adminOnly || admin) && (!onWorkspace ? item.tab !== "permissions" : tabAllowed(item.tab, { admin, can, permissionRole }))).map((item) => (
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

      <main className={`layout-main${light ? " layout-main-light" : ""}`}>{children}</main>

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
