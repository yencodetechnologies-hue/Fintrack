const express = require("express");
const router = express.Router();
const companyExpenseController = require("../controllers/companyExpenseController");

// Company Endpoints
router.post("/company/create", companyExpenseController.createCompany);
router.post("/company/join", companyExpenseController.joinCompany);
router.get("/user/:userId/companies", companyExpenseController.getUserCompanies);
router.get("/company/:companyId", companyExpenseController.getCompanyDetails);
router.post("/company/:companyId/regenerate-code", companyExpenseController.regenerateJoinCode);
router.post("/company/:companyId/touch-code", companyExpenseController.touchJoinCodeTimer);
router.delete("/company/:companyId/member/:memberUserId", companyExpenseController.removeMember);

// Expense Endpoints
router.post("/company/:companyId/category", companyExpenseController.addCustomCategory);
router.post("/company/:companyId/bank-accounts", companyExpenseController.addBankAccount);
router.post("/company/:companyId/bank-accounts/:accountId/delete", companyExpenseController.deleteBankAccount);
router.post("/company/:companyId/income", companyExpenseController.addIncome);
router.get("/company/:companyId/income", companyExpenseController.getIncomeHistory);
router.post("/expense/create", companyExpenseController.createExpense);
router.get("/company/:companyId/expenses", companyExpenseController.getCompanyExpenses);
router.post("/expense/:expenseId/update", companyExpenseController.updateExpense);
router.post("/expense/:expenseId/pay", companyExpenseController.payExpense);
router.post("/expense/:expenseId/receive", companyExpenseController.receiveExpense);
router.post("/expense/:expenseId/reset-unpaid", companyExpenseController.resetExpenseToUnpaid);
router.post("/expense/:expenseId/edit-settlement", companyExpenseController.editExpenseSettlement);
router.get("/company/:companyId/user/:userId/summary", companyExpenseController.getCompanyBalanceSummary);
router.delete("/company/:companyId", companyExpenseController.deleteCompany);
router.post("/company/:companyId/delete", companyExpenseController.deleteCompany);
router.delete("/expense/:expenseId", companyExpenseController.deleteExpense);
router.post("/expense/:expenseId/delete", companyExpenseController.deleteExpense);

module.exports = router;

