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
  static const Color sheetBg = Color(0xFF0C5F41);
  static const Color darkSurface = Color(0xFF0C3826);
  static const Color mintAccent = Color(0xFF10B981);
  static const Color darkText = Color(0xFF1E293B);

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
          backgroundColor: const Color(0xFFC53030),
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
          backgroundColor: sheetBg,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res["message"] ?? "Failed to mark as received", style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFFC53030),
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
                  "Mark Payment Received",
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
              "Self-report payment received for ₹$amount ('${widget.expense['description']}').",
              style: GoogleFonts.inter(
                color: Colors.white.withValues(alpha: 0.75),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 18),

            // Select Payer Dropdown
            Text(
              "Who Paid You? *",
              style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5),
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              value: _selectedPayerUserId,
              dropdownColor: Colors.white,
              borderRadius: BorderRadius.circular(16),
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.08))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.08))),
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
              style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5),
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              value: _paymentMode,
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
            const SizedBox(height: 22),

            // Submit Button
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton.icon(
                onPressed: _isSubmitting ? null : _submitReceived,
                icon: _isSubmitting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: mintAccent, strokeWidth: 2))
                    : const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                label: Text(
                  _isSubmitting ? "Updating Status..." : "Confirm Received ₹$amount",
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
