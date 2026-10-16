import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../services/expense_company_service.dart';
import '../../services/ledger_service.dart';
import 'add_expense_screen.dart';
import 'group_settings_screen.dart';

class GroupExpensesScreen extends StatefulWidget {
  final Map<String, dynamic> group;
  final String userId;
  final String userName;

  const GroupExpensesScreen({
    super.key,
    required this.group,
    required this.userId,
    required this.userName,
  });

  @override
  State<GroupExpensesScreen> createState() => _GroupExpensesScreenState();
}

class _GroupExpensesScreenState extends State<GroupExpensesScreen> {
  static const Color bgGreen = Color(0xFF0C5F41);
  static const Color darkSurface = Color(0xFF0C3826);
  static const Color mintAccent = Color(0xFF10B981);
  static const Color darkText = Color(0xFF1E293B);

  late Map<String, dynamic> _group;
  List<Map<String, dynamic>> _expenses = [];
  final Set<String> _expandedExpenseIds = {};
  bool _loading = true;
  bool _settling = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _group = Map<String, dynamic>.from(widget.group);
    _load();
  }

  String _id(dynamic value) {
    if (value is Map) return (value["_id"] ?? value["id"] ?? "").toString();
    return value?.toString() ?? "";
  }

  String get _groupId => _id(_group["_id"]);
  String get _companyId => _id(_group["companyId"]);
  String get _companyName => _group["companyId"] is Map
      ? (_group["companyId"]["name"] ?? "Company").toString()
      : "Company";
  String get _groupName => (_group["name"] ?? "Group").toString();
  String get _creatorId => _id(_group["createdBy"]);
  bool get _isCreator => _creatorId == widget.userId;
  bool get _isSettled => _group["settlementStatus"] == "settled";
  double get _total => _expenses.fold<double>(0,
      (sum, expense) => sum + ((expense["amount"] as num?)?.toDouble() ?? 0));

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final response = await ExpenseCompanyService.getGroupExpenses(
        groupId: _groupId, userId: widget.userId);
    if (!mounted) return;
    if (response["success"] == true &&
        response["group"] is Map &&
        response["expenses"] is List) {
      setState(() {
        _group = Map<String, dynamic>.from(response["group"]);
        _expenses = List<Map<String, dynamic>>.from(response["expenses"]);
        _loading = false;
      });
    } else {
      setState(() {
        _error =
            (response["message"] ?? "Could not load group expenses").toString();
        _loading = false;
      });
    }
  }

  Future<void> _addExpense() async {
    final members = _group["members"] is List
        ? List<Map<String, dynamic>>.from((_group["members"] as List)
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item)))
        : <Map<String, dynamic>>[];
    final added = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddExpenseScreen(
          companyId: _companyId,
          companyName: _companyName,
          userId: widget.userId,
          userName: widget.userName,
          groupId: _groupId,
          companyMembers: members,
        ),
      ),
    );
    if (added == true) _load();
  }

  Future<void> _showReceipt(Map<String, dynamic> expense) async {
    final response = await ExpenseCompanyService.getGroupExpenseReceipt(
      groupId: _groupId,
      expenseId: _id(expense["_id"]),
      userId: widget.userId,
    );
    if (!mounted) return;
    final data = (response["attachment"] ?? "").toString();
    if (response["success"] != true || data.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Receipt is unavailable")));
      return;
    }
    final bytes =
        base64Decode(data.contains(",") ? data.split(",").last : data);
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child:
            InteractiveViewer(child: Image.memory(bytes, fit: BoxFit.contain)),
      ),
    );
  }

  Future<void> _settleGroup() async {
    if (!_isCreator || _isSettled || _total <= 0) return;
    setState(() => _settling = true);
    final companies =
        await ExpenseCompanyService.getAllAvailableCompanies(widget.userId);
    if (!mounted) return;
    final lenders = companies
        .where((company) => _id(company["_id"]) != _companyId)
        .toList();
    var settlementType = "own_company";
    String? lenderCompanyId;
    String? dialogError;
    var saving = false;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text("Settle $_groupName",
              style: GoogleFonts.fraunces(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Total group expenses: ${_money(_total)}"),
                const SizedBox(height: 12),
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  value: "own_company",
                  groupValue: settlementType,
                  title: Text("Settled by $_companyName"),
                  onChanged: saving
                      ? null
                      : (value) =>
                          setDialogState(() => settlementType = value!),
                ),
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  value: "other_company",
                  groupValue: settlementType,
                  title: const Text("Settled by another company"),
                  onChanged: saving
                      ? null
                      : (value) =>
                          setDialogState(() => settlementType = value!),
                ),
                if (settlementType == "other_company")
                  if (lenders.isEmpty)
                    const Text("No other companies are available.")
                  else
                    DropdownButtonFormField<String>(
                      initialValue: lenderCompanyId,
                      isExpanded: true,
                      decoration:
                          const InputDecoration(labelText: "Company that paid"),
                      hint: const Text("Choose company"),
                      items: lenders
                          .map((company) => DropdownMenuItem<String>(
                                value: _id(company["_id"]),
                                child: Text(
                                    (company["name"] ?? "Company").toString(),
                                    overflow: TextOverflow.ellipsis),
                              ))
                          .toList(),
                      onChanged: saving
                          ? null
                          : (value) =>
                              setDialogState(() => lenderCompanyId = value),
                    ),
                if (settlementType == "other_company") ...[
                  const SizedBox(height: 8),
                  const Text(
                      "This records a company loan. Your company will owe the paying company until it is repaid."),
                ],
                if (dialogError != null) ...[
                  const SizedBox(height: 10),
                  Text(dialogError!, style: const TextStyle(color: Colors.red)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: saving ? null : () => Navigator.pop(dialogContext),
                child: const Text("Cancel")),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (settlementType == "other_company" &&
                          lenderCompanyId == null) {
                        setDialogState(() =>
                            dialogError = "Choose the company that paid.");
                        return;
                      }
                      setDialogState(() {
                        saving = true;
                        dialogError = null;
                      });
                      final response =
                          await LedgerService.settleExpenseGroup(_groupId, {
                        "userId": widget.userId,
                        "settlementType": settlementType,
                        if (lenderCompanyId != null)
                          "lenderCompanyId": lenderCompanyId,
                      });
                      if (!dialogContext.mounted) return;
                      if (response["success"] == true) {
                        Navigator.pop(dialogContext, response);
                      } else {
                        setDialogState(() {
                          saving = false;
                          dialogError =
                              (response["message"] ?? "Could not settle group")
                                  .toString();
                        });
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text("Settle group"),
            ),
          ],
        ),
      ),
    );
    if (mounted) setState(() => _settling = false);
    if (result == null || !mounted) return;
    await _load();
    if (!mounted) return;
    final isLoan = result["loan"] != null;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(isLoan
              ? "Group settled. Company loan recorded."
              : "Group settled by $_companyName.")),
    );
  }

  String _money(num value) => "₹${NumberFormat('#,##,##0.00').format(value)}";

  Future<void> _openSettings() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => GroupSettingsScreen(
          groupId: _groupId,
          groupName: _groupName,
          userId: widget.userId,
        ),
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgGreen,
      appBar: AppBar(
        backgroundColor: bgGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(_groupName,
            style: GoogleFonts.fraunces(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            tooltip: "Group settings",
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: mintAccent,
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics()),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            children: [
              Text(_companyName,
                  style: GoogleFonts.inter(color: Colors.white70)),
              const SizedBox(height: 5),
              Text("Group expenses",
                  style: GoogleFonts.fraunces(
                      color: Colors.white,
                      fontSize: 23,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("TOTAL RECORDED",
                              style: GoogleFonts.ibmPlexMono(
                                  color: const Color(0xFF64748B),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(height: 5),
                          Text(_money(_total),
                              style: GoogleFonts.fraunces(
                                  color: darkSurface,
                                  fontSize: 25,
                                  fontWeight: FontWeight.bold)),
                        ]),
                    if (_isSettled)
                      Chip(
                        label: Text(_group["settlementType"] == "other_company"
                            ? "Settled · loan recorded"
                            : "Settled by company"),
                        backgroundColor: const Color(0xFFE4F5EE),
                        labelStyle: GoogleFonts.inter(
                            color: darkSurface,
                            fontSize: 11,
                            fontWeight: FontWeight.bold),
                      )
                    else if (_isCreator && !_loading)
                      FilledButton(
                        onPressed:
                            _settling || _total <= 0 ? null : _settleGroup,
                        style: FilledButton.styleFrom(
                            backgroundColor: darkSurface,
                            foregroundColor: Colors.white),
                        child: Text(_settling ? "Settling..." : "Settle group"),
                      ),
                  ],
                ),
              ),
              if (_isSettled &&
                  _group["settlementType"] == "other_company") ...[
                const SizedBox(height: 8),
                Text(
                  "Owed to ${(_group["settlementCompanyId"] is Map ? _group["settlementCompanyId"]["name"] : "the paying company")}: ${_money((_group["settledAmount"] as num?) ?? _total)}. Repay this loan from Inter-co to clear the outstanding balance.",
                  style: GoogleFonts.inter(
                      color: Colors.white.withValues(alpha: 0.78),
                      fontSize: 12,
                      height: 1.4),
                ),
              ],
              const SizedBox(height: 16),
              if (_loading)
                const Padding(
                    padding: EdgeInsets.all(28),
                    child: Center(
                        child: CircularProgressIndicator(color: mintAccent)))
              else if (_error != null)
                Center(
                  child: Column(children: [
                    Text(_error!,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(color: Colors.white)),
                    TextButton(onPressed: _load, child: const Text("Retry")),
                  ]),
                )
              else if (_expenses.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 34),
                  child: Center(
                      child: Text("No expenses in this group yet",
                          style: GoogleFonts.inter(color: Colors.white70))),
                )
              else
                ..._expenses.map(_expenseCard),
            ],
          ),
        ),
      ),
      floatingActionButton: _isSettled
          ? null
          : FloatingActionButton.extended(
              onPressed: _loading ? null : _addExpense,
              backgroundColor: darkSurface,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded, color: mintAccent),
              label: const Text("Add expense"),
            ),
    );
  }

  Widget _expenseCard(Map<String, dynamic> expense) {
    final creator =
        expense["createdBy"] is Map ? expense["createdBy"]["name"] : null;
    final expenseId = _id(expense["_id"]);
    final expanded = _expandedExpenseIds.contains(expenseId);
    final date = DateTime.tryParse(
        (expense["date"] ?? expense["createdAt"] ?? "").toString());
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: darkText.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() {
              if (expanded) {
                _expandedExpenseIds.remove(expenseId);
              } else {
                _expandedExpenseIds.add(expenseId);
              }
            }),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: darkSurface.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.receipt_long_rounded,
                        color: darkSurface, size: 17),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          (expense["description"] ?? "Expense").toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                              color: darkText,
                              fontSize: 13,
                              fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          "${expense["category"] ?? "General"} · ${date == null ? "" : DateFormat("dd MMM yyyy").format(date)} · ${creator ?? "group member"}",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                              color: const Color(0xFF64748B), fontSize: 10.5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(_money((expense["amount"] as num?) ?? 0),
                      style: GoogleFonts.inter(
                          color: darkSurface,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(width: 4),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: darkSurface,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
          if (expanded && expense["hasAttachment"] == true)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 60, bottom: 6),
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                      padding: EdgeInsets.zero, foregroundColor: darkSurface),
                  onPressed: () => _showReceipt(expense),
                  icon: const Icon(Icons.attach_file_rounded, size: 16),
                  label: const Text("View receipt"),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
