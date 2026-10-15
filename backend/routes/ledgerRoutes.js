const express = require("express");
const router = express.Router();
const c = require("../controllers/ledgerController");

router.post("/expenses", c.createExpense);
router.post("/expenses/:expenseId/approve", c.approveExpense);
router.post("/expenses/:expenseId/reject", c.rejectExpense);
router.post("/expenses/:expenseId/pay", c.payExpense);
router.post("/expenses/:expenseId/delete", c.deleteExpense);
router.delete("/expenses/:expenseId", c.deleteExpense);
router.post("/reimbursements", c.reimburse);
router.post("/lend", c.lend);
router.post("/transactions/:transactionId/reverse", c.reverseTransaction);
router.get("/companies/:companyId/expenses", c.listExpenses);
router.get("/companies/:companyId/balances", c.balances);
router.get("/companies/:companyId/transactions", c.listTransactions);
router.get("/companies/:companyId/audit-log", c.auditLog);

router.post("/transactions/:transactionId/verify", c.verifyTransaction);
router.post("/intercompany", c.intercompanyTransfer);
router.post("/routed-payments", c.routedPayment);
router.get("/companies/:companyId/intercompany", c.intercompanyBalances);
router.get("/companies/:companyId/borrow-sources", c.listCompaniesForBorrow);
router.post("/companies/:companyId/settings", c.updateCompanySettings);
router.get("/companies/:companyId/report", c.report);
router.get("/companies/:companyId/export", c.exportCsv);
router.post("/groups", c.createGroup);
router.get("/companies/:companyId/groups", c.listGroups);
router.get("/groups/:groupId", c.groupDetail);
router.post("/groups/:groupId/members", c.addGroupMember);
router.post("/groups/:groupId/notes", c.addGroupNote);

module.exports = router;
