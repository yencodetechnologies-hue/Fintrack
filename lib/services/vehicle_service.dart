import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

// Every call on one vehicle sends the owner's userId: the server only acts on your own vehicles.
class VehicleService {
  static final String _baseUrl = AppConfig.vehicles;

  // 1. Create Vehicle
  static Future<Map<String, dynamic>> createVehicle({
    required String userId,
    required String name,
    required String vehicleType,
    required String fuelType,
    required String brand,
    required String model,
    bool isManualModel = false,
    required double averageMileage,
    double tankCapacity = 40,
    double currentFuelLevel = 30,
    double lowRangeThresholdKm = 25,
    double odometerKm = 0,
  }) async {
    try {
      final res = await http.post(
        Uri.parse(_baseUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "userId": userId,
          "name": name,
          "vehicleType": vehicleType,
          "fuelType": fuelType,
          "brand": brand,
          "model": model,
          "isManualModel": isManualModel,
          "averageMileage": averageMileage,
          "tankCapacity": tankCapacity,
          "currentFuelLevel": currentFuelLevel,
          "lowRangeThresholdKm": lowRangeThresholdKm,
          "odometerKm": odometerKm,
        }),
      );

      return jsonDecode(res.body);
    } catch (e) {
      return {"success": false, "message": "Network error: $e"};
    }
  }

  // 2. Get User Vehicles
  static Future<List<dynamic>> getUserVehicles(String userId) async {
    try {
      final res = await http.get(Uri.parse("$_baseUrl/user/$userId"));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data["success"] == true) {
          return data["vehicles"] ?? [];
        }
      }
    } catch (e) {
      debugPrint("Error fetching user vehicles: $e");
    }
    return [];
  }

  // 3. Get Vehicle by ID
  static Future<Map<String, dynamic>?> getVehicleById(String vehicleId, String userId) async {
    try {
      final res = await http.get(Uri.parse("$_baseUrl/$vehicleId?userId=$userId"));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data["success"] == true) {
          return data["vehicle"];
        }
      }
    } catch (e) {
      debugPrint("Error fetching vehicle by ID: $e");
    }
    return null;
  }

  // 4. Update Vehicle
  static Future<Map<String, dynamic>> updateVehicle(String vehicleId, String userId, Map<String, dynamic> updateData) async {
    try {
      final res = await http.put(
        Uri.parse("$_baseUrl/$vehicleId"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({...updateData, "userId": userId}),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {"success": false, "message": "Network error: $e"};
    }
  }

  // 5. Delete Vehicle
  static Future<bool> deleteVehicle(String vehicleId, String userId) async {
    try {
      final res = await http.delete(Uri.parse("$_baseUrl/$vehicleId?userId=$userId"));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data["success"] == true;
      }
    } catch (e) {
      debugPrint("Error deleting vehicle: $e");
    }
    return false;
  }


  // 6. Log Refuel / Recharge
  static Future<Map<String, dynamic>> addRefuelLog({
    required String vehicleId,
    required String userId,
    required double fuelAdded,
    double cost = 0,
    double? odometer,
  }) async {
    try {
      final res = await http.post(
        Uri.parse("$_baseUrl/$vehicleId/refuel"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "userId": userId,
          "fuelAdded": fuelAdded,
          "cost": cost,
          "odometer": odometer,
        }),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {"success": false, "message": "Network error: $e"};
    }
  }

  // 7. Save Ride History
  static Future<Map<String, dynamic>> saveRide({
    required String vehicleId,
    required String userId,
    required DateTime startTime,
    required DateTime endTime,
    required double distanceKm,
    required double fuelUsed,
    required double avgSpeedKmh,
  }) async {
    try {
      final res = await http.post(
        Uri.parse("$_baseUrl/$vehicleId/ride"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "userId": userId,
          "startTime": startTime.toIso8601String(),
          "endTime": endTime.toIso8601String(),
          "distanceKm": distanceKm,
          "fuelUsed": fuelUsed,
          "avgSpeedKmh": avgSpeedKmh,
        }),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {"success": false, "message": "Network error: $e"};
    }
  }
}
