import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../services/trip_service.dart';

class JoinTripScreen extends StatefulWidget {
  final String userId;
  final String userName;

  const JoinTripScreen({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<JoinTripScreen> createState() => _JoinTripScreenState();
}

class _JoinTripScreenState extends State<JoinTripScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _codeController = TextEditingController();

  bool _isLoading = false;
  bool _isScanning = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _handleJoin(String joinCode) async {
    final code = joinCode.trim().toUpperCase();
    if (code.isEmpty || code.length < 5) {
      _showSnackBar("Please enter a valid trip code");
      return;
    }

    setState(() => _isLoading = true);

    try {
      final res = await TripService.joinTrip(
        userId: widget.userId,
        joinCode: code,
      );

      if (!mounted) return;

      if (res["success"] == true) {
        _showSnackBar(res["message"] ?? "Joined trip successfully!");
        Navigator.pop(context, true);
      } else {
        _showSnackBar(res["message"] ?? "Failed to join trip");
      }
    } catch (e) {
      if (mounted) _showSnackBar("Error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.inter(color: Colors.white)),
        backgroundColor: const Color(0xFF113F3D),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const Color scaffoldBg = Color(0xFF195754);
    const Color darkSurface = Color(0xFF113F3D);
    const Color mintAccent = Color(0xFF10B981);
    const Color forestDark = Color(0xFF113F3D);
    const Color textMuted = Color(0xFF6B7280);

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: darkSurface,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "Join a Trip",
          style: GoogleFonts.inter(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 20,
            fontStyle: FontStyle.italic,
          ),
        ),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: mintAccent,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14),
          tabs: const [
            Tab(icon: Icon(Icons.pin_rounded, size: 18), text: "6-Digit Code"),
            Tab(icon: FaIcon(FontAwesomeIcons.qrcode, size: 16), text: "Scan QR"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 1: Enter 6-Digit Code
          SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: scaffoldBg.withValues(alpha: 0.08),
                    ),
                    child: const FaIcon(FontAwesomeIcons.ticket, color: scaffoldBg, size: 22),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "Enter 6-Digit Trip Code",
                    style: GoogleFonts.inter(
                      color: forestDark,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Ask the trip organizer for their 6-digit trip code (e.g. TRP892) and enter it below.",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(color: textMuted, fontSize: 13),
                  ),
                  const SizedBox(height: 20),

                  // Code Input Field
                  TextField(
                    controller: _codeController,
                    textCapitalization: TextCapitalization.characters,
                    textAlign: TextAlign.center,
                    maxLength: 6,
                    style: GoogleFonts.ibmPlexMono(
                      color: forestDark,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 6,
                    ),
                    decoration: InputDecoration(
                      counterText: "",
                      hintText: "TRP892",
                      hintStyle: GoogleFonts.ibmPlexMono(
                        color: textMuted.withValues(alpha: 0.4),
                        fontSize: 20,
                        letterSpacing: 6,
                      ),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      contentPadding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: scaffoldBg, width: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: scaffoldBg,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      onPressed: _isLoading ? null : () => _handleJoin(_codeController.text),
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Text(
                              "Join Trip Now",
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Tab 2: Scan QR Code
          Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Stack(
                      children: [
                        MobileScanner(
                          onDetect: (capture) {
                            if (!_isScanning) return;
                            final List<Barcode> barcodes = capture.barcodes;
                            for (final barcode in barcodes) {
                              final rawVal = barcode.rawValue;
                              if (rawVal != null && rawVal.trim().isNotEmpty) {
                                setState(() => _isScanning = false);
                                _handleJoin(rawVal.trim());
                                break;
                              }
                            }
                          },
                        ),
                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: mintAccent.withValues(alpha: 0.8), width: 3),
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Text(
                  "Point camera at the organizer's Trip QR code to join automatically.",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(color: Colors.white70, fontSize: 13),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

extension TextFieldExtension on TextField {
  // Helper extension if needed
}
