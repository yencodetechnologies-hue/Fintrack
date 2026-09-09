import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/expense_company_service.dart';

class ReceivedExpenseModal extends StatefulWidget {
  final Map<String, dynamic> expense;
  final String userId;
  final List<Map<String, dynamic>> companyMembers;

  const ReceivedExpenseModal({
    Key? key,
    required this.expense,
    required this.userId,
    required this.companyMembers,
  }) : super(key: key);

  @override
  State<ReceivedExpenseModal> createState() => _ReceivedExpenseModalState();
}

class _ReceivedExpenseModalState extends State<ReceivedExpenseModal> {
  static const Color creamSheet = Color(0xFFFBF9F1);
  static const Color forestDark = Color(0xFF0F261C);
  static const Color darkText = Color(0xFF1E293B);
  static const Color terracotta = Color(0xFFB8452D);

  String? _selectedPayerUserId;
  String _paymentMode = "cash";
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
    // Default selected payer to first non-self member if available
    final otherMembers = widget.companyMembers.where((m) => m["userId"] != null && m["userId"].toString() != widget.userId).toList();
    if (otherMembers.isNotEmpty) {
      _selectedPayerUserId = otherMembers.first["userId"].toString();
    }
  }

  Future<void> _submitReceived() async {
    if (_selectedPayerUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Please select who paid you", style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
          backgroundColor: terracotta,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    final res = await ExpenseCompanyService.receiveExpense(
      expenseId: widget.expense["_id"].toString(),
      userId: widget.userId,
      payerUserId: _selectedPayerUserId!,
      paymentMode: _paymentMode,
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (res["success"] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Expense marked as received & settled!", style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
          backgroundColor: forestDark,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res["message"] ?? "Failed to mark as received", style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
          backgroundColor: terracotta,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final amount = widget.expense["amount"] ?? 0;
    final validMembers = widget.companyMembers.where((m) => m["userId"] != null).toList();

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
              "Mark Payment Received",
              style: GoogleFonts.fraunces(
                color: forestDark,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "Self-report payment received for ₹$amount ('${widget.expense['description']}').",
              style: GoogleFonts.inter(
                color: darkText.withValues(alpha: 0.7),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 20),

            // Select Payer Dropdown
            Text(
              "Who Paid You? *",
              style: GoogleFonts.inter(color: forestDark, fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              value: _selectedPayerUserId,
              dropdownColor: Colors.white,
              borderRadius: BorderRadius.circular(16),
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: forestDark.withValues(alpha: 0.2))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: forestDark.withValues(alpha: 0.2))),
              ),
              items: validMembers.map((m) {
                final isSelf = m["userId"].toString() == widget.userId;
                return DropdownMenuItem(
                  value: m["userId"].toString(),
                  child: Text(
                    "${m['name']} (${m['role'].toString().toUpperCase()})${isSelf ? ' (You)' : ''}",
                    style: GoogleFonts.inter(color: darkText, fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _selectedPayerUserId = val);
              },
            ),
            const SizedBox(height: 18),

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
            const SizedBox(height: 24),

            // Submit Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _isSubmitting ? null : _submitReceived,
                icon: _isSubmitting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.check_circle_rounded, color: Colors.white),
                label: Text(
                  _isSubmitting ? "Updating Status..." : "Confirm Received ₹$amount",
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
