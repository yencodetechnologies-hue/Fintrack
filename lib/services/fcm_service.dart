import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../firebase_options.dart';
import '../screens/view_reminder_page.dart';
import '../screens/ledger/ledger_home_screen.dart';
import 'api_service.dart';
import 'ledger_events.dart';
import 'user_storage.dart';

const String _paymentReminderChannelId = 'payment_reminder';
const String _paymentReminderChannelName = 'Payment Reminders';
// company expense tracker updates (expenses, approvals, vouchers, loans…) — separate so either can be muted
const String _companyChannelId = 'company_updates';
const String _companyChannelName = 'Company updates';

/// Top-level background handler — must be a top-level or static function.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
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

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('FCM permission denied by user');
        return null;
      }

      await _waitForApnsTokenIfNeeded(messaging);

      for (var attempt = 1; attempt <= 5; attempt++) {
        final fcmToken = await messaging.getToken();
        if (fcmToken != null && fcmToken.isNotEmpty) {
          debugPrint('FCM Token: $fcmToken');
          return fcmToken;
        }

        debugPrint('FCM getToken attempt $attempt returned empty token');
        if (attempt < 5) {
          await Future.delayed(Duration(milliseconds: 800 * attempt));
          await _waitForApnsTokenIfNeeded(messaging);
        }
      }

      return null;
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
    for (var i = 0; i < 20 && apnsToken == null; i++) {
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
      onDidReceiveNotificationResponse: (response) {
        _handleNotificationClick(navKey, _decodePayload(response.payload));
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
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _companyChannelId,
        _companyChannelName,
        description: 'Expenses, approvals, payments, vouchers and loans in your companies',
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

    final company = message.data['type'] == 'ledger';
    final androidDetails = AndroidNotificationDetails(
      company ? _companyChannelId : _paymentReminderChannelId,
      company ? _companyChannelName : _paymentReminderChannelName,
      channelDescription: company ? 'Expenses, approvals, payments, vouchers and loans in your companies' : 'Credit card payment reminder notifications',
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
      notificationDetails: NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      ),
      // the whole data map, so a tap can open the right company
      payload: jsonEncode(message.data),
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
      if (message.data["type"] == "ledger") notifyLedgerChanged();
      // Android does not auto-display FCM banners while foregrounded.
      if (Platform.isAndroid) {
        _showForegroundNotification(message);
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _handleNotificationClick(navKey, message.data);
    });

    final initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationClick(navKey, initialMessage.data);
    }

    messaging.onTokenRefresh.listen((token) async {
      debugPrint('FCM token refreshed: $token');
      final userId = await UserStorage.getUserId();
      if (userId != null) {
        await syncTokenWithServer(userId, token);
      }
    });

    final userId = await UserStorage.getUserId();
    if (userId != null) {
      await syncTokenWithServer(userId);
    }
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

  static Map<String, dynamic> _decodePayload(String? payload) {
    if (payload == null || payload.isEmpty) return const {};
    try {
      final decoded = jsonDecode(payload);
      return decoded is Map<String, dynamic> ? decoded : const {};
    } catch (_) {
      return {"type": payload}; // older payloads carried only the type
    }
  }

  /// Company notifications (type "ledger") open that company's workspace; everything else opens the card
  /// reminders, as before.
  static Future<void> _handleNotificationClick(
    GlobalKey<NavigatorState> navKey, [
    Map<String, dynamic> data = const {},
  ]) async {
    await Future.delayed(const Duration(milliseconds: 500));

    final userId = await UserStorage.getUserId();
    final userName = await UserStorage.getUserName();
    if (userId == null) return;

    final companyId = data['companyId']?.toString() ?? '';
    if (data['type'] == 'ledger' && companyId.isNotEmpty) {
      notifyLedgerChanged();
      navKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => LedgerHomeScreen(
            userId: userId,
            userName: userName ?? "User",
            companies: const [],
            initialCompanyId: companyId,
          ),
        ),
      );
      return;
    }

    {
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
