import { useCallback, useEffect, useMemo, useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { useAuth } from "../context/AuthContext.jsx";
import { useToast } from "../context/ToastContext.jsx";
import {
  deleteExpense,
  getCompanyBalanceSummary,
  getCompanyDetails,
  getCompanyExpenses,
  resetExpenseStatus,
} from "../api.js";
import { formatDate, money } from "../utils.js";
import Navbar from "../components/Navbar.jsx";
import Sidebar from "../components/Sidebar.jsx";
import ExpenseCard from "../components/ExpenseCard.jsx";
import AddExpenseModal from "../components/AddExpenseModal.jsx";
import EditExpenseModal from "../components/EditExpenseModal.jsx";
import PayModal from "../components/PayModal.jsx";
import ReceiveModal from "../components/ReceiveModal.jsx";
import EditSettlementModal from "../components/EditSettlementModal.jsx";
import FundsPanel from "../components/FundsPanel.jsx";
import SettingsPanel from "../components/SettingsPanel.jsx";
import ConfirmDialog from "../components/ConfirmDialog.jsx";

export default function DashboardPage() {
  const { companyId } = useParams();
  const { user, logout } = useAuth();
  const { showToast } = useToast();
  const navigate = useNavigate();

  const [company, setCompany] = useState(null);
  const [members, setMembers] = useState([]);
  const [currentUserRole, setCurrentUserRole] = useState("member");
  const [expenses, setExpenses] = useState([]);
  const [summary, setSummary] = useState({ totalReceivable: 0, totalPayable: 0, totalCompanySpent: 0, netBalance: 0 });
  const [loading, setLoading] = useState(true);
  const [viewMode, setViewMode] = useState("company");
  const [activeTab, setActiveTab] = useState("ledger");

  const [search, setSearch] = useState("");
  const [statusFilter, setStatusFilter] = useState("All");
  const [categoryFilter, setCategoryFilter] = useState("All");

  const [modal, setModal] = useState(null); // {type, expense?}
  const [confirmingLogout, setConfirmingLogout] = useState(false);

  const isAdmin = currentUserRole === "admin";
  const showCompanyTotals = isAdmin && viewMode === "company";
  const bankAccounts = company?.bankAccounts || [];
  const cashBalance = company?.cashBalance || 0;
  const customCategories = company?.customCategories || [];

  const load = useCallback(async () => {
    const [detailsRes, expensesRes, summaryRes] = await Promise.all([
      getCompanyDetails(companyId, user.id),
      getCompanyExpenses(companyId, user.id),
      getCompanyBalanceSummary(companyId, user.id),
    ]);

    if (detailsRes.success === false) {
      showToast(detailsRes.message || "Failed to load company", "error");
      navigate("/companies", { replace: true });
      return;
    }

    setCompany(detailsRes.company);
    setMembers(detailsRes.members || []);
    setCurrentUserRole(detailsRes.currentUserRole || "member");
    if (expensesRes.success) setExpenses(expensesRes.expenses || []);
    if (summaryRes.success) {
      setSummary({
        totalReceivable: summaryRes.totalReceivable || 0,
        totalPayable: summaryRes.totalPayable || 0,
        totalCompanySpent: summaryRes.totalCompanySpent || 0,
        netBalance: summaryRes.netBalance || 0,
      });
    }
    setLoading(false);
  }, [companyId, user.id, navigate, showToast]);

  useEffect(() => {
    setLoading(true);
    load();
    const interval = setInterval(load, 5000);
    return () => clearInterval(interval);
  }, [load]);

  useEffect(() => {
    if (!isAdmin && activeTab === "funds") setActiveTab("ledger");
  }, [isAdmin, activeTab]);

  const categories = useMemo(() => {
    const set = new Set(["All"]);
    expenses.forEach((e) => e.category && set.add(e.category));
    return Array.from(set);
  }, [expenses]);

  const filtered = useMemo(() => {
    let list = expenses;

    if (isAdmin && viewMode === "self") {
      list = list.filter((e) => {
        const logAs = e.logAs || (e.status === "paid" ? "company" : "self");
        const creatorId = typeof e.createdBy === "object" ? e.createdBy?._id : e.createdBy;
        return logAs === "self" && creatorId === user.id;
      });
    }

    if (search.trim()) {
      const q = search.trim().toLowerCase();
      list = list.filter((e) => {
        const desc = (e.description || "").toLowerCase();
        const cat = (e.category || "").toLowerCase();
        const creator = (e.createdBy?.name || "").toLowerCase();
        const amt = String(e.amount || "");
        return desc.includes(q) || cat.includes(q) || creator.includes(q) || amt.includes(q);
      });
    }

    if (statusFilter !== "All") {
      list = list.filter((e) => (statusFilter === "Paid" ? e.status === "paid" : e.status !== "paid"));
    }

    if (categoryFilter !== "All") {
      list = list.filter((e) => (e.category || "").toLowerCase() === categoryFilter.toLowerCase());
    }

    return [...list].sort((a, b) => new Date(b.createdAt || b.date) - new Date(a.createdAt || a.date));
  }, [expenses, isAdmin, viewMode, user.id, search, statusFilter, categoryFilter]);

  const grouped = useMemo(() => {
    const groups = [];
    let lastKey = null;
    for (const e of filtered) {
      const d = new Date(e.createdAt || e.date);
      const key = d.toDateString();
      if (key !== lastKey) {
        groups.push({ key, label: formatDate(d), items: [] });
        lastKey = key;
      }
      groups[groups.length - 1].items.push(e);
    }
    return groups;
  }, [filtered]);

  async function handleToggleStatus(expense, status) {
    const res = await resetExpenseStatus(expense._id, user.id, status);
    if (res.success) {
      showToast(res.message || "Status updated");
      load();
    } else {
      showToast(res.message || "Failed to change status", "error");
    }
  }

  async function confirmDeleteExpense() {
    const expense = modal.expense;
    const res = await deleteExpense(expense._id, user.id, companyId);
    setModal(null);
    if (res.success) {
      showToast("Expense deleted successfully");
      load();
    } else {
      showToast(res.message || "Failed to delete expense", "error");
    }
  }

  if (loading || !company) {
    return (
      <div style={{ minHeight: "100vh", display: "flex", alignItems: "center", justifyContent: "center" }}>
        <div className="spinner" />
      </div>
    );
  }

  return (
    <div style={{ minHeight: "100vh" }}>
      <Navbar crumb={company.name} backTo="/companies">
        <button className="nav-text-btn" onClick={() => setConfirmingLogout(true)}>⎋ Log out</button>
      </Navbar>

      <div className="app-shell">
        <Sidebar
          company={company}
          isAdmin={isAdmin}
          viewMode={viewMode}
          onViewModeChange={setViewMode}
          active={activeTab}
          onNavigate={setActiveTab}
          userName={user.name}
        />

        <div className="main-panel">
          {activeTab === "ledger" && (
            <>
              <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", flexWrap: "wrap", gap: 10, marginBottom: 6 }}>
                <h1 style={{ fontSize: 26, margin: 0 }}>
                  {isAdmin && viewMode === "self" ? `Self Expenses` : `${company.name} Ledger`}
                </h1>
              </div>
              <p style={{ color: "var(--muted)", fontSize: 13.5, margin: "0 0 24px" }}>
                {isAdmin && viewMode === "self"
                  ? "Expenses you've personally logged, outside of company spending."
                  : "Every expense logged for this company."}
              </p>

              <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(190px, 1fr))", gap: 14, marginBottom: 28 }}>
                <div className="stat-card">
                  <div style={labelStyle}>{showCompanyTotals ? "TOTAL EXPENSE SPENT" : "YOU ARE OWED"}</div>
                  <div style={bigNumberStyle}>{money(showCompanyTotals ? summary.totalCompanySpent : summary.totalReceivable)}</div>
                </div>
                <div className="stat-card">
                  <div style={labelStyle}>YOU OWE (PAYABLE)</div>
                  <div style={{ ...bigNumberStyle, color: "var(--terracotta)" }}>{money(summary.totalPayable)}</div>
                </div>
                <div className="stat-card">
                  <div style={labelStyle}>NET STANDING BALANCE</div>
                  <div style={{ ...bigNumberStyle, color: summary.netBalance >= 0 ? "var(--forest)" : "var(--terracotta)" }}>
                    {summary.netBalance >= 0 ? "+" : ""}{money(summary.netBalance)}
                  </div>
                </div>
              </div>

              <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", flexWrap: "wrap", gap: 12, marginBottom: 18, borderTop: "1px solid var(--slate-border-2)", paddingTop: 20 }}>
                <div>
                  <h2 style={{ margin: 0, fontSize: 18 }}>Expense Ledger</h2>
                  <span style={{ color: "var(--muted)", fontSize: 12.5 }}>{filtered.length} entries</span>
                </div>
                <div style={{ display: "flex", gap: 8, flexWrap: "wrap", alignItems: "center" }}>
                  <input
                    className="field-input"
                    style={{ width: 210 }}
                    placeholder="Search description, category..."
                    value={search}
                    onChange={(e) => setSearch(e.target.value)}
                  />
                  <select className="field-select" style={{ width: "auto" }} value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)}>
                    {["All", "Outstanding", "Paid"].map((s) => <option key={s} value={s}>{s}</option>)}
                  </select>
                  <select className="field-select" style={{ width: "auto" }} value={categoryFilter} onChange={(e) => setCategoryFilter(e.target.value)}>
                    {categories.map((c) => <option key={c} value={c}>{c}</option>)}
                  </select>
                  <button className="btn btn-primary" onClick={() => setModal({ type: "add" })}>+ Add Expense</button>
                </div>
              </div>

              {grouped.length === 0 ? (
                <div className="card" style={{ textAlign: "center", color: "var(--muted)" }}>
                  No expenses found.
                </div>
              ) : (
                grouped.map((group) => (
                  <div key={group.key} style={{ marginBottom: 16 }}>
                    <div style={{ color: "var(--muted)", fontSize: 11.5, fontWeight: 700, marginBottom: 8, letterSpacing: 0.6, textTransform: "uppercase" }}>
                      {group.label}
                    </div>
                    {group.items.map((exp) => (
                      <ExpenseCard
                        key={exp._id}
                        expense={exp}
                        user={user}
                        isAdmin={isAdmin}
                        companyName={company.name}
                        showCompanyTotals={showCompanyTotals}
                        onPay={(e) => setModal({ type: "pay", expense: e })}
                        onReceive={(e) => setModal({ type: "receive", expense: e })}
                        onEdit={(e) => setModal({ type: "edit", expense: e })}
                        onEditSettlement={(e) => setModal({ type: "editSettlement", expense: e })}
                        onToggleStatus={handleToggleStatus}
                        onDelete={(e) => setModal({ type: "confirmDelete", expense: e })}
                      />
                    ))}
                  </div>
                ))
              )}
            </>
          )}

          {activeTab === "funds" && isAdmin && (
            <FundsPanel
              company={company}
              user={user}
              bankAccounts={bankAccounts}
              cashBalance={cashBalance}
              onChanged={(accounts, cash) => setCompany((c) => ({ ...c, bankAccounts: accounts, cashBalance: cash }))}
            />
          )}

          {activeTab === "settings" && (
            <SettingsPanel company={company} members={members} user={user} isAdmin={isAdmin} onChanged={load} />
          )}
        </div>
      </div>

      {modal?.type === "add" && (
        <AddExpenseModal
          company={company}
          user={user}
          isAdmin={isAdmin}
          lockedLogAs={isAdmin ? viewMode : null}
          members={members}
          bankAccounts={bankAccounts}
          cashBalance={cashBalance}
          customCategories={customCategories}
          onClose={() => setModal(null)}
          onCreated={load}
        />
      )}

      {modal?.type === "edit" && (
        <EditExpenseModal
          expense={modal.expense}
          user={user}
          customCategories={customCategories}
          onClose={() => setModal(null)}
          onUpdated={load}
        />
      )}

      {modal?.type === "pay" && (
        <PayModal
          expense={modal.expense}
          user={user}
          isAdmin={isAdmin}
          lockedPayAs={showCompanyTotals ? "company" : null}
          bankAccounts={bankAccounts}
          cashBalance={cashBalance}
          onClose={() => setModal(null)}
          onPaid={load}
        />
      )}

      {modal?.type === "receive" && (
        <ReceiveModal
          expense={modal.expense}
          user={user}
          members={members}
          onClose={() => setModal(null)}
          onReceived={load}
        />
      )}

      {modal?.type === "editSettlement" && (
        <EditSettlementModal
          expense={modal.expense}
          settlement={modal.expense.settlement}
          user={user}
          onClose={() => setModal(null)}
          onSaved={load}
        />
      )}

      {modal?.type === "confirmDelete" && (
        <ConfirmDialog
          title="Delete expense?"
          message={`Delete "${modal.expense.description}" (₹${modal.expense.amount})? This cannot be undone.`}
          confirmLabel="Delete"
          danger
          onConfirm={confirmDeleteExpense}
          onCancel={() => setModal(null)}
        />
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

const labelStyle = {
  fontSize: 10.5,
  color: "var(--muted)",
  fontWeight: 700,
  letterSpacing: 0.6,
  marginBottom: 6,
};

const bigNumberStyle = {
  fontFamily: "Fraunces, serif",
  fontSize: 22,
  fontWeight: 700,
  color: "var(--forest)",
};
