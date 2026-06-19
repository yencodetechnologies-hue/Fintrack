import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'reset_password_page.dart';
import 'package:card/config/app_config.dart';

const _kpur    = Color(0xFF4A148C);
const _kBlack  = Color(0xFF000000);
const _kWhite  = Color(0xFFFFFFFF);
const _kHint   = Color(0xFFADB5C7);
const _kBorder = Color(0xFFE4E9F2);
const _kText   = Color(0xFF1A1A2E);

class OtpPage extends StatefulWidget {
  final String email;
  const OtpPage({super.key, required this.email});

  @override
  State<OtpPage> createState() => _OtpPageState();
}

class _OtpPageState extends State<OtpPage> {
  final otpController = TextEditingController();
  bool loading = false;


  Future<void> verifyOtp() async {
    setState(() => loading = true);
    try {
      final res = await http.post(
        Uri.parse(AppConfig.verifyOtp),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "email": widget.email,
          "otp": otpController.text.trim(),
        }),
      );
      final data = jsonDecode(res.body);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(data["message"])));
      if (res.statusCode == 200) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ResetPasswordPage(email: widget.email),
          ),
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
          "Verify OTP",
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
                "assets/images/EnterOTP.png",
                height: 220,
                fit: BoxFit.contain,
              ),
            ),

            const SizedBox(height: 20),


            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Text(
                "OTP sent to ${widget.email}\nEnter the code below to verify.",
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _kHint,
                  fontSize: 13,
                  height: 1.6,
                ),
              ),
            ),

            const SizedBox(height: 28),


            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: TextField(
                controller: otpController,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 6,
                style: const TextStyle(
                  color: _kText,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 8,
                ),
                decoration: InputDecoration(
                  hintText: "• • • • • •",
                  hintStyle: TextStyle(
                    color: _kHint.withOpacity(0.6),
                    fontSize: 20,
                    letterSpacing: 8,
                  ),
                  counterText: "",
                  filled: true,
                  fillColor: _kWhite,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 18),
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
                    borderSide:
                    const BorderSide(color: _kpur, width: 1.5),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 28),


            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: loading
                  ? const Center(
                  child: CircularProgressIndicator(color: _kBlack))
                  : SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: verifyOtp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kBlack,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    "Verify OTP",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),


            TextButton(
              onPressed: () {},
              child: const Text(
                "Didn't receive OTP? Resend",
                style: TextStyle(
                  color: _kBlack,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
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