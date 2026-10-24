import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../config/app_config.dart';
import '../services/user_storage.dart';
import 'home_screen.dart';
import 'main_navigation_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  double _opacity = 0.0;
  double _scale = 0.85;

  static const Color _bg         = Color(0xFFF6F4EB); // Vintage Cream Sheet
  static const Color _forestDark = Color(0xFF113F3D); // QFin Deep Forest Green

  @override
  void initState() {
    super.initState();
    _startAnimation();
    startApp();
  }

  void _startAnimation() {
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) {
        setState(() {
          _opacity = 1.0;
          _scale = 1.0;
        });
      }
    });
  }

  Future<void> startApp() async {
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    final userId = await UserStorage.getUserId();
    final userName = await UserStorage.getUserName();

    if (!mounted) return;

    if (userId != null && userId.isNotEmpty) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => MainNavigationScreen(
            userId: userId,
            userName: userName ?? "User",
          ),
        ),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Center(
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 1200),
            curve: Curves.easeOutCubic,
            opacity: _opacity,
            child: AnimatedScale(
              duration: const Duration(milliseconds: 1200),
              curve: Curves.easeOutBack,
              scale: _scale,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Vintage QFin Emblem Container
                  // the Q Fin logo is a full green square: shown as a rounded tile, like the app icon
                  Container(
                    width: 120,
                    height: 120,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: _forestDark.withValues(alpha: 0.08),
                          blurRadius: 25,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Image.asset(
                      'assets/images/logo.png',
                    ),
                  ),
                  // the logo already says "Q FIN", so no app-name text under it
                  const SizedBox(height: 24),

                  // Subtitle
                  Text(
                    AppConfig.appSubtitle,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: Colors.black54,
                      fontWeight: FontWeight.w500,
                    ),
                  ),

                  const SizedBox(height: 44),

                  // Elegant Vintage Progress Indicator
                  const SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(_forestDark),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}