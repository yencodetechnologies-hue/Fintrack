import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

class LendService {

  static final String baseUrl = AppConfig.lend;

  // ADD LEND
  static Future<Map<String, dynamic>> addLend({
    required String userId,
    required String userName,
    required String name,
    required String reason,
    required String amount,
    required String date,
  }) async {
    try {
      final response = await http.post(
        Uri.parse("$baseUrl/create"),
        headers: {
          "Content-Type": "application/json",
        },
        body: jsonEncode({
          "userId": userId,
          "userName": userName,
          "name": name,
          "reason": reason,
          "amount": amount,
          "date": date,
        }),
      );

      return jsonDecode(response.body);

    } catch (e) {
      return {
        "success": false,
        "message": e.toString(),
      };
    }
  }

  // GET USER LENDS
  static Future<List<dynamic>> getLends(String userId) async {
    try {
      final response = await http.get(
        Uri.parse("$baseUrl/$userId"),
      );

      return jsonDecode(response.body);

    } catch (e) {
      throw Exception("Error: $e");
    }
  }

  // DELETE LEND
  static Future<Map<String, dynamic>> deleteLend(
      String lendId) async {
    try {
      final response = await http.delete(
        Uri.parse("$baseUrl/$lendId"),
      );

      return jsonDecode(response.body);

    } catch (e) {
      return {
        "success": false,
        "message": e.toString(),
      };
    }
  }

  // UPDATE RECEIVED STATUS
  static Future<Map<String, dynamic>> markReceived(
      String lendId) async {
    try {
      final response = await http.put(
        Uri.parse("$baseUrl/received/$lendId"),
      );

      return jsonDecode(response.body);

    } catch (e) {
      return {
        "success": false,
        "message": e.toString(),
      };
    }
  }
}