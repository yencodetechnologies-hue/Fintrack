import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:async';
import 'firebase_options.dart';
import 'services/fcm_service.dart';
import 'services/user_storage.dart';
import 'screens/splash_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  } catch (e, stack) {
    debugPrint('Firebase init failed: $e\n$stack');
  }

  // Show UI immediately — do not block first frame on push notification setup.
  runApp(const MyApp());

  WidgetsBinding.instance.addPostFrameCallback((_) {
    _initializePushServices();
  });
}

Future<void> _initializePushServices() async {
  try {
    await FCMService.initialize(navigatorKey);
    final userId = await UserStorage.getUserId();
    if (userId != null) {
      unawaited(FCMService.syncTokenWithServer(userId));
    }
  } catch (e, stack) {
    debugPrint('FCM init failed: $e\n$stack');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        textTheme: GoogleFonts.poppinsTextTheme(ThemeData.dark().textTheme),
      ),
      home: const SplashScreen(),
    );
  }
}
