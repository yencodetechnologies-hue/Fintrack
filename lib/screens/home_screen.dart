import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../config/app_config.dart';
import '../services/api_service.dart';
import '../services/user_storage.dart';
import 'main_navigation_screen.dart';
import '../services/fcm_service.dart';
import 'forgot_password_page.dart';

class HomeScreen extends StatefulWidget {
  final bool initialIsSignup;
  const HomeScreen({super.key, this.initialIsSignup = false});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late bool _isSignInTab;

  // Sign In Controllers
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  // Sign Up Controllers
  final _signupNameController = TextEditingController();
  final _signupEmailController = TextEditingController();
  final _signupPasswordController = TextEditingController();
  final _signupConfirmPasswordController = TextEditingController();

  bool _obscurePassword = true;
  final bool _obscureSignupPassword = true;
  final bool _obscureConfirmPassword = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _isSignInTab = !widget.initialIsSignup;
    checkLogin();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _signupNameController.dispose();
    _signupEmailController.dispose();
    _signupPasswordController.dispose();
    _signupConfirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> checkLogin() async {
    final userId = await UserStorage.getUserId();
    final userName = await UserStorage.getUserName();

    if (userId == null) return;

    final session = await ApiService.validateSession(userId);
    if (session['success'] != true) {
      await UserStorage.clearUserId();
      return;
    }

    unawaited(FCMService.syncTokenWithServer(userId));

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => MainNavigationScreen(
          userId: userId,
          userName: userName ?? "User",
        ),
      ),
    );
  }

  Future<void> _handleLogin() async {
    if (_emailController.text.trim().isEmpty || _passwordController.text.isEmpty) {
      _showSnackBar("Please fill in all fields");
      return;
    }

    setState(() => _isLoading = true);

    try {
      final token = await FCMService.getToken();
      final res = await ApiService.login(
        _emailController.text.trim(),
        _passwordController.text,
        token,
      );

      if (!mounted) return;
      await _finishLogin(res);
    } catch (e) {
      if (!mounted) return;
      _showSnackBar("Error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _finishLogin(Map<String, dynamic> res) async {
    {
      if (res["success"] == true) {
        final userId = UserStorage.parseMongoId(res["user"]?["id"]);
        if (userId == null) throw Exception("userId is NULL");

        final userName = res["user"]["name"]?.toString() ?? "User";
        final userEmail = res["user"]["email"]?.toString() ?? "";

        await UserStorage.saveUserId(userId);
        await UserStorage.saveUserName(userName);
        await UserStorage.saveUserEmail(userEmail);

        if (!mounted) return;

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => MainNavigationScreen(
              userId: userId,
              userName: userName,
            ),
          ),
        );
      } else {
        _showSnackBar(res["message"] ?? "Login failed");
      }
    }
  }

  Future<void> _openEmailCodeLogin() async {
    final emailCtrl = TextEditingController(text: _emailController.text.trim());
    final codeCtrl = TextEditingController();
    bool codeSent = false;
    bool busy = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text("Sign in with email code", style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: emailCtrl,
                enabled: !codeSent,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: "Email address"),
              ),
              if (codeSent)
                TextField(
                  controller: codeCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: const InputDecoration(labelText: "6-digit code from your email"),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: busy ? null : () => Navigator.pop(ctx), child: const Text("Cancel")),
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      setDialog(() => busy = true);
                      if (!codeSent) {
                        final res = await ApiService.requestLoginOtp(emailCtrl.text.trim());
                        if (!ctx.mounted) return;
                        setDialog(() {
                          busy = false;
                          codeSent = res["success"] == true;
                        });
                        _showSnackBar(res["message"]?.toString() ?? "Could not send code");
                        return;
                      }
                      final token = await FCMService.getToken();
                      final res = await ApiService.verifyLoginOtp(emailCtrl.text.trim(), codeCtrl.text.trim(), token);
                      if (!ctx.mounted) return;
                      setDialog(() => busy = false);
                      if (res["success"] == true) Navigator.pop(ctx);
                      if (!mounted) return;
                      await _finishLogin(res);
                    },
              child: Text(codeSent ? "Sign in" : "Send code"),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleSignup() async {
    if (_signupNameController.text.trim().isEmpty ||
        _signupEmailController.text.trim().isEmpty ||
        _signupPasswordController.text.isEmpty ||
        _signupConfirmPasswordController.text.isEmpty) {
      _showSnackBar("Please fill in all fields");
      return;
    }

    if (_signupPasswordController.text != _signupConfirmPasswordController.text) {
      _showSnackBar("Passwords do not match");
      return;
    }

    setState(() => _isLoading = true);

    try {
      final token = await FCMService.getToken();
      final res = await ApiService.signup(
        _signupNameController.text.trim(),
        _signupEmailController.text.trim(),
        _signupPasswordController.text,
        _signupConfirmPasswordController.text,
        token,
      );

      if (!mounted) return;

      if (res["success"] == true) {
        final userId = UserStorage.parseMongoId(res["userId"]);
        if (userId == null) throw Exception("userId NULL after signup");

        final userName = _signupNameController.text.trim();
        final userEmail = _signupEmailController.text.trim();

        await UserStorage.saveUserId(userId);
        await UserStorage.saveUserName(userName);
        await UserStorage.saveUserEmail(userEmail);

        if (!mounted) return;

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => MainNavigationScreen(
              userId: userId,
              userName: userName,
            ),
          ),
        );
      } else {
        _showSnackBar(res["message"] ?? "Signup failed");
      }
    } catch (e) {
      if (!mounted) return;
      _showSnackBar("Error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF0F172A),
        behavior: SnackBarBehavior.floating,
        content: Text(
          msg,
          style: GoogleFonts.karla(color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const Color forestDark = Color(0xFF113F3D); // Deep Forest Green Header
    const Color creamSheet = Color(0xFFF6F4EB); // Vintage Cream Sheet
    const Color darkPill = Color(0xFF1E293B); // Dark Pill Active Tab
    const Color terracotta = Color(0xFFB8452D); // Terracotta Primary Button Accent
    const Color goldText = Color(0xFFD4AF37); // Vintage Muted Gold Accent
    const Color darkText = Color(0xFF1E293B);
    const Color mutedText = Color(0xFF6B7280);

    return Scaffold(
      backgroundColor: forestDark,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // 1. Vintage Editorial Top Header Banner
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Column(
                children: [
                  // Circular Monogram Logo with Golden Dotted Border Ring
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: goldText.withValues(alpha: 0.6),
                        width: 1.5,
                      ),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.05),
                        border: Border.all(
                          color: goldText.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          "Q",
                          style: GoogleFonts.inter(
                            fontSize: 32,
                            fontWeight: FontWeight.w500,
                            fontStyle: FontStyle.italic,
                            color: goldText,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "Welcome back to ${AppConfig.appName}",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 26,
                      fontWeight: FontWeight.w500,
                      fontStyle: FontStyle.italic,
                      color: Colors.white,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    AppConfig.appSubtitle.toUpperCase(),
                    style: GoogleFonts.ibmPlexMono(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: goldText.withValues(alpha: 0.9),
                      letterSpacing: 2.0,
                    ),
                  ),
                ],
              ),
            ),

            // 2. Vintage Cream Bottom Sheet Canvas
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: creamSheet,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(32),
                    topRight: Radius.circular(32),
                  ),
                ),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  child: Column(
                    children: [
                      // Top Sheet Handle Bar
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Segmented Vintage Capsule Switcher (Sign In vs Open Account)
                      Container(
                        height: 50,
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(25),
                          border: Border.all(color: darkText.withValues(alpha: 0.4), width: 1.2),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() => _isSignInTab = true),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: _isSignInTab ? darkPill : Colors.transparent,
                                    borderRadius: BorderRadius.circular(22),
                                  ),
                                  child: Center(
                                    child: Text(
                                      "Sign in",
                                      style: GoogleFonts.outfit(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: _isSignInTab ? Colors.white : darkText,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() => _isSignInTab = false),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: !_isSignInTab ? darkPill : Colors.transparent,
                                    borderRadius: BorderRadius.circular(22),
                                  ),
                                  child: Center(
                                    child: Text(
                                      "Open account",
                                      style: GoogleFonts.outfit(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: !_isSignInTab ? Colors.white : darkText,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Form Fields (Sign In / Sign Up)
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: _isSignInTab
                            ? _buildVintageSignInForm(darkText, mutedText, terracotta)
                            : _buildVintageSignUpForm(darkText, mutedText, terracotta),
                      ),

                      const SizedBox(height: 24),

                      // Footer Navigation Link
                      GestureDetector(
                        onTap: () => setState(() => _isSignInTab = !_isSignInTab),
                        child: RichText(
                          text: TextSpan(
                            style: GoogleFonts.inter(fontSize: 14, color: mutedText),
                            children: [
                              TextSpan(
                                text: _isSignInTab ? "New to ${AppConfig.appName}? " : "Already have an account? ",
                              ),
                              TextSpan(
                                text: _isSignInTab ? "Open an account" : "Sign in",
                                style: GoogleFonts.inter(
                                  color: darkText,
                                  fontWeight: FontWeight.bold,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVintageSignInForm(Color darkText, Color mutedText, Color terracotta) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildVintageInput(
          label: "EMAIL ADDRESS",
          controller: _emailController,
          hint: "you@company.com",
          icon: Icons.alternate_email_rounded,
          type: TextInputType.emailAddress,
          darkText: darkText,
          mutedText: mutedText,
        ),
        const SizedBox(height: 16),
        _buildVintageInput(
          label: "PASSWORD",
          controller: _passwordController,
          hint: "••••••••••••",
          icon: Icons.lock_outline_rounded,
          isObscure: _obscurePassword,
          darkText: darkText,
          mutedText: mutedText,
          suffix: GestureDetector(
            onTap: () => setState(() => _obscurePassword = !_obscurePassword),
            child: Text(
              _obscurePassword ? "SHOW" : "HIDE",
              style: GoogleFonts.ibmPlexMono(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: mutedText,
                letterSpacing: 1.0,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerRight,
          child: GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ForgotPasswordPage()),
              );
            },
            child: Text(
              "Forgot password?",
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: terracotta,
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        _buildTerracottaButton(
          label: "Sign in",
          isLoading: _isLoading,
          onTap: _handleLogin,
          terracotta: terracotta,
        ),
        const SizedBox(height: 10),
        Center(
          child: TextButton(
            onPressed: _isLoading ? null : _openEmailCodeLogin,
            child: Text(
              "Sign in with email code instead",
              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: terracotta),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVintageSignUpForm(Color darkText, Color mutedText, Color terracotta) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildVintageInput(
          label: "FULL NAME",
          controller: _signupNameController,
          hint: "John Doe",
          icon: Icons.person_outline_rounded,
          darkText: darkText,
          mutedText: mutedText,
        ),
        const SizedBox(height: 14),
        _buildVintageInput(
          label: "EMAIL ADDRESS",
          controller: _signupEmailController,
          hint: "you@company.com",
          icon: Icons.alternate_email_rounded,
          type: TextInputType.emailAddress,
          darkText: darkText,
          mutedText: mutedText,
        ),
        const SizedBox(height: 14),
        _buildVintageInput(
          label: "PASSWORD",
          controller: _signupPasswordController,
          hint: "••••••••••••",
          icon: Icons.lock_outline_rounded,
          isObscure: _obscureSignupPassword,
          darkText: darkText,
          mutedText: mutedText,
        ),
        const SizedBox(height: 14),
        _buildVintageInput(
          label: "CONFIRM PASSWORD",
          controller: _signupConfirmPasswordController,
          hint: "••••••••••••",
          icon: Icons.lock_outline_rounded,
          isObscure: _obscureConfirmPassword,
          darkText: darkText,
          mutedText: mutedText,
        ),
        const SizedBox(height: 24),
        _buildTerracottaButton(
          label: "Open account",
          isLoading: _isLoading,
          onTap: _handleSignup,
          terracotta: terracotta,
        ),
      ],
    );
  }

  Widget _buildVintageInput({
    required String label,
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required Color darkText,
    required Color mutedText,
    TextInputType type = TextInputType.text,
    bool isObscure = false,
    Widget? suffix,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.ibmPlexMono(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: mutedText,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          height: 52,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black.withValues(alpha: 0.12), width: 1),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: darkText.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: darkText, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: controller,
                  obscureText: isObscure,
                  keyboardType: type,
                  style: GoogleFonts.inter(
                    color: darkText,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: GoogleFonts.inter(
                      color: mutedText.withValues(alpha: 0.5),
                      fontSize: 14,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
              if (suffix != null) suffix,
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTerracottaButton({
    required String label,
    required bool isLoading,
    required VoidCallback onTap,
    required Color terracotta,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: isLoading ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: terracotta,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
              )
            : Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
      ),
    );
  }
}