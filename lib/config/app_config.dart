class AppConfig {

  static const String baseUrl = "http://192.168.100.248:3009";


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
}