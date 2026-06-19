import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

class LiabilityService {

  static final String baseUrl = AppConfig.liability;

  // ADD LIABILITY
  static Future<Map<String, dynamic>> addLiability({
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

  // GET USER LIABILITY
  static Future<List<dynamic>> getLiabilities(
      String userId) async {
    try {
      final response = await http.get(
        Uri.parse("$baseUrl/$userId"),
      );

      return jsonDecode(response.body);

    } catch (e) {
      throw Exception("Error: $e");
    }
  }

  // DELETE LIABILITY
  static Future<Map<String, dynamic>> deleteLiability(
      String liabilityId) async {
    try {
      final response = await http.delete(
        Uri.parse("$baseUrl/$liabilityId"),
      );

      return jsonDecode(response.body);

    } catch (e) {
      return {
        "success": false,
        "message": e.toString(),
      };
    }
  }

  // MARK PAID
  static Future<Map<String, dynamic>> markPaid(
      String liabilityId) async {
    try {
      final response = await http.put(
        Uri.parse("$baseUrl/paid/$liabilityId"),
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