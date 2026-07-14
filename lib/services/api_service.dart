import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

class ApiService {
  static final String _signupurl = AppConfig.signup;
  static final String _loginurl = AppConfig.login;


  static Future<Map<String, dynamic>> signup(String name,
      String email,
      String password,
      String confirmPassword,
      String? token,) async {
    try {
      final res = await http.post(
        Uri.parse(_signupurl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "name": name,
          "email": email,
          "password": password,
          "confirmPassword": confirmPassword,
          if (token != null && token.isNotEmpty) "fcmToken": token,
        }),
      );

      return jsonDecode(res.body);
    } catch (e) {
      return {"success": false, "message": "Connection error"};
    }
  }


  static Future<Map<String, dynamic>> login(String email,
      String password,
      String? token,) async {
    try {
      final res = await http.post(
        Uri.parse(_loginurl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "email": email,
          "password": password,
          if (token != null && token.isNotEmpty) "fcmToken": token,
        }),
      );

      return jsonDecode(res.body);
    } catch (e) {
      return {"success": false, "message": "Connection error"};
    }
  }


  static Future<Map<String, dynamic>> validateSession(String userId) async {
    try {
      final res = await http.get(
        Uri.parse("${AppConfig.authBase}/session/$userId"),
        headers: {"Content-Type": "application/json"},
      );

      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) {
        return {
          ...decoded,
          "statusCode": res.statusCode,
        };
      }

      return {
        "success": false,
        "statusCode": res.statusCode,
        "message": "Invalid response: ${res.body}",
      };
    } catch (e) {
      return {
        "success": false,
        "message": "Connection error: $e",
      };
    }
  }

  static Future<Map<String, dynamic>> updateFcmToken(
    String userId,
    String token,
  ) async {
    try {
      final res = await http.post(
        Uri.parse(AppConfig.updateFcmToken),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "userId": userId,
          "fcmToken": token,
        }),
      );

      if (res.statusCode < 200 || res.statusCode >= 300) {
        debugPrint(
          'FCM token sync HTTP ${res.statusCode}: ${res.body}',
        );
        return {
          "success": false,
          "statusCode": res.statusCode,
          "message": "HTTP ${res.statusCode}: ${res.body}",
        };
      }

      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return {"success": false, "message": "Invalid response: ${res.body}"};
    } catch (e) {
      debugPrint('FCM token sync error: $e');
      return {"success": false, "message": "Connection error: $e"};
    }
  }

  static Future<Map<String, dynamic>> deleteAccount(String userId) async {
    try {
      final res = await http.delete(
        Uri.parse("${AppConfig.authBase}/delete-account/$userId"),
        headers: {"Content-Type": "application/json"},
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {"success": false, "message": "Connection error: $e"};
    }
  }
}

