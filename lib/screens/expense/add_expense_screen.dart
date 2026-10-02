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
  final bool isAdmin;
  final String? lockedLogAs;
  final List<String> customCategories;
  final List<Map<String, dynamic>> bankAccounts;
  final num cashBalance;

  final List<Map<String, dynamic>> companyMembers;

  const AddExpenseScreen({
    super.key,
    required this.companyId,
    required this.companyName,
    required this.userId,
    required this.userName,
    this.isAdmin = false,
    this.lockedLogAs,
    this.customCategories = const [],
    this.bankAccounts = const [],
    this.cashBalance = 0,
    this.companyMembers = const [],
  });

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  static const Color creamSheet = Color(0xFF0C5F41);
  static const Color darkSurface = Color(0xFF0C3826);
  static const Color forestDark = Color(0xFF0C5F41);
  static const Color mintAccent = Color(0xFF10B981);
  static const Color darkText = Color(0xFF1E293B);

  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _descController = TextEditingController();

  String _selectedCategory = "General";
  DateTime _selectedDate = DateTime.now();
  String? _base64Image;
  String _logAs = "company";

  String? _fundId;
  Set<String> _selectedVisibleUserIds = {};
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _logAs = widget.lockedLogAs ?? (widget.isAdmin ? "company" : "self");
    for (final c in widget.customCategories) {
      if (!_categories.contains(c)) _categories.insert(_categories.length - 1, c);
    }

    // Initialize selected members (default: all members selected)
    _selectedVisibleUserIds = widget.companyMembers
        .map((m) => (m["userId"] ?? m["_id"])?.toString() ?? "")
        .where((id) => id.isNotEmpty)
        .toSet();
  }

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

  final Map<String, IconData> _categoryIcons = {
    "General": Icons.category_rounded,
    "Food & Dining": Icons.restaurant_rounded,
    "Travel & Transport": Icons.directions_car_rounded,
    "Office Supplies": Icons.inventory_2_rounded,
    "Utilities": Icons.bolt_rounded,
    "Software & Tech": Icons.laptop_mac_rounded,
    "Other": Icons.more_horiz_rounded,
  };

  final List<IconData> _selectableIcons = [
    Icons.shopping_cart_rounded,
    Icons.campaign_rounded,
    Icons.build_rounded,
    Icons.medical_services_rounded,
    Icons.school_rounded,
    Icons.fitness_center_rounded,
    Icons.local_shipping_rounded,
    Icons.receipt_rounded,
    Icons.phonelink_rounded,
    Icons.local_cafe_rounded,
    Icons.flight_takeoff_rounded,
    Icons.home_work_rounded,
  ];

  IconData _selectedCustomIcon = Icons.shopping_cart_rounded;

  IconData _getCategoryIcon(String category) {
    return _categoryIcons[category] ?? Icons.label_rounded;
  }

  void _promptCustomCategoryDialog() {
    final customTextController = TextEditingController();
    IconData tempSelectedIcon = _selectedCustomIcon;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: creamSheet,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              const Icon(Icons.add_circle_outline_rounded, color: mintAccent),
              const SizedBox(width: 8),
              Text("Custom Category", style: GoogleFonts.fraunces(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Enter custom category name:",
                style: GoogleFonts.inter(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.75)),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: customTextController,
                autofocus: true,
                style: GoogleFonts.inter(color: darkText, fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  hintText: "e.g. Marketing, Equipment",
                  hintStyle: GoogleFonts.inter(color: darkText.withValues(alpha: 0.4), fontSize: 13),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.08))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: darkSurface, width: 1.8)),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                "Choose Category Icon:",
                style: GoogleFonts.inter(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.75), fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _selectableIcons.map((iconData) {
                  final isSelected = tempSelectedIcon == iconData;
                  return GestureDetector(
                    onTap: () {
                      setDialogState(() {
                        tempSelectedIcon = iconData;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isSelected ? mintAccent : Colors.white.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? Colors.white : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: Icon(
                        iconData,
                        size: 20,
                        color: isSelected ? darkSurface : Colors.white,
                      ),
                    ),
                  );
                }).toList(),
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
              child: Text("Cancel", style: GoogleFonts.inter(color: Colors.white.withValues(alpha: 0.7))),
            ),
            ElevatedButton(
              onPressed: () {
                final customName = customTextController.text.trim();
                if (customName.isNotEmpty) {
                  setState(() {
                    _categoryIcons[customName] = tempSelectedIcon;
                    if (!_categories.contains(customName)) {
                      _categories.insert(_categories.length - 1, customName);
                    }
                    _selectedCategory = customName;
                    ExpenseCompanyService.addCustomCategory(companyId: widget.companyId, userId: widget.userId, name: customName);
                  });
                  Navigator.pop(ctx);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: darkSurface,
                foregroundColor: Colors.white,
                elevation: 0,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text("Add Category", style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _showCategoryBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: darkText.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Select Category",
                  style: GoogleFonts.fraunces(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: darkText,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: darkText, size: 22),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Flexible(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.1,
                  ),
                  itemCount: _categories.length,
                  itemBuilder: (context, index) {
                    final cat = _categories[index];
                    final isCustomAction = cat == "+ Add Custom Category...";
                    final isSelected = _selectedCategory == cat;
                    final iconData = isCustomAction ? Icons.add_circle_outline_rounded : _getCategoryIcon(cat);

                    return InkWell(
                      onTap: () {
                        Navigator.pop(ctx);
                        if (isCustomAction) {
                          _promptCustomCategoryDialog();
                        } else {
                          setState(() => _selectedCategory = cat);
                        }
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? darkSurface
                                  : (isCustomAction ? forestDark.withValues(alpha: 0.1) : const Color(0xFFF1F5F9)),
                              shape: BoxShape.circle,
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: darkSurface.withValues(alpha: 0.25),
                                        blurRadius: 6,
                                        offset: const Offset(0, 3),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Icon(
                              iconData,
                              size: 22,
                              color: isSelected ? Colors.white : (isCustomAction ? forestDark : darkText),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            isCustomAction ? "+ Custom" : cat,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 11.5,
                              fontWeight: isSelected || isCustomAction ? FontWeight.bold : FontWeight.w500,
                              color: isSelected ? darkSurface : (isCustomAction ? forestDark : darkText),
                              height: 1.15,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showVisibleToBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final allIds = widget.companyMembers
              .map((m) => (m["userId"] ?? m["_id"])?.toString() ?? "")
              .where((id) => id.isNotEmpty)
              .toSet();
          final isAllSelected = _selectedVisibleUserIds.length == allIds.length;

          return Container(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: darkText.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Visible To Members",
                      style: GoogleFonts.fraunces(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                        color: darkText,
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          if (isAllSelected) {
                            _selectedVisibleUserIds = {widget.userId};
                          } else {
                            _selectedVisibleUserIds = Set.from(allIds);
                          }
                        });
                        setModalState(() {});
                      },
                      child: Text(
                        isAllSelected ? "Deselect All" : "Select All",
                        style: GoogleFonts.inter(
                          color: forestDark,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  "Choose members who can view this expense in their ledger until settled.",
                  style: GoogleFonts.inter(color: darkText.withValues(alpha: 0.55), fontSize: 12),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const BouncingScrollPhysics(),
                    itemCount: widget.companyMembers.length,
                    separatorBuilder: (_, __) => Divider(height: 1, color: Colors.black.withValues(alpha: 0.06)),
                    itemBuilder: (context, index) {
                      final member = widget.companyMembers[index];
                      final uId = (member["userId"] ?? member["_id"])?.toString() ?? "";
                      final name = member["name"]?.toString() ?? "Member";
                      final isSelf = uId == widget.userId;
                      final isChecked = _selectedVisibleUserIds.contains(uId) || isSelf;

                      return CheckboxListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        activeColor: forestDark,
                        checkColor: Colors.white,
                        title: Text(
                          isSelf ? "$name (You)" : name,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: isChecked ? FontWeight.bold : FontWeight.w500,
                            color: darkText,
                          ),
                        ),
                        subtitle: Text(
                          isSelf ? "Expense Creator (Always visible)" : (isChecked ? "Can view expense" : "Hidden until settled"),
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            color: isChecked ? forestDark : darkText.withValues(alpha: 0.4),
                          ),
                        ),
                        value: isChecked,
                        onChanged: isSelf
                            ? null
                            : (val) {
                                setState(() {
                                  if (val == true) {
                                    _selectedVisibleUserIds.add(uId);
                                  } else {
                                    _selectedVisibleUserIds.remove(uId);
                                  }
                                });
                                setModalState(() {});
                              },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: forestDark,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text("Done", style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14.5)),
                  ),
                ),
              ],
            ),
          );
        },
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
          backgroundColor: const Color(0xFFC53030),
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

    if (widget.isAdmin && _logAs == "company" && _fundId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Select the bank account or InCash this expense is paid from")),
      );
      return;
    }

    setState(() => _isSaving = true);

    final res = await ExpenseCompanyService.createExpense(
      companyId: widget.companyId,
      userId: widget.userId,
      amount: double.parse(_amountController.text.trim()),
      description: _descController.text.trim(),
      category: _selectedCategory,
      date: _selectedDate,
      attachment: _base64Image ?? "",
      logAs: widget.isAdmin ? _logAs : "self",
      visibleTo: _selectedVisibleUserIds.toList(),
      fundId: (widget.isAdmin && _logAs == "company") ? _fundId : null,
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
          backgroundColor: const Color(0xFFC53030),
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
              color: darkSurface,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: const Icon(Icons.arrow_back_rounded, color: mintAccent, size: 20),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "Add Expense",
          style: GoogleFonts.fraunces(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 17),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: Colors.black.withValues(alpha: 0.06), width: 1.0),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 9,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.isAdmin && widget.lockedLogAs == null) ...[
                    Text(
                      "Log Expense As *",
                      style: GoogleFonts.inter(color: darkText, fontWeight: FontWeight.bold, fontSize: 13.5),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
                      ),
                      padding: const EdgeInsets.all(4),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _logAs = "company"),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: _logAs == "company" ? darkSurface : Colors.transparent,
                                  borderRadius: BorderRadius.circular(11),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.business_rounded,
                                      size: 16,
                                      color: _logAs == "company" ? mintAccent : darkText.withValues(alpha: 0.6),
                                    ),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        "Company (${widget.companyName})",
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.inter(
                                          color: _logAs == "company" ? Colors.white : darkText,
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
                              onTap: () => setState(() => _logAs = "self"),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: _logAs == "self" ? darkSurface : Colors.transparent,
                                  borderRadius: BorderRadius.circular(11),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.person_rounded,
                                      size: 16,
                                      color: _logAs == "self" ? mintAccent : darkText.withValues(alpha: 0.6),
                                    ),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        "Self (${widget.userName.split(' ').first})",
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.inter(
                                          color: _logAs == "self" ? Colors.white : darkText,
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
                      _logAs == "company"
                          ? "• Logged directly as official company expense (Settled)."
                          : "• Logged as individual member expense (Outstanding). Requires settlement.",
                      style: GoogleFonts.inter(color: darkText.withValues(alpha: 0.55), fontSize: 11, fontStyle: FontStyle.italic),
                    ),
                    const SizedBox(height: 16),
                  ],

                  if (widget.isAdmin && _logAs == "company") ...[
                    Text(
                      "Paid From *",
                      style: GoogleFonts.inter(color: darkText, fontWeight: FontWeight.bold, fontSize: 13.5),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: _fundId,
                      isExpanded: true,
                      dropdownColor: Colors.white,
                      hint: Text("Select bank account or InCash", style: GoogleFonts.inter(color: darkText.withValues(alpha: 0.5), fontSize: 14)),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.08))),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.08))),
                      ),
                      items: [
                        DropdownMenuItem<String>(
                          value: "cash",
                          child: Text("InCash (₹${widget.cashBalance.toStringAsFixed(2)})",
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(color: darkText, fontWeight: FontWeight.w600, fontSize: 14)),
                        ),
                        ...widget.bankAccounts.map((b) {
                          final number = (b["accountNumber"] ?? "").toString();
                          final last4 = number.length > 4 ? number.substring(number.length - 4) : number;
                          final bal = ((b["balance"] as num?) ?? 0).toStringAsFixed(2);
                          return DropdownMenuItem<String>(
                            value: b["_id"].toString(),
                            child: Text("${b["bankName"]} •••• $last4 (₹$bal)",
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(color: darkText, fontWeight: FontWeight.w600, fontSize: 14)),
                          );
                        }),
                      ],
                      onChanged: (v) => setState(() => _fundId = v),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Category Selector
                  Text(
                    "Category",
                    style: GoogleFonts.inter(color: darkText, fontWeight: FontWeight.bold, fontSize: 13.5),
                  ),
                  const SizedBox(height: 5),
                  InkWell(
                    onTap: _showCategoryBottomSheet,
                    borderRadius: BorderRadius.circular(11),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(_getCategoryIcon(_selectedCategory), color: darkSurface, size: 18),
                              const SizedBox(width: 9),
                              Text(
                                _selectedCategory,
                                style: GoogleFonts.inter(color: darkText, fontWeight: FontWeight.w600, fontSize: 14),
                              ),
                            ],
                          ),
                          const Icon(Icons.keyboard_arrow_down_rounded, color: darkSurface, size: 20),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Amount Field
                  Text(
                    "Amount (₹) *",
                    style: GoogleFonts.inter(color: darkText, fontWeight: FontWeight.bold, fontSize: 13.5),
                  ),
                  const SizedBox(height: 5),
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
                      color: darkText,
                      fontSize: 16.5,
                      fontWeight: FontWeight.bold,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: "0.00",
                      hintStyle: GoogleFonts.ibmPlexMono(color: darkText.withValues(alpha: 0.3), fontSize: 16.5),
                      prefixIcon: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                        child: Text("₹", style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.bold, color: darkText)),
                      ),
                      prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.08))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.08))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: darkSurface, width: 1.4)),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Description Field
                  Text(
                    "Description / Purpose *",
                    style: GoogleFonts.inter(color: darkText, fontWeight: FontWeight.bold, fontSize: 13.5),
                  ),
                  const SizedBox(height: 5),
                  TextFormField(
                    controller: _descController,
                    validator: (val) => val == null || val.trim().isEmpty ? "Description is required" : null,
                    style: GoogleFonts.inter(color: darkText, fontSize: 14, fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: "e.g. Office lunch, Flight tickets",
                      hintStyle: GoogleFonts.inter(color: darkText.withValues(alpha: 0.4), fontSize: 13.5),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      prefixIcon: const Icon(Icons.description_rounded, color: darkSurface, size: 18),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.08))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.08))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: darkSurface, width: 1.4)),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Date Selector
                  Text(
                    "Expense Date",
                    style: GoogleFonts.inter(color: darkText, fontWeight: FontWeight.bold, fontSize: 13.5),
                  ),
                  const SizedBox(height: 5),
                  InkWell(
                    onTap: _selectDate,
                    borderRadius: BorderRadius.circular(11),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.calendar_today_rounded, color: darkSurface, size: 18),
                              const SizedBox(width: 9),
                              Text(
                                DateFormat('dd MMM yyyy').format(_selectedDate),
                                style: GoogleFonts.inter(color: darkText, fontWeight: FontWeight.w600, fontSize: 14),
                              ),
                            ],
                          ),
                          const Icon(Icons.edit_calendar_rounded, color: darkSurface, size: 18),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  const SizedBox(height: 14),

                  // Visible To Member Selector Dropdown Trigger (Only when logged as Self/User expense)
                  if (!widget.isAdmin || _logAs == "self") ...[
                    Text(
                      "Visible To (Select Members)",
                      style: GoogleFonts.inter(color: darkText, fontWeight: FontWeight.bold, fontSize: 13.5),
                    ),
                    const SizedBox(height: 5),
                    InkWell(
                      onTap: _showVisibleToBottomSheet,
                      borderRadius: BorderRadius.circular(11),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  const Icon(Icons.people_alt_rounded, color: darkSurface, size: 18),
                                  const SizedBox(width: 9),
                                  Expanded(
                                    child: Text(
                                      _selectedVisibleUserIds.length == widget.companyMembers.length
                                          ? "All Members (${widget.companyMembers.length})"
                                          : "${_selectedVisibleUserIds.length} of ${widget.companyMembers.length} Members Selected",
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.inter(
                                        color: darkText,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: darkSurface.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _selectedVisibleUserIds.length == widget.companyMembers.length ? "All" : "${_selectedVisibleUserIds.length}",
                                    style: GoogleFonts.inter(color: darkSurface, fontWeight: FontWeight.bold, fontSize: 12),
                                  ),
                                  const SizedBox(width: 3),
                                  const Icon(Icons.keyboard_arrow_down_rounded, color: darkSurface, size: 18),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      "• Selected members can view this expense. Restriction automatically unlocks for everyone once paid/settled.",
                      style: GoogleFonts.inter(color: darkText.withValues(alpha: 0.55), fontSize: 11, fontStyle: FontStyle.italic),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // Receipt Attachment
                  Text(
                    "Receipt / Attachment (Optional)",
                    style: GoogleFonts.inter(color: darkText, fontWeight: FontWeight.bold, fontSize: 13.5),
                  ),
                  const SizedBox(height: 5),
                  GestureDetector(
                    onTap: _pickReceiptImage,
                    child: Container(
                      width: double.infinity,
                      height: 58,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(color: Colors.black.withValues(alpha: 0.08), width: 1.0),
                      ),
                      child: _base64Image != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.memory(
                                base64Decode(_base64Image!.split(',').last),
                                fit: BoxFit.cover,
                              ),
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.cloud_upload_outlined, color: darkSurface, size: 19),
                                const SizedBox(height: 3),
                                Text(
                                  "Tap to upload receipt image",
                                  style: GoogleFonts.inter(color: darkText.withValues(alpha: 0.5), fontSize: 12.5, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 17),

                  // Save Expense Button
                  SizedBox(
                    width: double.infinity,
                    height: 47,
                    child: ElevatedButton.icon(
                      onPressed: _isSaving ? null : _submitExpense,
                      icon: _isSaving
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: mintAccent, strokeWidth: 2.2))
                          : const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                      label: Text(
                        _isSaving ? "Saving Expense..." : "Post Expense",
                        style: GoogleFonts.inter(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: darkSurface,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
