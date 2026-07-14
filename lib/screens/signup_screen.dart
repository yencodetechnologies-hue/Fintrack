import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../config/app_config.dart';
import '../services/api_service.dart';
import '../services/user_storage.dart';
import 'card_home.dart';
import '../services/fcm_service.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final signupName = TextEditingController();
  final signupEmail = TextEditingController();
  final signupPassword = TextEditingController();
  final signupConfirmPassword = TextEditingController();

  bool signupLoading = false;
  bool _obscure = true;
  bool _confirmObscure = true;

  @override
  void dispose() {
    signupName.dispose();
    signupEmail.dispose();
    signupPassword.dispose();
    signupConfirmPassword.dispose();
    super.dispose();
  }

  Future<void> handleSignup() async {
    if (signupName.text.isEmpty ||
        signupEmail.text.isEmpty ||
        signupPassword.text.isEmpty ||
        signupConfirmPassword.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppConfig.darkSlate,
          behavior: SnackBarBehavior.floating,
          content: Text(
            "Please fill in all fields",
            style: TextStyle(
              color: AppConfig.primaryTeal,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
      return;
    }

    if (signupPassword.text != signupConfirmPassword.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppConfig.darkSlate,
          behavior: SnackBarBehavior.floating,
          content: Text(
            "Passwords do not match",
            style: TextStyle(
              color: AppConfig.primaryTeal,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
      return;
    }

    setState(() => signupLoading = true);

    try {
      // FCM token is optional — signup must succeed even without notifications.
      final token = await FCMService.getToken();

      final res = await ApiService.signup(
        signupName.text.trim(),
        signupEmail.text.trim(),
        signupPassword.text,
        signupConfirmPassword.text,
        token,
      );

      debugPrint("SIGNUP RESPONSE: $res");

      if (!mounted) return;

      if (res["success"] == true) {
        final userId = res["userId"]?.toString();

        if (userId == null) {
          throw Exception("userId NULL after signup");
        }

        final userName = signupName.text.trim();
        final userEmail = signupEmail.text.trim();

        await UserStorage.saveUserId(userId);
        await UserStorage.saveUserName(userName);
        await UserStorage.saveUserEmail(userEmail);

        if (!mounted) return;

        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => CardHome(
              userId: userId,
              userName: userName,
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppConfig.darkSlate,
            behavior: SnackBarBehavior.floating,
            content: Text(
              res["message"] ?? "Signup failed",
              style: const TextStyle(
                color: AppConfig.primaryTeal,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppConfig.darkSlate,
          behavior: SnackBarBehavior.floating,
          content: Text(
            "Error: $e",
            style: const TextStyle(
              color: AppConfig.primaryTeal,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => signupLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConfig.background, // Deep space black
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(
          color: AppConfig.primaryTeal,
        ),
        title: const Text(
          AppConfig.appName,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          // Background soft glowing teal orb 1
          Positioned(
            top: -80,
            left: -80,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppConfig.primaryTeal.withOpacity(0.12),
              ),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 90, sigmaY: 90),
                child: Container(color: Colors.transparent),
              ),
            ),
          ),
          // Background soft glowing blue orb 2
          Positioned(
            bottom: -100,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppConfig.gradientEnd.withOpacity(0.08),
              ),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 80, sigmaY: 80),
                child: Container(color: Colors.transparent),
              ),
            ),
          ),

          // Main content
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Brand / Logo Section
                    Center(
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withOpacity(0.02),
                              border: Border.all(
                                color: AppConfig.primaryTeal.withOpacity(0.15),
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppConfig.primaryTeal.withOpacity(0.05),
                                  blurRadius: 15,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: Image.asset(
                              "assets/images/logo.png",
                              width: 56,
                              height: 56,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            AppConfig.appName,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            AppConfig.signupSubtitle,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 30),

                    // Glassmorphic Signup Form Card
                    Container(
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.08),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 30,
                            offset: const Offset(0, 15),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            "Sign Up",
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "Please fill in the details below to create an account",
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.4),
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Name Input
                          _CustomInputField(
                            controller: signupName,
                            hint: "Full Name",
                            icon: Icons.person_outline_rounded,
                            keyboardType: TextInputType.name,
                          ),
                          const SizedBox(height: 16),

                          // Email Input
                          _CustomInputField(
                            controller: signupEmail,
                            hint: "Email Address",
                            icon: Icons.alternate_email_rounded,
                            keyboardType: TextInputType.emailAddress,
                          ),
                          const SizedBox(height: 16),

                          // Password Input
                          _CustomInputField(
                            controller: signupPassword,
                            hint: "Password",
                            icon: Icons.lock_outline_rounded,
                            obscure: _obscure,
                            suffixIcon: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _obscure = !_obscure;
                                });
                              },
                              child: Icon(
                                _obscure
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                color: AppConfig.primaryTeal.withOpacity(0.6),
                                size: 20,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Confirm Password Input
                          _CustomInputField(
                            controller: signupConfirmPassword,
                            hint: "Confirm Password",
                            icon: Icons.lock_outline_rounded,
                            obscure: _confirmObscure,
                            suffixIcon: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _confirmObscure = !_confirmObscure;
                                });
                              },
                              child: Icon(
                                _confirmObscure
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                color: AppConfig.primaryTeal.withOpacity(0.6),
                                size: 20,
                              ),
                            ),
                          ),
                          const SizedBox(height: 28),

                          // Action Button
                          signupLoading
                              ? const Center(
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(vertical: 8),
                                    child: CircularProgressIndicator(
                                      color: AppConfig.primaryTeal,
                                    ),
                                  ),
                                )
                              : _GradientButton(
                                  label: "Sign Up",
                                  onTap: handleSignup,
                                ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 30),

                    // Login navigation link
                    Center(
                      child: GestureDetector(
                        onTap: () {
                          Navigator.pop(context);
                        },
                        child: RichText(
                          text: const TextSpan(
                            text: "Already have an account? ",
                            style: TextStyle(
                              color: AppConfig.hintColor,
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                            ),
                            children: [
                              TextSpan(
                                text: "Log In",
                                style: TextStyle(
                                  color: AppConfig.primaryTeal,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomInputField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final bool obscure;
  final Widget? suffixIcon;

  const _CustomInputField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.obscure = false,
    this.suffixIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
          width: 1.2,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboardType,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(
            color: AppConfig.hintColor,
            fontSize: 14,
            fontWeight: FontWeight.w400,
          ),
          prefixIcon: Icon(
            icon,
            color: AppConfig.primaryTeal.withOpacity(0.7),
            size: 20,
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 36,
            minHeight: 20,
          ),
          suffixIcon: suffixIcon,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }
}

class _GradientButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _GradientButton({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [
            AppConfig.gradientStart,
            AppConfig.gradientEnd,
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        boxShadow: [
          BoxShadow(
            color: AppConfig.gradientStart.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.3,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}