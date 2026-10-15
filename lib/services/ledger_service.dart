import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

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

  static Future<Map<String, dynamic>> _post(String url, Map<String, dynamic> body) async {
    try {
      final res = await http
          .post(Uri.parse(url), headers: {"Content-Type": "application/json"}, body: jsonEncode(body))
          .timeout(const Duration(seconds: 20));
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
      _get("$_company/company/$companyId?userId=$userId");

  static Future<Map<String, dynamic>> regenerateJoinCode(String companyId, String userId) =>
      _post("$_company/company/$companyId/regenerate-code", {"userId": userId});

  static Future<Map<String, dynamic>> userCompanies(String userId) =>
      _get("$_company/user/$userId/companies");

  // ---- expenses ----
  static Future<Map<String, dynamic>> expenses(String companyId, String userId) =>
      _get("$_base/companies/$companyId/expenses?userId=$userId");

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
  static Future<Map<String, dynamic>> intercompany(Map<String, dynamic> body) => _post("$_base/intercompany", body);
  static Future<Map<String, dynamic>> routed(Map<String, dynamic> body) => _post("$_base/routed-payments", body);

  static Future<Map<String, dynamic>> verify(String txId, String userId) =>
      _post("$_base/transactions/$txId/verify", {"userId": userId});

  static Future<Map<String, dynamic>> reverse(String txId, String userId) =>
      _post("$_base/transactions/$txId/reverse", {"userId": userId});

  // ---- reads ----
  static Future<Map<String, dynamic>> balances(String companyId, String userId) =>
      _get("$_base/companies/$companyId/balances?userId=$userId");

  static Future<Map<String, dynamic>> transactions(String companyId, String userId) =>
      _get("$_base/companies/$companyId/transactions?userId=$userId");

  static Future<Map<String, dynamic>> auditLog(String companyId, String userId) =>
      _get("$_base/companies/$companyId/audit-log?userId=$userId");

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

  // ---- groups ----
  static Future<Map<String, dynamic>> groups(String companyId, String userId) =>
      _get("$_base/companies/$companyId/groups?userId=$userId");

  static Future<Map<String, dynamic>> createGroup(Map<String, dynamic> body) => _post("$_base/groups", body);

  static Future<Map<String, dynamic>> groupDetail(String groupId, String userId) =>
      _get("$_base/groups/$groupId?userId=$userId");

  static Future<Map<String, dynamic>> addGroupMember(String groupId, String userId, String memberUserId) =>
      _post("$_base/groups/$groupId/members", {"userId": userId, "memberUserId": memberUserId});

  static Future<Map<String, dynamic>> addGroupNote(String groupId, String userId, String text) =>
      _post("$_base/groups/$groupId/notes", {"userId": userId, "text": text});
}
