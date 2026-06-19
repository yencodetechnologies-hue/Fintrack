import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'otp_page.dart';
import 'package:card/config/app_config.dart';

const _kpur    = Color(0xFF4A148C);
const _kBlack  = Color(0xFF000000);
const _kWhite  = Color(0xFFFFFFFF);
const _kHint   = Color(0xFFADB5C7);
const _kBorder = Color(0xFFE4E9F2);
const _kText   = Color(0xFF1A1A2E);

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final emailController = TextEditingController();
  bool loading = false;


  Future<bool> checkEmailExists(String email) async {
    final res = await http.post(
      Uri.parse(AppConfig.checkEmail),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"email": email}),
    );
    final data = jsonDecode(res.body);
    return data["exists"] == true;
  }

  Future<void> sendOtp() async {
    final email = emailController.text.trim();
    if (email.isEmpty || !email.contains("@")) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Enter valid email")),
      );
      return;
    }
    setState(() => loading = true);
    try {
      final res = await http.post(
        Uri.parse(AppConfig.forgotPassword),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"email": email}),
      );
      final data = jsonDecode(res.body);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(data["message"])));
      if (res.statusCode == 200) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => OtpPage(email: email)),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kWhite,


      appBar: AppBar(
        elevation: 0,
        backgroundColor: _kBlack,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          "Forgot Password",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
      ),

      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [

            const SizedBox(height: 24),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Image.asset(
                "assets/images/Forgot password.png",
                height: 220,
                fit: BoxFit.contain,
              ),
            ),

            const SizedBox(height: 24),


            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 28),
              child: Text(
                "Enter your registered email and we'll send you an OTP to reset your password.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _kHint,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ),

            const SizedBox(height: 28),


            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(color: _kText, fontSize: 14),
                decoration: InputDecoration(
                  hintText: "Enter your email",
                  hintStyle: const TextStyle(color: _kHint, fontSize: 14),
                  prefixIcon: const Icon(
                      Icons.mail_outline_rounded, color: _kHint),
                  filled: true,
                  fillColor: _kWhite,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _kBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _kBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _kpur, width: 1.5),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),


            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: loading
                  ? const Center(
                  child: CircularProgressIndicator(color: _kBlack))
                  : SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: sendOtp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kBlack,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    "Send OTP",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}