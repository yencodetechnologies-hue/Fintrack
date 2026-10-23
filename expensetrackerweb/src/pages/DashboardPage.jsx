import { useCallback, useEffect, useMemo, useState } from "react";
import { useNavigate, useParams, useSearchParams } from "react-router-dom";
import { useAuth } from "../context/AuthContext.jsx";
import { useToast } from "../context/ToastContext.jsx";
import {
  deleteExpense,
  getCompanyBalanceSummary,
  getCompanyDetails,
  getCompanyExpenses,
  getLedgerBalances,
  getLedgerExpenses,
  getLedgerIntercompany,
  getLedgerLoans,
  getUserCompanies,
  approveLedgerExpense,
  rejectLedgerExpense,
  getLedgerReport,
  getLedgerTransactions,
  getLedgerAuditLog,
  getLedgerExportUrl,
  getLedgerBorrowSources,
  createCompanyLoan,
  repayCompanyLoan,
  receiveCompanyLoan,
  getLoanBorrowerFunds,
  deleteCompanyLoan,
  payLedgerExpense,
  getLedgerPayerConfirmations,
  confirmLedgerPayer,
  verifyLedgerTransaction,
  lendToCompany,
  reimburseAdmin,
  getPayableBills,
  routedCompanyPayment,
  resetExpenseStatus,
  setLedgerExpenseVisibility,
  deleteLedgerExpense,
  reverseLedgerTransaction,
} from "../api.js";
import { bankAccountLabel, companyCategories, expenseStatusLabel, fileToBase64, formatDate, formatDateTime, money, PAYMENT_METHODS, postedByName } from "../utils.js";
import Modal from "../components/Modal.jsx";
import AppLayout, { rememberCompany } from "../components/AppLayout.jsx";
import ExpenseCard from "../components/ExpenseCard.jsx";
import AddExpenseModal from "../components/AddExpenseModal.jsx";
import EditExpenseModal from "../components/EditExpenseModal.jsx";
import PayModal from "../components/PayModal.jsx";
import ReceiveModal from "../components/ReceiveModal.jsx";
import EditSettlementModal from "../components/EditSettlementModal.jsx";
import FundsPanel from "../components/FundsPanel.jsx";
import SettingsPanel from "../components/SettingsPanel.jsx";
import ConfirmDialog from "../components/ConfirmDialog.jsx";
import ExpenseDetailModal from "../components/ExpenseDetailModal.jsx";
import PayableBillsPreview from "../components/PayableBillsPreview.jsx";
import OutstandingReport from "../components/OutstandingReport.jsx";
import ExpenseAnalysis from "../components/ExpenseAnalysis.jsx";
import VouchersPanel from "../components/VouchersPanel.jsx";
import PaymentsPanel from "../components/PaymentsPanel.jsx";
import PeriodFilter from "../components/PeriodFilter.jsx";
import StaffVouchers from "../components/StaffVouchers.jsx";
import CreateVoucherModal from "../components/CreateVoucherModal.jsx";
import PermissionsPanel from "../components/PermissionsPanel.jsx";
import ReceivedModal from "../components/ReceivedModal.jsx";
import { makeCan, tabAllowed } from "../permissions.js";
import { useCompanyLive } from "../realtime.js";
import HandBackModal from "../components/HandBackModal.jsx";
import LoanDetailModal from "../components/LoanDetailModal.jsx";

const TODAY_KEY = new Date().toDateString();
const roundMoney = (n) => Math.round(n * 100) / 100;

function getExpenseDateKey(expense) {
  const raw = expense.date || expense.createdAt;
  if (!raw) return "No Date";
  if (typeof raw === "string" && /^\d{4}-\d{2}-\d{2}$/.test(raw)) {
    return raw;
  }
  const d = new Date(raw);
  if (isNaN(d.getTime())) return "No Date";
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}

function formatGroupDate(dateStr) {
  if (!dateStr || dateStr === "No Date") return "Undated";
  const parts = dateStr.split("-");
  let d;
  if (parts.length === 3) {
    d = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]));
  } else {
    d = new Date(dateStr);
  }
  if (isNaN(d.getTime())) return "Undated";

  const today = new Date();
  const isToday =
    d.getDate() === today.getDate() &&
    d.getMonth() === today.getMonth() &&
    d.getFullYear() === today.getFullYear();

  const yesterday = new Date(today);
  yesterday.setDate(yesterday.getDate() - 1);
  const isYesterday =
    d.getDate() === yesterday.getDate() &&
    d.getMonth() === yesterday.getMonth() &&
    d.getFullYear() === yesterday.getFullYear();

  const formatted = formatDate(d);
  if (isToday) return `Today · ${formatted}`;
  if (isYesterday) return `Yesterday · ${formatted}`;
  return formatted;
}

