// Used only when VITE_API_BASE_URL is not set at build time: a page served from localhost
// talks to the local backend, every deployed copy talks to the live one.
const LIVE_API_BASE = "https://fintrack.yencodetechnologies.in";
const isLocalPage = typeof window !== "undefined" && ["localhost", "127.0.0.1"].includes(window.location.hostname);
const DEFAULT_API_BASE = isLocalPage ? "http://localhost:3009" : LIVE_API_BASE;
export const API_BASE = (import.meta.env.VITE_API_BASE_URL || DEFAULT_API_BASE).replace(/\/+$/, "");

// set by realtime.js; sent with writes so the server doesn't announce our own change back to us
let socketId = null;
export function setSocketId(id) {
  socketId = id;
}
const liveHeaders = () => (socketId ? { "X-Socket-Id": socketId } : {});

function getApiBase() {
  return API_BASE;
}

function authUrl(path) {
  return `${getApiBase()}/api/auth${path}`;
}

function companyUrl(path) {
  return `${getApiBase()}/api/company-expense${path}`;
}

async function parse(res) {
  let data;
  try {
    data = await res.json();
  } catch {
    return { success: false, message: `Server error (${res.status})` };
  }
  return data;
}

async function post(url, body) {
  try {
    const res = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json", ...liveHeaders() },
      body: JSON.stringify(body),
    });
    return await parse(res);
  } catch (e) {
    return { success: false, message: e.message || "Network error" };
  }
}

async function get(url) {
  try {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 12000);
    let res;
    try {
      res = await fetch(url, { signal: controller.signal });
    } finally {
      clearTimeout(timeout);
    }
    return await parse(res);
  } catch (e) {
    if (e.name === "AbortError") return { success: false, message: "Request timed out. Please try again." };
    return { success: false, message: e.message || "Network error" };
  }
}

async function del(url, body) {
  try {
    const res = await fetch(url, {
      method: "DELETE",
      headers: { "Content-Type": "application/json", ...liveHeaders() },
      body: JSON.stringify(body),
    });
    return await parse(res);
  } catch (e) {
    return { success: false, message: e.message || "Network error" };
  }
}

// ---- Auth ----
export const login = (email, password) => post(authUrl("/login"), { email, password });
export const signup = (name, email, password, confirmPassword) =>
  post(authUrl("/signup"), { name, email, password, confirmPassword });

// ---- Company ----
export const createCompany = (userId, name, details, userName, memberUserIds = []) =>
  post(companyUrl("/company/create"), { userId, name, details, userName, memberUserIds });
export const getCompanyMemberCandidates = (userId) =>
  get(companyUrl(`/company/candidates?userId=${userId}`));
export const joinCompany = (userId, joinCode, userName) =>
  post(companyUrl("/company/join"), { userId, joinCode, userName });
export const getUserCompanies = (userId) => get(companyUrl(`/user/${userId}/companies`));
export const getCompanyDetails = (companyId, userId) =>
  get(companyUrl(`/company/${companyId}?userId=${userId}`));
export const regenerateJoinCode = (companyId, userId) =>
  post(companyUrl(`/company/${companyId}/regenerate-code`), { userId });
export const removeMember = (companyId, memberUserId, userId) =>
  del(companyUrl(`/company/${companyId}/member/${memberUserId}`), { userId });
export const deleteCompany = (companyId, userId) =>
  post(companyUrl(`/company/${companyId}/delete`), { userId });

// ---- Categories ----
export const addCustomCategory = (companyId, userId, name) =>
  post(companyUrl(`/company/${companyId}/category`), { userId, name });

// ---- Bank accounts & income ----
export const addBankAccount = (companyId, userId, bankName, accountHolder, accountNumber, ifsc) =>
  post(companyUrl(`/company/${companyId}/bank-accounts`), {
    userId,
    bankName,
    accountHolder,
    accountNumber,
    ifsc,
  });
export const deleteBankAccount = (companyId, userId, accountId) =>
  post(companyUrl(`/company/${companyId}/bank-accounts/${accountId}/delete`), { userId });
