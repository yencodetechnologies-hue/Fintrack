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
import { bankAccountLabel, companyCategories, expenseStatusLabel, fileToBase64, formatDate, money, PAYMENT_METHODS, postedByName, roleLabel, roleNames } from "../utils.js";
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
import LoansPanel from "../components/LoansPanel.jsx";
import { TableCard, pageOf, tableMeta, usePageSize } from "../components/DataTable.jsx";
import { NewLenderFields, newLenderPayload } from "../components/NewLenderFields.jsx";
import LoanDetailModal from "../components/LoanDetailModal.jsx";
import AccountsPanel from "../components/AccountsPanel.jsx";
import { useFundTopUp } from "../components/FundTopUp.jsx";

// Home Today: expenses whose own expense date is today (not when they were posted), worked out at render time
const isTodayExpense = (expense) => new Date(expense.date || expense.createdAt).toDateString() === new Date().toDateString();
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

const isSettledExpense = (e) => Boolean(e) && (String(e.lifecycle || "").startsWith("paid") || ["reimbursed", "awaiting_confirmation"].includes(e.lifecycle) || e.status === "paid");

// value of the "+ Add company…" choice in the lender pickers (then a name + GSTIN are asked for)
const ADD_COMPANY = "__add_company__";

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
  const [myRoleName, setMyRoleName] = useState(null); // custom role name, if I have one
  // my role as shown on "Post expense as": Admin (company Admin), my custom role (e.g. Partner), or the manager name
  const myRoleLabel = permissionRole === "primary" ? "Admin" : myRoleName || roleNames(company).manager;
  const [canReverse, setCanReverse] = useState(false); // super admin, or a role with "Reverse ledger transactions"
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
  // Loans opened from the menu always starts at the list of companies / people (not a statement left open)
  const [loansFocus, setLoansFocus] = useState({ id: "", n: 0 });
  const changeTab = useCallback((tab) => {
    setActiveTab(tab);
    setSearchParams({ tab }, { replace: true });
    if (tab === "interco") setLoansFocus((f) => ({ id: "", n: f.n + 1 }));
  }, [setSearchParams]);
  const urlTab = searchParams.get("tab");
  useEffect(() => {
    if (urlTab) setActiveTab(tabFromUrl(urlTab));
  }, [urlTab]);
  const [companies, setCompanies] = useState([]);
  const [ledgerExpenses, setLedgerExpenses] = useState([]);
  const [ledgerBalances, setLedgerBalances] = useState(null);
  const [loans, setLoans] = useState([]);
  const [pendingBorrows, setPendingBorrows] = useState([]);
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
  // Home "My outstanding" tile → Payments, scrolled to "Your outstanding"
  const [focusOwnOutstanding, setFocusOwnOutstanding] = useState(false);
  useEffect(() => {
    if (activeTab !== "payments") setFocusOwnOutstanding(false);
  }, [activeTab]);
  // Home "Total expenses" tile period: all | week | month | custom (by each expense's date)
  const [totalPeriod, setTotalPeriod] = useState("month"); // default: this month
  const [totalFrom, setTotalFrom] = useState("");
  const [totalTo, setTotalTo] = useState("");
  const [reversingTx, setReversingTx] = useState(null);
  const [selectedExpenseDetail, setSelectedExpenseDetail] = useState(null);

  const [reportFrom, setReportFrom] = useState("");
  const [reportTo, setReportTo] = useState("");
  const [reportCategory, setReportCategory] = useState("All");
  const [reportRole, setReportRole] = useState("all"); // all | manager | staff | role:<customRoleId>
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
  // deleting a paid expense (undoes its payment): the company Admin, or a custom role given that power
  const canDeletePaid = permissionRole === "primary" || (permissionRole === "custom" && myPermissions?.delete_paid_expenses === true);
  // Admin powers a custom role can be given: edit company-paid expenses, post an expense as borrowed
  const canEditCompanyPosts = permissionRole === "primary" || (permissionRole === "custom" && myPermissions?.edit_paid_expenses === true);
  const canPostBorrowed = permissionRole === "primary" || (permissionRole === "custom" && myPermissions?.post_borrowed === true);
  // adding a new company / person to borrow from
  const canAddLender = isAdmin && can("intercompany") && can("add_lenders");
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
  // "not enough balance → add money → carry on" for payments made from this company's funds
  const fundTopUp = useFundTopUp({ companyId, user, funds: availableCompanyFunds, onFunded: () => load() });

  // Other companies this user manages: they can pay this company's expenses (recorded as a loan).
  // Other companies I manage that this company may use: only the Admin's own companies (the server's borrow list),
  // so "pay from another company" never offers an unrelated company I happen to manage
  const managedOtherCompanies = useMemo(() => {
    const allowed = new Set(borrowSources.map((c) => String(c._id)));
    return companies.filter((c) => String(c._id) !== companyId && c.userRole === "admin" && !c.external && allowed.has(String(c._id)));
  }, [companies, companyId, borrowSources]);
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
    setMyRoleName(detailsRes.myRoleName || null);
    setCanReverse(Boolean(detailsRes.canReverse));
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
      apply(getLedgerBorrowSources(companyId, user.id), setBorrowSources, (result) => result.companies || []);
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
      apply(getLedgerLoans(companyId, user.id), (result) => { setLoans(result.loans || []); setPendingBorrows(result.pending || []); }, (result) => result);
      apply(getLedgerBorrowSources(companyId, user.id), setBorrowSources, (result) => result.companies || []);
    }

    return () => { active = false; };
    // tabTick: reload this tab's lists when a live update touches them
  }, [activeTab, company, companyId, user.id, tabTick]);

  const loadReport = useCallback(async (from = reportFrom, to = reportTo, cat = reportCategory, role = reportRole) => {
    setLoadingReport(true);
    const res = await getLedgerReport(companyId, user.id, from, to, cat, role);
    if (res.success) setReport(res.report);
    setLoadingReport(false);
  }, [companyId, user.id, reportFrom, reportTo, reportCategory, reportRole]);

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

  // Expenses page: the viewer's rows per page over the filtered list, still grouped by day. A day split across two
  // pages keeps its full count and total in its header.
  const [EXPENSES_PER_PAGE, setExpensesPerPage] = usePageSize();
  const [expensePage, setExpensePage] = useState(1);
  const filteredExpenseCount = groupedLedgerExpenses.reduce((n, g) => n + g.items.length, 0);
  const expensePages = Math.max(1, Math.ceil(filteredExpenseCount / EXPENSES_PER_PAGE));
  const currentExpensePage = Math.min(expensePage, expensePages);
  // a new filter or search starts again at page 1
  useEffect(() => {
    setExpensePage(1);
  }, [statusFilter, search, expenseDateFrom, expenseDateTo, postedByFilter]);
  const pagedLedgerExpenses = useMemo(() => {
    const start = (currentExpensePage - 1) * EXPENSES_PER_PAGE;
    const end = start + EXPENSES_PER_PAGE;
    const out = [];
    let index = 0;
    for (const group of groupedLedgerExpenses) {
      const from = Math.max(start - index, 0);
      const to = Math.min(end - index, group.items.length);
      if (to > from) out.push({ ...group, dayCount: group.items.length, items: group.items.slice(from, to), continued: from > 0 });
      index += group.items.length;
      if (index >= end) break;
    }
    return out;
  }, [groupedLedgerExpenses, currentExpensePage]);
  function goToExpensePage(page) {
    setExpensePage(page);
    document.querySelector(".layout-main")?.scrollTo?.({ top: 0, behavior: "smooth" });
    window.scrollTo({ top: 0, behavior: "smooth" });
  }

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
    if (paymentDraft.payer === "borrow" && paymentDraft.sourceCompanyId === ADD_COMPANY) {
      const check = newLenderPayload(paymentDraft.newKind, paymentDraft.newName, paymentDraft.newGstin, paymentDraft.newPhone);
      if (check.error) { showToast(check.error, "error"); return; }
    }

    // only this company's own money is balance-checked; another company paying is a loan
    if (paymentDraft.payer === "company" && payingCompanyId === companyId) {
      const selectedFund = payingFunds.find((f) => String(f.fundId) === String(paymentDraft.fundId)) || payingFunds[0];
      if (selectedFund && Number(selectedFund.balance || 0) < Number(expense.amount || 0)) {
        return fundTopUp.ask(selectedFund, Number(expense.amount || 0), () => recordLedgerPayment(expense));
      }
    }
    recordLedgerPayment(expense);
  }

  async function recordLedgerPayment(expense) {
    const { payingCompanyId: _payingCompanyId, newName, newGstin, newKind, newPhone, ...rawDraft } = paymentDraft;
    // "+ Add company…": send the new company instead of an id
    const draft = rawDraft.payer === "borrow" && rawDraft.sourceCompanyId === ADD_COMPANY
      ? { ...rawDraft, sourceCompanyId: undefined, newCompany: newLenderPayload(newKind, newName, newGstin, newPhone).newCompany }
      : rawDraft;
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

  function submitIntercoAction(event) {
    event.preventDefault();
    // repaying spends this company's own fund
    if (intercoModal?.type === "repay") {
      const fund = availableCompanyFunds.find((f) => String(f.fundId) === String(intercoDraft.fundId));
      const need = Number(intercoDraft.amount || 0);
      if (fund && need > 0 && Number(fund.balance || 0) < need) return fundTopUp.ask(fund, need, saveIntercoAction);
    }
    saveIntercoAction();
  }

  async function saveIntercoAction() {
    const kind = intercoModal?.type;
    if (kind === "borrow" && intercoDraft.companyId === ADD_COMPANY && (!intercoDraft.newName?.trim() || (intercoDraft.newKind !== "person" && !intercoDraft.newGstin?.trim()))) {
      showToast(intercoDraft.newKind === "person" ? "Enter the person's name" : "Enter the new company's name and GSTIN", "error");
      return;
    }
    setIntercoSaving(true);
    const result = kind === "receive"
      ? await receiveCompanyLoan(intercoModal.loan._id, { userId: user.id, amount: Number(intercoDraft.amount), borrowerFundId: intercoDraft.fundId, method: intercoDraft.method, reference: intercoDraft.reference })
      : kind === "repay"
      ? await repayCompanyLoan(intercoModal.loan._id, { userId: user.id, amount: Number(intercoDraft.amount), fundId: intercoDraft.fundId, method: intercoDraft.method, reference: intercoDraft.reference })
      : await createCompanyLoan({ userId: user.id, borrowerCompanyId: companyId, ...(intercoDraft.companyId === ADD_COMPANY ? { newCompany: intercoDraft.newKind === "person" ? { kind: "person", name: (intercoDraft.newName || "").trim(), phone: (intercoDraft.newPhone || "").trim() } : { name: (intercoDraft.newName || "").trim(), gstin: (intercoDraft.newGstin || "").trim().toUpperCase() } } : { lenderCompanyId: intercoDraft.companyId }), amount: Number(intercoDraft.amount), fundId: intercoDraft.fundId, method: intercoDraft.method, reference: intercoDraft.reference, note: (intercoDraft.note || "").trim() });
    setIntercoSaving(false);
    if (result.success) {
      showToast(kind === "receive" ? (result.borrowerShort > 0 ? `Marked as received · ${intercoModal.loan.borrowerCompanyId?.name || "The borrower"}'s account is now ${money(result.borrowerShort)} below zero` : "Marked as received") :kind === "repay" ? "Loan repayment recorded" : "Loan recorded");
      setIntercoModal(null);
      // a new loan: open the statement of the company / person it was borrowed from
      if (kind === "borrow") setLoansFocus((f) => ({ id: String(result.loan?.lenderCompanyId?._id || result.loan?.lenderCompanyId || ""), n: f.n + 1 }));
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
      showToast(res.undone ? "Expense deleted · its payment was undone" : "Expense deleted");
      if (res.undone) load(); // Cash/Bank and loans changed
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

  function submitMoneyAction(event) {
    event.preventDefault();
    // reimbursing pays out of a company fund (lending puts money in)
    if (moneyModal !== "lend") {
      const fund = availableCompanyFunds.find((f) => String(f.fundId) === String(moneyDraft.fundId));
      const need = Number(moneyDraft.amount || 0);
      if (fund && need > 0 && Number(fund.balance || 0) < need) return fundTopUp.ask(fund, need, saveMoneyAction);
    }
    saveMoneyAction();
  }

  async function saveMoneyAction() {
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
    <AppLayout companyId={companyId} isAdmin={isAdmin} can={can} permissionRole={permissionRole} roleName={myRoleName} activeTab={activeTab} onTabChange={changeTab} title={company.name}>
        <div className="main-panel">
          {!pageAllowed && (
            <div className="card" style={{ textAlign: "center", color: "var(--muted)", padding: 28 }}>This page is turned off for you in this company.</div>
          )}
          {pageAllowed && <>
          {activeTab === "home" && (
            <>
              <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", flexWrap: "wrap", gap: 10, marginBottom: 20 }}>
                <h1 style={{ fontSize: 22, margin: 0 }}>Home</h1>
                {can("post_expenses") && <button className="btn btn-primary" onClick={() => setModal({ type: "add" })}>+ Post Expense</button>}
              </div>
              {(() => {
                const periodExpenses = expensesInPeriod(ledgerExpenses, totalPeriod, totalFrom, totalTo);
                const totalSpent = periodExpenses.reduce((sum, expense) => sum + Number(expense.amount || 0), 0);
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
                      sub={`${periodExpenses.length} expense${periodExpenses.length === 1 ? "" : "s"}`}
                      onClick={() => changeTab("expenses")}
                      title="View all expenses"
                      extra={
                        // a small pill; the real select sits invisibly on top (keeps 16px text so phones don't zoom)
                        <span className={`tile-period ${totalPeriod !== "month" ? "on" : ""}`} onClick={(e) => e.stopPropagation()}>
                          {{ all: "All time", week: "This week", month: "This month", custom: "Custom" }[totalPeriod]}
                          <select value={totalPeriod} onChange={(e) => setTotalPeriod(e.target.value)} aria-label="Period">
                            <option value="all">All time</option>
                            <option value="week">This week</option>
                            <option value="month">This month</option>
                            <option value="custom">Custom</option>
                          </select>
                        </span>
                      }
                      below={totalPeriod === "custom" && (
                        // From / To on their own rows, so a full dd/mm/yyyy date fits even in a narrow tile
                        <div className="tile-period-dates" onClick={(e) => e.stopPropagation()}>
                          <label><span>From</span><input type="date" value={totalFrom} max={totalTo || undefined} onChange={(e) => setTotalFrom(e.target.value)} /></label>
                          <label><span>To</span><input type="date" value={totalTo} min={totalFrom || undefined} onChange={(e) => setTotalTo(e.target.value)} /></label>
                        </div>
                      )}
                    />
                    <HomeTile
                      label={isAdmin ? "My outstanding" : "Company owes you"}
                      onClick={isAdmin && can("reimburse") ? () => { setFocusOwnOutstanding(true); changeTab("payments"); } : undefined}
                      title={isAdmin && can("reimburse") ? "Pay your outstanding from company funds" : undefined}
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
                          label={`${company.name}${/s$/i.test(company.name.trim()) ? "'" : "'s"} balance`}
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
              {/* Home lists only expenses dated today; the rest live on the Expenses page */}
              {(() => {
                const list = ledgerExpenses.filter(isTodayExpense);
                // today's total leaves out rejected expenses
                const todayTotal = list.filter((e) => e.lifecycle !== "rejected").reduce((sum, e) => sum + Number(e.amount || 0), 0);
                return (
                  <TableCard title={`Today · ${formatDate(new Date())}`} meta={`${list.length} ${list.length === 1 ? "expense" : "expenses"} · ${money(todayTotal)}`} items={list}>
                    {(rows) => (
                      <>
                    {list.length === 0 ? (
                      <div className="dt-empty">No expenses today.</div>
                    ) : (
                      <table className="dt">
                        <thead>
                          <tr><th>Description</th><th>Category</th><th>Posted by</th><th>Status</th><th className="num">Amount</th></tr>
                        </thead>
                        <tbody>
                          {rows.map((expense) => {
                            const tone = expense.lifecycle === "rejected" ? "bad" : expense.lifecycle === "approved" || expense.lifecycle?.startsWith("paid") ? "good" : expense.lifecycle === "reimbursed" ? "done" : "wait";
                            return (
                              <tr key={expense._id} className="dt-click" tabIndex={0} onClick={() => setSelectedExpenseDetail(expense)} onKeyDown={(e) => { if (e.key === "Enter") setSelectedExpenseDetail(expense); }}>
                                <td className="dt-wrap-text"><span className="dt-strong">{expense.description}</span></td>
                                <td>{expense.category || "General"}</td>
                                <td>{postedByName(expense, company)}</td>
                                <td><span className={`dt-status ${tone}`}>{expenseStatusLabel(expense, company)}</span></td>
                                <td className="num">{money(expense.amount)}</td>
                              </tr>
                            );
                          })}
                        </tbody>
                      </table>
                    )}
                  
                      </>
                    )}
                  </TableCard>
                );
              })()}
              {/* loans recorded today (borrowed or lent); only shown when there are some */}
              {(() => {
                const todaysLoans = loans.filter((loan) => new Date(loan.createdAt).toDateString() === new Date().toDateString());
                if (!todaysLoans.length) return null;
                const borrowedToday = todaysLoans.filter((loan) => String(loan.borrowerCompanyId?._id || loan.borrowerCompanyId) === companyId).reduce((sum, loan) => sum + Number(loan.amount || 0), 0);
                return (
                  <TableCard title="Loans today" meta={`${todaysLoans.length} ${todaysLoans.length === 1 ? "loan" : "loans"}${borrowedToday > 0 ? ` · ${money(borrowedToday)} borrowed` : ""}`} items={todaysLoans}>
                    {(rows) => (
                      <>
                    <table className="dt">
                      <thead>
                        <tr><th>Type</th><th>Company / person</th><th>Details</th><th>Method</th><th>Status</th><th className="num">Amount</th></tr>
                      </thead>
                      <tbody>
                        {rows.map((loan) => {
                          const weBorrowed = String(loan.borrowerCompanyId?._id || loan.borrowerCompanyId) === companyId;
                          const other = weBorrowed ? loan.lenderCompanyId : loan.borrowerCompanyId;
                          const sourceLabel = loan.source === "expense" ? "Paid an expense" : loan.source === "group" ? "Paid a group's expenses" : "Direct loan";
                          const due = Number(loan.balance) > 0;
                          return (
                            <tr key={loan._id} className="dt-click" tabIndex={0} onClick={() => setViewingLoan(loan)} onKeyDown={(e) => { if (e.key === "Enter") setViewingLoan(loan); }}>
                              <td><span className={`row-tag ${weBorrowed ? "bad" : "good"}`}>{weBorrowed ? "Borrowed" : "Lent"}</span></td>
                              <td className="dt-strong">{other?.name || "Another company"}</td>
                              <td>{loan.note || sourceLabel}{loan.reference && <span className="dt-sub">Ref {loan.reference}</span>}</td>
                              <td>{loan.method || "—"}</td>
                              <td><span className={`dt-status ${due ? "wait" : "good"}`}>{due ? `${money(loan.balance)} due` : "Repaid"}</span></td>
                              <td className="num">{money(loan.amount)}</td>
                            </tr>
                          );
                        })}
                      </tbody>
                    </table>
                  
                      </>
                    )}
                  </TableCard>
                );
              })()}
              {/* only shown when something is waiting for a second manager */}
              {isAdmin && can("verify") && pendingVerification.length > 0 && (
                <TableCard title="Pending verification" meta={`${pendingVerification.length} waiting`} items={pendingVerification}>
                  {(rows) => (
                    <>
                  <table className="dt">
                    <thead>
                      <tr><th>Date</th><th>Details</th><th>Recorded by</th><th className="num">Amount</th><th className="num">Action</th></tr>
                    </thead>
                    <tbody>
                      {rows.map((transaction) => (
                        <tr key={transaction._id}>
                          <td className="nowrap">{formatDate(transaction.createdAt)}</td>
                          <td className="dt-wrap-text dt-strong">{transaction.memo || transaction.type}</td>
                          <td>{transaction.createdBy?.name || "Manager"}</td>
                          <td className="num">{money(transaction.entries?.reduce((sum, entry) => sum + Number(entry.debit || 0), 0))}</td>
                          <td><span className="dt-actions"><button className="btn btn-primary btn-sm" onClick={() => verifyTransaction(transaction)}>Verify</button></span></td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                
                    </>
                  )}
                </TableCard>
              )}
            </>
          )}

          {activeTab === "expenses" && (
            <>
              <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", flexWrap: "wrap", gap: 10, marginBottom: 6 }}>
                <h1 style={{ fontSize: 22, margin: 0 }}>Expenses</h1>
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
                  padding: "12px 14px",
                  // row 1: search (full width) · row 2: filters on the left, the total on the right
                  display: "flex",
                  flexWrap: "wrap",
                  alignItems: "center",
                  gap: 10,
                  background: "#fff",
                  boxShadow: "0 1px 3px rgba(0,0,0,0.04)",
                }}
              >
                <div style={{ position: "relative", flex: "1 1 100%", minWidth: 0 }}>
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

                <div style={{ display: "flex", alignItems: "center", gap: 10, flexWrap: "wrap", flex: "1 1 100%", paddingTop: 10, borderTop: "1px solid var(--slate-border-2)" }}>
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
                      <option value="managers">All {roleNames(company).managers.toLowerCase()}</option>
                      <option value="staff">All {roleNames(company).staffs.toLowerCase()}</option>
                      {members.some((m) => m.role === "admin") && (
                        <optgroup label={roleNames(company).managers}>
                          {members.filter((m) => m.role === "admin").map((m) => <option key={m.userId} value={String(m.userId)}>{m.name}</option>)}
                        </optgroup>
                      )}
                      {members.some((m) => m.role !== "admin") && (
                        <optgroup label={roleNames(company).staffs}>
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
                      style={{ height: 38, padding: "0 12px", fontSize: 13 }}
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

                  {/* total of everything the filters show (all dates in the period, search, status, posted by) */}
                  {groupedLedgerExpenses.length > 0 && (() => {
                    const count = groupedLedgerExpenses.reduce((n, g) => n + g.items.length, 0);
                    return (
                      <div className="expense-filter-total">
                        <small>{count} {count === 1 ? "expense" : "expenses"} · Total</small>
                        <strong>{money(groupedLedgerExpenses.reduce((sum, g) => sum + g.total, 0))}</strong>
                      </div>
                    );
                  })()}
                </div>
              </div>
              {groupedLedgerExpenses.length === 0 ? (
                <div className="card" style={{ textAlign: "center", color: "var(--muted)", padding: 24 }}>
                  No expenses match your search or date filters.
                  {(search || expenseDateFrom || expenseDateTo || statusFilter !== "All" || postedByFilter !== "all") && (
                    <div style={{ marginTop: 10 }}>
                      <button
                        type="button"
                        className="btn btn-outline"
                        style={{ fontSize: 13, padding: "6px 14px" }}
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
                <TableCard
                  title="Expenses"
                  meta={tableMeta(filteredExpenseCount, currentExpensePage, expensePages, "expenses")}
                  page={currentExpensePage}
                  pages={expensePages}
                  onPage={goToExpensePage}
                  count={filteredExpenseCount}
                  pageSize={EXPENSES_PER_PAGE}
                  onPageSize={(n) => { setExpensesPerPage(n); setExpensePage(1); }}
                >
                  <table className="dt">
                    <thead>
                      <tr>
                        <th>Date</th>
                        <th>Description</th>
                        <th>Category</th>
                        <th>Posted by</th>
                        <th>Status</th>
                        <th className="num">Amount</th>
                        <th className="num">Action</th>
                      </tr>
                    </thead>
                    <tbody>
                      {pagedLedgerExpenses.flatMap((group) => [
                        // one header row per day, with that day's count and total
                        <tr key={`day-${group.key}`} className="dt-group">
                          <td colSpan={7} className="dt-day">
                            {group.label}
                            <span className="dt-group-total">{group.continued ? "continued · " : ""}{group.dayCount} {group.dayCount === 1 ? "expense" : "expenses"} · {money(group.total)}</span>
                          </td>
                        </tr>,
                        ...group.items.map((expense) => {
                          const tone = expense.lifecycle === "rejected" ? "bad" : expense.lifecycle === "approved" || expense.lifecycle?.startsWith("paid") ? "good" : expense.lifecycle === "reimbursed" ? "done" : "wait";
                          return (
                            <tr
                              key={expense._id}
                              className="dt-click"
                              tabIndex={0}
                              onClick={() => setSelectedExpenseDetail(expense)}
                              onKeyDown={(e) => { if (e.key === "Enter") setSelectedExpenseDetail(expense); }}
                            >
                              <td className="nowrap">
                                {/* the day row above carries the date; each row shows just its time */}
                                <span className="dt-time">{new Date(expense.createdAt).toLocaleTimeString("en-IN", { hour: "2-digit", minute: "2-digit" })}</span>
                              </td>
                              <td className="dt-wrap-text">
                                <span className="dt-strong">{expense.description}</span>
                                {(expense.hasAttachment || expense.hasPaymentReceipt) && <span className="dt-sub">📎 Receipt</span>}
                              </td>
                              <td>{expense.category || "General"}</td>
                              <td>{postedByName(expense, company)}</td>
                              <td><span className={`dt-status ${tone}`}>{expenseStatusLabel(expense, company)}</span></td>
                              <td className="num">{money(expense.amount)}</td>
                              <td onClick={(e) => e.stopPropagation()}>
                                <span className="dt-actions">
                                  {isAdmin && expense.lifecycle === "submitted" ? (
                                    can("approve_expenses") ? <button type="button" className="btn btn-primary btn-sm" onClick={() => decideLedgerExpense(expense, "approve")}>Approve</button> : null
                                  ) : canMarkReceived(expense) ? (
                                    <button type="button" className="row-link-btn" title="You got this money back: close the expense" onClick={() => setReceivingExpense(expense)}>✓ Mark received</button>
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
                              </td>
                            </tr>
                          );
                        }),
                      ])}
                    </tbody>
                  </table>
                </TableCard>
              )}
            </>
          )}

          {activeTab === "interco" && (
            <>
              <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 12, flexWrap: "wrap" }}><h1 style={{ fontSize: 22, margin: 0 }}>Loans</h1>{isAdmin && can("intercompany") && <div className="m-action-row" style={{ display: "flex", gap: 8, flexWrap: "wrap" }}><button className="btn btn-outline" onClick={() => { setRouteDraft({ sourceCompanyId: "", adminUserId: "", amount: "", method: "UPI", reference: "" }); setIntercoModal({ type: "routed" }); }}>Routed payment to manager</button><button className="btn btn-dark" onClick={() => { setIntercoDraft({ companyId: "", amount: "", fundId: availableCompanyFunds[0]?.fundId || "cash", method: "UPI", reference: "" }); setIntercoModal({ type: "borrow" }); }}>Record a loan</button></div>}</div>
              {isAdmin && payerRequests.length > 0 && (
                <div style={{ marginTop: 18 }}>
                  <TableCard title="Payment confirmations" meta={`${payerRequests.length} waiting`} items={payerRequests}>
                    {(rows) => (
                      <>
                    <table className="dt">
                      <thead>
                        <tr><th>Date</th><th>Expense</th><th>Asked by</th><th className="num">Amount</th><th>Pay from</th><th className="num">Action</th></tr>
                      </thead>
                      <tbody>
                        {rows.map((expense) => (
                          <tr key={expense._id}>
                            <td className="nowrap">{formatDate(expense.createdAt)}</td>
                            <td className="dt-wrap-text dt-strong">{expense.description}</td>
                            <td>{expense.companyId?.name || "Another company"}</td>
                            <td className="num">{money(expense.amount)}</td>
                            <td>
                              <select className="field-select" style={{ height: 32, padding: "0 8px", fontSize: 13 }} value={payerFundSelections[expense._id] || availableCompanyFunds[0]?.fundId || "cash"} onChange={(event) => setPayerFundSelections((current) => ({ ...current, [expense._id]: event.target.value }))}>
                                {availableCompanyFunds.map((fund) => <option key={fund.fundId} value={fund.fundId}>{fund.name}</option>)}
                              </select>
                            </td>
                            <td>
                              {can("intercompany") && (
                                <span className="dt-actions">
                                  <button className="btn btn-outline btn-sm" onClick={() => respondToPayerRequest(expense, false)}>Reject</button>
                                  <button className="btn btn-primary btn-sm" onClick={() => respondToPayerRequest(expense, true)}>Accept</button>
                                </span>
                              )}
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  
                      </>
                    )}
                  </TableCard>
                </div>
              )}
              <LoansPanel companyId={companyId} user={user} loans={loans} pending={pendingBorrows} focus={loansFocus} refreshKey={tick("loans")} onOpenLoan={(loanId) => { const loan = loans.find((l) => String(l._id) === String(loanId)); if (loan) setViewingLoan(loan); }} />
            </>
          )}

          {activeTab === "reports" && (
            <>
              {/* header: title, then the filters and Export on one line (the report reloads as soon as a filter changes) */}
              <div className="report-head">
                <h1>Reports</h1>
                <div className="report-filters">
                  <PeriodFilter label="" from={reportFrom} to={reportTo} years={expenseYears} onChange={(from, to) => { setReportFrom(from); setReportTo(to); }} />
                  <select className="field-select" value={reportRole} onChange={(e) => setReportRole(e.target.value)} aria-label="Role">
                    <option value="all">All roles</option>
                    <option value="manager">{roleNames(company).managers}</option>
                    <option value="staff">{roleNames(company).staffs}</option>
                    {(company.customRoles || []).map((r) => (
                      <option key={r._id} value={`role:${r._id}`}>{r.name}</option>
                    ))}
                  </select>
                  <select className="field-select" value={reportCategory} onChange={(e) => setReportCategory(e.target.value)} aria-label="Category">
                    <option value="All">All categories</option>
                    {companyCategories(company).map((c) => (
                      <option key={c} value={c}>{c}</option>
                    ))}
                  </select>
                  {(reportFrom || reportTo || reportCategory !== "All" || reportRole !== "all") && (
                    <button type="button" className="report-link" onClick={() => { setReportFrom(""); setReportTo(""); setReportCategory("All"); setReportRole("all"); }}>Clear</button>
                  )}
                  <a className="btn btn-outline btn-sm" href={getLedgerExportUrl(companyId, user.id, reportFrom, reportTo, reportCategory, reportRole)} target="_blank" rel="noreferrer">
                    Export CSV
                  </a>
                </div>
              </div>

              {/* summary: four figures in one strip */}
              <div className={`card report-strip ${loadingReport ? "loading" : ""}`}>
                {report ? (() => {
                  const net = Number(report.intercompanyNet || 0);
                  return (
                    <>
                      <div><small>Expenses</small><strong>{money(report.expenses)}</strong></div>
                      <div><small>Paid by managers</small><strong>{money(report.paidByAdmins)}</strong></div>
                      <div><small>Owed to managers</small><strong className={Number(report.owedToAdmins) > 0 ? "out" : ""}>{money(report.owedToAdmins)}</strong></div>
                      <div>
                        <small>Inter-company</small>
                        <strong className={net < 0 ? "out" : net > 0 ? "in" : ""}>{net < 0 ? `−${money(-net)}` : net > 0 ? `+${money(net)}` : money(0)}</strong>
                        <em>{net < 0 ? "we owe" : net > 0 ? "owed to us" : "settled"}</em>
                      </div>
                    </>
                  );
                })() : loadingReport ? <div className="spinner dark" style={{ margin: "6px auto" }} /> : <span style={{ color: "var(--muted)" }}>No report data.</span>}
              </div>

              <OutstandingReport companyId={companyId} company={company} userId={user.id} role={reportRole} refreshKey={reportTick} />
            </>
          )}

          {activeTab === "analysis" && isAdmin && <ExpenseAnalysis companyId={companyId} userId={user.id} refreshKey={tick("expenses")} />}

          {activeTab === "vouchers" && isAdmin && (
            <VouchersPanel companyId={companyId} company={company} user={user} members={members} funds={availableCompanyFunds} onChanged={load} refreshKey={tick("vouchers", "balances")} />
          )}

          {activeTab === "payments" && isAdmin && (
            <PaymentsPanel companyId={companyId} company={company} user={user} members={members} funds={availableCompanyFunds} onChanged={load} refreshKey={tick("balances", "expenses")} focusOwn={focusOwnOutstanding} />
          )}

          {activeTab === "transactions" && isAdmin && (
            <><LedgerHistory companyId={companyId} userId={user.id} loader={getLedgerTransactions} title="Ledger" isAdmin={isAdmin} onReverse={canReverse ? (tx) => setReversingTx(tx) : undefined} refreshKey={tick("ledger")} /></>
          )}
          {activeTab === "audit" && isAdmin && <><LedgerHistory companyId={companyId} userId={user.id} loader={getLedgerAuditLog} title="Audit log" refreshKey={tick("ledger")} /></>}

          {activeTab === "ledger" && (
            <>
              <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", flexWrap: "wrap", gap: 10, marginBottom: 6 }}>
                <h1 style={{ fontSize: 22, margin: 0 }}>
                  {isAdmin && viewMode === "self" ? `Self Expenses` : `${company.name} Ledger`}
                </h1>
              </div>
              <p style={{ color: "var(--muted)", fontSize: 14, margin: "0 0 24px" }}>
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
                  <h2 style={{ margin: 0, fontSize: 20 }}>Expense Ledger</h2>
                  <span style={{ color: "var(--muted)", fontSize: 13 }}>{filtered.length} entries</span>
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
                    <div style={{ color: "var(--muted)", fontSize: 12, fontWeight: 700, marginBottom: 8, letterSpacing: 0.6, textTransform: "uppercase" }}>
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

          {activeTab === "accounts" && isAdmin && (
            <AccountsPanel companyId={companyId} user={user} refreshKey={tick("balances", "expenses")} />
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
            <SettingsPanel
              company={company}
              members={members}
              user={user}
              isAdmin={isAdmin}
              can={can}
              powers={{
                admin: permissionRole === "primary",
                manageRoles: permissionRole === "primary" || myPermissions?.manage_roles === true,
                deleteCompany: permissionRole === "primary" || myPermissions?.delete_company === true,
              }}
              onChanged={load}
            />
          )}

          {activeTab === "permissions" && <PermissionsPanel companyId={companyId} company={company} members={members} user={user} refreshKey={tick("permissions") + tick("members")} onChanged={load} />}
          </>}
        </div>

      {modal?.type === "add" && (
        <AddExpenseModal
          company={company}
          user={user}
          isAdmin={isAdmin}
          canPostAsCompany={can("post_as_company")}
          myRoleLabel={myRoleLabel}
          // borrowing straight from Add Expense: the company Admin, or a custom role with that power
          canBorrow={canPostBorrowed && can("intercompany")}
          canAddLender={canAddLender}
          otherCompanies={managedOtherCompanies}
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
                <button type="button" className="btn btn-outline" style={{ padding: "2px 10px", fontSize: 12 }} onClick={() => setMoneyDraft((d) => ({ ...d, amount: String(Math.max(0, roundMoney(payeeBills.owed - (d.offsetAdvance ? payeeHeld : 0)))) }))}>
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
                      <span>Insufficient balance: {money(selectedFund?.balance || 0)} available ({money(expenseAmount)} required). You can add money when you pay.</span>
                    </div>
                  )}
                </>
              );
            })()}
            {paymentDraft.payer === "borrow" && (
              <>
                <label className="field-label" style={{ display: "block", marginTop: 12 }}>Borrowed from</label>
                <select
                  className="field-select"
                  value={paymentDraft.sourceCompanyId}
                  onChange={(event) => setPaymentDraft({ ...paymentDraft, sourceCompanyId: event.target.value })}
                >
                  <option value="">Choose company or person</option>
                  {borrowSources.map((source) => (
                    <option key={source._id} value={source._id}>{source.name}{source.lenderKind === "person" ? " (person)" : ""}</option>
                  ))}
                  {canAddLender && <option value={ADD_COMPANY}>+ Add company or person…</option>}
                </select>
                {paymentDraft.sourceCompanyId === ADD_COMPANY && (
                  <NewLenderFields
                    kind={paymentDraft.newKind || "company"}
                    onKind={(k) => setPaymentDraft((d) => ({ ...d, newKind: k }))}
                    name={paymentDraft.newName}
                    onName={(v) => setPaymentDraft((d) => ({ ...d, newName: v }))}
                    gstin={paymentDraft.newGstin}
                    onGstin={(v) => setPaymentDraft((d) => ({ ...d, newGstin: v }))}
                    phone={paymentDraft.newPhone}
                    onPhone={(v) => setPaymentDraft((d) => ({ ...d, newPhone: v }))}
                  />
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
                  <button className="btn btn-primary" style={{ flex: 1 }}>
                    {isInsufficient ? "Add money & pay" : "Record payment"}
                  </button>
                );
              })()}
            </div>
          </form>
        </Modal>
      )}

      {intercoModal && (
        <Modal onClose={() => setIntercoModal(null)} maxWidth={460}>
          <h2 style={{ marginTop: 0 }}>{intercoModal.type === "receive" ? "Mark repayment received" : intercoModal.type === "repay" ? "Repay company loan" : intercoModal.type === "routed" ? "Routed payment to manager" : "Record a loan"}</h2>
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
            {intercoModal.type === "borrow" && <><div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 8 }}><label className="field-label">Borrowed from</label>{intercoDraft.companyId === ADD_COMPANY ? <button type="button" className="report-link" onClick={() => setIntercoDraft({ ...intercoDraft, companyId: "" })}>Pick from the list</button> : canAddLender && <span style={{ display: "flex", gap: 12 }}><button type="button" className="report-link" onClick={() => setIntercoDraft({ ...intercoDraft, companyId: ADD_COMPANY, newKind: "company" })}>+ New company</button><button type="button" className="report-link" onClick={() => setIntercoDraft({ ...intercoDraft, companyId: ADD_COMPANY, newKind: "person" })}>+ New person</button></span>}</div><select className="field-select" value={intercoDraft.companyId} onChange={(event) => setIntercoDraft({ ...intercoDraft, companyId: event.target.value })} required><option value="">Choose company or person</option>{borrowSources.map((source) => <option key={source._id} value={source._id}>{source.name}{source.lenderKind === "person" ? " (person)" : ""}</option>)}{canAddLender && <option value={ADD_COMPANY}>+ Add company or person…</option>}</select>{intercoDraft.companyId === ADD_COMPANY && <><div style={{ display: "flex", gap: 8, marginTop: 8 }}>{["company", "person"].map((k) => <button key={k} type="button" className={`btn btn-sm ${(intercoDraft.newKind || "company") === k ? "btn-dark" : "btn-outline"}`} style={{ flex: 1 }} onClick={() => setIntercoDraft({ ...intercoDraft, newKind: k })}>{k === "company" ? "Company" : "Person"}</button>)}</div><div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 8, marginTop: 8 }}><input className="field-input" placeholder={intercoDraft.newKind === "person" ? "Person's name *" : "Company name *"} value={intercoDraft.newName || ""} onChange={(e) => setIntercoDraft({ ...intercoDraft, newName: e.target.value })} />{intercoDraft.newKind === "person" ? <input className="field-input" placeholder="Phone (optional)" inputMode="tel" value={intercoDraft.newPhone || ""} onChange={(e) => setIntercoDraft({ ...intercoDraft, newPhone: e.target.value })} /> : <input className="field-input" placeholder="GSTIN *" value={intercoDraft.newGstin || ""} onChange={(e) => setIntercoDraft({ ...intercoDraft, newGstin: e.target.value.toUpperCase() })} />}</div></>}</>}
            {intercoModal.type === "borrow" && <p style={{ color: "var(--muted)", fontSize: 13, margin: "10px 0 0" }}>{(intercoDraft.companyId === ADD_COMPANY ? intercoDraft.newName?.trim() : borrowSources.find((s) => s._id === intercoDraft.companyId)?.name) || "Lender"} → <strong>{company.name}</strong>. The amount is added to the fund you pick below and shows as owed to the lender.</p>}
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
          isCompanyAdmin={canEditCompanyPosts}
          myRoleLabel={myRoleLabel}
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
                      <span>{m.name} ({roleLabel(company, m.role)})</span>
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
          otherCompanies={managedOtherCompanies}
          canBorrow={can("intercompany")}
          canAddLender={canAddLender}
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
          title={isSettledExpense(deletingExpense) ? "Delete paid expense?" : "Delete expense?"}
          message={isSettledExpense(deletingExpense)
            ? `"${deletingExpense.description}" (${money(deletingExpense.amount)}) is already paid. Deleting it undoes the payment: the money goes back to the Cash/Bank it came from, anything owed to a person for it is removed, and any loan it created is cancelled. This can't be undone.`
            : `Are you sure you want to delete "${deletingExpense.description}" (${money(deletingExpense.amount)})?`}
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
          canDeletePaid={canDeletePaid}
          isCompanyAdmin={canEditCompanyPosts}
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

      {/* last, so it sits above whichever payment popup asked for it */}
      {fundTopUp.ui}
    </AppLayout>
  );
}

const labelStyle = {
  fontSize: 11,
  color: "var(--muted)",
  fontWeight: 700,
  letterSpacing: 0.6,
  marginBottom: 6,
};

// One summary tile on Home: label, big value, a short detail line (or rows), optionally clickable.
// Expenses whose date falls in the period: this week (from Monday), this month, or a custom from/to (YYYY-MM-DD).
function expensesInPeriod(list, period, from, to) {
  if (period === "all") return list;
  const now = new Date();
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  let start;
  let end;
  if (period === "week") {
    start = new Date(today);
    start.setDate(today.getDate() - ((today.getDay() + 6) % 7));
    end = new Date(start);
    end.setDate(start.getDate() + 7);
  } else if (period === "month") {
    start = new Date(now.getFullYear(), now.getMonth(), 1);
    end = new Date(now.getFullYear(), now.getMonth() + 1, 1);
  } else {
    start = from ? new Date(`${from}T00:00:00`) : null;
    end = to ? new Date(`${to}T00:00:00`) : null;
    if (end) end.setDate(end.getDate() + 1);
  }
  return list.filter((expense) => {
    const d = new Date(expense.date || expense.createdAt);
    if (Number.isNaN(d.getTime())) return false;
    return (!start || d >= start) && (!end || d < end);
  });
}

function HomeTile({ label, value, sub, color, onClick, title, extra, below }) {
  return (
    <div className={`stat-card home-tile${onClick ? " clickable" : ""}`} onClick={onClick} title={title}>
      <div className="home-tile-label">{extra ? <span className="home-tile-label-row"><span>{label}</span>{extra}</span> : label}</div>
      <div className="home-tile-value" style={color ? { color } : undefined}>{value}</div>
      {sub && <div className="home-tile-sub">{sub}</div>}
      {below}
    </div>
  );
}

const bigNumberStyle = {
  fontFamily: "Helvetica Neue, Helvetica, Arial, sans-serif",
  fontSize: 20,
  fontWeight: 700,
  color: "var(--forest)",
};

function LedgerHistory({ companyId, userId, loader, title, isAdmin, onReverse, refreshKey }) {
  const [rows, setRows] = useState([]);
  const [page, setPage] = useState(1);
  const [pageSize, setPageSize] = usePageSize();
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
  const ledger = title === "Ledger";
  const paged = pageOf(rows, page, pageSize);
  return (
    <TableCard title={title} meta={tableMeta(rows.length, paged.page, paged.pages)} page={paged.page} pages={paged.pages} onPage={setPage} count={rows.length} pageSize={pageSize} onPageSize={(n) => { setPageSize(n); setPage(1); }}>
      {!rows.length ? (
        <div className="dt-empty">No {title.toLowerCase()} records yet.</div>
      ) : (
        <table className="dt">
          <thead>
            <tr>
              <th>Time</th>
              <th>{ledger ? "Transaction" : "Action"}</th>
              <th>By</th>
              {ledger ? <th>Entries</th> : <th>Record</th>}
              {ledger && <th className="num">Amount</th>}
              {ledger && onReverse && <th className="num">Action</th>}
            </tr>
          </thead>
          <tbody>
            {paged.rows.flatMap((row, i) => {
              const canReverse = isAdmin && onReverse && ledger && !row.reversedBy && row.type !== "reversal";
              const total = Array.isArray(row.entries) ? row.entries.reduce((sum, entry) => sum + Number(entry.debit || 0), 0) : null;
              const at = new Date(row.createdAt || row.at);
              const day = formatDate(at);
              // a black day row before the first record of each day; the records show just their time
              const newDay = i === 0 || formatDate(new Date(paged.rows[i - 1].createdAt || paged.rows[i - 1].at)) !== day;
              const dayCount = newDay ? paged.rows.filter((r) => formatDate(new Date(r.createdAt || r.at)) === day).length : 0;
              return [
                newDay && (
                  <tr key={`day-${day}`} className="dt-group">
                    <td colSpan={ledger ? (onReverse ? 6 : 5) : 4} className="dt-day">
                      {day}
                      <span className="dt-group-total">{dayCount} {dayCount === 1 ? "record" : "records"}</span>
                    </td>
                  </tr>
                ),
                <tr key={row._id}>
                  <td className="nowrap"><span className="dt-time">{at.toLocaleTimeString("en-IN", { hour: "2-digit", minute: "2-digit" })}</span></td>
                  <td className="dt-wrap-text">
                    <span className="dt-strong" style={{ textTransform: ledger ? "none" : "capitalize" }}>{row.memo || (row.action || "Activity").replaceAll("_", " ")}</span>
                    {row.reversedBy && <span className="row-tag bad" style={{ marginLeft: 6 }}>Reversed</span>}
                    {ledger && row.type && <span className="dt-sub">{row.type.replaceAll("_", " ")}{row.method ? ` · ${row.method}` : ""}</span>}
                  </td>
                  <td>{row.createdBy?.name || row.userId?.name || "Staff"}</td>
                  {ledger ? (
                    <td style={{ minWidth: 220 }}>
                      {(row.entries || []).map((entry, i) => (
                        <span key={i} className="dt-sub" style={{ marginTop: i ? 2 : 0 }}>
                          {Number(entry.debit) > 0 ? "Dr" : "Cr"} {entry.accountId?.name || "Account"} · {money(Number(entry.debit) > 0 ? entry.debit : entry.credit)}
                        </span>
                      ))}
                    </td>
                  ) : (
                    <td style={{ textTransform: "capitalize" }}>{row.object || "—"}</td>
                  )}
                  {ledger && <td className="num">{total !== null ? money(total) : "—"}</td>}
                  {ledger && onReverse && (
                    <td><span className="dt-actions">{canReverse && <button type="button" className="btn btn-outline-danger btn-sm" onClick={() => onReverse(row)}>Reverse</button>}</span></td>
                  )}
                </tr>,
              ];
            })}
          </tbody>
        </table>
      )}
    </TableCard>
  );
}
