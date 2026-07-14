import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../screens/view_reminder_page.dart';
import 'api_service.dart';
import 'user_storage.dart';

const String _paymentReminderChannelId = 'payment_reminder';
const String _paymentReminderChannelName = 'Payment Reminders';

/// Top-level background handler — must be a top-level or static function.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint(
    'Background notification: ${message.notification?.title} - ${message.notification?.body}',
  );
}

class FCMService {
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static bool _localNotificationsReady = false;

  /// Returns an FCM token when available. Returns null if notifications
  /// are unavailable (simulator, denied permission, Firebase not ready).
  static Future<String?> getToken() async {
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      debugPrint('FCM permission status: ${settings.authorizationStatus}');
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

  static Future<void> _initLocalNotifications(
    GlobalKey<NavigatorState> navKey,
  ) async {
    const androidSettings = AndroidInitializationSettings('@mipmap/launcher_icon');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (_) {
        _handleNotificationClick(navKey);
      },
    );

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _paymentReminderChannelId,
        _paymentReminderChannelName,
        description: 'Credit card payment reminder notifications',
        importance: Importance.high,
      ),
    );

    _localNotificationsReady = true;
  }

  static Future<void> _showForegroundNotification(RemoteMessage message) async {
    if (!_localNotificationsReady) return;

    final notification = message.notification;
    final title = notification?.title ??
        message.data['title']?.toString() ??
        'Q Fin';
    final body = notification?.body ??
        message.data['body']?.toString() ??
        message.data['message']?.toString() ??
        '';

    if (body.isEmpty && notification == null) return;

    const androidDetails = AndroidNotificationDetails(
      _paymentReminderChannelId,
      _paymentReminderChannelName,
      channelDescription: 'Credit card payment reminder notifications',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/launcher_icon',
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    await _localNotifications.show(
      id: message.hashCode,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      ),
      payload: message.data['type']?.toString(),
    );
  }

  static Future<void> initialize(GlobalKey<NavigatorState> navKey) async {
    final messaging = FirebaseMessaging.instance;

    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint('FCM permission status: ${settings.authorizationStatus}');

    await _initLocalNotifications(navKey);

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
      // Android does not auto-display FCM banners while foregrounded.
      // iOS uses setForegroundNotificationPresentationOptions above; still
      // show via local notifications on Android so the user sees a banner.
      if (Platform.isAndroid) {
        _showForegroundNotification(message);
      }
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

    const maxAttempts = 3;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final res = await ApiService.updateFcmToken(userId, token);
      final success = res['success'] == true;
      debugPrint(
        'FCM token sync (attempt $attempt/$maxAttempts): ${res["message"] ?? res}',
      );
      if (success) return;

      final statusCode = res['statusCode'];
      if (statusCode == 404 || statusCode == 400) {
        debugPrint('FCM token sync: clearing stale saved user session');
        await UserStorage.clearUserId();
        return;
      }

      if (attempt < maxAttempts) {
        await Future.delayed(Duration(milliseconds: 500 * attempt));
      }
    }
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
