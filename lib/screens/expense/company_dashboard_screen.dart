import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../services/expense_company_service.dart';
import 'add_expense_screen.dart';
import 'company_settings_screen.dart';
import 'pay_expense_modal.dart';
import 'received_expense_modal.dart';
import 'edit_payment_modal.dart';

class CompanyDashboardScreen extends StatefulWidget {
  final String userId;
  final String userName;
  final List<Map<String, dynamic>> companies;
  final String initialCompanyId;

  const CompanyDashboardScreen({
    Key? key,
    required this.userId,
    required this.userName,
    required this.companies,
    required this.initialCompanyId,
  }) : super(key: key);

  @override
  State<CompanyDashboardScreen> createState() => _CompanyDashboardScreenState();
}

class _CompanyDashboardScreenState extends State<CompanyDashboardScreen> {
  static const Color creamSheet = Color(0xFF0C5F41);
  static const Color darkSurface = Color(0xFF0C3826);
  static const Color forestDark = Color(0xFF0C5F41);
  static const Color mintAccent = Color(0xFF10B981);
  static const Color darkText = Color(0xFF1E293B);
  static const Color terracotta = Color(0xFFB8452D);
  static const Color emerald = Color(0xFF10B981);

  late String _selectedCompanyId;
  List<Map<String, dynamic>> _userCompanies = [];
  Map<String, dynamic>? _currentCompany;
  List<Map<String, dynamic>> _companyMembers = [];
  String _currentUserRole = "member";

  bool _isLoading = true;
  List<Map<String, dynamic>> _expenses = [];
  final Set<String> _expandedExpenseIds = {};
  double _totalReceivable = 0.0;
  double _totalPayable = 0.0;
  double _totalCompanySpent = 0.0;
  double _netBalance = 0.0;

  String _searchQuery = "";
  String _selectedStatusFilter = "All"; // "All", "Outstanding", "Paid"
  String _selectedCategoryFilter = "All";
  final TextEditingController _searchController = TextEditingController();
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    _userCompanies = List.from(widget.companies);
    _selectedCompanyId = widget.initialCompanyId;

    // Hydrate cached data synchronously for instantaneous 0ms display
    final cachedExpenses = ExpenseCompanyService.getCachedExpenses(_selectedCompanyId);
    if (cachedExpenses != null && cachedExpenses.isNotEmpty) {
      _expenses = List.from(cachedExpenses);
      _isLoading = false;
    }
    final cachedSummary = ExpenseCompanyService.getCachedSummary(_selectedCompanyId, widget.userId);
    if (cachedSummary != null) {
      _totalReceivable = (cachedSummary["totalReceivable"] as num?)?.toDouble() ?? 0.0;
      _totalPayable = (cachedSummary["totalPayable"] as num?)?.toDouble() ?? 0.0;
      _totalCompanySpent = (cachedSummary["totalCompanySpent"] as num?)?.toDouble() ?? 0.0;
      _netBalance = (cachedSummary["netBalance"] as num?)?.toDouble() ?? 0.0;
      _isLoading = false;
    }
    final cachedDetails = ExpenseCompanyService.getCachedDetails(_selectedCompanyId, widget.userId);
    if (cachedDetails != null && cachedDetails["success"] == true) {
      _currentCompany = cachedDetails["company"];
      _companyMembers = List<Map<String, dynamic>>.from(cachedDetails["members"] ?? []);
      _currentUserRole = cachedDetails["currentUserRole"] ?? "member";
    }

    _refreshDashboard(showLoading: _expenses.isEmpty);

