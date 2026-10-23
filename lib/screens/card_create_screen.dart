import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../services/card_service.dart';
import '../data/indian_banks.dart';
import '../utils/bank_card_style.dart';
import '../utils/card_scan_mapper.dart';
import '../widgets/bank_card_preview.dart';
import '../widgets/bank_selector_field.dart';
import '../widgets/scan_card_section.dart';

class CardCreateScreen extends StatefulWidget {
  final String userId;
  final String userName;

  const CardCreateScreen({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<CardCreateScreen> createState() => _CardCreateScreenState();
}

class _CardCreateScreenState extends State<CardCreateScreen> {
  final bankController = TextEditingController();
  final customBankController = TextEditingController();
  final cardController = TextEditingController();
  final last4Controller = TextEditingController();

  String? selectedBankId;

  DateTime? selectedStatementDate;
  DateTime? paymentDueDate;

  bool loading = false;
  bool scanning = false;

  static const Color _bg         = Color(0xFF195754);
  static const Color _forestDark = Color(0xFF195754);
  static const Color _darkText   = Color(0xFF1E293B);
  static const Color _terracotta = Color(0xFFB8452D);

  @override
  void initState() {
    super.initState();
    bankController.addListener(_updateState);
    customBankController.addListener(_onCustomBankChanged);
    cardController.addListener(_updateState);
    last4Controller.addListener(_updateState);
  }

  void _onCustomBankChanged() {
    if (selectedBankId == kCustomBankId) {
      _syncBankController();
    }
  }

  void _syncBankController() {
    bankController.text = resolveBankName(
      selectedBankId: selectedBankId,
      customBankName: customBankController.text,
    );
  }

  void _onBankIdChanged(String? bankId) {
    setState(() {
      selectedBankId = bankId;
      _syncBankController();
    });
  }

  void _applyScannedBankSelection(CardScanFillResult fillResult) {
    if (!fillResult.filledBank) {
      return;
    }

    final matchedBankId = fillResult.matchedBankId ?? kCustomBankId;
    if (matchedBankId == kCustomBankId) {
      selectedBankId = kCustomBankId;
      customBankController.text = bankController.text.trim();
    } else {
      selectedBankId = matchedBankId;
    }
    _syncBankController();
  }

  void _updateState() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> pickDate(bool isStatement) async {
    DateTime initialDate = DateTime.now();

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(
              primary: _forestDark,
              onPrimary: Colors.white,
              surface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        if (isStatement) {
          selectedStatementDate = picked;
        } else {
          paymentDueDate = picked;
        }
      });
    }
  }

