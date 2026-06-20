import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import '../screens/view_reminder_page.dart';
import 'user_storage.dart';

class FCMService {
  /// Returns an FCM token when available. Returns null if notifications
  /// are unavailable (simulator, denied permission, Firebase not ready).
  static Future<String?> getToken() async {
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();
      await _logPushTokens(messaging);
      return await messaging.getToken();
    } catch (e) {
      debugPrint('FCM getToken error: $e');
      return null;
    }
  }

  static Future<void> _logPushTokens(FirebaseMessaging messaging) async {
    if (Platform.isIOS) {
      String? apnsToken = await messaging.getAPNSToken();
      if (apnsToken == null) {
        for (var i = 0; i < 5 && apnsToken == null; i++) {
          await Future.delayed(const Duration(seconds: 1));
          apnsToken = await messaging.getAPNSToken();
        }
      }
      debugPrint('APNS Token: $apnsToken');
    }

    final fcmToken = await messaging.getToken();
    debugPrint('FCM Token: $fcmToken');
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
