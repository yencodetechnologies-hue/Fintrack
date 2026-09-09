import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/expense_company_service.dart';
import 'company_dashboard_screen.dart';

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
  static const Color creamSheet = Color(0xFFFBF9F1);
  static const Color forestDark = Color(0xFF0F261C);
  static const Color darkText = Color(0xFF1E293B);
  static const Color terracotta = Color(0xFFB8452D);

  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();

  bool _isJoining = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submitJoinCompany() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isJoining = true);

    final res = await ExpenseCompanyService.joinCompany(
      userId: widget.userId,
      joinCode: _codeController.text.trim(),
    );

    if (!mounted) return;
    setState(() => _isJoining = false);

    if (res["success"] == true) {
      final company = res["company"];

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Joined ${company['name']} successfully!",
            style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          backgroundColor: forestDark,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );

      // Fetch all user companies and route to dashboard
      final companies = await ExpenseCompanyService.getUserCompanies(widget.userId);

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => CompanyDashboardScreen(
            userId: widget.userId,
            userName: widget.userName,
            companies: companies.isNotEmpty ? companies : [company],
            initialCompanyId: company["_id"].toString(),
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            res["message"] ?? "Invalid Company Code",
            style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          backgroundColor: terracotta,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
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
              color: forestDark.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.arrow_back_rounded, color: forestDark, size: 20),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "Join Company",
          style: GoogleFonts.fraunces(
            color: forestDark,
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Enter 6-Digit Code",
                  style: GoogleFonts.fraunces(
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
                const SizedBox(height: 28),

                // Join Code Field
                Text(
                  "6-Digit Company Code *",
                  style: GoogleFonts.inter(color: terracotta, fontWeight: FontWeight.bold, fontSize: 13),
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
                    color: forestDark,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 8,
                  ),
                  decoration: InputDecoration(
                    counterText: "",
                    hintText: "123456",
                    hintStyle: GoogleFonts.ibmPlexMono(color: darkText.withValues(alpha: 0.25), fontSize: 28, letterSpacing: 8),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: terracotta.withValues(alpha: 0.3))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: terracotta.withValues(alpha: 0.3))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: terracotta, width: 2)),
                  ),
                ),
                const SizedBox(height: 36),

                // Submit Button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _isJoining ? null : _submitJoinCompany,
                    icon: _isJoining
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.group_add_rounded, color: Colors.white),
                    label: Text(
                      _isJoining ? "Joining Company..." : "Join Company",
                      style: GoogleFonts.inter(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: terracotta,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
