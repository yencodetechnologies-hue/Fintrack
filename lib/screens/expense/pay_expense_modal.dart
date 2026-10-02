import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/expense_company_service.dart';

class PayExpenseModal extends StatefulWidget {
  final Map<String, dynamic> expense;
  final String userId;
  final bool isAdmin;
  final String? lockedPayAs;
  final List<Map<String, dynamic>> bankAccounts;
  final num cashBalance;

  const PayExpenseModal({
    Key? key,
    required this.expense,
    required this.userId,
    this.isAdmin = false,
    this.lockedPayAs,
    this.bankAccounts = const [],
    this.cashBalance = 0,
  }) : super(key: key);

  @override
  State<PayExpenseModal> createState() => _PayExpenseModalState();
}

class _PayExpenseModalState extends State<PayExpenseModal> {
  static const Color sheetBg = Color(0xFF0C5F41);
  static const Color darkSurface = Color(0xFF0C3826);
  static const Color mintAccent = Color(0xFF10B981);
  static const Color darkText = Color(0xFF1E293B);

  String? _paymentMode;
  String? _base64Proof;
  String? _fundId;
  String _payAs = "company";
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _payAs = widget.lockedPayAs ?? (widget.isAdmin ? "company" : "self");
  }

  final Map<String, String> _modeOptions = {
    "cash": "Cash 💵",
    "card": "Card 💳",
    "upi": "UPI 📲",
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
          backgroundColor: const Color(0xFFC53030),
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
          backgroundColor: const Color(0xFFC53030),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    if (_paymentMode == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Select a payment mode (Cash, Card or UPI)", style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFFC53030),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    final needsBank = widget.isAdmin && _payAs == "company";
    if (needsBank && _fundId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Select the bank account or InCash this payment is made from",
              style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFFC53030),
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
      paymentMode: _paymentMode!,
      paymentProof: _base64Proof!,
      payAs: widget.isAdmin ? _payAs : "self",
      fundId: (widget.isAdmin && _payAs == "company") ? _fundId : null,
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (res["success"] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Payment submitted successfully!", style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
          backgroundColor: sheetBg,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res["message"] ?? "Failed to submit payment", style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFFC53030),
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
        color: sheetBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Pay Expense",
                  style: GoogleFonts.fraunces(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: darkSurface,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                    ),
                    child: const Icon(Icons.close_rounded, color: mintAccent, size: 18),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              "Paying ₹$amount to $creatorName for '${widget.expense['description']}'.",
              style: GoogleFonts.inter(
                color: Colors.white.withValues(alpha: 0.75),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 18),

            if (widget.isAdmin && widget.lockedPayAs == null) ...[
              Text(
                "Pay As *",
                style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5),
              ),
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(
                  color: darkSurface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                ),
                padding: const EdgeInsets.all(4),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _payAs = "company"),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: _payAs == "company" ? sheetBg : Colors.transparent,
                            borderRadius: BorderRadius.circular(11),
                            border: _payAs == "company"
                                ? Border.all(color: mintAccent.withValues(alpha: 0.5))
                                : null,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.business_rounded,
                                size: 16,
                                color: _payAs == "company" ? mintAccent : Colors.white.withValues(alpha: 0.6),
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  "Company",
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _payAs = "self"),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: _payAs == "self" ? sheetBg : Colors.transparent,
                            borderRadius: BorderRadius.circular(11),
                            border: _payAs == "self"
                                ? Border.all(color: mintAccent.withValues(alpha: 0.5))
                                : null,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.person_rounded,
                                size: 16,
                                color: _payAs == "self" ? mintAccent : Colors.white.withValues(alpha: 0.6),
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  "Self (as Member)",
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
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
              const SizedBox(height: 6),
              Text(
                _payAs == "company"
                    ? "• Company: Settles the expense permanently for the Company."
                    : "• Self: Paid from your personal pocket. Claim transfers to you until settled by Company.",
                style: GoogleFonts.inter(color: Colors.white.withValues(alpha: 0.65), fontSize: 11, fontStyle: FontStyle.italic),
              ),
              const SizedBox(height: 16),
            ],

            // Payment Mode Selector
            Text(
              "Payment Mode *",
              style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5),
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              value: _paymentMode,
              hint: Text("Select payment mode", style: GoogleFonts.inter(color: darkText.withValues(alpha: 0.5), fontSize: 14)),
              dropdownColor: Colors.white,
              borderRadius: BorderRadius.circular(16),
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.08))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.08))),
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

            if (widget.isAdmin && _payAs == "company") ...[
              Text(
                "Pay From *",
                style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: _fundId,
                isExpanded: true,
                dropdownColor: Colors.white,
                borderRadius: BorderRadius.circular(16),
                hint: Text(
                  "Select bank account or InCash",
                  style: GoogleFonts.inter(color: darkText.withValues(alpha: 0.5), fontSize: 14),
                ),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.08))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.08))),
                ),
                items: [
                  DropdownMenuItem<String>(
                    value: "cash",
                    child: Text(
                      "InCash (₹${widget.cashBalance.toStringAsFixed(2)})",
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(color: darkText, fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                  ),
                  ...widget.bankAccounts.map((b) {
                    final number = (b["accountNumber"] ?? "").toString();
                    final last4 = number.length > 4 ? number.substring(number.length - 4) : number;
                    final bal = ((b["balance"] as num?) ?? 0).toStringAsFixed(2);
                    return DropdownMenuItem<String>(
                      value: b["_id"].toString(),
                      child: Text(
                        "${b["bankName"]} •••• $last4 (₹$bal)",
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(color: darkText, fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                    );
                  }),
                ],
                onChanged: (val) => setState(() => _fundId = val),
              ),
              const SizedBox(height: 18),
            ],

            // Payment Proof Upload (REQUIRED)
            Row(
              children: [
                Text(
                  "Payment Proof Screenshot *",
                  style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(6)),
                  child: Text("Required", style: GoogleFonts.inter(color: const Color(0xFFDC2626), fontSize: 10, fontWeight: FontWeight.bold)),
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
                  color: darkSurface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _base64Proof == null ? const Color(0xFFFCA5A5) : Colors.white.withValues(alpha: 0.15),
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
                          const Icon(Icons.add_a_photo_rounded, color: mintAccent, size: 28),
                          const SizedBox(height: 6),
                          Text(
                            "Tap to upload UPI/Bank receipt screenshot",
                            style: GoogleFonts.inter(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 22),

            // Submit Button
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton.icon(
                onPressed: _isSubmitting ? null : _submitPay,
                icon: _isSubmitting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: mintAccent, strokeWidth: 2))
                    : const Icon(Icons.payment_rounded, color: Colors.white, size: 18),
                label: Text(
                  _isSubmitting ? "Submitting Payment..." : "Confirm & Pay ₹$amount",
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
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
    );
  }
}
