import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/expense_company_service.dart';

class EditPaymentModal extends StatefulWidget {
  final Map<String, dynamic> expense;
  final String userId;
  final Map<String, dynamic>? existingSettlement;

  const EditPaymentModal({
    Key? key,
    required this.expense,
    required this.userId,
    this.existingSettlement,
  }) : super(key: key);

  @override
  State<EditPaymentModal> createState() => _EditPaymentModalState();
}

class _EditPaymentModalState extends State<EditPaymentModal> {
  static const Color creamSheet = Color(0xFFFBF9F1);
  static const Color forestDark = Color(0xFF0F261C);
  static const Color darkText = Color(0xFF1E293B);
  static const Color terracotta = Color(0xFFB8452D);

  late String _paymentMode;
  String? _base64Proof;
  bool _isSubmitting = false;

  final Map<String, String> _modeOptions = {
    "cash": "Cash 💵",
    "upi": "UPI / GPay / PhonePe 📲",
    "bank_transfer": "Bank Transfer 🏦",
    "other": "Other 💳",
  };

  @override
  void initState() {
    super.initState();
    final currentMode = widget.existingSettlement?["paymentMode"]?.toString().toLowerCase();
    if (currentMode != null && _modeOptions.containsKey(currentMode)) {
      _paymentMode = currentMode;
    } else {
      _paymentMode = "cash";
    }
    _base64Proof = widget.existingSettlement?["paymentProof"]?.toString();
  }

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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Failed to select payment proof image",
            style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          backgroundColor: terracotta,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  Future<void> _submitEdit() async {
    setState(() => _isSubmitting = true);

    final res = await ExpenseCompanyService.editExpenseSettlement(
      expenseId: widget.expense["_id"].toString(),
      userId: widget.userId,
      paymentMode: _paymentMode,
      paymentProof: _base64Proof,
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (res["success"] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Payment details updated successfully!",
            style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          backgroundColor: forestDark,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            res["message"] ?? "Failed to update payment details",
            style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          backgroundColor: terracotta,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  Widget _buildProofWidget(String proof) {
    if (proof.startsWith("data:image")) {
      final base64Str = proof.split(',').last;
      final bytes = base64Decode(base64Str);
      return Image.memory(bytes, height: 160, width: double.infinity, fit: BoxFit.cover);
    } else if (proof.startsWith("http://") || proof.startsWith("https://")) {
      return Image.network(
        proof,
        height: 160,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          height: 120,
          color: Colors.black.withValues(alpha: 0.05),
          alignment: Alignment.center,
          child: Text("Image unable to load", style: GoogleFonts.inter(color: darkText)),
        ),
      );
    } else if (proof.isNotEmpty) {
      try {
        final bytes = base64Decode(proof);
        return Image.memory(bytes, height: 160, width: double.infinity, fit: BoxFit.cover);
      } catch (_) {}
    }
    return Container(
      height: 120,
      color: Colors.black.withValues(alpha: 0.05),
      alignment: Alignment.center,
      child: Text("Proof Attached", style: GoogleFonts.inter(color: darkText)),
    );
  }

  @override
  Widget build(BuildContext me) {
    final double amount = (widget.expense["amount"] ?? 0.0).toDouble();

    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: const BoxDecoration(
        color: creamSheet,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
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
                  color: Colors.black.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Edit Payment Details",
                  style: GoogleFonts.fraunces(color: forestDark, fontSize: 20, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: forestDark),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Expense Summary Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: forestDark.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.edit_note_rounded, color: forestDark),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.expense["description"] ?? "Expense",
                          style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: darkText, fontSize: 15),
                        ),
                        Text(
                          "Amount: ₹${amount.toStringAsFixed(2)}",
                          style: GoogleFonts.inter(color: darkText.withValues(alpha: 0.6), fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Mode Picker
            Text(
              "Payment Mode",
              style: GoogleFonts.inter(color: darkText, fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.black.withValues(alpha: 0.12)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _paymentMode,
                  isExpanded: true,
                  items: _modeOptions.entries.map((e) {
                    return DropdownMenuItem(
                      value: e.key,
                      child: Text(e.value, style: GoogleFonts.inter(color: darkText, fontWeight: FontWeight.w600)),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _paymentMode = val);
                  },
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Proof Upload / Preview
            Text(
              "Proof of Payment Image",
              style: GoogleFonts.inter(color: darkText, fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 8),

            if (_base64Proof != null && _base64Proof!.isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(
                  children: [
                    _buildProofWidget(_base64Proof!),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: GestureDetector(
                        onTap: _pickProofImage,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: forestDark.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.change_circle_rounded, color: Colors.white, size: 16),
                              const SizedBox(width: 4),
                              Text("Change Image", style: GoogleFonts.inter(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              GestureDetector(
                onTap: _pickProofImage,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: forestDark.withValues(alpha: 0.3), style: BorderStyle.solid),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.add_a_photo_rounded, color: forestDark, size: 32),
                      const SizedBox(height: 8),
                      Text(
                        "Tap to upload proof screenshot / photo (Optional)",
                        style: GoogleFonts.inter(color: forestDark, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),

            // Submit Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitEdit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: forestDark,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _isSubmitting
                    ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                    : Text(
                        "Update Payment Details",
                        style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
