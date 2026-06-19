import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/user_storage.dart';
import 'card_home.dart';
import '../services/fcm_service.dart';

const _kCardWhite = Color(0xFFFFFFFF);
const _kHint = Color(0xFFADB5C7);
const _kBorder = Color(0xFF00D9FF);
const _kText = Color(0xFFFFFFFF);
const _kpur = Color(0xFF000000);

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() =>
      _SignupScreenState();
}

class _SignupScreenState
    extends State<SignupScreen> {

  final signupName =
  TextEditingController();

  final signupEmail =
  TextEditingController();

  final signupPassword =
  TextEditingController();

  final signupConfirmPassword =
  TextEditingController();

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

      ScaffoldMessenger.of(context)
          .showSnackBar(
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

    if (signupPassword.text !=
        signupConfirmPassword.text) {

      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          backgroundColor: Colors.black,
          content: Text(
            "Passwords do not match",
            style: TextStyle(
              color: Color(0xFF00D9FF),
            ),
          ),
        ),
      );

      return;
    }

    setState(() => signupLoading = true);

    try {

      String? token =
      await FCMService.getToken();

      final res = await ApiService.signup(
        signupName.text,
        signupEmail.text,
        signupPassword.text,
        signupConfirmPassword.text,
        token,
      );

      debugPrint("SIGNUP RESPONSE: $res");

      if (!mounted) return;

      if (res["success"] == true) {

        final userId =
        res["userId"]?.toString();

        if (userId == null) {
          throw Exception(
              "userId NULL after signup");
        }

        final userName =
        signupName.text.trim();

        await UserStorage.saveUserId(
          userId,
        );

        await UserStorage.saveUserName(
          userName,
        );

        if (!mounted) return;

        Navigator.of(context)
            .pushReplacement(
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
                  "Signup failed",
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
        setState(
                () => signupLoading = false);
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

        iconTheme:
        const IconThemeData(
          color: Color(0xFF00D9FF),
        ),

        leading: Padding(
          padding:
          const EdgeInsets.all(8.0),

          child: CircleAvatar(
            backgroundColor:
            Colors.transparent,

            child: Image.asset(
              "assets/images/logo.png",
            ),
          ),
        ),

        title: const Text(
          "Card Reminder",

          style: TextStyle(
            fontWeight:
            FontWeight.bold,
            fontSize: 18,
            color: Color(0xFF00D9FF),
          ),
        ),

        centerTitle: true,
      ),

      body: Column(
        children: [

          Container(

            width: double.infinity,

            decoration:
            BoxDecoration(

              color: Colors.black,

              borderRadius:
              BorderRadius.only(
                bottomLeft:
                Radius.circular(36),

                bottomRight:
                Radius.circular(36),
              ),
            ),

            padding:
            const EdgeInsets.fromLTRB(
              28,
              32,
              28,
              36,
            ),

            child: const Text(
              "Create Your Account",

              textAlign:
              TextAlign.center,

              style: TextStyle(
                color: Color(0xFF00D9FF),
                fontSize: 30,
                fontWeight:
                FontWeight.w800,
                height: 1.3,
              ),
            ),
          ),

          Expanded(

            child: SingleChildScrollView(

              padding:
              const EdgeInsets.fromLTRB(
                24,
                28,
                24,
                32,
              ),

              child: Column(

                crossAxisAlignment:
                CrossAxisAlignment
                    .start,

                children: [

                  const Text(
                    "Signup",

                    style: TextStyle(
                      fontSize: 22,
                      fontWeight:
                      FontWeight.w800,
                      color:
                      Color(0xFF00D9FF),
                    ),
                  ),

                  const SizedBox(
                      height: 20),

                  _SField(
                    controller: signupName,
                    hint: "Full Name",
                  ),

                  const SizedBox(
                      height: 12),

                  _SField(
                    controller:
                    signupEmail,

                    hint:
                    "Enter your email",

                    keyboardType:
                    TextInputType
                        .emailAddress,
                  ),

                  const SizedBox(
                      height: 12),

                  _SField(
                    controller:
                    signupPassword,

                    hint: "Password",

                    obscure: _obscure,

                    suffixIcon:
                    GestureDetector(

                      onTap: () {

                        setState(() {
                          _obscure =
                          !_obscure;
                        });
                      },

                      child: Icon(

                        _obscure

                            ? Icons
                            .visibility_off_outlined

                            : Icons
                            .visibility_outlined,

                        color: const Color(
                            0xFF00D9FF),

                        size: 20,
                      ),
                    ),
                  ),

                  const SizedBox(
                      height: 12),

                  _SField(
                    controller:
                    signupConfirmPassword,

                    hint:
                    "Confirm Password",

                    obscure:
                    _confirmObscure,

                    suffixIcon:
                    GestureDetector(

                      onTap: () {

                        setState(() {
                          _confirmObscure =
                          !_confirmObscure;
                        });
                      },

                      child: Icon(

                        _confirmObscure

                            ? Icons
                            .visibility_off_outlined

                            : Icons
                            .visibility_outlined,

                        color: const Color(
                            0xFF00D9FF),

                        size: 20,
                      ),
                    ),
                  ),

                  const SizedBox(
                      height: 28),

                  signupLoading

                      ? const Center(
                    child:
                    CircularProgressIndicator(
                      color: Color(
                          0xFF00D9FF),
                    ),
                  )

                      : SizedBox(

                    width:
                    double.infinity,

                    height: 52,

                    child:
                    ElevatedButton(

                      onPressed:
                      handleSignup,

                      style:
                      ElevatedButton
                          .styleFrom(

                        backgroundColor:
                        Colors.black,

                        foregroundColor:
                        const Color(
                            0xFF00D9FF),

                        elevation: 10,

                        shadowColor:
                        const Color(
                            0xFF00D9FF),

                        side:
                        const BorderSide(
                          color: Color(
                              0xFF00D9FF),
                          width: 2,
                        ),

                        shape:
                        RoundedRectangleBorder(

                          borderRadius:
                          BorderRadius
                              .circular(
                            14,
                          ),
                        ),
                      ),

                      child: const Text(
                        "Signup",

                        style: TextStyle(
                          fontSize: 16,
                          fontWeight:
                          FontWeight
                              .w700,

                          letterSpacing:
                          0.3,

                          color: Color(
                              0xFF00D9FF),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(
                      height: 28),

                  Center(

                    child:
                    GestureDetector(

                      onTap: () {
                        Navigator.pop(
                            context);
                      },

                      child: RichText(

                        text:
                        const TextSpan(

                          text:
                          "Already have an account? ",

                          style: TextStyle(
                            color: _kHint,
                            fontSize: 14,
                          ),

                          children: [

                            TextSpan(
                              text: "Login",

                              style:
                              TextStyle(
                                color: Color(
                                    0xFF00D9FF),

                                fontWeight:
                                FontWeight
                                    .bold,
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

class _SField extends StatelessWidget {

  final TextEditingController
  controller;

  final String hint;

  final TextInputType?
  keyboardType;

  final bool obscure;

  final Widget? suffixIcon;

  const _SField({
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
          color: _kHint,
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
          BorderRadius.circular(
            12,
          ),

          borderSide:
          const BorderSide(
            color: Color(0xFF00D9FF),
            width: 2,
          ),
        ),

        enabledBorder:
        OutlineInputBorder(

          borderRadius:
          BorderRadius.circular(
            12,
          ),

          borderSide:
          const BorderSide(
            color: Color(0xFF00D9FF),
            width: 2,
          ),
        ),

        focusedBorder:
        OutlineInputBorder(

          borderRadius:
          BorderRadius.circular(
            12,
          ),

          borderSide:
          const BorderSide(
            color: Color(0xFF7DF9FF),
            width: 2.5,
          ),
        ),
      ),
    );
  }
}