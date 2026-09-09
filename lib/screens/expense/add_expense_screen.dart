import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../services/expense_company_service.dart';

class AddExpenseScreen extends StatefulWidget {
  final String companyId;
  final String companyName;
  final String userId;
  final String userName;

  const AddExpenseScreen({
    Key? key,
    required this.companyId,
    required this.companyName,
    required this.userId,
    required this.userName,
  }) : super(key: key);

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  static const Color creamSheet = Color(0xFFFBF9F1);
  static const Color forestDark = Color(0xFF0F261C);
  static const Color darkText = Color(0xFF1E293B);

  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _descController = TextEditingController();

  String _selectedCategory = "General";
  DateTime _selectedDate = DateTime.now();
  String? _base64Image;

  bool _isSaving = false;

  final List<String> _categories = [
    "General",
    "Food & Dining",
    "Travel & Transport",
    "Office Supplies",
    "Utilities",
    "Software & Tech",
    "Other",
    "+ Add Custom Category...",
  ];

  void _promptCustomCategoryDialog() {
    final customTextController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: creamSheet,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.add_circle_outline_rounded, color: forestDark),
            const SizedBox(width: 8),
            Text("Custom Category", style: GoogleFonts.fraunces(fontWeight: FontWeight.bold, fontSize: 18, color: forestDark)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Enter a custom category name for this expense:",
              style: GoogleFonts.inter(fontSize: 13, color: darkText.withValues(alpha: 0.7)),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: customTextController,
              autofocus: true,
              style: GoogleFonts.inter(color: darkText, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                hintText: "e.g. Marketing, Equipment, Taxes",
                hintStyle: GoogleFonts.inter(color: darkText.withValues(alpha: 0.4), fontSize: 13),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: forestDark.withValues(alpha: 0.2))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: forestDark, width: 1.8)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (_selectedCategory == "+ Add Custom Category...") {
                setState(() => _selectedCategory = _categories.first);
              }
            },
            child: Text("Cancel", style: GoogleFonts.inter(color: darkText.withValues(alpha: 0.6))),
          ),
          ElevatedButton(
            onPressed: () {
              final customName = customTextController.text.trim();
              if (customName.isNotEmpty) {
                setState(() {
                  if (!_categories.contains(customName)) {
                    _categories.insert(_categories.length - 1, customName);
                  }
                  _selectedCategory = customName;
                });
                Navigator.pop(ctx);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: forestDark,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text("Add Category", style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _pickReceiptImage() async {
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
          _base64Image = "data:image/jpeg;base64,${base64Encode(bytes)}";
        });
      }
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Failed to pick image", style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFFB8452D),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      builder: (ctx, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(primary: forestDark),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _submitExpense() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    final res = await ExpenseCompanyService.createExpense(
      companyId: widget.companyId,
      userId: widget.userId,
      amount: double.parse(_amountController.text.trim()),
      description: _descController.text.trim(),
      category: _selectedCategory,
      date: _selectedDate,
      attachment: _base64Image ?? "",
    );

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (res["success"] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Expense added successfully!", style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
          backgroundColor: forestDark,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res["message"] ?? "Failed to add expense", style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFFB8452D),
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
          "Add Expense",
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
                // Amount Field
                Text(
                  "Amount (₹) *",
                  style: GoogleFonts.inter(color: forestDark, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) return "Amount is required";
                    final numVal = double.tryParse(val.trim());
                    if (numVal == null || numVal <= 0) return "Enter a valid amount";
                    return null;
                  },
                  style: GoogleFonts.ibmPlexMono(
                    color: forestDark,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: InputDecoration(
                    hintText: "0.00",
                    hintStyle: GoogleFonts.ibmPlexMono(color: darkText.withValues(alpha: 0.3), fontSize: 24),
                    prefixIcon: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Text("₹", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: forestDark)),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: forestDark.withValues(alpha: 0.2))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: forestDark.withValues(alpha: 0.2))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: forestDark, width: 2)),
                  ),
                ),
                const SizedBox(height: 18),

                // Description Field
                Text(
                  "Description / Purpose *",
                  style: GoogleFonts.inter(color: forestDark, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _descController,
                  validator: (val) => val == null || val.trim().isEmpty ? "Description is required" : null,
                  style: GoogleFonts.inter(color: darkText, fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                    hintText: "e.g. Office lunch for team, Flight tickets",
                    hintStyle: GoogleFonts.inter(color: darkText.withValues(alpha: 0.4), fontSize: 13.5),
                    filled: true,
                    fillColor: Colors.white,
                    prefixIcon: const Icon(Icons.description_rounded, color: forestDark, size: 20),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: forestDark.withValues(alpha: 0.2))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: forestDark.withValues(alpha: 0.2))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: forestDark, width: 1.8)),
                  ),
                ),
                const SizedBox(height: 18),

                // Category Selector
                Text(
                  "Category",
                  style: GoogleFonts.inter(color: forestDark, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: _selectedCategory,
                  dropdownColor: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white,
                    prefixIcon: const Icon(Icons.category_rounded, color: forestDark, size: 20),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: forestDark.withValues(alpha: 0.2))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: forestDark.withValues(alpha: 0.2))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: forestDark, width: 1.8)),
                  ),
                  items: _categories.map((cat) {
                    final isCustomAction = cat == "+ Add Custom Category...";
                    return DropdownMenuItem(
                      value: cat,
                      child: Row(
                        children: [
                          if (isCustomAction) ...[
                            const Icon(Icons.add_circle_outline_rounded, color: forestDark, size: 18),
                            const SizedBox(width: 8),
                          ],
                          Text(
                            cat,
                            style: GoogleFonts.inter(
                              color: isCustomAction ? forestDark : darkText,
                              fontWeight: isCustomAction ? FontWeight.bold : FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val == "+ Add Custom Category...") {
                      _promptCustomCategoryDialog();
                    } else if (val != null) {
                      setState(() => _selectedCategory = val);
                    }
                  },
                ),
                const SizedBox(height: 18),

                // Date Selector
                Text(
                  "Expense Date",
                  style: GoogleFonts.inter(color: forestDark, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 6),
                InkWell(
                  onTap: _selectDate,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: forestDark.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.calendar_today_rounded, color: forestDark, size: 18),
                            const SizedBox(width: 12),
                            Text(
                              DateFormat('dd MMM yyyy').format(_selectedDate),
                              style: GoogleFonts.inter(color: darkText, fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                          ],
                        ),
                        const Icon(Icons.edit_calendar_rounded, color: forestDark, size: 18),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),

                // Receipt Attachment
                Text(
                  "Receipt / Attachment (Optional)",
                  style: GoogleFonts.inter(color: forestDark, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: _pickReceiptImage,
                  child: Container(
                    width: double.infinity,
                    height: 110,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: forestDark.withValues(alpha: 0.25), width: 1.5),
                    ),
                    child: _base64Image != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Image.memory(
                              base64Decode(_base64Image!.split(',').last),
                              fit: BoxFit.cover,
                            ),
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.cloud_upload_outlined, color: forestDark, size: 30),
                              const SizedBox(height: 6),
                              Text(
                                "Tap to upload receipt image",
                                style: GoogleFonts.inter(color: darkText.withValues(alpha: 0.6), fontSize: 12.5, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 32),

                // Save Expense Button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _isSaving ? null : _submitExpense,
                    icon: _isSaving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.check_rounded, color: Colors.white),
                    label: Text(
                      _isSaving ? "Saving Expense..." : "Post Expense",
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