    // Auto-refresh silently every 5 seconds in background so changes from backend update immediately
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && !_isLoading) {
        _refreshDashboard(showLoading: false);
      }
    });
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  DateTimeRange? _selectedDateRange;

  List<Map<String, dynamic>> get _filteredExpenses {
    final list = _expenses.where((exp) {
      if (_searchQuery.trim().isNotEmpty) {
        final query = _searchQuery.trim().toLowerCase();
        final desc = (exp["description"] ?? "").toString().toLowerCase();
        final cat = (exp["category"] ?? "").toString().toLowerCase();
        final creator = exp["createdBy"] != null ? (exp["createdBy"]["name"] ?? "").toString().toLowerCase() : "";
        final amountStr = exp["amount"] != null ? exp["amount"].toString() : "";
        if (!desc.contains(query) && !cat.contains(query) && !creator.contains(query) && !amountStr.contains(query)) {
          return false;
        }
      }

      if (_selectedStatusFilter != "All") {
        final isPaid = exp["status"] == "paid" || exp["isSettled"] == true;
        if (_selectedStatusFilter == "Paid" && !isPaid) return false;
        if (_selectedStatusFilter == "Outstanding" && isPaid) return false;
      }

      if (_selectedCategoryFilter != "All") {
        final cat = (exp["category"] ?? "").toString().toLowerCase();
        if (cat != _selectedCategoryFilter.toLowerCase()) return false;
      }

      if (_selectedDateRange != null) {
        final expDateRaw = exp["date"] ?? exp["createdAt"];
        if (expDateRaw != null) {
          final expDate = DateTime.parse(expDateRaw.toString());
          final start = DateTime(_selectedDateRange!.start.year, _selectedDateRange!.start.month, _selectedDateRange!.start.day);
          final end = DateTime(_selectedDateRange!.end.year, _selectedDateRange!.end.month, _selectedDateRange!.end.day, 23, 59, 59);
          if (expDate.isBefore(start) || expDate.isAfter(end)) {
            return false;
          }
        }
      }

      return true;
    }).toList();

    list.sort((a, b) {
      final aDateRaw = a["createdAt"] ?? a["date"];
      final bDateRaw = b["createdAt"] ?? b["date"];
      final aDate = aDateRaw != null ? DateTime.tryParse(aDateRaw.toString()) ?? DateTime(1970) : DateTime(1970);
      final bDate = bDateRaw != null ? DateTime.tryParse(bDateRaw.toString()) ?? DateTime(1970) : DateTime(1970);
      return bDate.compareTo(aDate);
    });

    return list;
  }

  List<String> get _availableCategories {
    final categories = <String>["All"];
    for (final exp in _expenses) {
      final cat = exp["category"]?.toString().trim();
      if (cat != null && cat.isNotEmpty && !categories.contains(cat)) {
        categories.add(cat);
      }
    }
    return categories;
  }

  bool get _isAdmin {
    if (_currentUserRole == "admin") return true;
    if (_currentCompany != null) {
      final creatorId = _currentCompany!["createdBy"];
      if (creatorId != null) {
        if (creatorId is Map && creatorId["_id"]?.toString() == widget.userId) return true;
        if (creatorId.toString() == widget.userId) return true;
      }
    }
    return false;
  }

  Future<void> _refreshDashboard({bool showLoading = false}) async {
    if (showLoading) {
      setState(() => _isLoading = true);
    }

    try {
      // Execute all dashboard requests concurrently in parallel using Future.wait
      final results = await Future.wait([
        ExpenseCompanyService.getUserCompanies(widget.userId),
        ExpenseCompanyService.getCompanyDetails(_selectedCompanyId, widget.userId),
        ExpenseCompanyService.getCompanyExpenses(_selectedCompanyId, userId: widget.userId),
        ExpenseCompanyService.getCompanyBalanceSummary(
          companyId: _selectedCompanyId,
          userId: widget.userId,
        ),
      ]);

      final updatedCompanies = results[0] as List<Map<String, dynamic>>;
      final detailsRes = results[1] as Map<String, dynamic>;
      final expensesList = results[2] as List<Map<String, dynamic>>;
      final summaryRes = results[3] as Map<String, dynamic>;

      if (updatedCompanies.isNotEmpty) {
        _userCompanies = updatedCompanies;
        if (!_userCompanies.any((c) => c["_id"].toString() == _selectedCompanyId)) {
          _selectedCompanyId = _userCompanies.first["_id"].toString();
        }
      }

      if (detailsRes["success"] == true) {
        _currentCompany = detailsRes["company"];
        _companyMembers = List<Map<String, dynamic>>.from(detailsRes["members"] ?? []);
        _currentUserRole = detailsRes["currentUserRole"] ?? "member";
      }

      if (!mounted) return;

      setState(() {
        _expenses = expensesList;
        _totalReceivable = (summaryRes["totalReceivable"] as num?)?.toDouble() ?? 0.0;
        _totalPayable = (summaryRes["totalPayable"] as num?)?.toDouble() ?? 0.0;
        _totalCompanySpent = (summaryRes["totalCompanySpent"] as num?)?.toDouble() ?? 0.0;
        _netBalance = (summaryRes["netBalance"] as num?)?.toDouble() ?? 0.0;
      });
    } catch (_) {
      // Ignore exception to let finally block clear loading indicator
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _openFilterModalSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final hasActiveFilters = _selectedStatusFilter != "All" ||
                _selectedCategoryFilter != "All" ||
                _selectedDateRange != null;

            return Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Modal Handle
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: darkText.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Header Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.tune_rounded, color: forestDark, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            "Filter Expenses",
                            style: GoogleFonts.fraunces(
                              color: darkText,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      if (hasActiveFilters)
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _selectedStatusFilter = "All";
                              _selectedCategoryFilter = "All";
                              _selectedDateRange = null;
                            });
                            setModalState(() {});
                          },
                          child: Text(
                            "Reset All",
                            style: GoogleFonts.inter(
                              color: terracotta,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const Divider(height: 24),

                  // 1. Status Filter
                  Text(
                    "STATUS",
                    style: GoogleFonts.inter(
                      color: darkText.withValues(alpha: 0.5),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildModalFilterChip(
                        label: "All Status",
                        isSelected: _selectedStatusFilter == "All",
                        onTap: () {
                          setState(() => _selectedStatusFilter = "All");
                          setModalState(() {});
                        },
                      ),
                      _buildModalFilterChip(
                        label: "Outstanding",
                        isSelected: _selectedStatusFilter == "Outstanding",
                        badgeColor: terracotta,
                        onTap: () {
                          setState(() => _selectedStatusFilter = "Outstanding");
                          setModalState(() {});
                        },
                      ),
                      _buildModalFilterChip(
                        label: "Paid / Settled",
                        isSelected: _selectedStatusFilter == "Paid",
                        badgeColor: emerald,
                        onTap: () {
                          setState(() => _selectedStatusFilter = "Paid");
                          setModalState(() {});
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // 2. Date Filter
                  Text(
                    "DATE RANGE",
                    style: GoogleFonts.inter(
                      color: darkText.withValues(alpha: 0.5),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                  // Quick Date Preset Chips
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildDatePresetChip(
                          label: "Today",
                          isSelected: _isPresetActive("today"),
                          onTap: () {
                            final now = DateTime.now();
                            final range = DateTimeRange(start: now, end: now);
                            setState(() => _selectedDateRange = range);
                            setModalState(() {});
                          },
                        ),
                        const SizedBox(width: 6),
                        _buildDatePresetChip(
                          label: "This Week",
                          isSelected: _isPresetActive("week"),
                          onTap: () {
                            final now = DateTime.now();
                            final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
                            final range = DateTimeRange(start: startOfWeek, end: now);
                            setState(() => _selectedDateRange = range);
                            setModalState(() {});
                          },
                        ),
                        const SizedBox(width: 6),
                        _buildDatePresetChip(
                          label: "This Month",
                          isSelected: _isPresetActive("month"),
                          onTap: () {
                            final now = DateTime.now();
                            final startOfMonth = DateTime(now.year, now.month, 1);
                            final range = DateTimeRange(start: startOfMonth, end: now);
                            setState(() => _selectedDateRange = range);
                            setModalState(() {});
                          },
                        ),
                        const SizedBox(width: 6),
                        _buildDatePresetChip(
                          label: "Last 30 Days",
                          isSelected: _isPresetActive("30days"),
                          onTap: () {
                            final now = DateTime.now();
                            final start30 = now.subtract(const Duration(days: 30));
                            final range = DateTimeRange(start: start30, end: now);
                            setState(() => _selectedDateRange = range);
                            setModalState(() {});
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Custom Calendar Range Picker Box
                  GestureDetector(
                    onTap: () async {
                      final picked = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                        initialDateRange: _selectedDateRange,
                        builder: (c, child) {
                          return Theme(
                            data: ThemeData.light().copyWith(
                              scaffoldBackgroundColor: Colors.white,
                              dialogBackgroundColor: Colors.white,
                              colorScheme: const ColorScheme.light(
                                primary: forestDark,
                                onPrimary: Colors.white,
                                surface: Colors.white,
                                onSurface: darkText,
                                secondary: emerald,
                              ),
                              appBarTheme: AppBarTheme(
                                backgroundColor: forestDark,
                                iconTheme: const IconThemeData(color: Colors.white),
                                titleTextStyle: GoogleFonts.fraunces(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                            ),
                            child: child!,
                          );
                        },
                      );
                      if (picked != null) {
                        setState(() => _selectedDateRange = picked);
                        setModalState(() {});
                      }
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: _selectedDateRange != null ? forestDark.withValues(alpha: 0.08) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _selectedDateRange != null ? forestDark : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.calendar_today_rounded,
                                size: 16,
                                color: _selectedDateRange != null ? forestDark : darkText.withValues(alpha: 0.6),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                _selectedDateRange != null
                                    ? "${DateFormat('dd MMM yyyy').format(_selectedDateRange!.start)}  →  ${DateFormat('dd MMM yyyy').format(_selectedDateRange!.end)}"
                                    : "Pick Custom Date Range...",
                                style: GoogleFonts.inter(
                                  color: _selectedDateRange != null ? forestDark : darkText,
                                  fontWeight: _selectedDateRange != null ? FontWeight.bold : FontWeight.w500,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          if (_selectedDateRange != null)
                            GestureDetector(
                              onTap: () {
                                setState(() => _selectedDateRange = null);
                                setModalState(() {});
                              },
                              child: const Icon(Icons.close_rounded, size: 16, color: terracotta),
                            )
                          else
                            Icon(Icons.chevron_right_rounded, size: 18, color: darkText.withValues(alpha: 0.4)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 3. Category Filter
                  if (_availableCategories.length > 1) ...[
                    Text(
                      "CATEGORIES",
                      style: GoogleFonts.inter(
                        color: darkText.withValues(alpha: 0.5),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _availableCategories.map((cat) {
                        final isSelected = _selectedCategoryFilter == cat;
                        return _buildModalFilterChip(
                          label: cat,
                          isSelected: isSelected,
                          badgeColor: forestDark,
                          onTap: () {
                            setState(() {
                              _selectedCategoryFilter = isSelected ? "All" : cat;
                            });
                            setModalState(() {});
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Apply Button
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: forestDark,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: Text(
                        "Apply Filters",
                        style: GoogleFonts.inter(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            );
          },
        );
      },
    );
  }

  bool _isPresetActive(String type) {
    if (_selectedDateRange == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = DateTime(_selectedDateRange!.start.year, _selectedDateRange!.start.month, _selectedDateRange!.start.day);
    final end = DateTime(_selectedDateRange!.end.year, _selectedDateRange!.end.month, _selectedDateRange!.end.day);

    if (type == "today") {
      return start == today && end == today;
    } else if (type == "week") {
      final startOfWeek = today.subtract(Duration(days: today.weekday - 1));
      return start == startOfWeek && end == today;
    } else if (type == "month") {
      final startOfMonth = DateTime(today.year, today.month, 1);
      return start == startOfMonth && end == today;
    } else if (type == "30days") {
      final start30 = today.subtract(const Duration(days: 30));
      return start == start30 && end == today;
    }
    return false;
  }

  Widget _buildDatePresetChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? forestDark : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? forestDark : const Color(0xFFE2E8F0),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            color: isSelected ? Colors.white : darkText,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildModalFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    Color? badgeColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? (badgeColor ?? forestDark) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? (badgeColor ?? forestDark) : const Color(0xFFE2E8F0),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            color: isSelected ? Colors.white : darkText,
            fontSize: 12.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  void _openPayModal(Map<String, dynamic> expense) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: PayExpenseModal(
            expense: expense,
            userId: widget.userId,
            isAdmin: _isAdmin,
          ),
        );
      },
    );
    if (result == true) {
      _refreshDashboard(showLoading: false);
    }
  }

  void _openReceivedModal(Map<String, dynamic> expense) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: ReceivedExpenseModal(
            expense: expense,
            userId: widget.userId,
            companyMembers: _companyMembers,
          ),
        );
      },
    );
    if (result == true) {
      _refreshDashboard(showLoading: false);
    }
  }

  Future<void> _changeExpenseStatus(Map<String, dynamic> expense, String targetStatus) async {
    final bool isTargetPaid = targetStatus == "paid";
    final String title = isTargetPaid ? "Mark Expense as Paid?" : "Change Status to Unpaid?";
    final String contentMsg = isTargetPaid
        ? "This expense will be marked as Paid (Settled).\n\nAre you sure you want to proceed?"
        : "This expense will be reset to Outstanding (Unpaid) status, and any existing settlement history for this expense will be cleared.\n\nAre you sure you want to proceed?";
    final String confirmBtnText = isTargetPaid ? "Mark as Paid" : "Reset to Unpaid";

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          title,
          style: GoogleFonts.fraunces(color: darkText, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        content: Text(
          contentMsg,
          style: GoogleFonts.inter(color: darkText.withValues(alpha: 0.8), fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              "Cancel",
              style: GoogleFonts.inter(color: Colors.grey[700], fontWeight: FontWeight.bold),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: isTargetPaid ? forestDark : terracotta,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(confirmBtnText, style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final res = await ExpenseCompanyService.resetExpenseToUnpaid(
      expenseId: expense["_id"].toString(),
      userId: widget.userId,
      status: targetStatus,
    );

    if (!mounted) return;

    if (res["success"] == true) {
      setState(() {
        expense["status"] = targetStatus;
        if (targetStatus == "outstanding") {
          expense["settlements"] = [];
          expense["settlement"] = null;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isTargetPaid ? "Expense status changed to Paid (Settled)" : "Expense status changed to Unpaid (Outstanding)",
            style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          backgroundColor: forestDark,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      _refreshDashboard(showLoading: false);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            res["message"] ?? "Failed to update expense status",
            style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          backgroundColor: terracotta,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  Future<void> _openEditPaymentModal(Map<String, dynamic> expense, Map<String, dynamic>? existingSettlement) async {
    final updated = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => EditPaymentModal(
        expense: expense,
        userId: widget.userId,
        existingSettlement: existingSettlement,
      ),
    );

    if (updated == true) {
      _refreshDashboard(showLoading: false);
    }
  }


  Widget _buildImageWidget(String imageStr) {
    if (imageStr.isEmpty) return const SizedBox.shrink();
    try {
      String cleanBase64 = imageStr;
      if (imageStr.contains(",")) {
        cleanBase64 = imageStr.split(",").last;
      }
      final Uint8List bytes = base64Decode(cleanBase64.trim());
      return Container(
        constraints: const BoxConstraints(maxHeight: 160),
        width: double.infinity,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.memory(
            bytes,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              padding: const EdgeInsets.all(16),
              color: Colors.grey.withValues(alpha: 0.1),
              child: const Text("Unable to render image proof"),
            ),
          ),
        ),
      );
    } catch (_) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          children: [
            Icon(Icons.broken_image_rounded, color: Colors.grey),
            SizedBox(width: 8),
            Text("Invalid image data"),
          ],
        ),
      );
    }
  }

  Future<void> _confirmDeleteExpense(Map<String, dynamic> expense) async {
    final expenseId = expense["_id"]?.toString() ?? "";
    final desc = expense["description"] ?? "Expense";

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.delete_outline_rounded, color: terracotta, size: 24),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                "Delete Expense",
                style: GoogleFonts.inter(color: darkText, fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ],
        ),
        content: Text(
          "Are you sure you want to permanently delete \"$desc\"? This will remove all associated payment settlements and cannot be undone.",
          style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF475569)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text("Cancel", style: GoogleFonts.inter(color: const Color(0xFF64748B), fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: terracotta,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text("Delete", style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Deleting expense...")),
        );
      }
      final res = await ExpenseCompanyService.deleteExpense(
        expenseId: expenseId,
        userId: widget.userId,
        companyId: _selectedCompanyId,
      );
      if (!mounted) return;
      if (res["success"] == true) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Expense deleted successfully"),
            backgroundColor: emerald,
          ),
        );
        _refreshDashboard(showLoading: false);
      } else {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res["message"] ?? "Failed to delete expense"),
            backgroundColor: terracotta,
          ),
        );
      }
    }
  }

  void _openExpenseAuditModal(Map<String, dynamic> expense) {
    final creator = expense["createdBy"];
    final creatorId = creator != null ? (creator is Map ? creator["_id"]?.toString() ?? "" : creator.toString()) : "";
    final creatorName = creator != null ? (creator is Map ? creator["name"] ?? "Member" : "Member") : "Member";
    final creatorEmail = creator != null ? (creator is Map ? creator["email"] ?? "" : "") : "";
    final isPaid = expense["status"] == "paid";
    final amount = (expense["amount"] as num?)?.toDouble() ?? 0.0;
    final dateStr = expense["date"] != null
        ? DateFormat("dd MMM, yyyy • hh:mm a").format(DateTime.parse(expense["date"]))
        : "";

    final settlementSingle = expense["settlement"];
    final String paidById = settlementSingle != null && settlementSingle["paidBy"] != null
        ? (settlementSingle["paidBy"] is Map ? settlementSingle["paidBy"]["_id"]?.toString() ?? "" : settlementSingle["paidBy"].toString())
        : "";
    final String paidToId = settlementSingle != null && settlementSingle["paidTo"] != null
        ? (settlementSingle["paidTo"] is Map ? settlementSingle["paidTo"]["_id"]?.toString() ?? "" : settlementSingle["paidTo"].toString())
        : "";

    final bool isAdmin = _isAdmin;
    final bool isCreator = creatorId == widget.userId;
    final bool isPayer = paidById == widget.userId;
    final bool isReceiver = paidToId == widget.userId;
    final bool canManagePayment = isAdmin || isCreator || isPayer || isReceiver;

    final settlementsRaw = expense["settlements"] as List?;
    final List<Map<String, dynamic>> settlementList = [];
    if (settlementsRaw != null && settlementsRaw.isNotEmpty) {
      for (var item in settlementsRaw) {
        if (item is Map<String, dynamic>) {
          settlementList.add(item);
        } else if (item != null) {
          settlementList.add(Map<String, dynamic>.from(item));
        }
      }
    } else if (expense["settlement"] != null) {
      final s = expense["settlement"];
      if (s is Map<String, dynamic>) {
        settlementList.add(s);
      }
    }

    final bool canDeleteExpense = isAdmin || (isCreator && !isPaid && settlementList.isEmpty);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
          decoration: const BoxDecoration(
            color: creamSheet,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Fixed Drag Handle & Modal Header
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: darkSurface,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                          ),
                          child: const Icon(Icons.info_outline_rounded, color: mintAccent, size: 20),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          "Expense Audit & Details",
                          style: GoogleFonts.fraunces(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
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
                const SizedBox(height: 8),
                Divider(color: Colors.white.withValues(alpha: 0.15)),
                const SizedBox(height: 8),

                // 1. Amount & Category Box
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                                  decoration: BoxDecoration(
                                    color: darkSurface.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    expense["category"] ?? "General",
                                    style: GoogleFonts.inter(color: darkSurface, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                                  decoration: BoxDecoration(
                                    color: isPaid ? emerald.withValues(alpha: 0.12) : terracotta.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    isPaid ? "PAID / SETTLED" : "OUTSTANDING",
                                    style: GoogleFonts.inter(color: isPaid ? emerald : terracotta, fontSize: 9.5, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              expense["description"] ?? "Expense",
                              style: GoogleFonts.inter(color: darkText, fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              "₹${amount.toStringAsFixed(2)}",
                              style: GoogleFonts.fraunces(color: forestDark, fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              dateStr,
                              style: GoogleFonts.inter(color: darkText.withValues(alpha: 0.5), fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // 2. Creator & Original Bill Attachment Info
                      Text(
                        "Created By",
                        style: GoogleFonts.fraunces(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 16,
                                  backgroundColor: darkSurface,
                                  child: Text(
                                    creatorName.isNotEmpty ? creatorName[0].toUpperCase() : "M",
                                    style: GoogleFonts.inter(color: mintAccent, fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        creatorName,
                                        style: GoogleFonts.inter(color: darkText, fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                      if (creatorEmail.isNotEmpty)
                                        Text(
                                          creatorEmail,
                                          style: GoogleFonts.inter(color: darkText.withValues(alpha: 0.5), fontSize: 11),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            if (expense["attachment"] != null && expense["attachment"].toString().isNotEmpty) ...[
                              const SizedBox(height: 10),
                              const Divider(),
                              const SizedBox(height: 6),
                              Text(
                                "Original Bill / Receipt Proof:",
                                style: GoogleFonts.inter(color: darkText, fontWeight: FontWeight.bold, fontSize: 11.5),
                              ),
                              const SizedBox(height: 6),
                              _buildImageWidget(expense["attachment"].toString()),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // 3. Payment & Settlement History Timeline
                      if (settlementList.isNotEmpty) ...[
                        Text(
                          "Payment History (${settlementList.length})",
                          style: GoogleFonts.fraunces(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        ...settlementList.asMap().entries.map((entry) {
                          final idx = entry.key + 1;
                          final s = entry.value;
                          final sPayer = s["paidBy"] != null ? s["paidBy"]["name"] ?? "Member" : "Member";
                          final sPayerEmail = s["paidBy"] != null ? s["paidBy"]["email"] ?? "" : "";
                          final sReceiver = s["paidTo"] != null ? s["paidTo"]["name"] ?? "Member" : "";
                          final sMode = s["paymentMode"]?.toString().toUpperCase() ?? "CASH";
                          final sProof = s["paymentProof"]?.toString() ?? "";
                          final sDate = s["createdAt"] != null
                              ? DateFormat("dd MMM, yyyy • hh:mm a").format(DateTime.parse(s["createdAt"]))
                              : "";
                          final isFinalStep = isPaid && idx == settlementList.length;

                          return Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isFinalStep ? emerald.withValues(alpha: 0.4) : forestDark.withValues(alpha: 0.2),
                                width: isFinalStep ? 1.5 : 1.0,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: isFinalStep ? emerald.withValues(alpha: 0.12) : forestDark.withValues(alpha: 0.08),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          isFinalStep ? "Payment #$idx • Final Settlement" : "Payment #$idx",
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.inter(
                                            color: isFinalStep ? emerald : forestDark,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (sDate.isNotEmpty) ...[
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: Text(
                                          sDate,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.inter(color: darkText.withValues(alpha: 0.5), fontSize: 11),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Icon(
                                      isFinalStep ? Icons.check_circle_rounded : Icons.payment_rounded,
                                      color: isFinalStep ? emerald : forestDark,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        "Paid by $sPayer${sReceiver.isNotEmpty ? ' to $sReceiver' : ''}",
                                        style: GoogleFonts.inter(color: darkText, fontWeight: FontWeight.bold, fontSize: 14),
                                      ),
                                    ),
                                  ],
                                ),
                                if (sPayerEmail.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 26, top: 2),
                                    child: Text(
                                      sPayerEmail,
                                      style: GoogleFonts.inter(color: darkText.withValues(alpha: 0.5), fontSize: 11.5),
                                    ),
                                  ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Text(
                                      "Payment Method: ",
                                      style: GoogleFonts.inter(color: darkText.withValues(alpha: 0.6), fontSize: 12),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: forestDark.withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        sMode,
                                        style: GoogleFonts.ibmPlexMono(color: forestDark, fontWeight: FontWeight.bold, fontSize: 11.5),
                                      ),
                                    ),
                                  ],
                                ),
                                if (sProof.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  const Divider(),
                                  const SizedBox(height: 8),
                                  Text(
                                    "Proof of Payment Image (Payment #$idx):",
                                    style: GoogleFonts.inter(color: darkText, fontWeight: FontWeight.bold, fontSize: 12),
                                  ),
                                  const SizedBox(height: 8),
                                  _buildImageWidget(sProof),
                                ],
                              ],
                            ),
                          );
                        }),
                        const SizedBox(height: 12),
                      ],

                      // 4. Payment Actions (Edit Payment Details or Change to Unpaid)
                      if (canManagePayment) ...[
                        Text(
                          "Payment Options",
                          style: GoogleFonts.fraunces(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            if (isPaid || settlementList.isNotEmpty) ...[
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    _openEditPaymentModal(
                                      expense,
                                      settlementList.isNotEmpty ? settlementList.last : null,
                                    );
                                  },
                                  icon: const Icon(Icons.edit_rounded, size: 16, color: mintAccent),
                                  label: Text("Edit Payment", style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                                  style: OutlinedButton.styleFrom(
                                    backgroundColor: darkSurface,
                                    foregroundColor: Colors.white,
                                    side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                            ],
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  _changeExpenseStatus(expense, isPaid ? "outstanding" : "paid");
                                },
                                icon: Icon(isPaid ? Icons.undo_rounded : Icons.check_circle_rounded, size: 16, color: isPaid ? const Color(0xFFFCA5A5) : mintAccent),
                                label: Text(
                                  isPaid ? "Change to Unpaid" : "Mark as Paid",
                                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: darkSurface,
                                  foregroundColor: isPaid ? const Color(0xFFFCA5A5) : mintAccent,
                                  side: BorderSide(color: isPaid ? const Color(0xFFFCA5A5).withValues(alpha: 0.5) : mintAccent.withValues(alpha: 0.5)),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (canDeleteExpense) ...[
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.pop(ctx);
                                _confirmDeleteExpense(expense);
                              },
                              icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Color(0xFFFCA5A5)),
                              label: Text("Delete Expense", style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                              style: OutlinedButton.styleFrom(
                                backgroundColor: darkSurface,
                                foregroundColor: const Color(0xFFFCA5A5),
                                side: BorderSide(color: const Color(0xFFFCA5A5).withValues(alpha: 0.5)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                      ],
                    ]),
                  ),
                );
              },
            );
          }

  void _openCompanyMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: darkText.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                "Select Company Ledger",
                style: GoogleFonts.fraunces(color: darkText, fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 14),
              ListView.separated(
                shrinkWrap: true,
                physics: const BouncingScrollPhysics(),
                itemCount: _userCompanies.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final c = _userCompanies[index];
                  final isSelected = c["_id"].toString() == _selectedCompanyId;
                  return Container(
                    decoration: BoxDecoration(
                      color: isSelected ? forestDark.withValues(alpha: 0.08) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected ? forestDark : const Color(0xFFE2E8F0),
                        width: isSelected ? 1.5 : 1.0,
                      ),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      leading: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: isSelected ? forestDark : Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: isSelected ? null : Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Icon(
                          Icons.business_rounded,
                          color: isSelected ? Colors.white : forestDark,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        c["name"],
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.bold,
                          color: isSelected ? forestDark : darkText,
                          fontSize: 14.5,
                        ),
                      ),
                      subtitle: (c["details"] != null && c["details"].toString().isNotEmpty)
                          ? Text(
                              c["details"].toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                color: darkText.withValues(alpha: 0.5),
                                fontSize: 12,
                              ),
                            )
                          : null,
                      trailing: isSelected
                          ? Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: forestDark,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.check_rounded, color: Colors.white, size: 14),
                            )
                          : null,
                      onTap: () {
                        Navigator.pop(ctx);
                        setState(() {
                          _selectedCompanyId = c["_id"].toString();
                        });
                        _refreshDashboard();
                      },
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final companyName = _currentCompany?["name"] ?? "Company Dashboard";

    return Scaffold(
      backgroundColor: creamSheet,
      appBar: AppBar(
        backgroundColor: creamSheet,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF0C3826),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: const Icon(Icons.arrow_back_rounded, color: Color(0xFF10B981), size: 20),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: GestureDetector(
          onTap: _openCompanyMenu,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  companyName,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.fraunces(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF10B981), size: 22),
            ],
          ),
        ),
        actions: [
          IconButton(
            tooltip: "Company Settings",
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF0C3826),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: const Icon(Icons.settings_rounded, color: Color(0xFF10B981), size: 20),
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CompanySettingsScreen(
                    companyId: _selectedCompanyId,
                    userId: widget.userId,
                    userName: widget.userName,
                  ),
                ),
              ).then((_) => _refreshDashboard(showLoading: false));
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF0C3826),
        foregroundColor: Colors.white,
        elevation: 6,
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AddExpenseScreen(
                companyId: _selectedCompanyId,
                companyName: companyName,
                userId: widget.userId,
                userName: widget.userName,
                isAdmin: _isAdmin,
                companyMembers: _companyMembers,
              ),
            ),
          );
          if (result == true) {
            _refreshDashboard(showLoading: false);
          }
        },
        icon: const Icon(Icons.add_rounded, size: 22, color: emerald),
        label: Text(
          "Add Expense",
          style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ),
      body: RefreshIndicator(
        color: emerald,
        onRefresh: _refreshDashboard,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 90),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Balance Summary Card
              _buildBalanceSummaryCard(),
              const SizedBox(height: 24),

                    // 2. Expense Ledger Feed Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Expense Ledger",
                          style: GoogleFonts.fraunces(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          _searchQuery.isNotEmpty || _selectedStatusFilter != "All" || _selectedCategoryFilter != "All"
                              ? "${_filteredExpenses.length} / ${_expenses.length} Entries"
                              : "${_expenses.length} Entries",
                          style: GoogleFonts.ibmPlexMono(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Search & Filter Row
                    Row(
                      children: [
                        // Search Input Bar
                        Expanded(
                          child: Container(
                            height: 40,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.02),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: TextField(
                              controller: _searchController,
                              onChanged: (val) => setState(() => _searchQuery = val),
                              style: GoogleFonts.inter(color: darkText, fontSize: 13),
                              textAlignVertical: TextAlignVertical.center,
                              decoration: InputDecoration(
                                isDense: true,
                                hintText: "Search description, category...",
                                hintStyle: GoogleFonts.inter(color: darkText.withValues(alpha: 0.4), fontSize: 12.5),
                                prefixIcon: const Icon(Icons.search_rounded, color: forestDark, size: 18),
                                prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                suffixIcon: _searchQuery.isNotEmpty
                                    ? IconButton(
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        icon: const Icon(Icons.clear_rounded, size: 16, color: darkText),
                                        onPressed: () {
                                          _searchController.clear();
                                          setState(() => _searchQuery = "");
                                        },
                                      )
                                    : null,
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Filter Icon Button with Active Indicator Badge
                        Material(
                          color: (_selectedStatusFilter != "All" || _selectedCategoryFilter != "All" || _selectedDateRange != null)
                              ? mintAccent
                              : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          elevation: 1,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => _openFilterModalSheet(),
                            child: Container(
                              width: 40,
                              height: 40,
                              alignment: Alignment.center,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Icon(
                                    Icons.tune_rounded,
                                    color: (_selectedStatusFilter != "All" || _selectedCategoryFilter != "All" || _selectedDateRange != null)
                                        ? darkSurface
                                        : forestDark,
                                    size: 20,
                                  ),
                                  if (_selectedStatusFilter != "All" || _selectedCategoryFilter != "All" || _selectedDateRange != null)
                                    Positioned(
                                      top: 2,
                                      right: 2,
                                      child: Container(
                                        width: 8,
                                        height: 8,
                                        decoration: const BoxDecoration(
                                          color: Color(0xFFDC2626),
                                          shape: BoxShape.circle,
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
                    const SizedBox(height: 14),

                    // 3. Expenses List Feed
                    if (_isLoading)
                      const _ExpenseListShimmer()
                    else if (_expenses.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
                        ),
                        child: Column(
                          children: [
                            Icon(Icons.receipt_long_rounded, size: 48, color: darkText.withValues(alpha: 0.3)),
                            const SizedBox(height: 12),
                            Text(
                              "No expenses posted yet",
                              style: GoogleFonts.inter(color: darkText, fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "Tap the '+' button below to add your first expense claim.",
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(color: darkText.withValues(alpha: 0.5), fontSize: 13),
                            ),
                          ],
                        ),
                      )
                    else if (_filteredExpenses.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
                        ),
                        child: Column(
                          children: [
                            Icon(Icons.search_off_rounded, size: 40, color: darkText.withValues(alpha: 0.3)),
                            const SizedBox(height: 10),
                            Text(
                              "No matching expenses",
                              style: GoogleFonts.inter(color: darkText, fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "Try clearing search keywords or filter options.",
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(color: darkText.withValues(alpha: 0.5), fontSize: 12),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _searchQuery = "";
                                  _selectedStatusFilter = "All";
                                  _selectedCategoryFilter = "All";
                                });
                              },
                              icon: const Icon(Icons.refresh_rounded, size: 14, color: forestDark),
                              label: Text("Reset Search & Filters", style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: forestDark,
                                side: const BorderSide(color: forestDark, width: 1.2),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _filteredExpenses.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final exp = _filteredExpenses[index];
                          final dateLabel = _getDateHeaderLabel(exp["date"] ?? exp["createdAt"]);
                          final prevDateLabel = index > 0
                              ? _getDateHeaderLabel(_filteredExpenses[index - 1]["date"] ?? _filteredExpenses[index - 1]["createdAt"])
                              : null;

                          final showHeader = index == 0 || dateLabel != prevDateLabel;

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (showHeader) ...[
                                if (index > 0) const SizedBox(height: 6),
                                _buildDateHeader(dateLabel),
                              ],
                              _buildExpenseCard(exp),
                            ],
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  String _getDateHeaderLabel(dynamic dateRaw) {
    if (dateRaw == null) return "Other";
    try {
      final parsed = DateTime.parse(dateRaw.toString()).toLocal();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));
      final expDay = DateTime(parsed.year, parsed.month, parsed.day);

      if (expDay.isAtSameMomentAs(today)) {
        return "Today • ${DateFormat('dd MMM, yyyy').format(parsed)}";
      } else if (expDay.isAtSameMomentAs(yesterday)) {
        return "Yesterday • ${DateFormat('dd MMM, yyyy').format(parsed)}";
      } else {
        return DateFormat("dd MMMM, yyyy").format(parsed);
      }
    } catch (_) {
      return "Other";
    }
  }

  Widget _buildDateHeader(String dateLabel) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 6, left: 2, right: 2),
      child: Row(
        children: [
          Icon(Icons.calendar_month_rounded, size: 14, color: Colors.white.withValues(alpha: 0.85)),
          const SizedBox(width: 6),
          Text(
            dateLabel,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 1,
              color: Colors.white.withValues(alpha: 0.2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    Color? badgeColor,
  }) {
    final activeColor = badgeColor ?? forestDark;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? activeColor : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? activeColor : Colors.black.withValues(alpha: 0.1),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            color: isSelected ? Colors.white : darkText,
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildBalanceSummaryCard() {
    final netColor = _netBalance >= 0 ? const Color(0xFF0C5F41) : terracotta;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _isAdmin ? "TOTAL EXPENSE SPENT" : "YOU ARE OWED (RECEIVABLE)",
                        style: GoogleFonts.ibmPlexMono(
                          color: const Color(0xFF6B7280),
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "₹${(_isAdmin ? _totalCompanySpent : _totalReceivable).toStringAsFixed(2)}",
                        style: GoogleFonts.fraunces(
                          color: const Color(0xFF0C5F41),
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 10),
                width: 1,
                height: 32,
                color: Colors.black.withValues(alpha: 0.08),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        "YOU OWE (PAYABLE)",
                        style: GoogleFonts.ibmPlexMono(
                          color: const Color(0xFF6B7280),
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        "₹${_totalPayable.toStringAsFixed(2)}",
                        style: GoogleFonts.fraunces(
                          color: terracotta,
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Divider(color: Colors.black.withValues(alpha: 0.08), height: 1),
          const SizedBox(height: 8),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  "Net Standing Balance",
                  style: GoogleFonts.inter(
                    color: const Color(0xFF132A20),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    "${_netBalance >= 0 ? '+' : ''}₹${_netBalance.toStringAsFixed(2)}",
                    style: GoogleFonts.fraunces(
                      color: netColor,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExpenseCard(Map<String, dynamic> expense) {
    final creatorId = expense["createdBy"] != null ? expense["createdBy"]["_id"].toString() : "";
    final creatorName = expense["createdBy"] != null ? expense["createdBy"]["name"] ?? "Member" : "Member";
    final isViewerCreator = creatorId == widget.userId;

    final currentCreditor = expense["currentCreditor"] ?? expense["createdBy"];
    final creditorId = currentCreditor != null ? currentCreditor["_id"].toString() : creatorId;
    final creditorName = currentCreditor != null ? currentCreditor["name"] ?? "Member" : creatorName;
    final isViewerCreditor = creditorId == widget.userId;

    final isPaid = expense["status"] == "paid";
    final amount = (expense["amount"] as num?)?.toDouble() ?? 0.0;
    final dateStr = expense["date"] != null
        ? DateFormat("dd MMM, yyyy").format(DateTime.parse(expense["date"]))
        : "";

    final settlement = expense["settlement"];
    final settlementPayer = settlement != null && settlement["paidBy"] != null ? settlement["paidBy"]["name"] ?? "Member" : "";
    final settlementRecipient = settlement != null && settlement["paidTo"] != null ? settlement["paidTo"]["name"] ?? "Member" : creatorName;

    final String paidById = settlement != null && settlement["paidBy"] != null
        ? (settlement["paidBy"] is Map ? settlement["paidBy"]["_id"]?.toString() ?? "" : settlement["paidBy"].toString())
        : "";
    final String paidToId = settlement != null && settlement["paidTo"] != null
        ? (settlement["paidTo"] is Map ? settlement["paidTo"]["_id"]?.toString() ?? "" : settlement["paidTo"].toString())
        : "";

    final bool isAdmin = _isAdmin;
    final bool isCreator = creatorId == widget.userId;
    final bool isPayer = paidById == widget.userId;
    final bool isReceiver = paidToId == widget.userId;
    final bool canManagePayment = isAdmin || isCreator || isPayer || isReceiver;

    final String expenseId = expense["_id"]?.toString() ?? "";
    final bool isExpanded = _expandedExpenseIds.contains(expenseId);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          setState(() {
            if (isExpanded) {
              _expandedExpenseIds.remove(expenseId);
            } else {
              _expandedExpenseIds.add(expenseId);
            }
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.black.withValues(alpha: 0.08), width: 1.0),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Category, Date, Status Badge, Controls & Expand Arrow
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: forestDark.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              expense["category"] ?? "General",
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(color: forestDark, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            dateStr,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(color: darkText.withValues(alpha: 0.5), fontSize: 10),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isPaid ? emerald.withValues(alpha: 0.12) : terracotta.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isPaid ? "PAID / SETTLED" : "OUTSTANDING",
                          style: GoogleFonts.inter(
                            color: isPaid ? emerald : terracotta,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => _openExpenseAuditModal(expense),
                        behavior: HitTestBehavior.opaque,
                        child: const SizedBox(
                          width: 20,
                          height: 20,
                          child: Icon(Icons.info_outline_rounded, color: forestDark, size: 16),
                        ),
                      ),
                      if (canManagePayment) ...[
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: PopupMenuButton<String>(
                            color: Colors.white,
                            surfaceTintColor: Colors.white,
                            elevation: 6,
                            shadowColor: Colors.black.withValues(alpha: 0.2),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            constraints: const BoxConstraints(),
                            padding: EdgeInsets.zero,
                            icon: Icon(Icons.more_vert_rounded, color: darkText.withValues(alpha: 0.7), size: 16),
                            tooltip: "Payment Options",
                            onSelected: (val) {
                              if (val == "unpaid") {
                                _changeExpenseStatus(expense, "outstanding");
                              } else if (val == "mark_paid") {
                                _changeExpenseStatus(expense, "paid");
                              } else if (val == "edit") {
                                _openEditPaymentModal(expense, settlement);
                              } else if (val == "delete") {
                                _confirmDeleteExpense(expense);
                              }
                            },
                            itemBuilder: (ctx) => [
                              if (isPaid || settlement != null)
                                PopupMenuItem(
                                  value: "edit",
                                  child: Row(
                                    children: [
                                      const Icon(Icons.edit_rounded, size: 18, color: forestDark),
                                      const SizedBox(width: 10),
                                      Text(
                                        "Edit Payment Details",
                                        style: GoogleFonts.inter(fontSize: 13, color: forestDark, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                              PopupMenuItem(
                                value: isPaid ? "unpaid" : "mark_paid",
                                child: Row(
                                  children: [
                                    Icon(
                                      isPaid ? Icons.undo_rounded : Icons.check_circle_rounded,
                                      size: 18,
                                      color: isPaid ? terracotta : emerald,
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      isPaid ? "Change to Unpaid" : "Mark as Paid / Settled",
                                      style: GoogleFonts.inter(
                                        fontSize: 13,
                                        color: isPaid ? terracotta : emerald,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (isAdmin)
                                PopupMenuItem(
                                  value: "delete",
                                  child: Row(
                                    children: [
                                      const Icon(Icons.delete_outline_rounded, size: 18, color: terracotta),
                                      const SizedBox(width: 10),
                                      Text(
                                        "Delete Expense",
                                        style: GoogleFonts.inter(
                                          fontSize: 13,
                                          color: terracotta,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: Icon(
                          isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                          color: forestDark,
                          size: 18,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 2),

              // Title & Amount Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      expense["description"] ?? "Expense Claim",
                      style: GoogleFonts.inter(
                        color: darkText,
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    "₹${amount.toStringAsFixed(2)}",
                    style: GoogleFonts.fraunces(
                      color: darkText,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),

              // Creditor info (Who is currently owed money)
              Row(
                children: [
                  Icon(Icons.person_outline_rounded, size: 14, color: darkText.withValues(alpha: 0.5)),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Builder(
                      builder: (_) {
                        final String companyName = _currentCompany?["name"] ?? "Company";
                        final String logAsType = expense["logAs"] ?? (isPaid ? "company" : "self");
                        final bool isCompanyLogged = logAsType == "company";

                        final String subtext = isPaid
                            ? (isCompanyLogged
                                ? "Logged by $companyName (Company)"
                                : (isViewerCreator ? "Logged by $creatorName (You • Paid)" : "Paid by $creatorName"))
                            : (settlement != null
                                ? (isViewerCreditor
                                    ? "Paid to $settlementRecipient by You • Owed to You"
                                    : (settlement?["paidTo"]?["_id"]?.toString() == widget.userId
                                        ? "Paid by $settlementPayer • Owed to $creditorName"
                                        : "$settlementPayer paid $settlementRecipient • Owed to $creditorName"))
                                : (isViewerCreditor
                                    ? "Logged by $creatorName (You) • Owed to You"
                                    : "Logged by $creatorName • Owed to $creditorName"));

                        return Text(
                          subtext,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            color: darkText.withValues(alpha: 0.65),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),

              // EXPANDED / UNFOLDED CONTENT (Fluid AnimatedCrossFade)
              AnimatedCrossFade(
                firstChild: const SizedBox.shrink(),
                secondChild: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (expense["attachment"] != null && expense["attachment"].toString().isNotEmpty) ...[
                        Row(
                          children: [
                            const Icon(Icons.attach_file_rounded, size: 14, color: forestDark),
                            const SizedBox(width: 4),
                            Text("Receipt Attached", style: GoogleFonts.inter(color: forestDark, fontSize: 11.5, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                      const Divider(height: 1),
                      const SizedBox(height: 10),

                      // Contextual Action Buttons / Settlement Info
                      if (!isPaid) ...[
                        if (!isViewerCreditor)
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () => _openPayModal(expense),
                              icon: const Icon(Icons.payment_rounded, size: 18, color: Colors.white),
                              label: Text("Pay (₹${amount.toStringAsFixed(0)})"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: forestDark,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          )
                        else
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () => _openReceivedModal(expense),
                              icon: const Icon(Icons.check_circle_outline_rounded, size: 18, color: forestDark),
                              label: const Text("Mark Payment Received"),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: forestDark,
                                side: const BorderSide(color: forestDark, width: 1.5),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                      ],

                      // Settlement Summary Footer (if any payment was made)
                      if (settlement != null) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Icon(
                              isPaid ? Icons.verified_rounded : Icons.history_rounded,
                              size: 16,
                              color: isPaid ? emerald : forestDark,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                isPaid
                                    ? (settlementPayer.isNotEmpty
                                        ? "Settled via ${settlement['paymentMode']?.toString().toUpperCase()} by $settlementPayer"
                                        : "Settled / Company Funded")
                                    : "Paid via ${settlement['paymentMode']?.toString().toUpperCase()} by $settlementPayer to $settlementRecipient",
                                style: GoogleFonts.inter(
                                  color: isPaid ? emerald : darkText.withValues(alpha: 0.7),
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                crossFadeState: isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 300),
                sizeCurve: Curves.fastOutSlowIn,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExpenseListShimmer extends StatefulWidget {
  const _ExpenseListShimmer({Key? key}) : super(key: key);

  @override
  State<_ExpenseListShimmer> createState() => _ExpenseListShimmerState();
}

class _ExpenseListShimmerState extends State<_ExpenseListShimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.3, end: 0.8).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Opacity(
          opacity: _animation.value,
          child: Column(
            children: List.generate(3, (index) {
              return Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          width: 60,
                          height: 16,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        Container(
                          width: 70,
                          height: 16,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: 140,
                      height: 18,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: 100,
                      height: 14,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        );
      },
    );
  }
}