export const addIncome = (companyId, userId, amount, destination, sourceBankAccountId, description) =>
  post(companyUrl(`/company/${companyId}/income`), {
    userId,
    amount,
    destination,
    sourceBankAccountId,
    description,
  });
export const getIncomeHistory = (companyId, userId) =>
  get(companyUrl(`/company/${companyId}/income?userId=${userId}`));

// ---- Expenses ----
export const createExpense = (payload) => post(companyUrl("/expense/create"), payload);
export const getCompanyExpenses = (companyId, userId) =>
  get(companyUrl(`/company/${companyId}/expenses?userId=${userId}`));
export const updateExpense = (expenseId, payload) =>
  post(companyUrl(`/expense/${expenseId}/update`), payload);
export const payExpense = (expenseId, payload) =>
  post(companyUrl(`/expense/${expenseId}/pay`), payload);
export const receiveExpense = (expenseId, payload) =>
  post(companyUrl(`/expense/${expenseId}/receive`), payload);
export const resetExpenseStatus = (expenseId, userId, status) =>
  post(companyUrl(`/expense/${expenseId}/reset-unpaid`), { userId, status });
export const editExpenseSettlement = (expenseId, userId, paymentMode, paymentProof) =>
  post(companyUrl(`/expense/${expenseId}/edit-settlement`), { userId, paymentMode, paymentProof });
export const deleteExpense = (expenseId, userId, companyId) =>
  post(companyUrl(`/expense/${expenseId}/delete`), { userId, companyId });
export const getCompanyBalanceSummary = (companyId, userId) =>
  get(companyUrl(`/company/${companyId}/user/${userId}/summary`));

// ---- Expense groups ----
export const createExpenseGroup = (companyId, userId, name, memberIds) =>
  post(companyUrl("/groups"), { companyId, userId, name, memberIds });
export const getUserExpenseGroups = (userId) => get(companyUrl(`/groups?userId=${userId}`));
export const getGroupExpenses = (groupId, userId) =>
  get(companyUrl(`/groups/${groupId}/expenses?userId=${userId}`));
export const createGroupExpense = (groupId, payload) =>
  post(companyUrl(`/groups/${groupId}/expenses`), payload);
export const getGroupExpenseReceipt = (groupId, expenseId, userId) =>
  get(companyUrl(`/groups/${groupId}/expenses/${expenseId}/receipt?userId=${userId}`));
export const getGroupMembers = (groupId, userId) =>
  get(companyUrl(`/groups/${groupId}/members?userId=${userId}`));
export const addGroupMember = (groupId, userId, memberId) =>
  post(companyUrl(`/groups/${groupId}/members`), { userId, memberId });
export const removeGroupMember = (groupId, memberId, userId) =>
  del(companyUrl(`/groups/${groupId}/members/${memberId}`), { userId });
export const settleExpenseGroup = (groupId, payload) =>
  post(`${getApiBase()}/api/ledger/groups/${groupId}/settle`, payload);

