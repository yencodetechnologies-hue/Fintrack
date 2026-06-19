import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

class CardService {
  static final String baseUrl = AppConfig.cards;


  static Future<Map<String, dynamic>> addCard({
    required String userId,
    required String bankName,
    required String cardName,
    required String last4digits,
    required String statementDate,
    required String paymentDueDate,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(baseUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "userId": userId,
          "bankName": bankName,
          "cardName": cardName,
          "last4digits": last4digits,
          "statementDate": statementDate,
          "paymentDueDate": paymentDueDate,
        }),
      );

      return jsonDecode(response.body);
    } catch (e) {
      return {"success": false, "message": e.toString()};
    }
  }


  static Future<List<dynamic>> getCards(String userId) async {
    try {
      final response = await http.get(
        Uri.parse("$baseUrl?userId=$userId"),
      );

      final data = jsonDecode(response.body);
      return data["data"] ?? [];
    } catch (e) {
      throw Exception("Error: $e");
    }
  }


  static Future<Map<String, dynamic>> deleteCard(
      String cardId, String userId) async {
    try {
      final response = await http.delete(
        Uri.parse("$baseUrl/$cardId"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"userId": userId}),
      );

      return jsonDecode(response.body);
    } catch (e) {
      return {"success": false, "message": e.toString()};
    }
  }


  static Future<Map<String, dynamic>> updateCard({
    required String cardId,
    required String userId,
    required String bankName,
    required String cardName,
    required String last4digits,
    required String statementDate,
    required String paymentDueDate,
  }) async {
    try {
      final response = await http.put(
        Uri.parse("$baseUrl/$cardId"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "userId": userId,
          "bankName": bankName,
          "cardName": cardName,
          "last4digits": last4digits,
          "statementDate": statementDate,
          "paymentDueDate": paymentDueDate,
        }),
      );

      return jsonDecode(response.body);
    } catch (e) {
      return {"success": false, "message": e.toString()};
    }
  }
}