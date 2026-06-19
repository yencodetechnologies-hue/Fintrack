import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import '../screens/view_reminder_page.dart';
import 'user_storage.dart';

class FCMService {
  static Future<String?> getToken() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    await messaging.requestPermission();
    String? token = await messaging.getToken();
    return token;
  }

  /// Sets up message tap listeners for when the app is in the background or terminated.
  static Future<void> initializeNotificationClickedHandler(GlobalKey<NavigatorState> navKey) async {
    // 1. Listen for background clicks (when app is running in background)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _handleNotificationClick(navKey);
    });

    // 2. Listen for terminated clicks (when app is launched from notification tap)
    FirebaseMessaging.instance.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) {
        _handleNotificationClick(navKey);
      }
    });
  }

  static Future<void> _handleNotificationClick(GlobalKey<NavigatorState> navKey) async {
    // Wait a brief moment to ensure navigator state is fully initialized
    await Future.delayed(const Duration(milliseconds: 500));
    
    String? userId = await UserStorage.getUserId();
    String? userName = await UserStorage.getUserName();
    
    if (userId != null) {
      navKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => ViewReminderPage(
            userId: userId,
            userName: userName ?? "User",
          ),
        ),
      );
    }
  }
}