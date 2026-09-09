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
import 'create_company_screen.dart';
import 'join_company_screen.dart';

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
  static const Color creamSheet = Color(0xFFFBF9F1);
  static const Color forestDark = Color(0xFF0F261C);
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
  double _totalReceivable = 0.0;
  double _totalPayable = 0.0;
  double _totalCompanySpent = 0.0;
  double _netBalance = 0.0;

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

  @override
  void initState() {
    super.initState();
    _userCompanies = List.from(widget.companies);
    _selectedCompanyId = widget.initialCompanyId;
    _refreshDashboard();
  }

  Future<void> _refreshDashboard() async {
    setState(() => _isLoading = true);

    try {
      // Fetch user companies to stay updated
      final updatedCompanies = await ExpenseCompanyService.getUserCompanies(widget.userId);
      if (updatedCompanies.isNotEmpty) {
        _userCompanies = updatedCompanies;
        if (!_userCompanies.any((c) => c["_id"].toString() == _selectedCompanyId)) {
          _selectedCompanyId = _userCompanies.first["_id"].toString();
        }
      }

      // Fetch current company details & members
      final detailsRes = await ExpenseCompanyService.getCompanyDetails(_selectedCompanyId, widget.userId);
      if (detailsRes["success"] == true) {
        _currentCompany = detailsRes["company"];
        _companyMembers = List<Map<String, dynamic>>.from(detailsRes["members"] ?? []);
        _currentUserRole = detailsRes["currentUserRole"] ?? "member";
      }

      // Fetch expenses feed
      final expensesList = await ExpenseCompanyService.getCompanyExpenses(_selectedCompanyId);

      // Fetch balance summary
      final summaryRes = await ExpenseCompanyService.getCompanyBalanceSummary(
        companyId: _selectedCompanyId,
        userId: widget.userId,
      );

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
          ),
        );
      },
    );
    if (result == true) {
      _refreshDashboard();
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
      _refreshDashboard();
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
        constraints: const BoxConstraints(maxHeight: 250),
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

  void _openExpenseAuditModal(Map<String, dynamic> expense) {
    final creator = expense["createdBy"];
    final creatorName = creator != null ? creator["name"] ?? "Member" : "Member";
    final creatorEmail = creator != null ? creator["email"] ?? "" : "";
    final isPaid = expense["status"] == "paid";
    final amount = (expense["amount"] as num?)?.toDouble() ?? 0.0;
    final dateStr = expense["date"] != null
        ? DateFormat("dd MMM, yyyy • hh:mm a").format(DateTime.parse(expense["date"]))
        : "";

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
      } else {
        settlementList.add(Map<String, dynamic>.from(s));
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.88),
          decoration: const BoxDecoration(
            color: creamSheet,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
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
                    color: darkText.withValues(alpha: 0.2),
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
                          color: forestDark.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.info_outline_rounded, color: forestDark, size: 20),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        "Expense Audit & Details",
                        style: GoogleFonts.fraunces(color: forestDark, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: darkText),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Divider(),
              const SizedBox(height: 8),

              // Scrollable Body Content
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. Amount & Category Box
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: forestDark.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    expense["category"] ?? "General",
                                    style: GoogleFonts.inter(color: forestDark, fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isPaid ? emerald.withValues(alpha: 0.12) : terracotta.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    isPaid ? "PAID / SETTLED" : "OUTSTANDING",
                                    style: GoogleFonts.inter(color: isPaid ? emerald : terracotta, fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              expense["description"] ?? "Expense",
                              style: GoogleFonts.inter(color: darkText, fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              "₹${amount.toStringAsFixed(2)}",
                              style: GoogleFonts.fraunces(color: forestDark, fontSize: 26, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              dateStr,
                              style: GoogleFonts.inter(color: darkText.withValues(alpha: 0.5), fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),

                      // 2. Creator & Original Bill Attachment Info
                      Text(
                        "Created By",
                        style: GoogleFonts.fraunces(color: darkText, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: forestDark.withValues(alpha: 0.1),
                                  child: Text(
                                    creatorName.isNotEmpty ? creatorName[0].toUpperCase() : "M",
                                    style: GoogleFonts.inter(color: forestDark, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        creatorName,
                                        style: GoogleFonts.inter(color: darkText, fontWeight: FontWeight.bold, fontSize: 14.5),
                                      ),
                                      if (creatorEmail.isNotEmpty)
                                        Text(
                                          creatorEmail,
                                          style: GoogleFonts.inter(color: darkText.withValues(alpha: 0.5), fontSize: 12),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            if (expense["attachment"] != null && expense["attachment"].toString().isNotEmpty) ...[
                              const SizedBox(height: 14),
                              const Divider(),
                              const SizedBox(height: 10),
                              Text(
                                "Original Bill / Receipt Proof:",
                                style: GoogleFonts.inter(color: darkText, fontWeight: FontWeight.bold, fontSize: 12.5),
                              ),
                              const SizedBox(height: 10),
                              _buildImageWidget(expense["attachment"].toString()),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),

                      // 3. Payment & Settlement History Timeline
                      if (settlementList.isNotEmpty) ...[
                        Text(
                          "Payment History (${settlementList.length})",
                          style: GoogleFonts.fraunces(color: darkText, fontSize: 16, fontWeight: FontWeight.bold),
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
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: isFinalStep ? emerald.withValues(alpha: 0.12) : forestDark.withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        isFinalStep ? "Payment #$idx • Final Settlement" : "Payment #$idx",
                                        style: GoogleFonts.inter(
                                          color: isFinalStep ? emerald : forestDark,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    if (sDate.isNotEmpty)
                                      Text(
                                        sDate,
                                        style: GoogleFonts.inter(color: darkText.withValues(alpha: 0.5), fontSize: 11),
                                      ),
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
                    ],
                  ),
                ),
              ),
            ],
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
            color: creamSheet,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Select Company Ledger",
                style: GoogleFonts.fraunces(color: forestDark, fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 14),

              ListView.separated(
                shrinkWrap: true,
                itemCount: _userCompanies.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final c = _userCompanies[index];
                  final isSelected = c["_id"].toString() == _selectedCompanyId;
                  return ListTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    tileColor: isSelected ? forestDark.withValues(alpha: 0.1) : Colors.white,
                    leading: const Icon(Icons.business_rounded, color: forestDark),
                    title: Text(c["name"], style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: darkText)),
                    trailing: isSelected ? const Icon(Icons.check_circle_rounded, color: forestDark) : null,
                    onTap: () {
                      Navigator.pop(ctx);
                      setState(() {
                        _selectedCompanyId = c["_id"].toString();
                      });
                      _refreshDashboard();
                    },
                  );
                },
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CreateCompanyScreen(userId: widget.userId, userName: widget.userName),
                          ),
                        ).then((_) => _refreshDashboard());
                      },
                      icon: const Icon(Icons.add_business_rounded, size: 18),
                      label: const Text("Create New"),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: forestDark,
                        side: const BorderSide(color: forestDark),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => JoinCompanyScreen(userId: widget.userId, userName: widget.userName),
                          ),
                        ).then((_) => _refreshDashboard());
                      },
                      icon: const Icon(Icons.group_add_rounded, size: 18),
                      label: const Text("Join Another"),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: terracotta,
                        side: const BorderSide(color: terracotta),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
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
              color: forestDark.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.arrow_back_rounded, color: forestDark, size: 20),
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
                    color: forestDark,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.keyboard_arrow_down_rounded, color: forestDark, size: 22),
            ],
          ),
        ),
        actions: [
          IconButton(
            tooltip: "Company Settings",
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: forestDark.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.settings_rounded, color: forestDark, size: 20),
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
              ).then((_) => _refreshDashboard());
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: forestDark,
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
              ),
            ),
          );
          if (result == true) {
            _refreshDashboard();
          }
        },
        icon: const Icon(Icons.add_rounded, size: 22),
        label: Text(
          "Add Expense",
          style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: forestDark))
          : RefreshIndicator(
              color: forestDark,
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
                            color: darkText,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          "${_expenses.length} Entries",
                          style: GoogleFonts.ibmPlexMono(
                            color: darkText.withValues(alpha: 0.5),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // 3. Expenses List Feed
                    if (_expenses.isEmpty)
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
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _expenses.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 14),
                        itemBuilder: (context, index) {
                          return _buildExpenseCard(_expenses[index]);
                        },
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildBalanceSummaryCard() {
    final netColor = _netBalance >= 0 ? emerald : terracotta;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: forestDark,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: forestDark.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isAdmin ? "TOTAL EXPENSE SPENT" : "YOU ARE OWED (RECEIVABLE)",
                    style: GoogleFonts.ibmPlexMono(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "₹${(_isAdmin ? _totalCompanySpent : _totalReceivable).toStringAsFixed(2)}",
                    style: GoogleFonts.fraunces(
                      color: emerald,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Container(width: 1, height: 40, color: Colors.white.withValues(alpha: 0.15)),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    "YOU OWE (PAYABLE)",
                    style: GoogleFonts.ibmPlexMono(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "₹${_totalPayable.toStringAsFixed(2)}",
                    style: GoogleFonts.fraunces(
                      color: terracotta,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(color: Colors.white.withValues(alpha: 0.12)),
          const SizedBox(height: 8),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Net Standing Balance",
                style: GoogleFonts.inter(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                "${_netBalance >= 0 ? '+' : ''}₹${_netBalance.toStringAsFixed(2)}",
                style: GoogleFonts.fraunces(
                  color: netColor,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
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

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Category, Date, Status Badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: forestDark.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          expense["category"] ?? "General",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(color: forestDark, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      dateStr,
                      style: GoogleFonts.inter(color: darkText.withValues(alpha: 0.5), fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isPaid ? emerald.withValues(alpha: 0.12) : terracotta.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      isPaid ? "PAID / SETTLED" : "OUTSTANDING",
                      style: GoogleFonts.inter(
                        color: isPaid ? emerald : terracotta,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  IconButton(
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(4),
                    tooltip: "View Expense Details & History",
                    icon: const Icon(Icons.info_outline_rounded, color: forestDark, size: 20),
                    onPressed: () => _openExpenseAuditModal(expense),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Title & Amount
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  expense["description"] ?? "Expense Claim",
                  style: GoogleFonts.inter(
                    color: darkText,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                "₹${amount.toStringAsFixed(2)}",
                style: GoogleFonts.fraunces(
                  color: darkText,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Creditor info (Who is currently owed money)
          Row(
            children: [
              Icon(Icons.person_outline_rounded, size: 15, color: darkText.withValues(alpha: 0.5)),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  isPaid
                      ? (isViewerCreator ? "Logged by You (Paid)" : "Paid by $creatorName")
                      : (settlement != null
                          ? (isViewerCreditor
                              ? "Paid to $settlementRecipient by You • Owed to You"
                              : (settlement?["paidTo"]?["_id"]?.toString() == widget.userId
                                  ? "Paid by $settlementPayer • Owed to $creditorName"
                                  : "$settlementPayer paid $settlementRecipient • Owed to $creditorName"))
                          : (isViewerCreditor ? "Claimed by You • Owed to You" : "Owed to $creditorName")),
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: darkText.withValues(alpha: 0.7),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),

          // Attachment / Proof if any
          if (expense["attachment"] != null && expense["attachment"].toString().isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.attach_file_rounded, size: 14, color: forestDark),
                const SizedBox(width: 4),
                Text("Receipt Attached", style: GoogleFonts.inter(color: forestDark, fontSize: 11.5, fontWeight: FontWeight.bold)),
              ],
            ),
          ],

          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 12),

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
    );
  }
}
