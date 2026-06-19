import 'dart:convert';
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
          "fcmToken": token,
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
          "fcmToken": token,
        }),
      );

      return jsonDecode(res.body);
    } catch (e) {
      return {"success": false, "message": "Connection error"};
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