// ---- Company ledger (shared with the mobile app) ----
const ledgerUrl = (path) => `${getApiBase()}/api/ledger${path}`;
export const getLedgerBalances = (companyId, userId) => get(ledgerUrl(`/companies/${companyId}/balances?userId=${userId}`));
export const getLedgerExpenses = (companyId, userId) => get(ledgerUrl(`/companies/${companyId}/expenses?userId=${userId}`));
export const createLedgerExpense = (payload) => post(ledgerUrl("/expenses"), payload);
export const approveLedgerExpense = (expenseId, userId) => post(ledgerUrl(`/expenses/${expenseId}/approve`), { userId });
export const rejectLedgerExpense = (expenseId, userId) => post(ledgerUrl(`/expenses/${expenseId}/reject`), { userId });
export const verifyLedgerTransaction = (transactionId, userId) => post(ledgerUrl(`/transactions/${transactionId}/verify`), { userId });
export const payLedgerExpense = (expenseId, payload) => post(ledgerUrl(`/expenses/${expenseId}/pay`), payload);
export const getLedgerBorrowSources = (companyId, userId) => get(ledgerUrl(`/companies/${companyId}/borrow-sources?userId=${userId}`));
export const createCompanyLoan = (payload) => post(ledgerUrl("/loans"), payload);
// only the person who recorded it; reversed in both companies, a paid bill or settled group is reopened
export const deleteCompanyLoan = (loanId, userId) => post(ledgerUrl(`/loans/${loanId}/delete`), { userId });
// a manager's own expense: they got the money back (from company Cash/Bank or a person); closes it
export const receivedLedgerExpense = (expenseId, payload) => post(ledgerUrl(`/expenses/${expenseId}/received`), payload);
export const repayCompanyLoan =(loanId, payload) => post(ledgerUrl(`/loans/${loanId}/repay`), payload);
// lender's managers mark a repayment as received, choosing which of the borrower's Cash/Bank it came from
export const receiveCompanyLoan = (loanId, payload) => post(ledgerUrl(`/loans/${loanId}/receive`), payload);
export const getLoanBorrowerFunds = (loanId, userId) => get(ledgerUrl(`/loans/${loanId}/borrower-funds?userId=${userId}`));
export const lendToCompany = (payload) => post(ledgerUrl("/lend"), payload);
export const getPayableBills = (companyId, personId, userId) =>
  get(ledgerUrl(`/companies/${companyId}/payables/${personId}?userId=${userId}`));
export const reimburseAdmin = (payload) => post(ledgerUrl("/reimbursements"), payload);
export const routedCompanyPayment = (payload) => post(ledgerUrl("/routed-payments"), payload);
export const getLedgerPayerConfirmations = (companyId, userId) => get(ledgerUrl(`/companies/${companyId}/payer-confirmations?userId=${userId}`));
export const confirmLedgerPayer = (expenseId, userId, accept, fundId) => post(ledgerUrl(`/expenses/${expenseId}/payer-confirmation`), { userId, accept, ...(fundId ? { fundId } : {}) });
export const getLedgerIntercompany = (companyId, userId) => get(ledgerUrl(`/companies/${companyId}/intercompany?userId=${userId}`));
// feature switches per role: GET returns my switches (+ both lists for whoever may edit them)
export const getPermissions = (companyId, userId) => get(ledgerUrl(`/companies/${companyId}/permissions?userId=${userId}`));
export const updatePermissions = (companyId, userId, role, permissions) => post(ledgerUrl(`/companies/${companyId}/permissions`), { userId, role, permissions });
export const getLoanDetail = (loanId, userId) => get(ledgerUrl(`/loans/${loanId}?userId=${userId}`));
export const getLoanReceipts = (loanId, userId) => get(ledgerUrl(`/loans/${loanId}?userId=${userId}&receipts=1`));
export const getLedgerLoans =(companyId, userId) => get(ledgerUrl(`/companies/${companyId}/loans?userId=${userId}`));
export const getLedgerReport = (companyId, userId, from, to, category) => {
  const params = new URLSearchParams({ userId });
  if (from) params.set("from", from);
  if (to) params.set("to", to);
  if (category && category !== "All") params.set("category", category);
  return get(ledgerUrl(`/companies/${companyId}/report?${params}`));
};
export const getExpenseAnalysis = (companyId, userId, months = 12) =>
  get(ledgerUrl(`/companies/${companyId}/analysis?userId=${userId}&months=${months}`));
export const getOutstandingReport = (companyId, userId) =>
  get(ledgerUrl(`/companies/${companyId}/outstanding?userId=${userId}`));
