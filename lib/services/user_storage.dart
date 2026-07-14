import 'package:shared_preferences/shared_preferences.dart';

class UserStorage {
  /// Normalizes MongoDB ids returned as strings or nested JSON maps.
  static String? parseMongoId(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    if (value is Map) {
      return parseMongoId(value[r'$oid'] ?? value['_id'] ?? value['id']);
    }
    final asString = value.toString().trim();
    return asString.isEmpty ? null : asString;
  }

  static const keyUserId = "user_id";
  static const keyUserName = "user_name";

  static const keyUserEmail = "user_email";

  static Future<void> saveUserId(String id) async {

    final prefs =
    await SharedPreferences.getInstance();

    await prefs.setString(
      keyUserId,
      id,
    );
  }

  static Future<String?> getUserId() async {

    final prefs =
    await SharedPreferences.getInstance();

    return prefs.getString(
      keyUserId,
    );
  }

  static Future<void> saveUserName(
      String name) async {

    final prefs =
    await SharedPreferences.getInstance();

    await prefs.setString(
      keyUserName,
      name,
    );
  }

  static Future<String?> getUserName() async {

    final prefs =
    await SharedPreferences.getInstance();

    return prefs.getString(
      keyUserName,
    );
  }

  static Future<void> saveUserEmail(
      String email) async {

    final prefs =
    await SharedPreferences.getInstance();

    await prefs.setString(
      keyUserEmail,
      email,
    );
  }

  static Future<String?> getUserEmail() async {

    final prefs =
    await SharedPreferences.getInstance();

    return prefs.getString(
      keyUserEmail,
    );
  }

  static Future<void> clearUserId() async {

    final prefs =
    await SharedPreferences.getInstance();

    await prefs.remove(keyUserId);
    await prefs.remove(keyUserName);
    await prefs.remove(keyUserEmail);
  }
}