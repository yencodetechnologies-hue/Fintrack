import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import '../screens/view_reminder_page.dart';
import 'api_service.dart';
import 'user_storage.dart';

class FCMService {
  /// Returns an FCM token when available. Returns null if notifications
  /// are unavailable (simulator, denied permission, Firebase not ready).
  static Future<String?> getToken() async {
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      await _waitForApnsTokenIfNeeded(messaging);
      final fcmToken = await messaging.getToken();
      debugPrint('FCM Token: $fcmToken');
      return fcmToken;
    } catch (e) {
      debugPrint('FCM getToken error: $e');
      return null;
    }
  }

  static Future<void> _waitForApnsTokenIfNeeded(
    FirebaseMessaging messaging,
  ) async {
    if (!Platform.isIOS) return;

    String? apnsToken = await messaging.getAPNSToken();
    for (var i = 0; i < 3 && apnsToken == null; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      apnsToken = await messaging.getAPNSToken();
    }
    debugPrint('APNS Token: $apnsToken');
  }

  static Future<void> initialize(GlobalKey<NavigatorState> navKey) async {
    final messaging = FirebaseMessaging.instance;

    await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (Platform.isIOS) {
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    }

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint(
        'Foreground notification: ${message.notification?.title} - ${message.notification?.body}',
      );
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _handleNotificationClick(navKey);
    });

    final initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationClick(navKey);
    }

    messaging.onTokenRefresh.listen((token) async {
      debugPrint('FCM token refreshed: $token');
      final userId = await UserStorage.getUserId();
      if (userId != null) {
        await syncTokenWithServer(userId, token);
      }
    });
  }

  static Future<void> syncTokenWithServer(
    String userId, [
    String? token,
  ]) async {
    token ??= await getToken();
    if (token == null || token.isEmpty) return;

    final res = await ApiService.updateFcmToken(userId, token);
    debugPrint('FCM token sync: ${res["message"] ?? res}');
  }

  static Future<void> _handleNotificationClick(
    GlobalKey<NavigatorState> navKey,
  ) async {
    await Future.delayed(const Duration(milliseconds: 500));

    final userId = await UserStorage.getUserId();
    final userName = await UserStorage.getUserName();

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
