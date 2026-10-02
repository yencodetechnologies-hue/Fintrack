const API_BASE = (import.meta.env.VITE_API_BASE_URL || "https://fintrack.yencodetechnologies.in").replace(/\/+$/, "");

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
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    return await parse(res);
  } catch (e) {
    return { success: false, message: e.message || "Network error" };
  }
}

async function get(url) {
  try {
    const res = await fetch(url);
    return await parse(res);
  } catch (e) {
    return { success: false, message: e.message || "Network error" };
  }
}

async function del(url, body) {
  try {
    const res = await fetch(url, {
      method: "DELETE",
      headers: { "Content-Type": "application/json" },
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
export const createCompany = (userId, name, details, userName) =>
  post(companyUrl("/company/create"), { userId, name, details, userName });
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
export const addIncome = (companyId, userId, amount, destination, sourceBankAccountId) =>
  post(companyUrl(`/company/${companyId}/income`), {
    userId,
    amount,
    destination,
    sourceBankAccountId,
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