export default function DashboardPage() {
  const { companyId } = useParams();
  const { user } = useAuth();
  const { showToast } = useToast();
  const navigate = useNavigate();

  const [company, setCompany] = useState(null);
  const [members, setMembers] = useState([]);
  const [currentUserRole, setCurrentUserRole] = useState("member");
  // feature switches for me in this company (null until loaded = everything allowed)
  const [myPermissions, setMyPermissions] = useState(null);
  const [permissionRole, setPermissionRole] = useState(null);
  const [hiddenStaffIds, setHiddenStaffIds] = useState([]);
  const [expenses, setExpenses] = useState([]);
  const [summary, setSummary] = useState({ totalReceivable: 0, totalPayable: 0, totalCompanySpent: 0, netBalance: 0 });
  const [loading, setLoading] = useState(true);
  const [viewMode] = useState("company");
  // the open tab lives in the URL (?tab=) so the sidebar on any page can open it and a refresh keeps it
  const [searchParams, setSearchParams] = useSearchParams();
  // old links to the removed "More" page land on Settings (its sections are sidebar items now)
  const tabFromUrl = (tab) => (tab === "more" ? "settings" : tab);
  const [activeTab, setActiveTab] = useState(() => tabFromUrl(searchParams.get("tab")) || "home");
  const changeTab = useCallback((tab) => {
    setActiveTab(tab);
    setSearchParams({ tab }, { replace: true });
  }, [setSearchParams]);
  const urlTab = searchParams.get("tab");
  useEffect(() => {
    if (urlTab) setActiveTab(tabFromUrl(urlTab));
  }, [urlTab]);
  const [companies, setCompanies] = useState([]);
  const [ledgerExpenses, setLedgerExpenses] = useState([]);
  const [ledgerBalances, setLedgerBalances] = useState(null);
  const [intercompany, setIntercompany] = useState([]);
  const [loans, setLoans] = useState([]);
  const [borrowSources, setBorrowSources] = useState([]);
  const [payerRequests, setPayerRequests] = useState([]);
  const [transactions, setTransactions] = useState([]);
  const [report, setReport] = useState(null);
  const [intercoModal, setIntercoModal] = useState(null);
  const [intercoDraft, setIntercoDraft] = useState({ companyId: "", amount: "", fundId: "cash", method: "UPI", reference: "" });
  const [intercoSaving, setIntercoSaving] = useState(false);
  const [borrowerFunds, setBorrowerFunds] = useState(null);
  const [moneyModal, setMoneyModal] = useState("");
  const [payeeBills, setPayeeBills] = useState({ loading: false, bills: [], owed: 0 });
  const [moneyDraft, setMoneyDraft] = useState({ adminUserId: "", amount: "", fundId: "cash", method: "UPI", reference: "", offsetAdvance: false });
  const [voucherModal, setVoucherModal] = useState(false);
  const [handBackOpen, setHandBackOpen] = useState(false);
  const [viewingLoan, setViewingLoan] = useState(null);
  const [deletingLoan, setDeletingLoan] = useState(null);
  const [routeDraft, setRouteDraft] = useState({ sourceCompanyId: "", adminUserId: "", amount: "", method: "UPI", reference: "" });
  const [paymentDraft, setPaymentDraft] = useState({ payer: "admin", fundId: "cash", sourceCompanyId: "", method: "UPI", reference: "", paymentReceipt: "" });
  const [payerFundSelections, setPayerFundSelections] = useState({});

  const [visibilityModal, setVisibilityModal] = useState(null);
  const [savingVisibility, setSavingVisibility] = useState(false);
  const [deletingExpense, setDeletingExpense] = useState(null);
  const [receivingExpense, setReceivingExpense] = useState(null);
  const [reversingTx, setReversingTx] = useState(null);
  const [selectedExpenseDetail, setSelectedExpenseDetail] = useState(null);

  const [reportFrom, setReportFrom] = useState("");
  const [reportTo, setReportTo] = useState("");
  const [reportCategory, setReportCategory] = useState("All");
  const [loadingReport, setLoadingReport] = useState(false);

  const [search, setSearch] = useState("");
  const [statusFilter, setStatusFilter] = useState("All");
  const [categoryFilter, setCategoryFilter] = useState("All");
  const [expenseDateFrom, setExpenseDateFrom] = useState("");
  // Expenses tab: "all", "company" (posted as the company), "managers", "staff", or one person's user id
  const [postedByFilter, setPostedByFilter] = useState("all");
  const [expenseDateTo, setExpenseDateTo] = useState("");

  const [modal, setModal] = useState(null); // {type, expense?}

  const isAdmin = currentUserRole === "admin";
  const can = useMemo(() => makeCan(myPermissions), [myPermissions]);
  const pageAllowed = tabAllowed(activeTab, { admin: isAdmin, can, permissionRole });
  const showCompanyTotals = isAdmin && viewMode === "company";
  const bankAccounts = company?.bankAccounts || [];
  const cashBalance = company?.cashBalance || 0;
  const customCategories = company?.customCategories || [];

  const availableCompanyFunds = useMemo(() => {
    const list = [];
    list.push({ fundId: "cash", name: "Cash", balance: Number(company?.cashBalance || 0) });

    const bankList = company?.bankAccounts || [];
    for (const b of bankList) {
      const bId = String(b._id);
      const label = bankAccountLabel(b);
      list.push({ fundId: bId, name: label, balance: Number(b.balance || 0) });
    }
    return list;
  }, [company]);

  // Other companies this user manages: they can pay this company's expenses (recorded as a loan).
  const managedOtherCompanies = useMemo(
    () => companies.filter((c) => String(c._id) !== companyId && c.userRole === "admin" && !c.external),
    [companies, companyId]
  );
  const payingCompanyId = paymentDraft.payingCompanyId || companyId;
  const payingCompany = payingCompanyId === companyId ? company : managedOtherCompanies.find((c) => String(c._id) === payingCompanyId);
  const payingFunds = payingCompanyId === companyId
    ? availableCompanyFunds
    : [
        { fundId: "cash", name: payingCompany?.cashAccountName || "Cash", balance: Number(payingCompany?.cashBalance || 0) },
        ...(payingCompany?.bankAccounts || []).map((b) => ({ fundId: String(b._id), name: bankAccountLabel(b), balance: Number(b.balance || 0) })),
      ];

  // Reimburse person: voucher money the chosen payee still holds, and how much of it the netting tick-box sets off
  const payeeHeld = Math.max(0, Number((ledgerBalances?.admins || []).find((a) => String(a.userId) === String(moneyDraft.adminUserId))?.advance || 0));
  const offsetAmount = moneyModal === "reimburse" && moneyDraft.offsetAdvance
    ? roundMoney(Math.min(payeeHeld, Math.max(0, payeeBills.owed - Number(moneyDraft.amount || 0))))
    : 0;

  const pendingVerification = transactions.filter((transaction) => transaction.verification === "pending" && !transaction.reversedBy);

  // Open loans this company still owes, totalled per lending company.
  const borrowedByLender = useMemo(() => {
    const byLender = new Map();
    for (const loan of loans) {
      if (String(loan.borrowerCompanyId?._id || loan.borrowerCompanyId) !== companyId) continue;
      const balance = Number(loan.balance || 0);
      if (!(balance > 0)) continue;
      const name = loan.lenderCompanyId?.name || "Another company";
      byLender.set(name, (byLender.get(name) || 0) + balance);
    }
    return [...byLender].map(([name, balance]) => ({ name, balance }));
  }, [loans, companyId]);

  // Open loans other companies still owe this company, totalled per borrower.
  const lentByBorrower = useMemo(() => {
    const byBorrower = new Map();
    for (const loan of loans) {
      if (String(loan.lenderCompanyId?._id || loan.lenderCompanyId) !== companyId) continue;
      const balance = Number(loan.balance || 0);
      if (!(balance > 0)) continue;
      const name = loan.borrowerCompanyId?.name || "Another company";
      byBorrower.set(name, (byBorrower.get(name) || 0) + balance);
    }
    return [...byBorrower].map(([name, balance]) => ({ name, balance }));
  }, [loans, companyId]);

  const load = useCallback(async () => {
    const detailsRes = await getCompanyDetails(companyId, user.id);

    if (detailsRes.success === false) {
      showToast(detailsRes.message || "Failed to load company", "error");
      const message = String(detailsRes.message || "").toLowerCase();
      if (!message.includes("fetch") && !message.includes("network") && !message.includes("timed out")) {
        navigate("/companies", { replace: true });
      }
      setLoading(false);
      return;
    }

    setCompany(detailsRes.company);
    rememberCompany(companyId);
    setMembers(detailsRes.members || []);
    setCurrentUserRole(detailsRes.currentUserRole || "member");
    setMyPermissions(detailsRes.myPermissions || null);
    setPermissionRole(detailsRes.permissionRole || null);
    setHiddenStaffIds(detailsRes.hiddenStaffIds || []);
    // Show the company workspace as soon as its required details arrive.
    // The lists and totals below are secondary and should not block first paint.
    setLoading(false);

    getUserCompanies(user.id).then((companyList) => {
      setCompanies(Array.isArray(companyList) ? companyList : companyList.companies || []);
    });
  }, [companyId, user.id, navigate, showToast]);

  useEffect(() => {
    setLoading(true);
    load();
  }, [load]);

  // Live updates instead of polling: the server says which parts of this company changed, and only those
  // reload. Each topic has a counter; a section reloads when one of its topics' counters moves.
  const [liveTicks, setLiveTicks] = useState({});
  const onLive = useCallback((topics) => {
    const all = topics.includes("*");
    if (all || topics.some((t) => ["company", "members", "permissions", "funds"].includes(t))) load();
    setLiveTicks((cur) => {
      const next = { ...cur };
      for (const t of topics) next[t] = (next[t] || 0) + 1;
      return next;
    });
  }, [load]);
  useCompanyLive(companyId, user.id, onLive);
  const tick = (...topics) => topics.reduce((sum, t) => sum + (liveTicks[t] || 0), liveTicks["*"] || 0);
  const tabTick =
    activeTab === "home" ? tick("expenses", "balances", "loans", "ledger")
      : activeTab === "expenses" ? tick("expenses", "balances")
        : activeTab === "interco" ? tick("loans", "balances", "expenses")
          : tick("expenses");
  const reportTick = tick("expenses", "balances", "loans");

  // Fetch only the data needed by the currently opened workspace section.
  useEffect(() => {
    if (!company) return;
    let active = true;
    const apply = (request, setter, pick = (result) => result) => {
      request.then((result) => {
        if (active && result?.success) setter(pick(result));
      });
    };

    if (activeTab === "home") {
      apply(getLedgerBalances(companyId, user.id), setLedgerBalances);
      apply(getLedgerLoans(companyId, user.id), setLoans, (result) => result.loans || []);
      apply(getLedgerExpenses(companyId, user.id), setLedgerExpenses, (result) => result.expenses || []);
      apply(getLedgerTransactions(companyId, user.id), setTransactions, (result) => result.transactions || []);
    } else if (activeTab === "expenses") {
      apply(getLedgerBalances(companyId, user.id), setLedgerBalances);
      apply(getLedgerExpenses(companyId, user.id), setLedgerExpenses, (result) => result.expenses || []);
      apply(getLedgerBorrowSources(companyId, user.id), setBorrowSources, (result) => result.companies || []);
    } else if (activeTab === "ledger") {
      apply(getCompanyExpenses(companyId, user.id), setExpenses, (result) => result.expenses || []);
      apply(getCompanyBalanceSummary(companyId, user.id), setSummary, (result) => ({
        totalReceivable: result.totalReceivable || 0,
        totalPayable: result.totalPayable || 0,
        totalCompanySpent: result.totalCompanySpent || 0,
        netBalance: result.netBalance || 0,
      }));
    } else if (activeTab === "interco") {
      apply(getLedgerIntercompany(companyId, user.id), setIntercompany, (result) => result.balances || []);
      apply(getLedgerLoans(companyId, user.id), setLoans, (result) => result.loans || []);
      apply(getLedgerBorrowSources(companyId, user.id), setBorrowSources, (result) => result.companies || []);
    }

    return () => { active = false; };
    // tabTick: reload this tab's lists when a live update touches them
  }, [activeTab, company, companyId, user.id, tabTick]);

  const loadReport = useCallback(async (from = reportFrom, to = reportTo, cat = reportCategory) => {
    setLoadingReport(true);
    const res = await getLedgerReport(companyId, user.id, from, to, cat);
    if (res.success) setReport(res.report);
    setLoadingReport(false);
  }, [companyId, user.id, reportFrom, reportTo, reportCategory]);

  useEffect(() => {
    if (activeTab !== "reports") return;
    loadReport();
  }, [activeTab, loadReport, reportTick]);

  useEffect(() => {
    if (!isAdmin || activeTab !== "interco") return;
    getLedgerPayerConfirmations(companyId, user.id).then((res) => { if (res.success) setPayerRequests(res.expenses || []); });
  }, [activeTab, companyId, user.id, isAdmin, tabTick]);

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
        const creator = postedByName(e, company).toLowerCase();
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

  const expenseYears = useMemo(() => {
    const years = new Set([String(new Date().getFullYear())]);
    for (const e of ledgerExpenses) {
      const key = getExpenseDateKey(e);
      if (/^\d{4}/.test(key)) years.add(key.slice(0, 4));
    }
    return [...years].sort().reverse();
  }, [ledgerExpenses]);

  const groupedLedgerExpenses = useMemo(() => {
    let list = ledgerExpenses.filter((expense) => (
      statusFilter === "All" ||
      (statusFilter === "Verify" ? expense.verification === "pending" : expense.lifecycle === statusFilter.toLowerCase())
    ));

    if (search.trim()) {
      const q = search.trim().toLowerCase();
      list = list.filter((e) => {
        const desc = (e.description || "").toLowerCase();
        const cat = (e.category || "").toLowerCase();
        const isComp = e.logAs === "company" || e.postedAs === "company";
        const creator = isComp ? (company?.name || "").toLowerCase() : (e.createdBy?.name || "").toLowerCase();
        const amt = String(e.amount || "");
        return desc.includes(q) || cat.includes(q) || creator.includes(q) || amt.includes(q);
      });
    }

    if (postedByFilter !== "all") {
      const managerIds = new Set(members.filter((m) => m.role === "admin").map((m) => String(m.userId)));
      list = list.filter((e) => {
        const isComp = e.logAs === "company" || e.postedAs === "company";
        const creatorId = String(e.createdBy?._id || e.createdBy || "");
        if (postedByFilter === "company") return isComp;
        if (postedByFilter === "managers") return !isComp && managerIds.has(creatorId);
        if (postedByFilter === "staff") return !isComp && !managerIds.has(creatorId);
        return !isComp && creatorId === postedByFilter;
      });
    }

    if (expenseDateFrom) {
      list = list.filter((e) => {
        const key = getExpenseDateKey(e);
        return key >= expenseDateFrom;
      });
    }

    if (expenseDateTo) {
      list = list.filter((e) => {
        const key = getExpenseDateKey(e);
        return key <= expenseDateTo;
      });
    }

    const sorted = [...list].sort((a, b) => {
      const timeB = new Date(b.date || b.createdAt).getTime() || 0;
      const timeA = new Date(a.date || a.createdAt).getTime() || 0;
      return timeB - timeA;
    });

    const map = new Map();
    for (const exp of sorted) {
      const key = getExpenseDateKey(exp);
      if (!map.has(key)) {
        map.set(key, {
          key,
          label: formatGroupDate(key),
          items: [],
          total: 0,
        });
      }
      const g = map.get(key);
      g.items.push(exp);
      g.total += Number(exp.amount || 0);
    }
    return Array.from(map.values());
  }, [ledgerExpenses, statusFilter, search, expenseDateFrom, expenseDateTo, company?.name, postedByFilter, members]);

  async function handleToggleStatus(expense, status) {
    const res = await resetExpenseStatus(expense._id, user.id, status);
    if (res.success) {
      showToast(res.message || "Status updated");
      load();
    } else {
      showToast(res.message || "Failed to change status", "error");
    }
  }

  // A manager's own expense (posted as themselves): the company owes them, so they can mark it "Received"
  // once they get the money back (from the company or a person). Approved, or already marked paid by them.
  function canMarkReceived(expense) {
    if (!expense || !isAdmin || !can("reimburse")) return false;
    if (String(expense.createdBy?._id || expense.createdBy) !== String(user.id)) return false;
    if (expense.logAs === "company" || expense.postedAs === "company" || expense.groupId) return false;
    const paidByMe = ["paid_by_admin", "paid_by_person"].includes(expense.lifecycle)
      && String(expense.paidByUserId?._id || expense.paidByUserId || expense.paidByAdminId?._id || expense.paidByAdminId) === String(user.id);
    return (expense.lifecycle === "approved" && expense.status !== "paid") || paidByMe;
  }

  // "Who paid?" choices this person may record on an approved bill (switches decide which)
  function payerOptions(expense) {
    const own = String(expense?.createdBy?._id || expense?.createdBy) === String(user.id);
    if (isAdmin) {
      return [
        ...(can("record_payments") ? [{ value: "admin", label: "Paid by me" }, { value: "company", label: "Paid by company" }] : []),
        ...(can("intercompany") ? [{ value: "borrow", label: "Borrowed from a company" }] : []),
      ];
    }
    return [
      { value: "person", label: "Paid by me" },
      ...(own ? [{ value: "company", label: "Paid by company" }] : []),
      ...(can("borrow") ? [{ value: "borrow", label: "Borrowed from a company" }] : []),
    ];
  }

  async function decideLedgerExpense(expense, action) {
    const request = action === "approve" ? approveLedgerExpense : rejectLedgerExpense;
    const res = await request(expense._id, user.id);
    if (res.success) {
      showToast(action === "approve" ? "Expense approved" : "Expense rejected");
      load();
    } else showToast(res.message || `Could not ${action} expense`, "error");
  }

  async function submitLedgerPayment(event) {
    event.preventDefault();
    const expense = modal?.expense;
    if (!expense) return;
    if (paymentDraft.payer === "company" && !paymentDraft.fundId) { showToast("Choose the paying fund", "error"); return; }
    if (paymentDraft.payer === "borrow" && !paymentDraft.sourceCompanyId) { showToast("Choose the company paying", "error"); return; }

    // only this company's own money is balance-checked; another company paying is a loan
    if (paymentDraft.payer === "company" && payingCompanyId === companyId) {
      const selectedFund = payingFunds.find((f) => String(f.fundId) === String(paymentDraft.fundId)) || payingFunds[0];
      if (selectedFund && Number(selectedFund.balance || 0) < Number(expense.amount || 0)) {
        showToast(`Insufficient balance in ${selectedFund.name} (${money(selectedFund.balance)} available)`, "error");
        return;
      }
    }

    const { payingCompanyId: _payingCompanyId, ...draft } = paymentDraft;
    // Paid by another company the user manages = this company borrows from it.
    const payload = draft.payer === "company" && payingCompanyId !== companyId
      ? { ...draft, payer: "borrow", sourceCompanyId: payingCompanyId, sourceFundId: draft.fundId }
      : draft;
    const result = await payLedgerExpense(expense._id, { userId: user.id, ...payload });
    if (result.success) {
      setModal(null);
      showToast(result.awaitingConfirmation ? "Payment request sent for confirmation" : "Payment recorded");
      load();
    } else showToast(result.message || "Could not record payment", "error");
  }

  async function submitIntercoAction(event) {
    event.preventDefault();
    setIntercoSaving(true);
    const kind = intercoModal?.type;
    const result = kind === "receive"
      ? await receiveCompanyLoan(intercoModal.loan._id, { userId: user.id, amount: Number(intercoDraft.amount), borrowerFundId: intercoDraft.fundId, method: intercoDraft.method, reference: intercoDraft.reference })
      : kind === "repay"
      ? await repayCompanyLoan(intercoModal.loan._id, { userId: user.id, amount: Number(intercoDraft.amount), fundId: intercoDraft.fundId, method: intercoDraft.method, reference: intercoDraft.reference })
      : await createCompanyLoan({ userId: user.id, borrowerCompanyId: companyId, lenderCompanyId: intercoDraft.companyId, amount: Number(intercoDraft.amount), fundId: intercoDraft.fundId, method: intercoDraft.method, reference: intercoDraft.reference, note: (intercoDraft.note || "").trim() });
    setIntercoSaving(false);
    if (result.success) {
      showToast(kind === "receive" ? (result.borrowerShort > 0 ? `Marked as received · ${intercoModal.loan.borrowerCompanyId?.name || "The borrower"}'s account is now ${money(result.borrowerShort)} below zero` : "Marked as received") :kind === "repay" ? "Loan repayment recorded" : "Company loan recorded");
      setIntercoModal(null);
      setIntercoDraft({ companyId: "", amount: "", fundId: "cash", method: "UPI", reference: "" });
      load();
    } else showToast(result.message || "Could not save company loan", "error");
  }

  async function respondToPayerRequest(expense, accept) {
    const fundId = payerFundSelections[expense._id] || availableCompanyFunds?.[0]?.fundId || "cash";
    const result = await confirmLedgerPayer(expense._id, user.id, accept, accept ? fundId : undefined);
    if (result.success) {
      showToast(accept ? "Payment accepted and loan recorded" : "Payment declined");
      getLedgerPayerConfirmations(companyId, user.id).then((res) => setPayerRequests(res.expenses || []));
      load();
    } else showToast(result.message || "Could not respond to payment request", "error");
  }

  async function verifyTransaction(transaction) {
    const result = await verifyLedgerTransaction(transaction._id, user.id);
    if (result.success) {
      showToast("Transaction verified");
      load();
    } else showToast(result.message || "Could not verify transaction", "error");
  }

  function openVisibilityModal(expense) {
    const ids = new Set((expense.visibleTo || []).map(String));
    setVisibilityModal({ expense, selectedIds: ids, allStaff: ids.size === 0 });
  }

  async function handleSaveVisibility(e) {
    e.preventDefault();
    if (!visibilityModal) return;
    setSavingVisibility(true);
    const visibleTo = visibilityModal.allStaff ? [] : Array.from(visibilityModal.selectedIds);
    const res = await setLedgerExpenseVisibility(visibilityModal.expense._id, user.id, visibleTo);
    setSavingVisibility(false);
    if (res.success) {
      showToast("Expense visibility updated");
      setVisibilityModal(null);
      load();
    } else {
      showToast(res.message || "Failed to update visibility", "error");
    }
  }

  async function confirmDeleteExpense() {
    const target = deletingExpense || modal?.expense;
    if (!target) return;
    const targetId = target._id;

    // 1. Optimistic removal: Instantly remove expense from UI so user doesn't wait
    setLedgerExpenses((prev) => prev.filter((e) => e._id !== targetId));
    setExpenses((prev) => prev.filter((e) => e._id !== targetId));
    setDeletingExpense(null);
    if (modal?.type === "confirmDelete") setModal(null);
    if (selectedExpenseDetail?._id === targetId) setSelectedExpenseDetail(null);

    // 2. Perform server deletion
    const res = await deleteLedgerExpense(targetId, user.id);
    if (res.success) {
      showToast("Expense deleted");
      // Fast targeted refresh of balances & expenses in background
      getLedgerBalances(companyId, user.id).then((bRes) => bRes?.success && setLedgerBalances(bRes));
      getLedgerExpenses(companyId, user.id).then((eRes) => eRes?.success && setLedgerExpenses(eRes.expenses || []));
    } else {
      showToast(res.message || "Failed to delete expense", "error");
      load(); // Revert back if server rejected
    }
  }

  async function confirmReverseTransaction() {
    if (!reversingTx) return;
    const res = await reverseLedgerTransaction(reversingTx._id, user.id);
    setReversingTx(null);
    if (res.success) {
      showToast("Transaction reversed");
      load();
    } else {
      showToast(res.message || "Failed to reverse transaction", "error");
    }
  }

  async function selectPayee(personId) {
    setMoneyDraft((d) => ({ ...d, adminUserId: personId, amount: "", offsetAdvance: false }));
    if (!personId) {
      setPayeeBills({ loading: false, bills: [], owed: 0 });
      return;
    }
    setPayeeBills({ loading: true, bills: [], owed: 0 });
    const res = await getPayableBills(companyId, personId, user.id);
    setPayeeBills(res.success ? { loading: false, bills: res.bills || [], owed: Number(res.owed || 0) } : { loading: false, bills: [], owed: 0 });
    if (!res.success) showToast(res.message || "Could not load open bills", "error");
  }

  async function submitMoneyAction(event) {
    event.preventDefault();
    setIntercoSaving(true);
    const payload = { companyId, userId: user.id, amount: Number(moneyDraft.amount), fundId: moneyDraft.fundId, method: moneyDraft.method, reference: moneyDraft.reference };
    const result = moneyModal === "lend" ? await lendToCompany(payload) : await reimburseAdmin({ ...payload, adminUserId: moneyDraft.adminUserId, offsetAdvance: Boolean(moneyDraft.offsetAdvance) });
    setIntercoSaving(false);
    if (result.success) {
      const payeeName = (ledgerBalances?.admins || []).find((a) => String(a.userId) === String(moneyDraft.adminUserId))?.name || "person";
      const offsetNote = result.offset > 0 ? ` · ${money(result.offset)} set off from voucher balance` : "";
      showToast(moneyModal === "lend"
        ? "Money lent to company"
        : `${payload.amount > 0 ? `Paid ${money(payload.amount)} to ${payeeName}` : `Settled ${payeeName}`}${offsetNote}${result.billsClosed ? ` · ${result.billsClosed} bill${result.billsClosed === 1 ? "" : "s"} closed` : ""}`);
      setMoneyModal("");
      load();
    } else showToast(result.message || "Could not record transaction", "error");
  }

  async function confirmDeleteLoan() {
    const loan = deletingLoan;
    setDeletingLoan(null);
    const res = await deleteCompanyLoan(loan._id, user.id);
    if (res.success) {
      showToast("Borrow deleted and reversed in both companies");
      load();
    } else showToast(res.message || "Could not delete this borrow", "error");
  }

  function openRepay(loan) {
    setIntercoDraft({ companyId: "", amount: "", fundId: availableCompanyFunds[0]?.fundId || "cash", method: "UPI", reference: "" });
    setIntercoModal({ type: "repay", loan });
  }

  async function openReceive(loan) {
    setBorrowerFunds(null);
    setIntercoDraft({ companyId: "", amount: "", fundId: "cash", method: "UPI", reference: "" });
    setIntercoModal({ type: "receive", loan });
    const res = await getLoanBorrowerFunds(loan._id, user.id);
    if (res.success) {
      setBorrowerFunds(res.funds);
      setIntercoDraft((draft) => ({ ...draft, fundId: res.funds[0]?.fundId || "cash" }));
    } else showToast(res.message || "Could not load the borrower's accounts", "error");
  }

  async function submitRoutedPayment(event) {
    event.preventDefault();
    setIntercoSaving(true);
    const result = await routedCompanyPayment({ userId: user.id, companyId, ...routeDraft, sourceFundId: "cash" });
    setIntercoSaving(false);
    if (result.success) {
      showToast("Routed payment recorded");
      setIntercoModal(null);
      load();
    } else showToast(result.message || "Could not record routed payment", "error");
  }


  if (loading || !company) {
    return (
      <div style={{ minHeight: "100vh", display: "flex", alignItems: "center", justifyContent: "center" }}>
        <div className="spinner" />
      </div>
    );
  }

  return (
    <AppLayout companyId={companyId} isAdmin={isAdmin} can={can} permissionRole={permissionRole} activeTab={activeTab} onTabChange={changeTab} title={company.name}>
        <div className="main-panel">
          {!pageAllowed && (
            <div className="card" style={{ textAlign: "center", color: "var(--muted)", padding: 28 }}>This page is turned off for you in this company.</div>
          )}
          {pageAllowed && <>
          {activeTab === "home" && (
            <>
              <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", flexWrap: "wrap", gap: 10, marginBottom: 20 }}>
                <h1 style={{ fontSize: 26, margin: 0 }}>Home</h1>
                {can("post_expenses") && <button className="btn btn-primary" onClick={() => setModal({ type: "add" })}>+ Post Expense</button>}
              </div>
              {(() => {
                const totalSpent = ledgerExpenses.reduce((sum, expense) => sum + Number(expense.amount || 0), 0);
                const borrowedTotal = borrowedByLender.reduce((sum, row) => sum + row.balance, 0);
                const lentTotal = lentByBorrower.reduce((sum, row) => sum + row.balance, 0);
                const cashTotal = availableCompanyFunds.filter((f) => f.fundId === "cash").reduce((s, f) => s + Number(f.balance || 0), 0);
                const bankTotal = availableCompanyFunds.filter((f) => f.fundId !== "cash").reduce((s, f) => s + Number(f.balance || 0), 0);
                const loanLines = (rows, arrow) => rows.slice(0, 2).map((row) => (
                  <div key={row.name} className="home-tile-line">
                    <span>{arrow(row.name)}</span>
                    <strong>{money(row.balance)}</strong>
                  </div>
                ));
                return (
                  <div className={`home-tiles ${isAdmin ? "" : "staff"}`}>
                    <HomeTile
                      label="Total expenses"
                      value={money(totalSpent)}
                      sub={`${ledgerExpenses.length} expense${ledgerExpenses.length === 1 ? "" : "s"}`}
                      onClick={() => changeTab("expenses")}
                      title="View all expenses"
                    />
                    <HomeTile
                      label={isAdmin ? "My outstanding" : "Company owes you"}
                      value={money(ledgerBalances?.myOwed)}
                      color={Number(ledgerBalances?.myOwed) > 0 ? "var(--terracotta)" : undefined}
                      sub={isAdmin ? `Owed to all people ${money(ledgerBalances?.totalOwedToAdmins)}` : "Paid by you, not yet reimbursed"}
                    />
                    {!isAdmin && (
                      <HomeTile
                        label="Voucher balance"
                        value={money(Math.max(0, Number(ledgerBalances?.myAdvance || 0)))}
                        sub={Number(ledgerBalances?.myAdvance) > 0 ? "Company money with you · tap to hand back" : "No voucher money with you"}
                        onClick={Number(ledgerBalances?.myAdvance) > 0 && can("vouchers") ? () => setHandBackOpen(true) : undefined}
                        title="Hand back unused voucher money"
                      />
                    )}
                    {isAdmin && (
                      <>
                        <HomeTile
                          label="Pending borrowed"
                          value={money(borrowedTotal)}
                          color={borrowedTotal > 0 ? "var(--terracotta)" : undefined}
                          sub={borrowedByLender.length ? loanLines(borrowedByLender, (name) => `from ${name}`) : "Nothing to repay"}
                          onClick={() => changeTab("interco")}
                          title="View company loans"
                        />
                        <HomeTile
                          label="Pending lent"
                          value={money(lentTotal)}
                          sub={lentByBorrower.length ? loanLines(lentByBorrower, (name) => `to ${name}`) : "Nothing to collect"}
                          onClick={() => changeTab("interco")}
                          title="View company loans"
                        />
                        <HomeTile
                          label="Balance"
                          value={money(cashTotal + bankTotal)}
                          sub={`Cash ${money(cashTotal)} · Bank ${money(bankTotal)}`}
                          onClick={() => changeTab("funds")}
                          title="View company funds"
                        />
                      </>
                    )}
                  </div>
                );
              })()}
              {isAdmin && (can("reimburse") || can("vouchers")) && <div className="m-action-row" style={{ display: "flex", flexWrap: "wrap", gap: 8, marginBottom: 22 }}>{can("reimburse") && <><button className="btn btn-dark" onClick={() => { setMoneyDraft({ adminUserId: "", amount: "", fundId: availableCompanyFunds[0]?.fundId || "cash", method: "UPI", reference: "", offsetAdvance: false }); setMoneyModal("lend"); }}>Lend to company</button><button className="btn btn-outline" onClick={() => { setMoneyDraft({ adminUserId: "", amount: "", fundId: availableCompanyFunds[0]?.fundId || "cash", method: "UPI", reference: "", offsetAdvance: false }); setMoneyModal("reimburse"); }}>Reimburse person</button></>}{can("vouchers") && <button className="btn btn-outline" onClick={() => setVoucherModal(true)}>Create voucher</button>}</div>}
              <StaffVouchers companyId={companyId} company={company} user={user} isAdmin={isAdmin} can={can} refreshKey={tick("vouchers", "balances")} onChanged={load} />
              {/* Home lists only expenses posted today; the rest live on the Expenses page */}
              <div style={{ marginBottom: 10 }}>
                <span className="today-chip">
                  <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                    <rect x="3" y="4" width="18" height="18" rx="2" /><path d="M16 2v4" /><path d="M8 2v4" /><path d="M3 10h18" />
                  </svg>
                  Today · {formatDate(new Date())}
                </span>
              </div>
              {ledgerExpenses.filter((expense) => new Date(expense.createdAt || expense.date).toDateString() === TODAY_KEY).length === 0 ? (
                <div className="card" style={{ color: "var(--muted)", textAlign: "center" }}>No expenses today.</div>
              ) : (
                <div className="card expense-list">
                  {ledgerExpenses
                    .filter((expense) => new Date(expense.createdAt || expense.date).toDateString() === TODAY_KEY)
                    .map((expense) => {
                      const tone = expense.lifecycle === "rejected" ? "bad" : expense.lifecycle === "approved" || expense.lifecycle?.startsWith("paid") ? "good" : expense.lifecycle === "reimbursed" ? "done" : "wait";
                      return (
                        <button type="button" key={expense._id} className="expense-row" onClick={() => setSelectedExpenseDetail(expense)}>
                          <span className="expense-row-main">
                            <span className="expense-row-title">{expense.description}</span>
                            <span className="expense-row-meta">{expense.category || "General"} · {postedByName(expense, company)} · {formatDate(expense.date || expense.createdAt)}</span>
                          </span>
                          <span className={`expense-row-status ${tone}`}>{expenseStatusLabel(expense, company)}</span>
                          <span className="expense-row-amount">{money(expense.amount)}</span>
                        </button>
                      );
                    })}
                </div>
              )}
              {/* only shown when something is waiting for a second manager */}
              {isAdmin && can("verify") && pendingVerification.length > 0 && (
                <>
                  <h2 style={{ margin: "22px 0 12px", fontSize: 19 }}>Pending verification</h2>
                  <div className="card expense-list">
                    {pendingVerification.map((transaction) => (
                      <div key={transaction._id} className="expense-row static">
                        <span className="expense-row-main">
                          <span className="expense-row-title">{transaction.memo || transaction.type}</span>
                          <span className="expense-row-meta">{transaction.createdBy?.name || "Manager"} · {formatDate(transaction.createdAt)}</span>
                        </span>
                        <span className="expense-row-amount">{money(transaction.entries?.reduce((sum, entry) => sum + Number(entry.debit || 0), 0))}</span>
                        <span className="expense-row-action"><button className="btn btn-primary btn-sm" onClick={() => verifyTransaction(transaction)}>Verify</button></span>
                      </div>
                    ))}
                  </div>
                </>
              )}
            </>
          )}

          {activeTab === "expenses" && (
            <>
              <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", flexWrap: "wrap", gap: 10, marginBottom: 6 }}>
                <h1 style={{ fontSize: 26, margin: 0 }}>Expenses</h1>
                {can("post_expenses") && <button className="btn btn-primary" onClick={() => setModal({ type: "add" })}>+ Post Expense</button>}
              </div>
              <p style={{ color: "var(--muted)", margin: "0 0 18px" }}>Review and track company expense submissions.</p>
              <div className="m-chip-row" style={{ display: "flex", flexWrap: "wrap", gap: 8, marginBottom: 14 }}>
                {["All", "Submitted", "Approved", ...(isAdmin ? ["Verify"] : [])].map((filter) => (
                  <button
                    key={filter}
                    className={`btn ${statusFilter === filter ? "btn-dark" : "btn-outline"}`}
                    onClick={() => setStatusFilter(filter)}
                  >
                    {filter}
                  </button>
                ))}
              </div>

              <div
                className="card m-filter-bar"
                style={{
                  marginBottom: 18,
                  padding: "10px 14px",
                  display: "flex",
                  flexWrap: "wrap",
                  alignItems: "center",
                  gap: 12,
                  background: "#fff",
                  boxShadow: "0 1px 3px rgba(0,0,0,0.04)",
                }}
              >
                <div style={{ position: "relative", flex: "1 1 240px", minWidth: 200 }}>
                  <svg
                    width="15"
                    height="15"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    strokeWidth="2.2"
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    aria-hidden="true"
                    style={{ position: "absolute", left: 11, top: "50%", transform: "translateY(-50%)", color: "var(--muted)", pointerEvents: "none" }}
                  >
                    <circle cx="11" cy="11" r="8" />
                    <line x1="21" y1="21" x2="16.65" y2="16.65" />
                  </svg>
                  <input
                    type="text"
                    className="field-input"
                    style={{ paddingLeft: 34, paddingRight: search ? 30 : 12, height: 38, marginBottom: 0 }}
                    placeholder="Search expenses by description, staff, amount…"
                    value={search}
                    onChange={(e) => setSearch(e.target.value)}
                  />
                  {search && (
                    <button
                      type="button"
                      onClick={() => setSearch("")}
                      style={{
                        position: "absolute",
                        right: 8,
                        top: "50%",
                        transform: "translateY(-50%)",
                        background: "none",
                        border: "none",
                        color: "var(--muted)",
                        cursor: "pointer",
                        fontSize: 14,
                        padding: 4,
                        lineHeight: 1,
                      }}
                      title="Clear search"
                    >
                      ✕
                    </button>
                  )}
                </div>

                <div style={{ display: "flex", alignItems: "center", gap: 8, flexWrap: "wrap" }}>
                  <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
                    <span style={{ fontSize: 12, fontWeight: 600, color: "var(--muted)" }}>Posted by</span>
                    <select
                      className="field-select"
                      style={{ height: 38, padding: "0 10px", fontSize: 13, width: "auto", minWidth: 150, marginBottom: 0 }}
                      value={postedByFilter}
                      onChange={(e) => setPostedByFilter(e.target.value)}
                      title="Show expenses posted by"
                    >
                      <option value="all">Everyone</option>
                      <option value="company">{company.name} (company)</option>
                      <option value="managers">All managers</option>
                      <option value="staff">All staff</option>
                      {members.some((m) => m.role === "admin") && (
                        <optgroup label="Managers">
                          {members.filter((m) => m.role === "admin").map((m) => <option key={m.userId} value={String(m.userId)}>{m.name}</option>)}
                        </optgroup>
                      )}
                      {members.some((m) => m.role !== "admin") && (
                        <optgroup label="Staff">
                          {members.filter((m) => m.role !== "admin").map((m) => <option key={m.userId} value={String(m.userId)}>{m.name}</option>)}
                        </optgroup>
                      )}
                    </select>
                  </div>

                  <PeriodFilter
                    from={expenseDateFrom}
                    to={expenseDateTo}
                    years={expenseYears}
                    onChange={(from, to) => { setExpenseDateFrom(from); setExpenseDateTo(to); }}
                  />

                  {(search || expenseDateFrom || expenseDateTo || statusFilter !== "All" || postedByFilter !== "all") && (
                    <button
                      type="button"
                      className="btn btn-outline"
                      style={{ height: 38, padding: "0 12px", fontSize: 12.5 }}
                      onClick={() => {
                        setSearch("");
                        setExpenseDateFrom("");
                        setExpenseDateTo("");
                        setStatusFilter("All");
                        setPostedByFilter("all");
                      }}
                    >
                      Reset
                    </button>
                  )}
                </div>
              </div>

              {postedByFilter !== "all" && groupedLedgerExpenses.length > 0 && (
                <div style={{ fontSize: 13, color: "var(--muted)", margin: "-6px 0 12px" }}>
                  {groupedLedgerExpenses.reduce((n, g) => n + g.items.length, 0)} expenses · total{" "}
                  <strong style={{ color: "var(--dark-text)" }}>{money(groupedLedgerExpenses.reduce((sum, g) => sum + g.total, 0))}</strong>
                </div>
              )}
              {groupedLedgerExpenses.length === 0 ? (
                <div className="card" style={{ textAlign: "center", color: "var(--muted)", padding: 24 }}>
                  No expenses match your search or date filters.
                  {(search || expenseDateFrom || expenseDateTo || statusFilter !== "All" || postedByFilter !== "all") && (
                    <div style={{ marginTop: 10 }}>
                      <button
                        type="button"
                        className="btn btn-outline"
                        style={{ fontSize: 12.5, padding: "6px 14px" }}
                        onClick={() => {
                          setSearch("");
                          setExpenseDateFrom("");
                            setExpenseDateTo("");
                          setStatusFilter("All");
                          setPostedByFilter("all");
                        }}
                      >
                        Clear filters
                      </button>
                    </div>
                  )}
                </div>
              ) : (
                groupedLedgerExpenses.map((group) => (
                  <div key={group.key} className="expense-date-group">
                    <div className="expense-date-breaker">
                      <div className="expense-date-badge">
                        <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" style={{ flexShrink: 0 }}>
                          <rect width="18" height="18" x="3" y="4" rx="2" ry="2" />
                          <line x1="16" x2="16" y1="2" y2="6" />
                          <line x1="8" x2="8" y1="2" y2="6" />
                          <line x1="3" x2="21" y1="10" y2="10" />
                        </svg>
                        <span>{group.label}</span>
                      </div>
                      <div className="expense-date-breaker-line" />
                      <span className="expense-date-total">
                        {group.items.length} {group.items.length === 1 ? "expense" : "expenses"} · {money(group.total)}
                      </span>
                    </div>

                    <div className="card expense-list">
                      {group.items.map((expense) => {
                        const tone = expense.lifecycle === "rejected" ? "bad" : expense.lifecycle === "approved" || expense.lifecycle?.startsWith("paid") ? "good" : expense.lifecycle === "reimbursed" ? "done" : "wait";
                        const postedBy = postedByName(expense, company);
                        return (
                          <div
                            key={expense._id}
                            className="expense-row"
                            role="button"
                            tabIndex={0}
                            onClick={() => setSelectedExpenseDetail(expense)}
                            onKeyDown={(e) => { if (e.key === "Enter") setSelectedExpenseDetail(expense); }}
                          >
                            <span className="expense-row-main">
                              <span className="expense-row-title">{expense.description}</span>
                              <span className="expense-row-meta">
                                {expense.category || "General"} · {postedBy} · {formatDate(expense.date || expense.createdAt)}
                                {(expense.hasAttachment || expense.hasPaymentReceipt) && (
                                  <span title="Has receipt" style={{ display: "inline-flex", alignItems: "center", gap: 3, marginLeft: 6 }}>
                                    <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                                      <path d="m21.44 11.05-9.19 9.19a6 6 0 0 1-8.49-8.49l8.57-8.57A4 4 0 1 1 18 8.84l-8.59 8.57a2 2 0 0 1-2.83-2.83l8.49-8.48" />
                                    </svg>
                                    Receipt
                                  </span>
                                )}
                              </span>
                            </span>
                            <span className={`expense-row-status ${tone}`}>{expenseStatusLabel(expense, company)}</span>
                            <span className="expense-row-amount">{money(expense.amount)}</span>
                            <span className="expense-row-action" onClick={(e) => e.stopPropagation()}>
                              {isAdmin && expense.lifecycle === "submitted" ? (
                                can("approve_expenses") ? <button type="button" className="btn btn-primary btn-sm" onClick={() => decideLedgerExpense(expense, "approve")}>Approve</button> : null
                              ) : canMarkReceived(expense) ? (
                                <button type="button" className="btn btn-primary btn-sm" onClick={() => setReceivingExpense(expense)}>Received</button>
                              ) : expense.lifecycle === "approved" && payerOptions(expense).length > 0 ? (
                                <button
                                  type="button"
                                  className="btn btn-primary btn-sm"
                                  onClick={() => {
                                    setPaymentDraft({ payer: payerOptions(expense)[0].value, fundId: availableCompanyFunds[0]?.fundId || "cash", sourceCompanyId: "", method: "UPI", reference: "", paymentReceipt: "" });
                                    setModal({ type: "ledgerPay", expense });
                                  }}
                                >
                                  Pay
                                </button>
                              ) : null}
                            </span>
                          </div>
                        );
                      })}
                    </div>
                  </div>
                ))
              )}
            </>
          )}

          {activeTab === "interco" && (
            <>
              <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 12, flexWrap: "wrap" }}><h1 style={{ fontSize: 26, margin: 0 }}>Inter-company</h1>{isAdmin && can("intercompany") && <div className="m-action-row" style={{ display: "flex", gap: 8, flexWrap: "wrap" }}><button className="btn btn-outline" onClick={() => { setRouteDraft({ sourceCompanyId: "", adminUserId: "", amount: "", method: "UPI", reference: "" }); setIntercoModal({ type: "routed" }); }}>Routed payment to manager</button><button className="btn btn-dark" onClick={() => { setIntercoDraft({ companyId: "", amount: "", fundId: availableCompanyFunds[0]?.fundId || "cash", method: "UPI", reference: "" }); setIntercoModal({ type: "borrow" }); }}>Borrow from a company</button></div>}</div>
              {isAdmin && payerRequests.length > 0 && (
                <>
                  <h2 style={{ fontSize: 18, marginTop: 22 }}>Payment confirmations</h2>
                  <div className="card expense-list">
                    {payerRequests.map((expense) => (
                      <div key={expense._id} className="expense-row static wrap">
                        <span className="expense-row-main">
                          <span className="expense-row-title">{expense.description}</span>
                          <span className="expense-row-meta">{expense.companyId?.name || "Another company"} asks {company.name} to pay · {formatDate(expense.createdAt)}</span>
                        </span>
                        <span className="expense-row-amount">{money(expense.amount)}</span>
                        <span style={{ display: "flex", gap: 6, alignItems: "center" }}>
                          <select className="field-select" style={{ height: 30, padding: "0 8px", fontSize: 12 }} value={payerFundSelections[expense._id] || availableCompanyFunds[0]?.fundId || "cash"} onChange={(event) => setPayerFundSelections((current) => ({ ...current, [expense._id]: event.target.value }))}>
                            {availableCompanyFunds.map((fund) => <option key={fund.fundId} value={fund.fundId}>{fund.name}</option>)}
                          </select>
                          {can("intercompany") && <>
                          <button className="btn btn-outline btn-sm" onClick={() => respondToPayerRequest(expense, false)}>Reject</button>
                          <button className="btn btn-primary btn-sm" onClick={() => respondToPayerRequest(expense, true)}>Accept</button>
                          </>}
                        </span>
                      </div>
                    ))}
                  </div>
                </>
              )}
              <h2 style={{ fontSize: 18, marginTop: 24 }}>Company balances</h2>
              {intercompany.length === 0 ? (
                <div className="card" style={{ color: "var(--muted)", padding: "12px 16px", fontSize: 13 }}>No inter-company balances yet.</div>
              ) : (
                <div className="card expense-list">
                  {intercompany.map((row) => (
                    <div key={row.companyId} className="expense-row static">
                      <span className="expense-row-main">
                        <span className="expense-row-title">{row.name}</span>
                        <span className="expense-row-meta">
                          {row.net > 0 ? "They owe this company" : row.net < 0 ? "This company owes them" : "Settled"}
                          {row.mismatch ? <span style={{ color: "var(--terracotta)", fontWeight: 600 }}> · Balance mismatch</span> : null}
                        </span>
                      </span>
                      <span className="expense-row-amount" style={{ color: row.net < 0 ? "var(--terracotta)" : row.net > 0 ? "var(--forest)" : "var(--muted)" }}>{money(Math.abs(row.net))}</span>
                    </div>
                  ))}
                </div>
              )}
              <h2 style={{ fontSize: 18, marginTop: 24 }}>Company loans</h2>
              {loans.length === 0 ? (
                <div className="card" style={{ color: "var(--muted)", padding: "12px 16px", fontSize: 13 }}>No company loans yet.</div>
              ) : (
                <div className="card expense-list">
                  {loans.map((loan) => {
                    const weBorrowed = String(loan.borrowerCompanyId?._id || loan.borrowerCompanyId) === companyId;
                    const lenderName = loan.lenderCompanyId?.name || "Another company";
                    const borrowerName = loan.borrowerCompanyId?.name || "Another company";
                    const sourceLabel = loan.source === "expense" ? "Paid an expense" : loan.source === "group" ? "Paid a group's expenses" : "Direct loan";
                    const open = Number(loan.balance) > 0;
                    return (
                      <div key={loan._id} className="expense-row" role="button" tabIndex={0} style={{ cursor: "pointer" }} onClick={() => setViewingLoan(loan)} onKeyDown={(e) => { if (e.key === "Enter") setViewingLoan(loan); }} title="View loan details">
                        <span className="expense-row-main">
                          <span className="expense-row-title">
                            <span className={`row-tag ${weBorrowed ? "bad" : "good"}`}>{weBorrowed ? "Borrowed" : "Lent"}</span>
                            {lenderName} → {borrowerName}
                          </span>
                          <span className="expense-row-meta">
                            {sourceLabel} · {formatDate(loan.createdAt)} · Original {money(loan.amount)}{Number(loan.repaid) > 0 ? ` · Repaid ${money(loan.repaid)}` : ""}{loan.note ? ` · ${loan.note}` : ""}
                          </span>
                        </span>
                        <span className="expense-row-amount" style={{ color: open ? "var(--terracotta)" : "var(--muted)" }}>{open ? `${money(loan.balance)} due` : "Repaid"}</span>
                        <span className="expense-row-action" style={{ display: "flex", gap: 6 }}>
                          {isAdmin && can("intercompany") && weBorrowed && open && (
                            <button className="btn btn-outline btn-sm" onClick={(e) => { e.stopPropagation(); openRepay(loan); }}>Repay</button>
                          )}
                          {isAdmin && can("intercompany") && !weBorrowed && open && !loan.borrowerCompanyId?.external && (
                            <button className="btn btn-outline btn-sm" onClick={(e) => { e.stopPropagation(); openReceive(loan); }}>Received</button>
                          )}
                          {can("intercompany") && String(loan.createdBy?._id || loan.createdBy) === String(user.id) && !(Number(loan.repaid) > 0) && (
                            <button className="btn btn-outline-danger btn-sm" onClick={(e) => { e.stopPropagation(); setDeletingLoan(loan); }}>Delete</button>
                          )}
                        </span>
                      </div>
                    );
                  })}
                </div>
              )}
            </>
          )}

          {activeTab === "reports" && (
            <>
              <h1 style={{ fontSize: 26, margin: "0 0 18px" }}>Reports</h1>
              <div className="card" style={{ marginBottom: 18, padding: 14 }}>
                <div className="m-stack" style={{ display: "flex", gap: 12, flexWrap: "wrap", alignItems: "flex-end" }}>
                  <div>
                    <label className="field-label">Period</label>
                    <PeriodFilter label="" from={reportFrom} to={reportTo} years={expenseYears} onChange={(from, to) => { setReportFrom(from); setReportTo(to); }} />
                  </div>
                  <div>
                    <label className="field-label">Category</label>
                    <select
                      className="field-select"
                      value={reportCategory}
                      onChange={(e) => setReportCategory(e.target.value)}
                    >
                      <option value="All">All Categories</option>
                      {companyCategories(company).map((c) => (
                        <option key={c} value={c}>{c}</option>
                      ))}
                    </select>
                  </div>
                  <button className="btn btn-primary" onClick={() => loadReport()}>
                    Apply Filter
                  </button>
                  {(reportFrom || reportTo || reportCategory !== "All") && (
                    <button
                      className="btn btn-outline"
                      onClick={() => {
                        setReportFrom("");
                        setReportTo("");
                        setReportCategory("All");
                        loadReport("", "", "All");
                      }}
                    >
                      Clear
                    </button>
                  )}
                </div>
              </div>

              {loadingReport ? (
                <div style={{ display: "flex", justifyContent: "center", padding: 48 }}>
                  <div className="spinner" />
                </div>
              ) : report ? (
                <div className="card">
                  <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 10, flexWrap: "wrap", marginBottom: 14 }}>
                    <h3 style={{ margin: 0, fontSize: 16 }}>Summary</h3>
                    <a
                      className="btn btn-primary"
                      href={getLedgerExportUrl(companyId, user.id, reportFrom, reportTo, reportCategory)}
                      target="_blank"
                      rel="noreferrer"
                    >
                      Export CSV
                    </a>
                  </div>
                  {(() => {
                    const net = Number(report.intercompanyNet || 0);
                    const tiles = [
                      { label: "EXPENSES", value: money(report.expenses), sub: "Paid in this period" },
                      { label: "PAID BY MANAGERS", value: money(report.paidByAdmins), sub: "Paid out of their own pocket" },
                      { label: "OWED TO MANAGERS", value: money(report.owedToAdmins), sub: "Not yet reimbursed", color: Number(report.owedToAdmins) > 0 ? "var(--terracotta)" : undefined },
                      {
                        label: "INTER-COMPANY NET",
                        value: net < 0 ? `We owe ${money(-net)}` : net > 0 ? `Owed to us ${money(net)}` : money(0),
                        sub: net < 0 ? "Net owed to other companies" : net > 0 ? "Net other companies owe us" : "Settled with other companies",
                        color: net < 0 ? "var(--terracotta)" : net > 0 ? "var(--forest)" : undefined,
                      },
                    ];
                    return (
                      <div className="m-tiles-2" style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(190px, 1fr))", gap: 12 }}>
                        {tiles.map((t) => (
                          <div key={t.label} className="stat-card" style={{ minWidth: 0 }}>
                            <div style={{ fontSize: 10.5, color: "var(--muted)", fontWeight: 700, letterSpacing: 0.6, marginBottom: 6 }}>{t.label}</div>
                            <div style={{ fontSize: 20, fontWeight: 800, color: t.color || "var(--dark-text)", whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{t.value}</div>
                            <div style={{ fontSize: 11.5, color: "var(--muted)", marginTop: 4 }}>{t.sub}</div>
                          </div>
                        ))}
                      </div>
                    );
                  })()}
                </div>
              ) : (
                <div className="card" style={{ color: "var(--muted)" }}>No report data.</div>
              )}
              <OutstandingReport companyId={companyId} userId={user.id} refreshKey={reportTick} />
            </>
          )}

          {activeTab === "analysis" && isAdmin && <ExpenseAnalysis companyId={companyId} userId={user.id} refreshKey={tick("expenses")} />}

          {activeTab === "vouchers" && isAdmin && (
            <VouchersPanel companyId={companyId} company={company} user={user} members={members} funds={availableCompanyFunds} onChanged={load} refreshKey={tick("vouchers", "balances")} />
          )}

          {activeTab === "payments" && isAdmin && (
            <PaymentsPanel companyId={companyId} company={company} user={user} members={members} funds={availableCompanyFunds} onChanged={load} refreshKey={tick("balances", "expenses")} />
          )}

          {activeTab === "transactions" && isAdmin && (
            <><h1 style={{ fontSize: 26, margin: "0 0 18px" }}>Ledger</h1><LedgerHistory companyId={companyId} userId={user.id} loader={getLedgerTransactions} title="Ledger" isAdmin={isAdmin} onReverse={(tx) => setReversingTx(tx)} refreshKey={tick("ledger")} /></>
          )}
          {activeTab === "audit" && isAdmin && <><h1 style={{ fontSize: 26, margin: "0 0 18px" }}>Audit log</h1><LedgerHistory companyId={companyId} userId={user.id} loader={getLedgerAuditLog} title="Audit log" refreshKey={tick("ledger")} /></>}

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
                        onViewDetail={(e) => setSelectedExpenseDetail(e)}
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
              refreshKey={tick("funds")}
              onChanged={(accounts, cash, newName) =>
                setCompany((c) => ({
                  ...c,
                  bankAccounts: accounts,
                  cashBalance: cash,
                  ...(newName ? { cashAccountName: newName } : {}),
                }))
              }
            />
          )}

          {activeTab === "settings" && (
            <SettingsPanel company={company} members={members} user={user} isAdmin={isAdmin} can={can} onChanged={load} />
          )}

          {activeTab === "permissions" && <PermissionsPanel companyId={companyId} user={user} refreshKey={tick("permissions")} />}
          </>}
        </div>

      {modal?.type === "add" && (
        <AddExpenseModal
          company={company}
          user={user}
          isAdmin={isAdmin}
          canPostAsCompany={can("post_as_company")}
          members={members}
          customCategories={customCategories}
          hiddenStaffIds={hiddenStaffIds}
          existingExpenses={ledgerExpenses}
          advanceBalance={Math.max(0, Number(ledgerBalances?.myAdvance || 0))}
          onCategoryAdded={(list) => setCompany((c) => ({ ...c, customCategories: list }))}
          onHiddenStaffChange={setHiddenStaffIds}
          onClose={() => setModal(null)}
          onCreated={load}
        />
      )}

      {viewingLoan && (
        <LoanDetailModal
          initialLoan={viewingLoan}
          companyId={companyId}
          user={user}
          onClose={() => setViewingLoan(null)}
          refreshKey={tick("loans")}
          onRepay={isAdmin && can("intercompany") ? (loan) => { setViewingLoan(null); openRepay(loans.find((l) => String(l._id) === String(loan._id)) || loan); } : undefined}
          onReceive={isAdmin && can("intercompany") ? (loan) => { setViewingLoan(null); openReceive(loans.find((l) => String(l._id) === String(loan._id)) || loan); } : undefined}
          onDelete={can("intercompany") ? (loan) => { setViewingLoan(null); setDeletingLoan(loan); } : undefined}
        />
      )}

      {deletingLoan && (
        <ConfirmDialog
          title="Delete this borrow?"
          message={`${deletingLoan.lenderCompanyId?.name || "Lender"} → ${deletingLoan.borrowerCompanyId?.name || "borrower"} · ${money(deletingLoan.amount)} will be reversed in both companies' books.${deletingLoan.source === "expense" ? " The bill it paid goes back to Approved · unpaid." : deletingLoan.source === "group" ? " The group it settled is reopened." : ` ${deletingLoan.borrowerCompanyId?.name || "The borrower"}'s Cash/Bank is put back.`} This can't be undone.`}
          confirmLabel="Delete borrow"
          danger
          onConfirm={confirmDeleteLoan}
          onCancel={() => setDeletingLoan(null)}
        />
      )}

      {voucherModal && (
        <CreateVoucherModal companyId={companyId} user={user} members={members} funds={availableCompanyFunds} onClose={() => setVoucherModal(false)} onCreated={load} />
      )}

      {handBackOpen && (
        <HandBackModal companyId={companyId} user={user} held={Math.max(0, Number(ledgerBalances?.myAdvance || 0))} onClose={() => setHandBackOpen(false)} onDone={load} />
      )}

      {moneyModal && (
        <Modal onClose={() => setMoneyModal("")} maxWidth={440}>
          <h2 style={{ marginTop: 0 }}>{moneyModal === "lend" ? "Lend to company" : "Reimburse person"}</h2>
          <form onSubmit={submitMoneyAction}>
            {moneyModal === "reimburse" && <><label className="field-label">Pay to</label><select className="field-select" value={moneyDraft.adminUserId} onChange={(event) => selectPayee(event.target.value)} required><option value="">Choose person</option>{(ledgerBalances?.admins || []).filter((admin) => String(admin.userId) !== user.id && Number(admin.owed) > 0).map((admin) => <option key={admin.userId} value={admin.userId}>{admin.name} · owed {money(admin.owed)}</option>)}</select></>}
            <label className="field-label" style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginTop: 12 }}>
              <span>Amount (₹)</span>
              {moneyModal === "reimburse" && moneyDraft.adminUserId && payeeBills.owed > 0 && (
                <button type="button" className="btn btn-outline" style={{ padding: "2px 10px", fontSize: 11.5 }} onClick={() => setMoneyDraft((d) => ({ ...d, amount: String(Math.max(0, roundMoney(payeeBills.owed - (d.offsetAdvance ? payeeHeld : 0)))) }))}>
                  Pay full balance · {money(Math.max(0, payeeBills.owed - (moneyDraft.offsetAdvance ? payeeHeld : 0)))}
                </button>
              )}
            </label>
            <input className="field-input" type="number" min={offsetAmount > 0 ? "0" : "0.01"} step="0.01" max={moneyModal === "reimburse" && moneyDraft.adminUserId && payeeBills.owed > 0 ? payeeBills.owed : undefined} value={moneyDraft.amount} onChange={(event) => setMoneyDraft({ ...moneyDraft, amount: event.target.value })} required />
            {moneyModal === "reimburse" && moneyDraft.adminUserId && payeeHeld > 0 && (
              <label style={{ display: "flex", alignItems: "flex-start", gap: 8, marginTop: 10, fontSize: 13, cursor: "pointer" }}>
                <input
                  type="checkbox"
                  checked={Boolean(moneyDraft.offsetAdvance)}
                  onChange={(event) => {
                    const on = event.target.checked;
                    setMoneyDraft((d) => ({ ...d, offsetAdvance: on, amount: String(Math.max(0, roundMoney(payeeBills.owed - (on ? payeeHeld : 0)))) }));
                  }}
                  style={{ marginTop: 2 }}
                />
                <span>
                  Set off the voucher balance they hold ({money(payeeHeld)})
                  {offsetAmount > 0 && <span style={{ display: "block", color: "var(--muted)", fontSize: 12 }}>{money(offsetAmount)} taken from their balance · {money(Number(moneyDraft.amount || 0))} paid now</span>}
                </span>
              </label>
            )}
            {moneyModal === "reimburse" && moneyDraft.adminUserId && <PayableBillsPreview bills={payeeBills.bills} loading={payeeBills.loading} amount={Number(moneyDraft.amount || 0) + offsetAmount} />}
            <label className="field-label" style={{ display: "block", marginTop: 12 }}>Paid from</label><select className="field-select" value={moneyDraft.fundId} onChange={(event) => setMoneyDraft({ ...moneyDraft, fundId: event.target.value })}>{availableCompanyFunds.map((fund) => <option key={fund.fundId} value={fund.fundId}>{fund.name} · {money(fund.balance)}</option>)}</select>
            <label className="field-label" style={{ display: "block", marginTop: 12 }}>Payment method</label>
            <select
              className="field-select"
              value={moneyDraft.method}
              onChange={(event) => setMoneyDraft({ ...moneyDraft, method: event.target.value })}
              required
            >
              {PAYMENT_METHODS.map((m) => (
                <option key={m} value={m}>{m}</option>
              ))}
              {moneyDraft.method && !PAYMENT_METHODS.includes(moneyDraft.method) && (
                <option value={moneyDraft.method}>{moneyDraft.method}</option>
              )}
            </select>
            <label className="field-label" style={{ display: "block", marginTop: 12 }}>Reference (optional)</label><input className="field-input" value={moneyDraft.reference} onChange={(event) => setMoneyDraft({ ...moneyDraft, reference: event.target.value })} />
            <div style={{ display: "flex", gap: 10, marginTop: 20 }}><button type="button" className="btn btn-outline" style={{ flex: 1 }} onClick={() => setMoneyModal("")}>Cancel</button><button className="btn btn-primary" style={{ flex: 1 }} disabled={intercoSaving}>{intercoSaving ? "Saving…" : "Record transaction"}</button></div>
          </form>
        </Modal>
      )}

      {modal?.type === "ledgerPay" && (
        <Modal onClose={() => setModal(null)} maxWidth={460}>
          <h2 style={{ marginTop: 0 }}>Record payment</h2>
          <p style={{ color: "var(--muted)" }}>{modal.expense.description} · {money(modal.expense.amount)}</p>
          <form onSubmit={submitLedgerPayment}>
            <label className="field-label">Who paid?</label>
            <select className="field-select" value={paymentDraft.payer} onChange={(event) => setPaymentDraft({ ...paymentDraft, payer: event.target.value })}>
              {payerOptions(modal.expense).map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}
            </select>
            {paymentDraft.payer === "company" && (() => {
              const selectedFund = payingFunds.find((f) => String(f.fundId) === String(paymentDraft.fundId)) || payingFunds[0];
              const expenseAmount = Number(modal.expense?.amount || 0);
              const isOtherCompany = payingCompanyId !== companyId;
              // borrowing from another company ignores its balance; only this company's own funds are checked
              const isInsufficient = !isOtherCompany && selectedFund && Number(selectedFund.balance || 0) < expenseAmount;

              return (
                <>
                  {isAdmin && managedOtherCompanies.length > 0 && (
                    <>
                      <label className="field-label" style={{ display: "block", marginTop: 12 }}>Paying company</label>
                      <select
                        className="field-select"
                        value={payingCompanyId}
                        onChange={(event) => setPaymentDraft({ ...paymentDraft, payingCompanyId: event.target.value, fundId: "cash" })}
                      >
                        <option value={companyId}>{company.name} (this company)</option>
                        {managedOtherCompanies.map((c) => (
                          <option key={c._id} value={String(c._id)}>{c.name}</option>
                        ))}
                      </select>
                      {isOtherCompany && (
                        <p style={{ margin: "6px 0 0", fontSize: 12, color: "var(--terracotta)", lineHeight: 1.45 }}>
                          {payingCompany?.name} → {company.name}: {money(expenseAmount)} will be recorded as borrowed by {company.name} from {payingCompany?.name}. Neither company's Cash/Bank changes; it shows in the Borrowed / Lent tiles.
                        </p>
                      )}
                    </>
                  )}
                  {!isOtherCompany && (
                    <>
                      <label className="field-label" style={{ display: "block", marginTop: 12 }}>Paid from</label>
                      <select className="field-select" value={paymentDraft.fundId} onChange={(event) => setPaymentDraft({ ...paymentDraft, fundId: event.target.value })}>
                        {payingFunds.map((fund) => {
                          const fundLow = Number(fund.balance || 0) < expenseAmount;
                          return (
                            <option key={fund.fundId} value={fund.fundId}>
                              {fund.name} · {money(fund.balance)} {fundLow ? "⚠️ (Insufficient balance)" : ""}
                            </option>
                          );
                        })}
                      </select>
                    </>
                  )}
                  {isInsufficient && (
                    <div
                      style={{
                        display: "flex",
                        alignItems: "center",
                        gap: 6,
                        marginTop: 6,
                        padding: "7px 10px",
                        background: "#FEF2F2",
                        border: "1px solid #FECACA",
                        borderRadius: 8,
                        color: "#DC2626",
                        fontSize: 12,
                        fontWeight: 600,
                      }}
                    >
                      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" style={{ flexShrink: 0 }}>
                        <circle cx="12" cy="12" r="10" />
                        <line x1="12" y1="8" x2="12" y2="12" />
                        <line x1="12" y1="16" x2="12.01" y2="16" />
                      </svg>
                      <span>Insufficient balance: {money(selectedFund?.balance || 0)} available ({money(expenseAmount)} required)</span>
                    </div>
                  )}
                </>
              );
            })()}
            {paymentDraft.payer === "borrow" && (
              <>
                <label className="field-label" style={{ display: "block", marginTop: 12 }}>Source company</label>
                <select
                  className="field-select"
                  value={paymentDraft.sourceCompanyId}
                  onChange={(event) => setPaymentDraft({ ...paymentDraft, sourceCompanyId: event.target.value })}
                >
                  <option value="">Choose company</option>
                  {borrowSources.map((source) => (
                    <option key={source._id} value={source._id}>{source.name}</option>
                  ))}
                </select>
                {borrowSources.length === 0 && (
                  <p style={{ margin: "6px 0 0", fontSize: 12, color: "var(--muted)", lineHeight: 1.4 }}>
                    No other companies found. You need at least one other company created in your workspace to borrow from.
                  </p>
                )}
              </>
            )}
            <label className="field-label" style={{ display: "block", marginTop: 12 }}>Payment method</label>
            <select
              className="field-select"
              value={paymentDraft.method}
              onChange={(event) => setPaymentDraft({ ...paymentDraft, method: event.target.value })}
              required
            >
              {PAYMENT_METHODS.map((m) => (
                <option key={m} value={m}>{m}</option>
              ))}
              {paymentDraft.method && !PAYMENT_METHODS.includes(paymentDraft.method) && (
                <option value={paymentDraft.method}>{paymentDraft.method}</option>
              )}
            </select>
            <label className="field-label" style={{ display: "block", marginTop: 12 }}>Reference (optional)</label><input className="field-input" value={paymentDraft.reference} onChange={(event) => setPaymentDraft({ ...paymentDraft, reference: event.target.value })} />
            <label className="field-label" style={{ display: "block", marginTop: 12 }}>Payment receipt (optional)</label><input type="file" accept="image/*" onChange={async (event) => { const file = event.target.files?.[0]; if (!file) { setPaymentDraft((current) => ({ ...current, paymentReceipt: "" })); return; } if (file.size > 5 * 1024 * 1024) { showToast("Receipt must be 5 MB or smaller", "error"); event.target.value = ""; return; } const paymentReceipt = await fileToBase64(file); setPaymentDraft((current) => ({ ...current, paymentReceipt })); }} />
            <div style={{ display: "flex", gap: 10, marginTop: 20 }}>
              <button type="button" className="btn btn-outline" style={{ flex: 1 }} onClick={() => setModal(null)}>Cancel</button>
              {(() => {
                const selectedFund = paymentDraft.payer === "company"
                  ? (payingFunds.find((f) => String(f.fundId) === String(paymentDraft.fundId)) || payingFunds[0])
                  : null;
                const isInsufficient = paymentDraft.payer === "company" && payingCompanyId === companyId && selectedFund && Number(selectedFund.balance || 0) < Number(modal.expense?.amount || 0);

                return (
                  <button
                    className="btn btn-primary"
                    style={{
                      flex: 1,
                      opacity: isInsufficient ? 0.55 : 1,
                      cursor: isInsufficient ? "not-allowed" : "pointer",
                    }}
                    disabled={isInsufficient}
                    title={isInsufficient ? "Cannot record payment: Insufficient balance in selected fund" : ""}
                  >
                    {isInsufficient ? "Insufficient Balance" : "Record payment"}
                  </button>
                );
              })()}
            </div>
          </form>
        </Modal>
      )}

      {intercoModal && (
        <Modal onClose={() => setIntercoModal(null)} maxWidth={460}>
          <h2 style={{ marginTop: 0 }}>{intercoModal.type === "receive" ? "Mark repayment received" : intercoModal.type === "repay" ? "Repay company loan" : intercoModal.type === "routed" ? "Routed payment to manager" : "Borrow from a company"}</h2>
          {intercoModal.type === "routed" ? <form onSubmit={submitRoutedPayment}>
            <label className="field-label">Source company</label><select className="field-select" value={routeDraft.sourceCompanyId} onChange={(event) => setRouteDraft({ ...routeDraft, sourceCompanyId: event.target.value })} required><option value="">Choose company</option>{borrowSources.map((source) => <option key={source._id} value={source._id}>{source.name}</option>)}</select>
            <label className="field-label" style={{ display: "block", marginTop: 12 }}>Manager being paid</label><select className="field-select" value={routeDraft.adminUserId} onChange={(event) => setRouteDraft({ ...routeDraft, adminUserId: event.target.value })} required><option value="">Choose manager</option>{members.filter((member) => member.role === "admin" && member.userId !== user.id).map((member) => <option key={member.userId} value={member.userId}>{member.name}</option>)}</select>
            <label className="field-label" style={{ display: "block", marginTop: 12 }}>Amount (₹)</label><input className="field-input" type="number" min="0.01" step="0.01" value={routeDraft.amount} onChange={(event) => setRouteDraft({ ...routeDraft, amount: event.target.value })} required />
            <label className="field-label" style={{ display: "block", marginTop: 12 }}>Payment method</label>
            <select
              className="field-select"
              value={routeDraft.method}
              onChange={(event) => setRouteDraft({ ...routeDraft, method: event.target.value })}
              required
            >
              {PAYMENT_METHODS.map((m) => (
                <option key={m} value={m}>{m}</option>
              ))}
              {routeDraft.method && !PAYMENT_METHODS.includes(routeDraft.method) && (
                <option value={routeDraft.method}>{routeDraft.method}</option>
              )}
            </select>
            <label className="field-label" style={{ display: "block", marginTop: 12 }}>Reference (optional)</label><input className="field-input" value={routeDraft.reference} onChange={(event) => setRouteDraft({ ...routeDraft, reference: event.target.value })} />
            <div style={{ display: "flex", gap: 10, marginTop: 20 }}><button type="button" className="btn btn-outline" style={{ flex: 1 }} onClick={() => setIntercoModal(null)}>Cancel</button><button className="btn btn-primary" style={{ flex: 1 }} disabled={intercoSaving}>{intercoSaving ? "Saving…" : "Confirm routed payment"}</button></div>
          </form> :
          <form onSubmit={submitIntercoAction}>
            {intercoModal.type === "borrow" && <><label className="field-label">Lender company</label><select className="field-select" value={intercoDraft.companyId} onChange={(event) => setIntercoDraft({ ...intercoDraft, companyId: event.target.value })} required><option value="">Choose company</option>{borrowSources.map((source) => <option key={source._id} value={source._id}>{source.name}</option>)}</select></>}
            {intercoModal.type === "borrow" && <p style={{ color: "var(--muted)", fontSize: 13, margin: "10px 0 0" }}>{(borrowSources.find((s) => s._id === intercoDraft.companyId)?.name || "Lender company")} → <strong>{company.name}</strong>. The amount is added to the fund you pick below and shows as owed to the lender.</p>}
            {intercoModal.type === "receive" && <p style={{ color: "var(--muted)" }}>{intercoModal.loan.borrowerCompanyId?.name || "Borrower"} → <strong>{company.name}</strong> · Outstanding balance: {money(intercoModal.loan.balance)}. The amount comes off what they owe you and out of the account you pick below.</p>}
            {intercoModal.type === "repay" && <p style={{ color: "var(--muted)" }}><strong>{company.name}</strong> → {intercoModal.loan.lenderCompanyId?.name || "lender"} · Outstanding balance: {money(intercoModal.loan.balance)}</p>}
            <label className="field-label" style={{ display: "block", marginTop: 12 }}>Amount (₹)</label><input className="field-input" type="number" min="0.01" step="0.01" max={intercoModal.type === "repay" || intercoModal.type === "receive" ? intercoModal.loan.balance : undefined} value={intercoDraft.amount} onChange={(event) => setIntercoDraft({ ...intercoDraft, amount: event.target.value })} required />
            {intercoModal.type === "receive" ? <><label className="field-label" style={{ display: "block", marginTop: 12 }}>Paid from ({intercoModal.loan.borrowerCompanyId?.name || "borrower"}'s account)</label><select className="field-select" value={intercoDraft.fundId} onChange={(event) => setIntercoDraft({ ...intercoDraft, fundId: event.target.value })} disabled={!borrowerFunds} required>{!borrowerFunds && <option value="">Loading…</option>}{(borrowerFunds || []).map((fund) => <option key={fund.fundId} value={fund.fundId}>{fund.name}</option>)}</select></> : <>
            <label className="field-label" style={{ display: "block", marginTop: 12 }}>{intercoModal.type === "repay" ? `Pay from (${company.name})` : `Receive into (${company.name})`}</label><select className="field-select" value={intercoDraft.fundId} onChange={(event) => setIntercoDraft({ ...intercoDraft, fundId: event.target.value })}>{availableCompanyFunds.map((fund) => <option key={fund.fundId} value={fund.fundId}>{fund.name} · {money(fund.balance)}</option>)}</select></>}
            <label className="field-label" style={{ display: "block", marginTop: 12 }}>Payment method</label>
            <select
              className="field-select"
              value={intercoDraft.method}
              onChange={(event) => setIntercoDraft({ ...intercoDraft, method: event.target.value })}
              required
            >
              {PAYMENT_METHODS.map((m) => (
                <option key={m} value={m}>{m}</option>
              ))}
              {intercoDraft.method && !PAYMENT_METHODS.includes(intercoDraft.method) && (
                <option value={intercoDraft.method}>{intercoDraft.method}</option>
              )}
            </select>
            <label className="field-label" style={{ display: "block", marginTop: 12 }}>Reference (optional)</label><input className="field-input" value={intercoDraft.reference} onChange={(event) => setIntercoDraft({ ...intercoDraft, reference: event.target.value })} />
            {intercoModal.type !== "repay" && intercoModal.type !== "receive" && <><label className="field-label" style={{ display: "block", marginTop: 12 }}>Reason for borrowing (optional)</label><textarea className="field-input" rows={2} maxLength={200} placeholder="e.g. Salary payout before client payment arrives" style={{ resize: "vertical", minHeight: 60, paddingTop: 10 }} value={intercoDraft.note || ""} onChange={(event) => setIntercoDraft({ ...intercoDraft, note: event.target.value })} /></>}
            <div style={{ display: "flex", gap: 10, marginTop: 20 }}><button type="button" className="btn btn-outline" style={{ flex: 1 }} onClick={() => setIntercoModal(null)}>Cancel</button><button className="btn btn-primary" style={{ flex: 1 }} disabled={intercoSaving}>{intercoSaving ? "Saving…" : intercoModal.type === "receive" ? "Mark received" : intercoModal.type === "repay" ? "Record repayment" : "Record loan"}</button></div>
          </form>}
        </Modal>
      )}

      {modal?.type === "edit" && (
        <EditExpenseModal
          expense={modal.expense}
          user={user}
          isAdmin={isAdmin}
          funds={availableCompanyFunds}
          customCategories={customCategories}
          hiddenCategories={company?.hiddenCategories || []}
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
          cashAccountName={company?.cashAccountName || "InCash"}
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

      {visibilityModal && (
        <Modal onClose={() => setVisibilityModal(null)} maxWidth={500}>
          <h2 style={{ marginTop: 0, marginBottom: 8 }}>Staff Visibility</h2>
          <p style={{ color: "var(--muted)", fontSize: 13, margin: "0 0 16px" }}>
            Choose which staff can see &quot;{visibilityModal.expense.description}&quot;.
          </p>
          <form onSubmit={handleSaveVisibility}>
            <label className="group-member-option" style={{ marginBottom: 12 }}>
              <input
                type="checkbox"
                checked={visibilityModal.allStaff}
                onChange={(e) => {
                  setVisibilityModal((curr) => ({
                    ...curr,
                    allStaff: e.target.checked,
                    selectedIds: e.target.checked ? new Set() : new Set(members.map((m) => String(m.userId))),
                  }));
                }}
              />
              <strong>Visible to all staff</strong>
            </label>

            {!visibilityModal.allStaff && (
              <div style={{ maxHeight: 220, overflowY: "auto", border: "1px solid var(--slate-border-2)", borderRadius: 10, padding: 10, marginBottom: 16 }}>
                {members.map((m) => {
                  const mId = String(m.userId);
                  const isChecked = visibilityModal.selectedIds.has(mId);
                  return (
                    <label key={mId} className="group-member-option" style={{ padding: "6px 0" }}>
                      <input
                        type="checkbox"
                        checked={isChecked}
                        onChange={(e) => {
                          const next = new Set(visibilityModal.selectedIds);
                          if (e.target.checked) next.add(mId);
                          else next.delete(mId);
                          setVisibilityModal((curr) => ({ ...curr, selectedIds: next }));
                        }}
                      />
                      <span>{m.name} ({m.role === "admin" ? "Manager" : "Staff"})</span>
                    </label>
                  );
                })}
              </div>
            )}

            <div style={{ display: "flex", gap: 10, marginTop: 18 }}>
              <button type="button" className="btn btn-outline" style={{ flex: 1 }} onClick={() => setVisibilityModal(null)}>
                Cancel
              </button>
              <button className="btn btn-primary" style={{ flex: 1 }} disabled={savingVisibility}>
                {savingVisibility ? "Saving…" : "Save Visibility"}
              </button>
            </div>
          </form>
        </Modal>
      )}

      {receivingExpense && (
        <ReceivedModal
          expense={receivingExpense}
          company={company}
          user={user}
          members={members}
          funds={availableCompanyFunds}
          onClose={() => setReceivingExpense(null)}
          onDone={() => {
            setReceivingExpense(null);
            setSelectedExpenseDetail(null);
            load();
            getLedgerExpenses(companyId, user.id).then((res) => res?.success && setLedgerExpenses(res.expenses || []));
            getLedgerBalances(companyId, user.id).then((res) => res?.success && setLedgerBalances(res));
          }}
        />
      )}

      {deletingExpense && (
        <ConfirmDialog
          title="Delete submitted expense?"
          message={`Are you sure you want to delete "${deletingExpense.description}" (${money(deletingExpense.amount)})?`}
          confirmLabel="Delete"
          danger
          onConfirm={confirmDeleteExpense}
          onCancel={() => setDeletingExpense(null)}
        />
      )}

      {reversingTx && (
        <ConfirmDialog
          title="Reverse transaction?"
          message={`A reversal entry will be booked in the ledger for "${reversingTx.memo || 'this transaction'}". No transaction records will be deleted.`}
          confirmLabel="Reverse Transaction"
          danger
          onConfirm={confirmReverseTransaction}
          onCancel={() => setReversingTx(null)}
        />
      )}

      {selectedExpenseDetail && (
        <ExpenseDetailModal
          expense={selectedExpenseDetail}
          user={user}
          isAdmin={isAdmin}
          can={can}
          company={company}
          onClose={() => setSelectedExpenseDetail(null)}
          onEdit={(exp) => setModal({ type: "edit", expense: exp })}
          onApprove={can("approve_expenses") ? (exp) => decideLedgerExpense(exp, "approve") : undefined}
          onReject={can("approve_expenses") ? (exp) => decideLedgerExpense(exp, "reject") : undefined}
          onReceived={canMarkReceived(selectedExpenseDetail) ? (exp) => setReceivingExpense(exp) : undefined}
          onRecordPayment={payerOptions(selectedExpenseDetail).length === 0 ? undefined : (exp) => {
            setPaymentDraft({
              payer: payerOptions(exp)[0].value,
              fundId: availableCompanyFunds[0]?.fundId || "cash",
              sourceCompanyId: "",
              method: "UPI",
              reference: "",
              paymentReceipt: "",
            });
            setModal({ type: "ledgerPay", expense: exp });
          }}
          onDelete={(exp) => setDeletingExpense(exp)}
          onVisibility={(exp) => openVisibilityModal(exp)}
          onReceiptsUpdated={() => getLedgerExpenses(companyId, user.id).then((res) => res?.success && setLedgerExpenses(res.expenses || []))}
        />
      )}

    </AppLayout>
  );
}

const labelStyle = {
  fontSize: 10.5,
  color: "var(--muted)",
  fontWeight: 700,
  letterSpacing: 0.6,
  marginBottom: 6,
};

// One summary tile on Home: label, big value, a short detail line (or rows), optionally clickable.
function HomeTile({ label, value, sub, color, onClick, title }) {
  return (
    <div className={`stat-card home-tile${onClick ? " clickable" : ""}`} onClick={onClick} title={title}>
      <div className="home-tile-label">{label}</div>
      <div className="home-tile-value" style={color ? { color } : undefined}>{value}</div>
      {sub && <div className="home-tile-sub">{sub}</div>}
    </div>
  );
}

const bigNumberStyle = {
  fontFamily: "Inter, system-ui, sans-serif",
  fontSize: 22,
  fontWeight: 700,
  color: "var(--forest)",
};

function LedgerHistory({ companyId, userId, loader, title, isAdmin, onReverse, refreshKey }) {
  const [rows, setRows] = useState([]);
  const [loading, setLoading] = useState(true);

  // quiet reload (no spinner) so live updates don't flash the list
  const fetchRows = useCallback(() => {
    loader(companyId, userId).then((result) => {
      setRows(result.transactions || result.logs || []);
      setLoading(false);
    });
  }, [companyId, userId, loader]);

  useEffect(() => {
    fetchRows();
  }, [fetchRows, refreshKey]);

  if (loading) return <div style={{ display: "flex", justifyContent: "center", padding: 35 }}><div className="spinner dark" /></div>;
  if (!rows.length) return <div className="card" style={{ color: "var(--muted)", padding: "12px 16px", fontSize: 13 }}>No {title.toLowerCase()} records yet.</div>;
  return (
    <div className="card expense-list">
      {rows.map((row) => {
        const canReverse = isAdmin && title === "Ledger" && !row.reversedBy && row.type !== "reversal";
        const total = Array.isArray(row.entries) ? row.entries.reduce((sum, entry) => sum + Number(entry.debit || 0), 0) : null;
        return (
          <div key={row._id} className="expense-row static">
            <span className="expense-row-main">
              <span className="expense-row-title">
                {row.memo || `${(row.action || "Activity").replaceAll("_", " ")} · ${row.object || ""}`}
                {row.reversedBy && <span className="row-tag bad" style={{ marginLeft: 6 }}>Reversed</span>}
              </span>
              <span className="expense-row-meta">
                {row.createdBy?.name || row.userId?.name || "Staff"} · {formatDateTime(row.createdAt || row.at)}
              </span>
              {Array.isArray(row.entries) && row.entries.length > 0 && (
                <span className="expense-row-meta" style={{ whiteSpace: "normal" }}>
                  {row.entries.map((entry) => `${Number(entry.debit) > 0 ? "Dr" : "Cr"} ${entry.accountId?.name || "Account"} ${money(Number(entry.debit) > 0 ? entry.debit : entry.credit)}`).join("  ·  ")}
                </span>
              )}
            </span>
            {total !== null && <span className="expense-row-amount">{money(total)}</span>}
            {canReverse && (
              <span className="expense-row-action">
                <button type="button" className="btn btn-outline-danger btn-sm" onClick={() => onReverse(row)}>Reverse</button>
              </span>
            )}
          </div>
        );
      })}
    </div>
  );
}
