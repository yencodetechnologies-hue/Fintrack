import 'dart:convert';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

class EmailSyncService {
  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: const [
      'email',
      'https://www.googleapis.com/auth/gmail.readonly',
    ],
    serverClientId: AppConfig.googleWebClientId,
  );

  static Future<Map<String, dynamic>> getStatus(String userId) async {
    final res = await http.get(
      Uri.parse("${AppConfig.emailStatus}?userId=$userId"),
    );
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> connectGmail(String userId) async {
    final account = await _googleSignIn.signIn();
    if (account == null) {
      return {"success": false, "message": "Sign-in cancelled"};
    }

    final authCode = account.serverAuthCode;
    if (authCode == null || authCode.isEmpty) {
      return {
        "success": false,
        "message": "Could not get auth code. Check googleWebClientId in AppConfig.",
      };
    }

    final res = await http.post(
      Uri.parse(AppConfig.emailConnect),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"userId": userId, "authCode": authCode}),
    );

    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> disconnectGmail(String userId) async {
    await _googleSignIn.signOut();
    final res = await http.delete(
      Uri.parse("${AppConfig.emailDisconnect}?userId=$userId"),
    );
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> syncBills(String userId) async {
    final res = await http.post(
      Uri.parse(AppConfig.emailSync),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"userId": userId}),
    );
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<List<Map<String, dynamic>>> getSuggestions(String userId) async {
    final res = await http.get(
      Uri.parse("${AppConfig.emailSuggestions}?userId=$userId"),
    );
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (body["success"] != true) return [];
    return List<Map<String, dynamic>>.from(body["data"] as List? ?? []);
  }

  static Future<Map<String, dynamic>> applyBill({
    required String userId,
    required String parsedBillId,
    String? cardId,
  }) async {
    final res = await http.post(
      Uri.parse(AppConfig.emailApply),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "userId": userId,
        "parsedBillId": parsedBillId,
        if (cardId != null) "cardId": cardId,
      }),
    );
    return jsonDecode(res.body) as Map<String, dynamic>;
  }
}
