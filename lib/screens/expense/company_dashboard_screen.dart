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
  final Set<String> _expandedExpenseIds = {};
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
        backgroundColor: creamSheet,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          title,
          style: GoogleFonts.fraunces(color: forestDark, fontWeight: FontWeight.bold),
        ),
        content: Text(
          contentMsg,
          style: GoogleFonts.inter(color: darkText, fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              "Cancel",
              style: GoogleFonts.inter(color: darkText.withValues(alpha: 0.6), fontWeight: FontWeight.bold),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: isTargetPaid ? emerald : terracotta,
              foregroundColor: Colors.white,
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
      _refreshDashboard();
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
                          style: GoogleFonts.fraunces(color: darkText, fontSize: 16, fontWeight: FontWeight.bold),
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
                                  icon: const Icon(Icons.edit_rounded, size: 16, color: forestDark),
                                  label: Text("Edit Payment", style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: forestDark,
                                    side: const BorderSide(color: forestDark, width: 1.2),
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
                                icon: Icon(isPaid ? Icons.undo_rounded : Icons.check_circle_rounded, size: 16, color: isPaid ? terracotta : emerald),
                                label: Text(
                                  isPaid ? "Change to Unpaid" : "Mark as Paid",
                                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: isPaid ? terracotta : emerald,
                                  side: BorderSide(color: isPaid ? terracotta : emerald, width: 1.2),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ),
                          ],
                        ),
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
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
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
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "₹${(_isAdmin ? _totalCompanySpent : _totalReceivable).toStringAsFixed(2)}",
                        style: GoogleFonts.fraunces(
                          color: emerald,
                          fontSize: 20,
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
                height: 40,
                color: Colors.white.withValues(alpha: 0.15),
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
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        "₹${_totalPayable.toStringAsFixed(2)}",
                        style: GoogleFonts.fraunces(
                          color: terracotta,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(color: Colors.white.withValues(alpha: 0.12)),
          const SizedBox(height: 8),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  "Net Standing Balance",
                  style: GoogleFonts.inter(
                    color: Colors.white.withValues(alpha: 0.8),
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black.withValues(alpha: 0.08), width: 1.1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.025),
                blurRadius: 8,
                offset: const Offset(0, 3),
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
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: forestDark.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              expense["category"] ?? "General",
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(color: forestDark, fontSize: 10.5, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            dateStr,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(color: darkText.withValues(alpha: 0.5), fontSize: 10.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: isPaid ? emerald.withValues(alpha: 0.12) : terracotta.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          isPaid ? "PAID / SETTLED" : "OUTSTANDING",
                          style: GoogleFonts.inter(
                            color: isPaid ? emerald : terracotta,
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                      IconButton(
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.all(2),
                        tooltip: "View Expense Details & History",
                        icon: const Icon(Icons.info_outline_rounded, color: forestDark, size: 18),
                        onPressed: () => _openExpenseAuditModal(expense),
                      ),
                      if (canManagePayment) ...[
                        PopupMenuButton<String>(
                          color: Colors.white,
                          surfaceTintColor: Colors.white,
                          elevation: 6,
                          shadowColor: Colors.black.withValues(alpha: 0.2),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(2),
                          icon: Icon(Icons.more_vert_rounded, color: darkText.withValues(alpha: 0.7), size: 18),
                          tooltip: "Payment Options",
                          onSelected: (val) {
                            if (val == "unpaid") {
                              _changeExpenseStatus(expense, "outstanding");
                            } else if (val == "mark_paid") {
                              _changeExpenseStatus(expense, "paid");
                            } else if (val == "edit") {
                              _openEditPaymentModal(expense, settlement);
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
                            if (isPaid)
                              PopupMenuItem(
                                value: "unpaid",
                                child: Row(
                                  children: [
                                    const Icon(Icons.undo_rounded, size: 18, color: terracotta),
                                    const SizedBox(width: 10),
                                    Text(
                                      "Change to Unpaid",
                                      style: GoogleFonts.inter(fontSize: 13, color: terracotta, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              )
                            else
                              PopupMenuItem(
                                value: "mark_paid",
                                child: Row(
                                  children: [
                                    const Icon(Icons.check_circle_rounded, size: 18, color: emerald),
                                    const SizedBox(width: 10),
                                    Text(
                                      "Mark as Paid / Settled",
                                      style: GoogleFonts.inter(fontSize: 13, color: emerald, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(width: 2),
                      Icon(
                        isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                        color: forestDark,
                        size: 20,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 6),

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
                        fontSize: 14.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    "₹${amount.toStringAsFixed(2)}",
                    style: GoogleFonts.fraunces(
                      color: darkText,
                      fontSize: 17.5,
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
                        color: darkText.withValues(alpha: 0.65),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
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
