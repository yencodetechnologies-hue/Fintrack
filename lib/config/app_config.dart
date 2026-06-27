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

  static const String cards = "$baseUrl/api/cards";

  static const String reminders = "$baseUrl/reminder";

  static const String reminderAdd = "$baseUrl/reminder/add";
  static const String reminderStatus = "$baseUrl/reminder/status";
  static const String lend = "$baseUrl/api/lend";
  static const String liability = "$baseUrl/api/liability";

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