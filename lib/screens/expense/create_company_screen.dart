import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/expense_company_service.dart';
import 'company_dashboard_screen.dart';

class CreateCompanyScreen extends StatefulWidget {
  final String userId;
  final String userName;

  const CreateCompanyScreen({
    Key? key,
    required this.userId,
    required this.userName,
  }) : super(key: key);

  @override
  State<CreateCompanyScreen> createState() => _CreateCompanyScreenState();
}

class _CreateCompanyScreenState extends State<CreateCompanyScreen> {
  static const Color creamSheet = Color(0xFFFBF9F1);
  static const Color forestDark = Color(0xFF0F261C);
  static const Color darkText = Color(0xFF1E293B);

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _detailsController = TextEditingController();

  bool _isCreating = false;

  @override
  void dispose() {
    _nameController.dispose();
    _detailsController.dispose();
    super.dispose();
  }

  Future<void> _submitCreateCompany() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isCreating = true);

    final res = await ExpenseCompanyService.createCompany(
      userId: widget.userId,
      name: _nameController.text.trim(),
      details: _detailsController.text.trim(),
    );

    if (!mounted) return;
    setState(() => _isCreating = false);

    if (res["success"] == true) {
      final company = res["company"];
      final joinCode = res["joinCode"] ?? company["joinCode"];

      _showCodeSuccessModal(company, joinCode.toString());
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res["message"] ?? "Failed to create company")),
      );
    }
  }

  void _showCodeSuccessModal(Map<String, dynamic> company, String joinCode) {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: creamSheet,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: forestDark,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_rounded, color: Colors.white, size: 36),
              ),
              const SizedBox(height: 16),
              Text(
                "Company Created!",
                style: GoogleFonts.fraunces(
                  color: forestDark,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "Your 6-digit company join code is ready. Share this code with members to let them join.",
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: darkText.withValues(alpha: 0.7),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 20),

              // Code Display Card
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: forestDark.withValues(alpha: 0.2), width: 1.5),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      joinCode,
                      style: GoogleFonts.ibmPlexMono(
                        color: forestDark,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 4,
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: joinCode));
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text("Join code copied to clipboard!")),
                        );
                      },
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text("Copy"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: forestDark,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx); // Close modal
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CompanyDashboardScreen(
                          userId: widget.userId,
                          userName: widget.userName,
                          companies: [company],
                          initialCompanyId: company["_id"].toString(),
                        ),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: forestDark,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: Text(
                    "Go to Company Dashboard",
                    style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
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
          "Create Company",
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
                  "Set Up Organization",
                  style: GoogleFonts.fraunces(
                    color: darkText,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  "Create a company ledger to track reimbursements and settlements with team members.",
                  style: GoogleFonts.inter(
                    color: darkText.withValues(alpha: 0.6),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 24),

                // Company Name Field
                Text(
                  "Company Name *",
                  style: GoogleFonts.inter(color: forestDark, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _nameController,
                  validator: (val) => val == null || val.trim().isEmpty ? "Company name is required" : null,
                  style: GoogleFonts.inter(color: darkText, fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                    hintText: "e.g. Acme Corporation, Yencode Tech",
                    hintStyle: GoogleFonts.inter(color: darkText.withValues(alpha: 0.4), fontSize: 13.5),
                    filled: true,
                    fillColor: Colors.white,
                    prefixIcon: const Icon(Icons.business_rounded, color: forestDark, size: 20),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: forestDark.withValues(alpha: 0.2))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: forestDark.withValues(alpha: 0.2))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: forestDark, width: 1.8)),
                  ),
                ),
                const SizedBox(height: 18),

                // Description Field
                Text(
                  "Company Details / Description (Optional)",
                  style: GoogleFonts.inter(color: forestDark, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _detailsController,
                  maxLines: 3,
                  style: GoogleFonts.inter(color: darkText, fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                    hintText: "e.g. Engineering Team Reimbursement Ledger",
                    hintStyle: GoogleFonts.inter(color: darkText.withValues(alpha: 0.4), fontSize: 13.5),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: forestDark.withValues(alpha: 0.2))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: forestDark.withValues(alpha: 0.2))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: forestDark, width: 1.8)),
                  ),
                ),
                const SizedBox(height: 32),

                // Submit Button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _isCreating ? null : _submitCreateCompany,
                    icon: _isCreating
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.add_business_rounded, color: Colors.white),
                    label: Text(
                      _isCreating ? "Creating Company..." : "Create & Generate Code",
                      style: GoogleFonts.inter(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: forestDark,
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