  Future<void> scanCard() async {
    if (scanning || loading) {
      return;
    }

    setState(() => scanning = true);

    try {
      final fillResult = await performCardScan(
        bankController: bankController,
        cardController: cardController,
        last4Controller: last4Controller,
      );

      if (!mounted) {
        return;
      }

      if (fillResult == null) {
        return;
      }

      if (!fillResult.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: _terracotta,
            behavior: SnackBarBehavior.floating,
            content: Text(
              fillResult.errorMessage ?? 'Could not scan card. Please try again.',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
        return;
      }

      setState(() {
        _applyScannedBankSelection(fillResult);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: _forestDark,
          behavior: SnackBarBehavior.floating,
          content: Text(
            'Card details filled from scan. Please select statement and due dates.',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: _terracotta,
          behavior: SnackBarBehavior.floating,
          content: Text(
            'Scan failed: $e',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => scanning = false);
      }
    }
  }

  Future<void> saveCard() async {
    if (selectedBankId == null ||
        bankController.text.isEmpty ||
        cardController.text.isEmpty ||
        selectedStatementDate == null ||
        paymentDueDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: _terracotta,
          behavior: SnackBarBehavior.floating,
          content: Text(
            "Please fill all fields",
            style: GoogleFonts.inter(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
      return;
    }

    String digits = last4Controller.text.trim();

    if (digits.length > 4) {
      digits = digits.substring(digits.length - 4);
    }

    if (digits.length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: _terracotta,
          behavior: SnackBarBehavior.floating,
          content: Text(
            "Enter valid 4 digits",
            style: GoogleFonts.inter(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
      return;
    }

    setState(() => loading = true);

    try {
      final res = await CardService.addCard(
        userId: widget.userId,
        bankName: bankController.text.trim(),
        cardName: cardController.text.trim(),
        last4digits: digits,
        statementDate: selectedStatementDate!.toIso8601String(),
        paymentDueDate: paymentDueDate!.toIso8601String(),
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            res["message"] ?? "Saved",
            style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white),
          ),
          backgroundColor: res["success"] == true ? _forestDark : _terracotta,
        ),
      );

      if (res["success"] == true) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text("Error: $e", style: GoogleFonts.inter(color: Colors.white)),
          backgroundColor: _terracotta,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Widget buildField({
    required String label,
    required IconData icon,
    required TextEditingController controller,
    TextInputType? keyboardType,
    int? maxLength,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F8F7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.black.withValues(alpha: 0.12),
          width: 1.2,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        maxLength: maxLength,
        style: GoogleFonts.inter(
          color: _darkText,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          counterText: "",
          labelText: label,
          labelStyle: GoogleFonts.inter(
            color: const Color(0xFF6B7280),
            fontSize: 14,
            fontWeight: FontWeight.w400,
          ),
          prefixIcon: Icon(
            icon,
            color: _forestDark,
            size: 20,
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 36,
            minHeight: 20,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }

  Widget buildDateTile({
    required String title,
    required String value,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F8F7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.black.withValues(alpha: 0.12),
          width: 1.2,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          onTap: onTap,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _forestDark.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.calendar_month_rounded,
              color: _forestDark,
              size: 20,
            ),
          ),
          title: Text(
            title,
            style: GoogleFonts.inter(
              color: const Color(0xFF6B7280),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              value,
              style: GoogleFonts.inter(
                color: _darkText,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          trailing: const Icon(
            Icons.chevron_right_rounded,
            color: _forestDark,
            size: 20,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    bankController.removeListener(_updateState);
    customBankController.removeListener(_onCustomBankChanged);
    cardController.removeListener(_updateState);
    last4Controller.removeListener(_updateState);
    bankController.dispose();
    customBankController.dispose();
    cardController.dispose();
    last4Controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat("dd MMM yyyy");
    final style = styleForBank(bankController.text);

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.arrow_back_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "Add Credit Card",
          style: GoogleFonts.inter(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            children: [
              // Dynamic Real-time Card Preview
              BankCardPreview(
                bank: bankController.text,
                name: widget.userName,
                digits: last4Controller.text,
                style: style,
              ),
              const SizedBox(height: 24),

              // QFin Form Container (White Card)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: Colors.black.withValues(alpha: 0.08),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      "Card Details",
                      style: GoogleFonts.inter(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: _darkText,
                      ),
                    ),
                    const SizedBox(height: 18),
                    ScanCardSection(
                      onScan: scanCard,
                      enabled: !loading && !scanning,
                    ),
                    if (scanning)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 18),
                        child: Center(
                          child: CircularProgressIndicator(
                            color: _forestDark,
                          ),
                        ),
                      ),
                    BankSelectorField(
                      selectedBankId: selectedBankId,
                      customBankController: customBankController,
                      onBankIdChanged: _onBankIdChanged,
                      onCustomBankChanged: _onCustomBankChanged,
                    ),
                    buildField(
                      label: "Card Nickname",
                      icon: Icons.credit_card_rounded,
                      controller: cardController,
                    ),
                    buildField(
                      label: "Last 4 Digits",
                      icon: Icons.lock_outline_rounded,
                      controller: last4Controller,
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                    ),
                    buildDateTile(
                      title: "Statement Date",
                      value: selectedStatementDate == null
                          ? "Select Statement Date"
                          : dateFormat.format(selectedStatementDate!),
                      onTap: () => pickDate(true),
                    ),
                    buildDateTile(
                      title: "Payment Due Date",
                      value: paymentDueDate == null
                          ? "Select Payment Due Date"
                          : dateFormat.format(paymentDueDate!),
                      onTap: () => pickDate(false),
                    ),
                    const SizedBox(height: 12),
                    loading
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: _forestDark,
                            ),
                          )
                        : SizedBox(
                            height: 52,
                            child: ElevatedButton(
                              onPressed: saveCard,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _forestDark,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: Text(
                                "Save Card",
                                style: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
