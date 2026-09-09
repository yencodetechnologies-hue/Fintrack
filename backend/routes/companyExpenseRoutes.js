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
router.post("/expense/create", companyExpenseController.createExpense);
router.get("/company/:companyId/expenses", companyExpenseController.getCompanyExpenses);
router.post("/expense/:expenseId/pay", companyExpenseController.payExpense);
router.post("/expense/:expenseId/receive", companyExpenseController.receiveExpense);
router.post("/expense/:expenseId/reset-unpaid", companyExpenseController.resetExpenseToUnpaid);
router.post("/expense/:expenseId/edit-settlement", companyExpenseController.editExpenseSettlement);
router.get("/company/:companyId/user/:userId/summary", companyExpenseController.getCompanyBalanceSummary);

module.exports = router;

