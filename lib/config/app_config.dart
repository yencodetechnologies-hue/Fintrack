import 'package:flutter/material.dart';

class AppConfig {
  static const String baseUrl = "https://fintrack.yencodetechnologies.in";

  static const String authBase = "$baseUrl/api/auth";
  static const String signup = "$authBase/signup";
  static const String login = "$authBase/login";

  static const String checkEmail = "$authBase/check-email";

  static const String forgotPassword = "$authBase/forgot-password";
  static const String verifyOtp = "$authBase/verify-otp";
  static const String resetPassword = "$authBase/reset-password";
  static const String updateFcmToken = "$authBase/update-fcm-token";

  static const String cards = "$baseUrl/api/cards";

  static const String reminders = "$baseUrl/reminder";

  static const String reminderAdd = "$baseUrl/reminder/add";
  static const String reminderStatus = "$baseUrl/reminder/status";
  static const String lend = "$baseUrl/api/lend";
  static const String liability = "$baseUrl/api/liability";
  static const String cron = "$baseUrl/api/cron/notification-logs";
  static const String trips = "$baseUrl/api/trips";
  static const String vehicles = "$baseUrl/api/vehicles";
  static const String companyExpense = "$baseUrl/api/company-expense";
  static const String ledger = "$baseUrl/api/ledger";


  static const String emailBase = "$baseUrl/api/email";
  static const String emailConnect = "$emailBase/connect";
  static const String emailConnectUrl = "$emailBase/connect-url";
  static const String emailStatus = "$emailBase/status";
  static const String emailSync = "$emailBase/sync";
  static const String emailSuggestions = "$emailBase/suggestions";
  static const String emailApply = "$emailBase/apply";
  static const String emailDisconnect = "$emailBase/disconnect";

  // Platform identifiers (must match Firebase + native project config)
  static const String iosBundleId = "com.yencode.fintracks";
  static const String androidPackageName = "com.yencode.fintrack";

  // Web OAuth client ID from Google Cloud Console (used by google_sign_in)
  static const String googleWebClientId =
      "1097214336094-h00iafanm4hk5g19k08lmnt4rr43pe7k.apps.googleusercontent.com";
  // App Text Branding
  static const String appName = "Q Fin";
  static const String appSubtitle = "Your secure smart wallet assistant";
  static const String signupSubtitle = "Join Fintrack for smart card management";

  // App Theme Colors
  static const Color background = Color(0xFF020617);
  static const Color primaryTeal = Color(0xFF00D9FF);
  static const Color hintColor = Color(0xFF94A3B8);
  static const Color darkSlate = Color(0xFF0F172A);

  // Gradient Colors
  static const Color gradientStart = Color(0xFF00F2FE);
  static const Color gradientEnd = Color(0xFF3B82F6);
}
