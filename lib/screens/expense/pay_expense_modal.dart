import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/expense_company_service.dart';

class PayExpenseModal extends StatefulWidget {
  final Map<String, dynamic> expense;
  final String userId;

  const PayExpenseModal({
    Key? key,
    required this.expense,
    required this.userId,
  }) : super(key: key);

  @override
  State<PayExpenseModal> createState() => _PayExpenseModalState();
}

class _PayExpenseModalState extends State<PayExpenseModal> {
  static const Color creamSheet = Color(0xFFFBF9F1);
  static const Color forestDark = Color(0xFF0F261C);
  static const Color darkText = Color(0xFF1E293B);
  static const Color terracotta = Color(0xFFB8452D);

  String _paymentMode = "cash";
  String? _base64Proof;
  bool _isSubmitting = false;

  final Map<String, String> _modeOptions = {
    "cash": "Cash 💵",
    "upi": "UPI / GPay / PhonePe 📲",
    "bank_transfer": "Bank Transfer 🏦",
    "other": "Other 💳",
  };

  Future<void> _pickProofImage() async {
    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 70,
      );
      if (image != null) {
        final bytes = await File(image.path).readAsBytes();
        setState(() {
          _base64Proof = "data:image/jpeg;base64,${base64Encode(bytes)}";
        });
      }
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Failed to select payment proof image", style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
          backgroundColor: terracotta,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  Future<void> _submitPay() async {
    if (_base64Proof == null || _base64Proof!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Payment proof screenshot/photo is required", style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
          backgroundColor: terracotta,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    final res = await ExpenseCompanyService.payExpense(
      expenseId: widget.expense["_id"].toString(),
      userId: widget.userId,
      paymentMode: _paymentMode,
      paymentProof: _base64Proof!,
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (res["success"] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Payment submitted successfully!", style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
          backgroundColor: forestDark,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res["message"] ?? "Failed to submit payment", style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
          backgroundColor: terracotta,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final creatorName = widget.expense["createdBy"] != null
        ? widget.expense["createdBy"]["name"] ?? "Creator"
        : "Creator";
    final amount = widget.expense["amount"] ?? 0;

    return Container(
      decoration: const BoxDecoration(
        color: creamSheet,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: darkText.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              "Pay Expense",
              style: GoogleFonts.fraunces(
                color: forestDark,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "Paying ₹$amount to $creatorName for '${widget.expense['description']}'.",
              style: GoogleFonts.inter(
                color: darkText.withValues(alpha: 0.7),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 20),

            // Payment Mode Selector
            Text(
              "Payment Mode *",
              style: GoogleFonts.inter(color: forestDark, fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              value: _paymentMode,
              dropdownColor: Colors.white,
              borderRadius: BorderRadius.circular(16),
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: forestDark.withValues(alpha: 0.2))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: forestDark.withValues(alpha: 0.2))),
              ),
              items: _modeOptions.entries.map((e) {
                return DropdownMenuItem(
                  value: e.key,
                  child: Text(e.value, style: GoogleFonts.inter(color: darkText, fontWeight: FontWeight.w600, fontSize: 14)),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _paymentMode = val);
              },
            ),
            const SizedBox(height: 18),

            // Payment Proof Upload (REQUIRED)
            Row(
              children: [
                Text(
                  "Payment Proof Screenshot *",
                  style: GoogleFonts.inter(color: forestDark, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                  child: Text("Required", style: GoogleFonts.inter(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: _pickProofImage,
              child: Container(
                width: double.infinity,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _base64Proof == null ? Colors.red.withValues(alpha: 0.4) : forestDark.withValues(alpha: 0.3),
                    width: 1.5,
                  ),
                ),
                child: _base64Proof != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.memory(
                          base64Decode(_base64Proof!.split(',').last),
                          fit: BoxFit.cover,
                        ),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.add_a_photo_rounded, color: forestDark, size: 28),
                          const SizedBox(height: 6),
                          Text(
                            "Tap to upload UPI/Bank receipt screenshot",
                            style: GoogleFonts.inter(color: darkText.withValues(alpha: 0.6), fontSize: 12.5, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 24),

            // Submit Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _isSubmitting ? null : _submitPay,
                icon: _isSubmitting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.payment_rounded, color: Colors.white),
                label: Text(
                  _isSubmitting ? "Submitting Payment..." : "Confirm & Pay ₹$amount",
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
    );
  }
}
