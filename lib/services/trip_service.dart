import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

class TripService {
  static final String _baseUrl = AppConfig.trips;

  // 1. Create Trip
  static Future<Map<String, dynamic>> createTrip({
    required String userId,
    required String name,
    required String fromLocation,
    required String toLocation,
    DateTime? startDate,
    DateTime? endDate,
    required double budget,
    String currency = "INR",
    String splitType = "equal",
    List<Map<String, dynamic>>? customShares,
  }) async {
    try {
      final res = await http.post(
        Uri.parse("$_baseUrl/create"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "userId": userId,
          "name": name,
          "fromLocation": fromLocation,
          "toLocation": toLocation,
          "startDate": startDate?.toIso8601String(),
          "endDate": endDate?.toIso8601String(),
          "budget": budget,
          "currency": currency,
          "splitType": splitType,
          if (customShares != null) "customShares": customShares,
        }),
      );

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return data;
    } catch (e) {
      return {
        "success": false,
        "message": "Network error creating trip: $e",
      };
    }
  }

  // 2. Fetch User Trips
  static Future<List<dynamic>> getUserTrips(String userId) async {
    try {
      final res = await http.get(
        Uri.parse("$_baseUrl/user/$userId"),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        if (data["success"] == true && data["trips"] != null) {
          return data["trips"] as List<dynamic>;
        }
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  // 3. Get Trip Details by ID
  static Future<Map<String, dynamic>?> getTripDetails(String tripId) async {
    try {
      final res = await http.get(
        Uri.parse("$_baseUrl/$tripId"),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        if (data["success"] == true && data["trip"] != null) {
          return data["trip"] as Map<String, dynamic>;
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // 4. Join Trip via 6-digit code or QR code
  static Future<Map<String, dynamic>> joinTrip({
    required String userId,
    required String joinCode,
  }) async {
    try {
      final res = await http.post(
        Uri.parse("$_baseUrl/join"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "userId": userId,
          "joinCode": joinCode.trim().toUpperCase(),
        }),
      );

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return data;
    } catch (e) {
      return {
        "success": false,
        "message": "Network error joining trip: $e",
      };
    }
  }

  // 5. Update Trip Details
  static Future<Map<String, dynamic>> updateTrip({
    required String tripId,
    required String userId,
    String? name,
    String? fromLocation,
    String? toLocation,
    DateTime? startDate,
    DateTime? endDate,
    double? budget,
    String? currency,
    String? splitType,
    String? status,
    List<Map<String, dynamic>>? customShares,
  }) async {
    try {
      final res = await http.put(
        Uri.parse("$_baseUrl/$tripId"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "userId": userId,
          if (name != null) "name": name,
          if (fromLocation != null) "fromLocation": fromLocation,
          if (toLocation != null) "toLocation": toLocation,
          if (startDate != null) "startDate": startDate.toIso8601String(),
          if (endDate != null) "endDate": endDate.toIso8601String(),
          if (budget != null) "budget": budget,
          if (currency != null) "currency": currency,
          if (splitType != null) "splitType": splitType,
          if (status != null) "status": status,
          if (customShares != null) "customShares": customShares,
        }),
      );

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return data;
    } catch (e) {
      return {
        "success": false,
        "message": "Network error updating trip: $e",
      };
    }
  }

  // 6. Delete Trip or Remove Member
  static Future<Map<String, dynamic>> deleteTrip({
    required String tripId,
    required String userId,
    String? removeMemberId,
  }) async {
    try {
      final res = await http.delete(
        Uri.parse("$_baseUrl/$tripId"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "userId": userId,
          if (removeMemberId != null) "removeMemberId": removeMemberId,
        }),
      );

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return data;
    } catch (e) {
      return {
        "success": false,
        "message": "Network error deleting trip: $e",
      };
    }
  }
}