export const getLedgerTransactions = (companyId, userId) => get(ledgerUrl(`/companies/${companyId}/transactions?userId=${userId}`));
export const getLedgerAuditLog = (companyId, userId) => get(ledgerUrl(`/companies/${companyId}/audit-log?userId=${userId}`));
export const getLedgerExportUrl = (companyId, userId, from, to, category) => {
  const params = new URLSearchParams({ userId, scope: "company" });
  if (from) params.set("from", from);
  if (to) params.set("to", to);
  if (category && category !== "All") params.set("category", category);
  return ledgerUrl(`/companies/${companyId}/export?${params}`);
};
export const getLedgerExpenseReceipts = (expenseId, userId) =>
  get(ledgerUrl(`/expenses/${expenseId}/receipts?userId=${userId}`));
export const setLedgerExpenseVisibility = (expenseId, userId, visibleTo) =>
  post(ledgerUrl(`/expenses/${expenseId}/visibility`), { userId, visibleTo });
export const updateLedgerExpenseReceipts = (expenseId, userId, receipts) =>
  post(ledgerUrl(`/expenses/${expenseId}/receipts`), { userId, ...receipts });
export const changeLedgerPayerType = (expenseId, userId, payerType, fundId) =>
  post(ledgerUrl(`/expenses/${expenseId}/payer-type`), { userId, payerType, fundId });
export const updateLedgerExpense = (expenseId, payload) =>
  post(ledgerUrl(`/expenses/${expenseId}/update`), payload);
export const deleteLedgerExpense = (expenseId, userId) =>
  del(ledgerUrl(`/expenses/${expenseId}`), { userId });
export const reverseLedgerTransaction = (transactionId, userId) =>
  post(ledgerUrl(`/transactions/${transactionId}/reverse`), { userId });
export const addCompanyMember = (companyId, userId, email, role) =>
  post(ledgerUrl(`/companies/${companyId}/members`), { userId, email, role });
export const addCompanyCategory = (companyId, userId, name) =>
  post(ledgerUrl(`/companies/${companyId}/categories`), { userId, name });
export const deleteCompanyCategory = (companyId, userId, name) =>
  post(ledgerUrl(`/companies/${companyId}/categories/delete`), { userId, name });
export const saveVisibilityPreference = (companyId, userId, hiddenStaffIds) =>
  post(ledgerUrl(`/companies/${companyId}/visibility-preference`), { userId, hiddenStaffIds });
export const inviteCompanyMember = (companyId, userId, email, role) =>
  post(ledgerUrl(`/companies/${companyId}/invites`), { userId, email, role });
export const setCompanyMemberRole = (companyId, userId, memberUserId, role) =>
  post(ledgerUrl(`/companies/${companyId}/members/${memberUserId}/role`), { userId, role });
export const updateCompanySettings = (companyId, payload) =>
  post(ledgerUrl(`/companies/${companyId}/settings`), payload);
// ---- Vouchers (money given to staff up front) ----
export const getVouchers = (companyId, userId) => get(ledgerUrl(`/companies/${companyId}/vouchers?userId=${userId}`));
export const createVoucher = (companyId, payload) => post(ledgerUrl(`/companies/${companyId}/vouchers`), payload);
export const claimVoucher = (voucherId, payload) => post(ledgerUrl(`/vouchers/${voucherId}/claim`), payload);
export const cancelVoucher = (voucherId, userId) => post(ledgerUrl(`/vouchers/${voucherId}/cancel`), { userId });
// the manager who created a voucher records what the staff member used, in their name
// creator only, before the claim: money goes back and the voucher is removed from the lists
export const deleteVoucher = (voucherId, userId) => post(ledgerUrl(`/vouchers/${voucherId}/delete`), { userId });
export const closeVoucher =(voucherId, payload) => post(ledgerUrl(`/vouchers/${voucherId}/close`), payload);
export const requestAdvanceReturn = (companyId, userId, amount, note) =>
  post(ledgerUrl(`/companies/${companyId}/advance-returns`), { userId, amount, note });
export const decideAdvanceReturn = (returnId, userId, accept) =>
  post(ledgerUrl(`/advance-returns/${returnId}/decide`), { userId, accept });

export const updateCashAccountName =(companyId, userId, cashAccountName) =>
  post(companyUrl(`/company/${companyId}/cash-account-name`), { userId, cashAccountName });

