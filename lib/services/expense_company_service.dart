import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

class ExpenseCompanyService {
  static const String _base = AppConfig.companyExpense;

  static Map<String, dynamic> _parseResponse(http.Response res) {
    try {
      final bodyStr = res.body.trim();
      if (bodyStr.startsWith("<")) {
        return {
          "success": false,
          "message": "Server error (${res.statusCode}). Please restart the backend Node.js server.",
        };
      }
      final data = jsonDecode(bodyStr);
      if (data is Map<String, dynamic>) {
        return data;
      }
      return {"success": false, "message": "Unexpected response structure"};
    } catch (e) {
      return {"success": false, "message": "Invalid JSON response (${res.statusCode})"};
    }
  }

  // 1. Create Company
  static Future<Map<String, dynamic>> createCompany({
    required String userId,
    required String name,
    String? details,
  }) async {
    try {
      final res = await http.post(
        Uri.parse("$_base/company/create"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "userId": userId,
          "name": name,
          "details": details ?? "",
        }),
      );
      return _parseResponse(res);
    } catch (e) {
      return {"success": false, "message": e.toString()};
    }
  }

  // 2. Join Company
  static Future<Map<String, dynamic>> joinCompany({
    required String userId,
    required String joinCode,
  }) async {
    try {
      final res = await http.post(
        Uri.parse("$_base/company/join"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "userId": userId,
          "joinCode": joinCode,
        }),
      );
      return _parseResponse(res);
    } catch (e) {
      return {"success": false, "message": e.toString()};
    }
  }

  // 3. Get User Companies
  static Future<List<Map<String, dynamic>>> getUserCompanies(String userId) async {
    try {
      final res = await http.get(Uri.parse("$_base/user/$userId/companies")).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = _parseResponse(res);
        if (data["success"] == true && data["companies"] is List) {
          return List<Map<String, dynamic>>.from(data["companies"]);
        }
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  // 4. Get Company Details & Members
  static Future<Map<String, dynamic>> getCompanyDetails(String companyId, String userId) async {
    try {
      final res = await http.get(Uri.parse("$_base/company/$companyId?userId=$userId")).timeout(const Duration(seconds: 10));
      return _parseResponse(res);
    } catch (e) {
      return {"success": false, "message": e.toString()};
    }
  }

  // 5. Admin Regenerate Join Code
  static Future<Map<String, dynamic>> regenerateJoinCode({
    required String companyId,
    required String userId,
  }) async {
    try {
      final res = await http.post(
        Uri.parse("$_base/company/$companyId/regenerate-code"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"userId": userId}),
      ).timeout(const Duration(seconds: 10));
      return _parseResponse(res);
    } catch (e) {
      return {"success": false, "message": e.toString()};
    }
  }

  // 5b. Admin Start/Touch Join Code Timer
  static Future<Map<String, dynamic>> touchJoinCodeTimer({
    required String companyId,
    required String userId,
  }) async {
    try {
      final res = await http.post(
        Uri.parse("$_base/company/$companyId/touch-code"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"userId": userId}),
      ).timeout(const Duration(seconds: 10));
      return _parseResponse(res);
    } catch (e) {
      return {"success": false, "message": e.toString()};
    }
  }

  // 6. Admin Remove Member
  static Future<Map<String, dynamic>> removeMember({
    required String companyId,
    required String memberUserId,
    required String userId,
  }) async {
    try {
      final res = await http.delete(
        Uri.parse("$_base/company/$companyId/member/$memberUserId"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"userId": userId}),
      ).timeout(const Duration(seconds: 10));
      return _parseResponse(res);
    } catch (e) {
      return {"success": false, "message": e.toString()};
    }
  }

  // 7. Create Expense
  static Future<Map<String, dynamic>> createExpense({
    required String companyId,
    required String userId,
    required double amount,
    required String description,
    String? category,
    DateTime? date,
    String? attachment,
  }) async {
    try {
      final res = await http.post(
        Uri.parse("$_base/expense/create"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "companyId": companyId,
          "userId": userId,
          "amount": amount,
          "description": description,
          "category": category ?? "General",
          "date": (date ?? DateTime.now()).toIso8601String(),
          "attachment": attachment ?? "",
        }),
      ).timeout(const Duration(seconds: 10));
      return _parseResponse(res);
    } catch (e) {
      return {"success": false, "message": e.toString()};
    }
  }

  // 8. Get Company Expenses (Feed)
  static Future<List<Map<String, dynamic>>> getCompanyExpenses(String companyId) async {
    try {
      final res = await http.get(Uri.parse("$_base/company/$companyId/expenses")).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = _parseResponse(res);
        if (data["success"] == true && data["expenses"] is List) {
          return List<Map<String, dynamic>>.from(data["expenses"]);
        }
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  // 9. Pay Expense Flow (§7.1)
  static Future<Map<String, dynamic>> payExpense({
    required String expenseId,
    required String userId,
    required String paymentMode,
    required String paymentProof,
  }) async {
    try {
      final res = await http.post(
        Uri.parse("$_base/expense/$expenseId/pay"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "userId": userId,
          "paymentMode": paymentMode,
          "paymentProof": paymentProof,
        }),
      ).timeout(const Duration(seconds: 10));
      return _parseResponse(res);
    } catch (e) {
      return {"success": false, "message": e.toString()};
    }
  }

  // 10. Receive Expense Flow (§7.2)
  static Future<Map<String, dynamic>> receiveExpense({
    required String expenseId,
    required String userId,
    required String payerUserId,
    required String paymentMode,
  }) async {
    try {
      final res = await http.post(
        Uri.parse("$_base/expense/$expenseId/receive"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "userId": userId,
          "payerUserId": payerUserId,
          "paymentMode": paymentMode,
        }),
      ).timeout(const Duration(seconds: 10));
      return _parseResponse(res);
    } catch (e) {
      return {"success": false, "message": e.toString()};
    }
  }

  // 11. Balance Summary
  static Future<Map<String, dynamic>> getCompanyBalanceSummary({
    required String companyId,
    required String userId,
  }) async {
    try {
      final res = await http.get(Uri.parse("$_base/company/$companyId/user/$userId/summary")).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        return _parseResponse(res);
      }
      return {"success": false, "totalReceivable": 0.0, "totalPayable": 0.0, "netBalance": 0.0};
    } catch (e) {
      return {"success": false, "totalReceivable": 0.0, "totalPayable": 0.0, "netBalance": 0.0};
    }
  }

  // 12. Reset Expense to Unpaid / Change Status
  static Future<Map<String, dynamic>> resetExpenseToUnpaid({
    required String expenseId,
    required String userId,
    String status = "outstanding",
  }) async {
    try {
      final res = await http.post(
        Uri.parse("$_base/expense/$expenseId/reset-unpaid"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"userId": userId, "status": status}),
      ).timeout(const Duration(seconds: 10));
      return _parseResponse(res);
    } catch (e) {
      return {"success": false, "message": e.toString()};
    }
  }

  // 13. Edit Expense Settlement Details
  static Future<Map<String, dynamic>> editExpenseSettlement({
    required String expenseId,
    required String userId,
    String? paymentMode,
    String? paymentProof,
  }) async {
    try {
      final res = await http.post(
        Uri.parse("$_base/expense/$expenseId/edit-settlement"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "userId": userId,
          if (paymentMode != null) "paymentMode": paymentMode,
          if (paymentProof != null) "paymentProof": paymentProof,
        }),
      ).timeout(const Duration(seconds: 10));
      return _parseResponse(res);
    } catch (e) {
      return {"success": false, "message": e.toString()};
    }
  }
}

