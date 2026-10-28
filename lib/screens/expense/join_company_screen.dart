import 'package:flutter/material.dart';
import '../ledger/ledger_common.dart' show toast;
import 'package:google_fonts/google_fonts.dart';
import '../../services/expense_company_service.dart';
import '../ledger/ledger_home_screen.dart';

class JoinCompanyScreen extends StatefulWidget {
  final String userId;
  final String userName;

  const JoinCompanyScreen({
    Key? key,
    required this.userId,
    required this.userName,
  }) : super(key: key);

  @override
  State<JoinCompanyScreen> createState() => _JoinCompanyScreenState();
}

class _JoinCompanyScreenState extends State<JoinCompanyScreen> {
  static const Color creamSheet = Color(0xFF195754);
  static const Color darkSurface = Color(0xFF113F3D);
  static const Color mintAccent = Color(0xFF10B981);
  static const Color darkText = Color(0xFF1E293B);

  final _formKey = GlobalKey<FormState>();
  late TextEditingController _userNameController;
  final _codeController = TextEditingController();

  bool _isJoining = false;

  @override
  void initState() {
    super.initState();
    _userNameController = TextEditingController(text: widget.userName);
  }

  @override
  void dispose() {
    _userNameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submitJoinCompany() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isJoining = true);

    final res = await ExpenseCompanyService.joinCompany(
      userId: widget.userId,
      userName: _userNameController.text.trim(),
      joinCode: _codeController.text.trim(),
    );

    if (!mounted) return;
    setState(() => _isJoining = false);

    if (res["success"] == true) {
      final company = res["company"];

      toast(context, "Joined ${company['name']} successfully!");

      // Fetch all user companies and route to dashboard
      final companies = await ExpenseCompanyService.getUserCompanies(widget.userId);

      if (!mounted) return;

      final updatedName = _userNameController.text.trim().isNotEmpty ? _userNameController.text.trim() : widget.userName;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => LedgerHomeScreen(
            userId: widget.userId,
            userName: updatedName,
            companies: companies.isNotEmpty ? companies : [company],
            initialCompanyId: company["_id"].toString(),
          ),
        ),
      );
    } else {
      toast(context, res["message"] ?? "Invalid Company Code", error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: creamSheet,
      appBar: AppBar(
        backgroundColor: creamSheet,
        elevation: 0,
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
          "Join Company",
          style: GoogleFonts.inter(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Enter 6-Digit Code",
                    style: GoogleFonts.inter(
                      color: darkText,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "Ask your company admin for the 6-digit numeric join code. Codes are valid for 5 minutes only.",
                    style: GoogleFonts.inter(
                      color: darkText.withValues(alpha: 0.6),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // User Name Field
                  Text(
                    "Your Name *",
                    style: GoogleFonts.inter(color: darkText, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _userNameController,
                    validator: (val) => val == null || val.trim().isEmpty ? "Your name is required" : null,
                    style: GoogleFonts.inter(color: darkText, fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      hintText: "Enter your full name",
                      hintStyle: GoogleFonts.inter(color: darkText.withValues(alpha: 0.4), fontSize: 14),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      prefixIcon: const Icon(Icons.person_rounded, color: darkSurface, size: 20),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.08))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.08))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: darkSurface, width: 1.6)),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Join Code Field
                  Text(
                    "6-Digit Company Code *",
                    style: GoogleFonts.inter(color: darkText, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _codeController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    textAlign: TextAlign.center,
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) return "Join code is required";
                      if (val.trim().length != 6) return "Code must be exactly 6 digits";
                      return null;
                    },
                    style: GoogleFonts.ibmPlexMono(
                      color: darkText,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 8,
                    ),
                    decoration: InputDecoration(
                      counterText: "",
                      hintText: "123456",
                      hintStyle: GoogleFonts.ibmPlexMono(color: darkText.withValues(alpha: 0.25), fontSize: 22, letterSpacing: 8),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.08))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.08))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: darkSurface, width: 1.8)),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Submit Button
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton.icon(
                      onPressed: _isJoining ? null : _submitJoinCompany,
                      icon: _isJoining
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: mintAccent, strokeWidth: 2))
                          : const Icon(Icons.group_add_rounded, color: Colors.white, size: 18),
                      label: Text(
                        _isJoining ? "Joining Company..." : "Join Company",
                        style: GoogleFonts.inter(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: darkSurface,
                        elevation: 0,
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
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
