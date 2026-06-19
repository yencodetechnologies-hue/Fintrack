import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'card_home.dart';
import '../services/fcm_service.dart';
import 'forgot_password_page.dart';
import 'signup_screen.dart';

const kCardWhite = Color(0xFFFFFFFF);
const kText = Color(0xFFFFFFFF);
const kHint = Color(0xFFADB5C7);
const kBorder = Color(0xFF00D9FF);
const kpur = Color(0xFF000000);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final loginEmail = TextEditingController();
  final loginPassword = TextEditingController();

  bool loginLoading = false;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    checkLogin();
  }

  @override
  void dispose() {
    loginEmail.dispose();
    loginPassword.dispose();
    super.dispose();
  }

  Future<void> checkLogin() async {
    String? userId = await UserStorage.getUserId();
    String? userName = await UserStorage.getUserName();

    if (userId != null) {
      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => CardHome(
            userId: userId,
            userName: userName ?? "User",
          ),
        ),
      );
    }
  }

  Future<void> handleLogin() async {
    if (loginEmail.text.isEmpty ||
        loginPassword.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.black,
          content: Text(
            "Enter all fields",
            style: TextStyle(
              color: Color(0xFF00D9FF),
            ),
          ),
        ),
      );

      return;
    }

    setState(() => loginLoading = true);

    try {
      String? token = await FCMService.getToken();

      final res = await ApiService.login(
        loginEmail.text,
        loginPassword.text,
        token,
      );

      if (!mounted) return;

      if (res["success"] == true) {
        final userId =
        res["user"]["id"]?.toString();

        if (userId == null) {
          throw Exception("❌ userId is NULL");
        }

        final userName =
            res["user"]["name"]?.toString() ??
                "User";

        await UserStorage.saveUserId(userId);

        await UserStorage.saveUserName(
          userName,
        );

        if (!mounted) return;

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => CardHome(
              userId: userId,
              userName: userName,
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(
          SnackBar(
            backgroundColor: Colors.black,
            content: Text(
              res["message"] ??
                  "Login failed",
              style: const TextStyle(
                color: Color(0xFF00D9FF),
              ),
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          backgroundColor: Colors.black,
          content: Text(
            "Error: $e",
            style: const TextStyle(
              color: Color(0xFF00D9FF),
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => loginLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,

      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.black,

        leading: Padding(
          padding: const EdgeInsets.all(8.0),

          child: CircleAvatar(
            backgroundColor: Colors.transparent,

            child: Image.asset(
              "assets/images/logo.png",
            ),
          ),
        ),

        title: const Text(
          "Card Reminder",

          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 20,
            color: Color(0xFF00D9FF),
          ),
        ),

        centerTitle: true,
      ),

      body: Column(
        children: [
          Container(
            width: double.infinity,

            decoration: BoxDecoration(
              color: Colors.black,

              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(36),
                bottomRight: Radius.circular(36),
              ),
            ),

            padding: const EdgeInsets.fromLTRB(
              28,
              32,
              28,
              36,
            ),

            child: const Center(
              child: Text(
                "Sign In To Continue",

                textAlign: TextAlign.center,

                style: TextStyle(
                  color: Color(0xFF00D9FF),
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  height: 1.3,
                ),
              ),
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                24,
                28,
                24,
                32,
              ),

              child: Column(
                crossAxisAlignment:
                CrossAxisAlignment.start,

                children: [
                  const Text(
                    "Login",

                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF00D9FF),
                    ),
                  ),

                  const SizedBox(height: 20),

                  _FormField(
                    controller: loginEmail,
                    hint: "Enter your email",
                    keyboardType:
                    TextInputType.emailAddress,
                  ),

                  const SizedBox(height: 15),

                  _FormField(
                    controller: loginPassword,
                    hint: "Enter your password",
                    obscure: _obscure,

                    suffixIcon: GestureDetector(
                      onTap: () {
                        setState(() {
                          _obscure = !_obscure;
                        });
                      },

                      child: Icon(
                        _obscure
                            ? Icons
                            .visibility_off_outlined
                            : Icons
                            .visibility_outlined,

                        color: const Color(0xFF00D9FF),
                        size: 20,
                      ),
                    ),
                  ),

                  Align(
                    alignment: Alignment.centerRight,

                    child: TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,

                          MaterialPageRoute(
                            builder: (_) =>
                            const ForgotPasswordPage(),
                          ),
                        );
                      },

                      child: const Text(
                        "Forgot Password?",

                        style: TextStyle(
                          color: Color(0xFF00D9FF),
                          fontWeight:
                          FontWeight.w600,
                        ),
                      ),
                    ),
                  ),

                  loginLoading
                      ? const Center(
                    child:
                    CircularProgressIndicator(
                      color:
                      Color(0xFF00D9FF),
                    ),
                  )
                      : _PurButton(
                    label: "Login",
                    onTap: handleLogin,
                  ),

                  const SizedBox(height: 28),

                  Center(
                    child: GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,

                          MaterialPageRoute(
                            builder: (_) =>
                            const SignupScreen(),
                          ),
                        );
                      },

                      child: RichText(
                        text: const TextSpan(
                          text:
                          "Don't have an account? ",

                          style: TextStyle(
                            color: kHint,
                            fontSize: 14,
                          ),

                          children: [
                            TextSpan(
                              text: "Signup",

                              style: TextStyle(
                                color:
                                Color(0xFF00D9FF),
                                fontWeight:
                                FontWeight.bold,
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
        ],
      ),
    );
  }
}

class _FormField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final TextInputType? keyboardType;
  final bool obscure;
  final Widget? suffixIcon;

  const _FormField({
    required this.controller,
    required this.hint,
    this.keyboardType,
    this.obscure = false,
    this.suffixIcon,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,

      style: const TextStyle(
        color: Colors.white,
        fontSize: 14,
      ),

      decoration: InputDecoration(
        hintText: hint,

        hintStyle: const TextStyle(
          color: kHint,
          fontSize: 14,
        ),

        suffixIcon: suffixIcon,

        filled: true,
        fillColor: Colors.black,

        contentPadding:
        const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),

        border: OutlineInputBorder(
          borderRadius:
          BorderRadius.circular(12),

          borderSide: const BorderSide(
            color: Color(0xFF00D9FF),
            width: 2,
          ),
        ),

        enabledBorder: OutlineInputBorder(
          borderRadius:
          BorderRadius.circular(12),

          borderSide: const BorderSide(
            color: Color(0xFF00D9FF),
            width: 2,
          ),
        ),

        focusedBorder: OutlineInputBorder(
          borderRadius:
          BorderRadius.circular(12),

          borderSide: const BorderSide(
            color: Color(0xFF7DF9FF),
            width: 2.5,
          ),
        ),
      ),
    );
  }
}

class _PurButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _PurButton({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 55,

      child: ElevatedButton(
        onPressed: onTap,

        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.black,
          foregroundColor:
          const Color(0xFF00D9FF),

          elevation: 10,

          shadowColor:
          const Color(0xFF00D9FF),

          side: const BorderSide(
            color: Color(0xFF00D9FF),
            width: 2,
          ),

          shape: RoundedRectangleBorder(
            borderRadius:
            BorderRadius.circular(14),
          ),
        ),

        child: const Text(
          "Login",

          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
            color: Color(0xFF00D9FF),
          ),
        ),
      ),
    );
  }
}