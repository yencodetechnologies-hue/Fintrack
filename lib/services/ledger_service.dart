import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:card/services/expense_company_service.dart';
import '../config/app_config.dart';
import 'ledger_live.dart';

class LedgerService {
  static const String _base = AppConfig.ledger;
  static const String _company = AppConfig.companyExpense;

  static Map<String, dynamic> _parse(http.Response res) {
    try {
      final body = res.body.trim();
      if (body.startsWith("<")) return {"success": false, "message": "Server error (${res.statusCode})"};
      final data = jsonDecode(body);
      return data is Map<String, dynamic> ? data : {"success": false, "message": "Unexpected response"};
    } catch (_) {
      return {"success": false, "message": "Invalid response (${res.statusCode})"};
    }
  }

  // our live-connection id rides along with writes, so the server doesn't echo our own change back to us
  static Map<String, String> get _headers => {
        "Content-Type": "application/json",
        if (LedgerLive.socketId != null) "X-Socket-Id": LedgerLive.socketId!,
      };

  static Future<Map<String, dynamic>> _post(String url, Map<String, dynamic> body) async {
    try {
      final res = await http
          .post(Uri.parse(url), headers: _headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 45));
      return _parse(res);
    } catch (e) {
      return {"success": false, "message": "Network error. Check your connection."};
    }
  }

  static Future<Map<String, dynamic>> _get(String url) async {
    try {
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
      return _parse(res);
    } catch (e) {
      return {"success": false, "message": "Network error. Check your connection."};
    }
  }

  static String _q(Map<String, String?> params) => params.entries
      .where((e) => e.value != null && e.value!.isNotEmpty)
      .map((e) => "${e.key}=${Uri.encodeQueryComponent(e.value!)}")
      .join("&");

  // ---- company context (members, bank accounts) from the existing API ----
  static Future<Map<String, dynamic>> companyDetails(String companyId, String userId) =>
      ExpenseCompanyService.getCompanyDetails(companyId, userId);

  /// [customRoleId] (primary admin only) adds them straight into a custom role.
  static Future<Map<String, dynamic>> addMember(String companyId, String userId, String email, String role, {String? customRoleId}) =>
      _post("$_base/companies/$companyId/members", {"userId": userId, "email": email, "role": role, if (customRoleId != null) "customRoleId": customRoleId});

  static Future<Map<String, dynamic>> setMemberRole(String companyId, String userId, String memberUserId, String role) =>
      _post("$_base/companies/$companyId/members/$memberUserId/role", {"userId": userId, "role": role});

  static Future<Map<String, dynamic>> regenerateJoinCode(String companyId, String userId) =>
      _post("$_company/company/$companyId/regenerate-code", {"userId": userId});

  static Future<Map<String, dynamic>> userCompanies(String userId) =>
      _get("$_company/user/$userId/companies");
  /// All my companies including the ones I removed from my list (each has hiddenFromList).
  static Future<Map<String, dynamic>> userCompaniesWithHidden(String userId) =>
      _get("$_company/user/$userId/companies?includeHidden=1");
  /// Admin only: remove a company from MY list (hidden: true) or restore it. The company itself is untouched.
  static Future<Map<String, dynamic>> setCompanyHidden(String companyId, String userId, bool hidden) =>
      _post("$_base/companies/$companyId/hide", {"userId": userId, "hidden": hidden});

  static Future<Map<String, dynamic>> _delete(String url, Map<String, dynamic> body) async {
    try {
      final req = http.Request("DELETE", Uri.parse(url))
        ..headers.addAll(_headers)
        ..body = jsonEncode(body);
      final streamed = await req.send().timeout(const Duration(seconds: 30));
      return _parse(await http.Response.fromStream(streamed));
    } catch (e) {
      return {"success": false, "message": "Network error. Check your connection."};
    }
  }

  // ---- expenses (same endpoints as the web) ----
  // Full list without receipt images; payer names and flags included.
  static Future<Map<String, dynamic>> expenses(String companyId, String userId) =>
      _get("$_base/companies/$companyId/expenses?userId=$userId");

  static Future<Map<String, dynamic>> expenseReceipts(String expenseId, String userId) =>
      _get("$_base/expenses/$expenseId/receipts?userId=$userId");

  static Future<Map<String, dynamic>> updateExpense(String id, Map<String, dynamic> body) =>
      _post("$_base/expenses/$id/update", body);

  static Future<Map<String, dynamic>> updateReceipts(String id, String userId, {String? attachment, String? paymentReceipt}) =>
      _post("$_base/expenses/$id/receipts", {
        "userId": userId,
        if (attachment != null) "attachment": attachment,
        if (paymentReceipt != null) "paymentReceipt": paymentReceipt,
      });

  static Future<Map<String, dynamic>> changePayerType(String id, String userId, String payerType, {String? fundId}) =>
      _post("$_base/expenses/$id/payer-type", {"userId": userId, "payerType": payerType, if (fundId != null) "fundId": fundId});

  /// A person's open bills oldest first (the Reimburse preview).
  /// A manager pays off their own outstanding from company funds. body: { userId, items: [{transactionId}|{expenseId}], fundId, method, reference }.
  static Future<Map<String, dynamic>> payOwnOutstanding(String companyId, Map<String, dynamic> body) =>
      _post("$_base/companies/$companyId/payables/self-pay", body);

  static Future<Map<String, dynamic>> payableBills(String companyId, String personId, String userId) =>
      _get("$_base/companies/$companyId/payables/$personId?userId=$userId");

  // ---- reports ----
  static Future<Map<String, dynamic>> outstanding(String companyId, String userId) =>
      _get("$_base/companies/$companyId/outstanding?userId=$userId");

  static Future<Map<String, dynamic>> analysis(String companyId, String userId, {int months = 12}) =>
      _get("$_base/companies/$companyId/analysis?userId=$userId&months=$months");

  // ---- loans ----
  static Future<Map<String, dynamic>> loanDetail(String loanId, String userId) =>
      _get("$_base/loans/$loanId?userId=$userId");

  static Future<Map<String, dynamic>> loanReceipts(String loanId, String userId) =>
      _get("$_base/loans/$loanId?userId=$userId&receipts=1");

  // ---- vouchers ----
  static Future<Map<String, dynamic>> vouchers(String companyId, String userId) =>
      _get("$_base/companies/$companyId/vouchers?userId=$userId");

  static Future<Map<String, dynamic>> createVoucher(String companyId, Map<String, dynamic> body) =>
      _post("$_base/companies/$companyId/vouchers", body);

  static Future<Map<String, dynamic>> claimVoucher(String voucherId, Map<String, dynamic> body) =>
      _post("$_base/vouchers/$voucherId/claim", body);

  /// The manager who created a voucher records what the staff member used, in their name.
  static Future<Map<String, dynamic>> closeVoucher(String voucherId, Map<String, dynamic> body) =>
      _post("$_base/vouchers/$voucherId/close", body);

  /// Creator only, before the claim: money goes back and the voucher is removed from the lists.
  static Future<Map<String, dynamic>> deleteVoucher(String voucherId, String userId) =>
      _post("$_base/vouchers/$voucherId/delete", {"userId": userId});

  static Future<Map<String, dynamic>> cancelVoucher(String voucherId, String userId) =>
      _post("$_base/vouchers/$voucherId/cancel", {"userId": userId});

  static Future<Map<String, dynamic>> requestAdvanceReturn(String companyId, String userId, num amount, String note) =>
      _post("$_base/companies/$companyId/advance-returns", {"userId": userId, "amount": amount, "note": note});

  static Future<Map<String, dynamic>> decideAdvanceReturn(String returnId, String userId, bool accept) =>
      _post("$_base/advance-returns/$returnId/decide", {"userId": userId, "accept": accept});

  // ---- company settings, members, categories, funds ----
  static Future<Map<String, dynamic>> inviteMember(String companyId, String userId, String email, String role, {String? customRoleId}) =>
      _post("$_base/companies/$companyId/invites", {"userId": userId, "email": email, "role": role, if (customRoleId != null) "customRoleId": customRoleId});

  /// Invited emails with their status: pending (waiting to sign up / emailSent false = email failed) or accepted (joined).
  static Future<Map<String, dynamic>> invites(String companyId, String userId) =>
      _get("$_base/companies/$companyId/invites?userId=$userId");
  static Future<Map<String, dynamic>> cancelInvite(String companyId, String inviteId, String userId) =>
      _post("$_base/companies/$companyId/invites/$inviteId/cancel", {"userId": userId});

  static Future<Map<String, dynamic>> removeMember(String companyId, String memberUserId, String userId) =>
      _delete("$_company/company/$companyId/member/$memberUserId", {"userId": userId});

  static Future<Map<String, dynamic>> deleteCompany(String companyId, String userId) =>
      _post("$_company/company/$companyId/delete", {"userId": userId});

  static Future<Map<String, dynamic>> saveVisibilityPreference(String companyId, String userId, List<String> hiddenStaffIds) =>
      _post("$_base/companies/$companyId/visibility-preference", {"userId": userId, "hiddenStaffIds": hiddenStaffIds});

  static Future<Map<String, dynamic>> addCategory(String companyId, String userId, String name) =>
      _post("$_base/companies/$companyId/categories", {"userId": userId, "name": name});

  static Future<Map<String, dynamic>> deleteCategory(String companyId, String userId, String name) =>
      _post("$_base/companies/$companyId/categories/delete", {"userId": userId, "name": name});

  static Future<Map<String, dynamic>> addBankAccount(String companyId, Map<String, dynamic> body) =>
      _post("$_company/company/$companyId/bank-accounts", body);

  static Future<Map<String, dynamic>> deleteBankAccount(String companyId, String accountId, String userId) =>
      _post("$_company/company/$companyId/bank-accounts/$accountId/delete", {"userId": userId});

  static Future<Map<String, dynamic>> addIncome(String companyId, Map<String, dynamic> body) =>
      _post("$_company/company/$companyId/income", body);

  static Future<Map<String, dynamic>> incomeHistory(String companyId, String userId) =>
      _get("$_company/company/$companyId/income?userId=$userId");

  static Future<Map<String, dynamic>> updateCashAccountName(String companyId, String userId, String name) =>
      _post("$_company/company/$companyId/cash-account-name", {"userId": userId, "cashAccountName": name});

  static Future<Map<String, dynamic>> dashboardExpenses(String companyId, String userId) =>
      _get("$_base/companies/$companyId/expenses?userId=$userId&summary=1");

  static Future<Map<String, dynamic>> createExpense(Map<String, dynamic> body) => _post("$_base/expenses", body);

  static Future<Map<String, dynamic>> approve(String id, String userId) =>
      _post("$_base/expenses/$id/approve", {"userId": userId});

  static Future<Map<String, dynamic>> reject(String id, String userId) =>
      _post("$_base/expenses/$id/reject", {"userId": userId});

  static Future<Map<String, dynamic>> pay(String id, Map<String, dynamic> body) =>
      _post("$_base/expenses/$id/pay", body);

  static Future<Map<String, dynamic>> deleteExpense(String id, String userId) =>
      _post("$_base/expenses/$id/delete", {"userId": userId});

  // ---- money movements ----
  static Future<Map<String, dynamic>> reimburse(Map<String, dynamic> body) => _post("$_base/reimbursements", body);
  static Future<Map<String, dynamic>> lend(Map<String, dynamic> body) => _post("$_base/lend", body);
  static Future<Map<String, dynamic>> routed(Map<String, dynamic> body) => _post("$_base/routed-payments", body);

  static Future<Map<String, dynamic>> verify(String txId, String userId) =>
      _post("$_base/transactions/$txId/verify", {"userId": userId});

  static Future<Map<String, dynamic>> reverse(String txId, String userId) =>
      _post("$_base/transactions/$txId/reverse", {"userId": userId});

  static Future<Map<String, dynamic>> loans(String companyId, String userId) =>
      _get("$_base/companies/$companyId/loans?userId=$userId");

  /// Every loan with one company / person as a statement (oldest first, running balance; > 0 = we owe them).
  static Future<Map<String, dynamic>> loanPartyStatement(String companyId, String partyId, String userId) =>
      _get("$_base/companies/$companyId/loan-parties/$partyId?userId=$userId");

  static Future<Map<String, dynamic>> payerConfirmations(String companyId, String userId) =>
      _get("$_base/companies/$companyId/payer-confirmations?userId=$userId");

  static Future<Map<String, dynamic>> createLoan(Map<String, dynamic> body) => _post("$_base/loans", body);

  /// Only the person who recorded it; reversed in both companies, a paid bill or settled group is reopened.
  static Future<Map<String, dynamic>> deleteLoan(String loanId, String userId) =>
      _post("$_base/loans/$loanId/delete", {"userId": userId});

  /// Feature switches per role: my switches, plus both lists for whoever may edit them.
  static Future<Map<String, dynamic>> permissions(String companyId, String userId) =>
      _get("$_base/companies/$companyId/permissions?userId=$userId");

  /// role: "manager" | "staff"; permissions: { key: bool }.
  static Future<Map<String, dynamic>> updatePermissions(String companyId, String userId, String role, Map<String, bool> permissions) =>
      _post("$_base/companies/$companyId/permissions", {"userId": userId, "role": role, "permissions": permissions});

  /// A manager's own expense: they got the money back. body: { userId, from: company|person, fundId?, personId?, method, reference }.
  static Future<Map<String, dynamic>> markReceived(String expenseId, Map<String, dynamic> body) =>
      _post("$_base/expenses/$expenseId/received", body);

  /// Rename the built-in Manager / Staff roles for this company ("" = default).
  static Future<Map<String, dynamic>> renameBuiltInRoles(String companyId, String userId, Map<String, String> names) =>
      _post("$_base/companies/$companyId/role-names", {"userId": userId, ...names});

  /// Admins only: make (or unmake) someone an Admin — full access like the company creator.
  static Future<Map<String, dynamic>> setMemberAdmin(String companyId, String memberUserId, String userId, bool admin) =>
      _post("$_base/companies/$companyId/members/$memberUserId/admin", {"userId": userId, "admin": admin});

  // ---- custom roles (primary admin only) ----
  /// A role is just a name; every switch starts off.
  static Future<Map<String, dynamic>> createCustomRole(String companyId, String userId, String name) =>
      _post("$_base/companies/$companyId/roles", {"userId": userId, "name": name});

  /// changes: { name?, permissions?: { key: bool } }
  static Future<Map<String, dynamic>> updateCustomRole(String companyId, String roleId, String userId, Map<String, dynamic> changes) =>
      _post("$_base/companies/$companyId/roles/$roleId", {"userId": userId, ...changes});

  /// Also removes the role's members from the company.
  static Future<Map<String, dynamic>> deleteCustomRole(String companyId, String roleId, String userId) =>
      _post("$_base/companies/$companyId/roles/$roleId/delete", {"userId": userId});

  /// roleId null takes them out of the role (back to staff).
  static Future<Map<String, dynamic>> setMemberCustomRole(String companyId, String memberUserId, String userId, String? roleId) =>
      _post("$_base/companies/$companyId/members/$memberUserId/custom-role", {"userId": userId, "roleId": roleId});

  static Future<Map<String, dynamic>> repayLoan(String loanId, Map<String, dynamic> body) =>
      _post("$_base/loans/$loanId/repay", body);

  /// Lender's managers mark a repayment as received; borrowerFundId is the borrower's Cash/Bank it came from.
  static Future<Map<String, dynamic>> receiveLoan(String loanId, Map<String, dynamic> body) =>
      _post("$_base/loans/$loanId/receive", body);

  static Future<Map<String, dynamic>> loanBorrowerFunds(String loanId, String userId) =>
      _get("$_base/loans/$loanId/borrower-funds?userId=$userId");

  static Future<Map<String, dynamic>> settleExpenseGroup(String groupId, Map<String, dynamic> body) =>
      _post("$_base/groups/$groupId/settle", body);

  static Future<Map<String, dynamic>> confirmPayer(String expenseId, String userId, bool accept, {String? fundId}) =>
      _post("$_base/expenses/$expenseId/payer-confirmation", {"userId": userId, "accept": accept, if (fundId != null) "fundId": fundId});

  static Future<Map<String, dynamic>> setExpenseVisibility(String expenseId, String userId, List<String> visibleTo) =>
      _post("$_base/expenses/$expenseId/visibility", {"userId": userId, "visibleTo": visibleTo});

  // ---- reads ----
  static Future<Map<String, dynamic>> balances(String companyId, String userId) =>
      _get("$_base/companies/$companyId/balances?userId=$userId");

  static Future<Map<String, dynamic>> transactions(String companyId, String userId) =>
      _get("$_base/companies/$companyId/transactions?userId=$userId");

  static Future<Map<String, dynamic>> auditLog(String companyId, String userId) =>
      _get("$_base/companies/$companyId/audit-log?userId=$userId");

  /// Past descriptions for a description field; kind: expense | payment | fund.
  static Future<Map<String, dynamic>> descriptionSuggestions(String companyId, String userId, String kind) =>
      _get("$_base/companies/$companyId/descriptions?userId=$userId&kind=$kind");

  /// Accounts statement: every money in/out with the balance after it, searched and paged on the server.
  static Future<Map<String, dynamic>> accountsEntries(String companyId, String userId,
          {required String from, required String to, String q = "", int page = 1, int limit = 25}) =>
      _get("$_base/companies/$companyId/accounts/entries?userId=$userId&from=$from&to=$to&q=${Uri.encodeQueryComponent(q)}&page=$page&limit=$limit");

  /// Changes one Accounts entry's amount in place (money added, company-paid expense, borrowed loan, repayment).
  /// changes: amount, details, method, reference, date ("YYYY-MM-DDTHH:mm", India time) — any of them.
  static Future<Map<String, dynamic>> editAccountsEntry(String companyId, String userId, String editId, Map<String, dynamic> changes) =>
      _post("$_base/companies/$companyId/accounts/entries/edit", {"userId": userId, "editId": editId, ...changes});

  /// The Admin removes a money-added / transfer entry (editId "income:ID"): the money comes back out of that account.
  static Future<Map<String, dynamic>> deleteAccountsEntry(String companyId, String userId, String editId) =>
      _post("$_base/companies/$companyId/accounts/entries/delete", {"userId": userId, "editId": editId});

  /// Accounts by day (older view): each day's money in/out, expenses and closing Cash + Bank balance.
  static Future<Map<String, dynamic>> accountsDays(String companyId, String userId, String from, String to) =>
      _get("$_base/companies/$companyId/accounts?userId=$userId&from=$from&to=$to");

  static Future<Map<String, dynamic>> intercompanyBalances(String companyId, String userId) =>
      _get("$_base/companies/$companyId/intercompany?userId=$userId");

  static Future<Map<String, dynamic>> borrowSources(String companyId, String userId) =>
      _get("$_base/companies/$companyId/borrow-sources?userId=$userId");

  static Future<Map<String, dynamic>> report(String companyId, String userId, {String? from, String? to, String? category}) =>
      _get("$_base/companies/$companyId/report?${_q({"userId": userId, "from": from, "to": to, "category": category})}");

  static String exportUrl(String companyId, String userId, {required bool full, String? from, String? to}) =>
      "$_base/companies/$companyId/export?${_q({"userId": userId, "scope": full ? "full" : "company", "from": from, "to": to})}";

  static Future<Map<String, dynamic>> updateSettings(String companyId, Map<String, dynamic> body) =>
      _post("$_base/companies/$companyId/settings", body);

  /// My own order of the companies list (top to bottom).
  static Future<Map<String, dynamic>> saveCompanyOrder(String userId, List<String> companyIds) =>
      _post("$_base/company-order", {"userId": userId, "companyIds": companyIds});

  /// Company groups: a named set of companies, only for organising the companies list. groupId null = create.
  static Future<Map<String, dynamic>> saveCompanyGroup(String? groupId, Map<String, dynamic> body) =>
      _post(groupId == null ? "$_base/company-groups" : "$_base/company-groups/$groupId", body);
  static Future<Map<String, dynamic>> deleteCompanyGroup(String groupId, String userId) =>
      _post("$_base/company-groups/$groupId/delete", {"userId": userId});

  /// Company logo as a data:image URL ("" removes it); primary Admin only.
  static Future<Map<String, dynamic>> setCompanyLogo(String companyId, String userId, String logo) =>
      _post("$_base/companies/$companyId/logo", {"userId": userId, "logo": logo});

}
