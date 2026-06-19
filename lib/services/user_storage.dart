import 'package:shared_preferences/shared_preferences.dart';

class UserStorage {

  static const keyUserId = "user_id";
  static const keyUserName = "user_name";

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

  static Future<void> clearUserId() async {

    final prefs =
    await SharedPreferences.getInstance();

    await prefs.remove(keyUserId);
    await prefs.remove(keyUserName);
  }
}