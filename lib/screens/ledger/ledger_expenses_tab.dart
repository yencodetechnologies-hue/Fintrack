import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../services/ledger_service.dart';
import '../../services/expense_company_service.dart';
import 'ledger_common.dart';

const List<String> kCategories = [
  "General",
  "Travel",
  "Food & Dining",
  "Rent",
  "Software",
  "Office Supplies",
  "Utilities",
  "Other"
];

class LedgerExpensesTab extends StatefulWidget {
  final LedgerScope scope;
  const LedgerExpensesTab({super.key, required this.scope});

  @override
  State<LedgerExpensesTab> createState() => _LedgerExpensesTabState();
}

class _LedgerExpensesTabState extends State<LedgerExpensesTab>
    with LedgerAutoRefresh, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  void onLedgerChanged() => _load(silent: true);

  LedgerScope get s => widget.scope;
  List<Map<String, dynamic>> _expenses = [];
  bool _loading = true;
  String? _loadError;
  String _filter = "All";
  final Set<String> _expandedExpenseIds = {};

  // Per-expense action busy states
  final Set<String> _busyExpenseIds = {};
  final Map<String, String> _busyAction = {};

  @override
  void initState() {
    super.initState();
    // Instant 0ms display: hydrate synchronously from cache
    final cached = ExpenseCompanyService.getCachedLedgerExpenses(s.companyId);
    if (cached != null && cached.isNotEmpty) {
      _expenses = List<Map<String, dynamic>>.from(cached);
      _loading = false;
    }
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted && _expenses.isEmpty) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    final res = await LedgerService.expenses(s.companyId, s.userId);
    if (!mounted) return;
    setState(() {
      if (res["success"] == true && res["expenses"] is List) {
        _expenses = List<Map<String, dynamic>>.from(res["expenses"]);
        _loadError = null;
      } else if (_expenses.isEmpty) {
        _loadError = res["message"]?.toString() ??
            "Could not load expenses. Please try again.";
      }
      _loading = false;
    });
  }

  List<Map<String, dynamic>> get _visible {
    switch (_filter) {
      case "Submitted":
        return _expenses.where((e) => e["lifecycle"] == "submitted").toList();
      case "Approved":
        return _expenses.where((e) => e["lifecycle"] == "approved").toList();
      case "Verify":
        return _expenses.where((e) => e["verification"] == "pending").toList();
      default:
        return _expenses;
    }
  }

  Future<void> _approveExpense(Map<String, dynamic> e) async {
    final id = e["_id"].toString();
    if (_busyExpenseIds.contains(id)) return;

    final prevLifecycle = e["lifecycle"];
    final prevApprovedBy = e["approvedBy"];

    // 1. Instant 0ms Optimistic UI feedback
    setState(() {
      _busyExpenseIds.add(id);
      _busyAction[id] = "approve";
      e["lifecycle"] = "approved";
      e["approvedBy"] = {"_id": s.userId, "name": s.userName};
    });
    ExpenseCompanyService.updateCachedExpenseLifecycle(
      s.companyId,
      id,
      "approved",
      approvedBy: {"_id": s.userId, "name": s.userName},
    );

    try {
      final res = await LedgerService.approve(id, s.userId);
      if (!mounted) return;
      if (res["success"] == true) {
        toast(
            context,
            _filter == "Submitted"
                ? "Expense approved (moved to Approved tab)"
                : "Expense approved");
        if (res["expense"] is Map<String, dynamic>) {
          setState(() {
            final idx = _expenses.indexWhere((x) => x["_id"].toString() == id);
            if (idx != -1) {
              _expenses[idx] = {
                ..._expenses[idx],
                ...Map<String, dynamic>.from(res["expense"]),
              };
            }
          });
        }
        notifyLedgerChanged();
        _load(silent: true);
      } else {
        // Rollback
        setState(() {
          e["lifecycle"] = prevLifecycle;
          e["approvedBy"] = prevApprovedBy;
        });
        ExpenseCompanyService.updateCachedExpenseLifecycle(
          s.companyId,
          id,
          prevLifecycle,
          approvedBy: prevApprovedBy,
        );
        toast(
            context, res["message"]?.toString() ?? "Could not approve expense",
            error: true);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        e["lifecycle"] = prevLifecycle;
        e["approvedBy"] = prevApprovedBy;
      });
      ExpenseCompanyService.updateCachedExpenseLifecycle(
        s.companyId,
        id,
        prevLifecycle,
        approvedBy: prevApprovedBy,
      );
      toast(context, "Network error. Please try again.", error: true);
    } finally {
      if (mounted) {
        setState(() {
          _busyExpenseIds.remove(id);
          _busyAction.remove(id);
        });
      }
    }
  }

  Future<void> _rejectExpense(Map<String, dynamic> e) async {
    final id = e["_id"].toString();
    if (_busyExpenseIds.contains(id)) return;

    final prevLifecycle = e["lifecycle"];

    setState(() {
      _busyExpenseIds.add(id);
      _busyAction[id] = "reject";
      e["lifecycle"] = "rejected";
    });
    ExpenseCompanyService.updateCachedExpenseLifecycle(
        s.companyId, id, "rejected");

    try {
      final res = await LedgerService.reject(id, s.userId);
      if (!mounted) return;
      if (res["success"] == true) {
        toast(context, "Expense rejected");
        if (res["expense"] is Map<String, dynamic>) {
          setState(() {
            final idx = _expenses.indexWhere((x) => x["_id"].toString() == id);
            if (idx != -1) {
              _expenses[idx] = {
                ..._expenses[idx],
                ...Map<String, dynamic>.from(res["expense"]),
              };
            }
          });
        }
        notifyLedgerChanged();
        _load(silent: true);
      } else {
        setState(() {
          e["lifecycle"] = prevLifecycle;
        });
        ExpenseCompanyService.updateCachedExpenseLifecycle(
            s.companyId, id, prevLifecycle);
        toast(context, res["message"]?.toString() ?? "Could not reject expense",
            error: true);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        e["lifecycle"] = prevLifecycle;
      });
      ExpenseCompanyService.updateCachedExpenseLifecycle(
          s.companyId, id, prevLifecycle);
      toast(context, "Network error. Please try again.", error: true);
    } finally {
      if (mounted) {
        setState(() {
          _busyExpenseIds.remove(id);
          _busyAction.remove(id);
        });
      }
    }
  }

  Future<void> _deleteExpense(Map<String, dynamic> e) async {
    final id = e["_id"].toString();
    if (_busyExpenseIds.contains(id)) return;

    final idx = _expenses.indexWhere((x) => x["_id"].toString() == id);
    if (idx == -1) return;
    final removed = _expenses[idx];

    setState(() {
      _busyExpenseIds.add(id);
      _busyAction[id] = "delete";
      _expenses.removeAt(idx);
    });
    ExpenseCompanyService.removeCachedExpense(s.companyId, id);

    try {
      final res = await LedgerService.deleteExpense(id, s.userId);
      if (!mounted) return;
      if (res["success"] == true) {
        toast(context, "Expense deleted");
        notifyLedgerChanged();
        _load(silent: true);
      } else {
        setState(() {
          _expenses.insert(idx, removed);
        });
        ExpenseCompanyService.insertCachedExpense(s.companyId, idx, removed);
        toast(context, res["message"]?.toString() ?? "Could not delete expense",
            error: true);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _expenses.insert(idx, removed);
      });
      ExpenseCompanyService.insertCachedExpense(s.companyId, idx, removed);
      toast(context, "Network error. Please try again.", error: true);
    } finally {
      if (mounted) {
        setState(() {
          _busyExpenseIds.remove(id);
          _busyAction.remove(id);
        });
      }
    }
  }

  Future<void> _confirmPayerAction(String id, bool accept) async {
    if (_busyExpenseIds.contains(id)) return;
    final actionKey = accept ? "accept" : "reject_payer";
    setState(() {
      _busyExpenseIds.add(id);
      _busyAction[id] = actionKey;
    });

    try {
      final res = await LedgerService.confirmPayer(id, s.userId, accept);
      if (!mounted) return;
      if (handleResult(
          context, res, accept ? "Payment accepted" : "Payment rejected")) {
        notifyLedgerChanged();
        _load(silent: true);
      }
    } catch (_) {
      if (!mounted) return;
      toast(context, "Network error. Please try again.", error: true);
    } finally {
      if (mounted) {
        setState(() {
          _busyExpenseIds.remove(id);
          _busyAction.remove(id);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: kForest,
      floatingActionButton: FloatingActionButton(
        backgroundColor: kForestDark,
        onPressed: _openPost,
        child: const Icon(Icons.add_rounded, color: kMint),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : RefreshIndicator(
              onRefresh: _load,
              child: _loadError != null
                  ? ListView(
                      padding: const EdgeInsets.fromLTRB(24, 100, 24, 90),
                      children: [
                        Text(_loadError!,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(color: Colors.white)),
                        const SizedBox(height: 12),
                        Center(
                            child: TextButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh_rounded, color: kMint),
                          label: const Text("Retry",
                              style: TextStyle(color: kMint)),
                        )),
                      ],
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                      children: [
                        Wrap(
                          spacing: 8,
                          children: [
                            "All",
                            "Submitted",
                            "Approved",
                            if (s.isAdmin) "Verify"
                          ]
                              .map((f) => ChoiceChip(
                                    label: Text(f),
                                    selected: _filter == f,
                                    selectedColor: Colors.white,
                                    backgroundColor: kForestDark,
                                    labelStyle: GoogleFonts.inter(
                                        color: _filter == f
                                            ? kForest
                                            : Colors.white,
                                        fontWeight: FontWeight.w700),
                                    onSelected: (_) =>
                                        setState(() => _filter = f),
                                  ))
                              .toList(),
                        ),
                        const SizedBox(height: 12),
                        if (_visible.isEmpty)
                          emptyState(s.isAdmin
                              ? "No expenses here"
                              : "You haven't posted any expenses yet"),
                        ..._visible.map(_card),
                      ],
                    ),
            ),
    );
  }

  Widget _card(Map<String, dynamic> e) {
    final status = e["lifecycle"]?.toString();
    final mine = idOf(e["createdBy"]) == s.userId;
    final id = e["_id"].toString();
    final expanded = _expandedExpenseIds.contains(id);
    final compactStatus = switch (status) {
      "paid_by_admin" || "paid_by_person" || "paid_by_company" => "Paid",
      "awaiting_confirmation" => "Waiting",
      "reimbursed" => "Repaid",
      _ => kLifecycleLabels[status] ?? "",
    };
    final subtitle = switch (status) {
      "approved" => "Approved by ${nameOf(e["approvedBy"], "admin")}",
      "paid_by_admin" ||
      "paid_by_person" ||
      "reimbursed" =>
        "Paid by ${nameOf(e["paidByUserId"] ?? e["paidByAdminId"], "member")}",
      "awaiting_confirmation" =>
        "Awaiting confirmation from ${nameOf(e["payerCompanyId"], "another company")}",
      _ =>
        "Posted by ${mine ? "you" : nameOf(e["createdBy"])} · ${dateLabel(e["date"])}",
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kDark.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() {
              if (expanded) {
                _expandedExpenseIds.remove(id);
              } else {
                _expandedExpenseIds.add(id);
              }
            }),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: kForest.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.receipt_long_rounded,
                        color: kForest, size: 17),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          e["description"]?.toString() ?? "Expense",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                              color: kDark,
                              fontSize: 13,
                              fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          "${e["category"] ?? "General"} · $subtitle",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                              color: kDark.withValues(alpha: 0.58),
                              fontSize: 10.5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(inr(e["amount"]),
                          style: GoogleFonts.inter(
                              color: kDark,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      statusPill(compactStatus, lifecycleColor(status)),
                    ],
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: kForest,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(58, 0, 14, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (e["verification"] == "pending") ...[
                    const SizedBox(height: 4),
                    statusPill("Pending verification", kAmber),
                  ],
                  if (e["verification"] == "verified") ...[
                    const SizedBox(height: 4),
                    statusPill("Verified", kMint),
                  ],
                  if (e["hasAttachment"] == true ||
                      (e["attachment"] != null &&
                          e["attachment"].toString().isNotEmpty))
                    TextButton.icon(
                      style: TextButton.styleFrom(
                          padding: EdgeInsets.zero, foregroundColor: kForest),
                      onPressed: () => _loadReceipt(
                          id, "attachment", e["attachment"]?.toString()),
                      icon: const Icon(Icons.attach_file_rounded, size: 16),
                      label: const Text("View receipt"),
                    ),
                  if (e["hasPaymentReceipt"] == true ||
                      (e["paymentReceipt"] != null &&
                          e["paymentReceipt"].toString().isNotEmpty))
                    TextButton.icon(
                      style: TextButton.styleFrom(
                          padding: EdgeInsets.zero, foregroundColor: kForest),
                      onPressed: () => _loadReceipt(id, "paymentReceipt",
                          e["paymentReceipt"]?.toString()),
                      icon: const Icon(Icons.receipt_long_rounded, size: 16),
                      label: const Text("View payment receipt"),
                    ),
                  ..._actions(e, status, mine),
                  if (s.isAdmin &&
                      (e["isAdminCreated"] == true ||
                          s.admins.any((m) =>
                              idOf(m["userId"]) == idOf(e["createdBy"])) ||
                          idOf(s.company["createdBy"]) == idOf(e["createdBy"])))
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => _editVisibility(e),
                        icon: const Icon(Icons.visibility_rounded, size: 16),
                        label: const Text("Edit staff visibility"),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _actions(Map<String, dynamic> e, String? status, bool mine) {
    final id = e["_id"].toString();
    final isBusy = _busyExpenseIds.contains(id);
    final currentAction = _busyAction[id];

    Widget btn(
      String label,
      VoidCallback? onTap, {
      bool filled = false,
      Color color = kForest,
      IconData? icon,
      String? actionKey,
    }) {
      final bool isLoadingThis = isBusy && currentAction == actionKey;
      final content = FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoadingThis) ...[
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: filled ? Colors.white : color,
                ),
              ),
              const SizedBox(width: 6),
            ] else if (icon != null) ...[
              Icon(icon, size: 16),
              const SizedBox(width: 5),
            ],
            Text(
              isLoadingThis ? "Please wait..." : label,
              maxLines: 1,
              style:
                  GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ],
        ),
      );
      final shape =
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
      const padding = EdgeInsets.symmetric(horizontal: 8);
      const size = Size.fromHeight(44);
      final effectiveOnTap = isBusy ? null : onTap;
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: filled
              ? ElevatedButton(
                  onPressed: effectiveOnTap,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: color.withValues(alpha: 0.5),
                    disabledForegroundColor:
                        Colors.white.withValues(alpha: 0.8),
                    elevation: 0,
                    padding: padding,
                    minimumSize: size,
                    shape: shape,
                  ),
                  child: content,
                )
              : OutlinedButton(
                  onPressed: effectiveOnTap,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: color,
                    backgroundColor: color.withValues(alpha: 0.06),
                    side: BorderSide(
                        color: color.withValues(alpha: isBusy ? 0.25 : 0.6)),
                    disabledForegroundColor: color.withValues(alpha: 0.4),
                    padding: padding,
                    minimumSize: size,
                    shape: shape,
                  ),
                  child: content,
                ),
        ),
      );
    }

    final row = <Widget>[];
    if (status == "submitted" && s.isAdmin) {
      row.add(btn("Approve", () => _approveExpense(e),
          filled: true, icon: Icons.check_rounded, actionKey: "approve"));
      row.add(btn("Reject", () => _rejectExpense(e),
          color: kTerracotta, icon: Icons.close_rounded, actionKey: "reject"));
    }
    if (status == "submitted" && mine) {
      row.add(btn("Delete", () => _deleteExpense(e),
          color: kTerracotta,
          icon: Icons.delete_outline_rounded,
          actionKey: "delete"));
    }
    if (status == "approved" && s.isAdmin) {
      row.add(btn("Paid by me", () => _openPay(e, "admin"),
          filled: true, icon: Icons.person_rounded));
      row.add(btn("Company", () => _openPay(e, "company"),
          icon: Icons.business_rounded));
      row.add(btn("Borrow", () => _openPay(e, "borrow"),
          icon: Icons.swap_horiz_rounded));
    }
    if (status == "approved" && !s.isAdmin && mine) {
      row.add(btn("Mark as received", () => _markReceived(e),
          filled: true, icon: Icons.check_circle_rounded));
    } else if (status == "approved" && !s.isAdmin) {
      row.add(btn("Pay", () => _openPay(e, "person"),
          filled: true, icon: Icons.person_rounded));
    }
    if (status == "awaiting_confirmation" &&
        s.isAdmin &&
        idOf(e["payerCompanyId"]) == s.companyId) {
      row.add(btn("Accept", () => _confirmPayerAction(id, true),
          filled: true, icon: Icons.check_rounded, actionKey: "accept"));
      row.add(btn("Reject", () => _confirmPayerAction(id, false),
          color: kTerracotta,
          icon: Icons.close_rounded,
          actionKey: "reject_payer"));
    }
    if (row.isEmpty) return const [];
    return [const SizedBox(height: 12), Row(children: row)];
  }

  Future<void> _markReceived(Map<String, dynamic> expense) async {
    final sourceData = await LedgerService.borrowSources(s.companyId, s.userId);
    if (!mounted) return;
    final sources =
        List<Map<String, dynamic>>.from(sourceData["companies"] ?? const []);
    String payerId = s.userId;
    String payerType = "person";
    String? sourceCompanyId;
    String method = "UPI";
    String receipt = "";
    bool saving = false;
    showLedgerSheet(
        context,
        "Mark as received",
        (ctx) => StatefulBuilder(
              builder: (ctx, set) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Paid by", style: labelStyle),
                  const SizedBox(height: 6),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: "person", label: Text("Person")),
                      ButtonSegment(value: "company", label: Text("Company")),
                    ],
                    selected: {payerType},
                    onSelectionChanged: (v) => set(() => payerType = v.first),
                  ),
                  if (payerType == "person") ...[
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: payerId,
                      decoration: fieldDecoration("Who paid?",
                          icon: Icons.person_rounded),
                      items: s.members
                          .map((m) => DropdownMenuItem(
                              value: m["userId"].toString(),
                              child: Text(m["name"].toString())))
                          .toList(),
                      onChanged: (v) => set(() => payerId = v ?? s.userId),
                    ),
                  ],
                  if (payerType == "company") ...[
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: sourceCompanyId,
                      decoration: fieldDecoration("Company that paid",
                          icon: Icons.business_rounded),
                      items: sources
                          .map((c) => DropdownMenuItem(
                              value: c["_id"].toString(),
                              child: Text(c["name"].toString())))
                          .toList(),
                      onChanged: (v) => set(() => sourceCompanyId = v),
                    ),
                    const SizedBox(height: 5),
                    Text("Your company will owe this company",
                        style: GoogleFonts.inter(
                            fontSize: 12, color: kDark.withValues(alpha: 0.6))),
                  ],
                  const SizedBox(height: 12),
                  Text("Payment method", style: labelStyle),
                  const SizedBox(height: 6),
                  methodChips(method, (v) => set(() => method = v)),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                        foregroundColor: kForest,
                        side: const BorderSide(color: kForest)),
                    onPressed: () async {
                      final img = await ImagePicker().pickImage(
                          source: ImageSource.gallery,
                          maxWidth: 1200,
                          imageQuality: 70);
                      if (img == null) return;
                      final bytes = await File(img.path).readAsBytes();
                      set(() => receipt =
                          "data:image/jpeg;base64,${base64Encode(bytes)}");
                    },
                    icon: Icon(receipt.isEmpty
                        ? Icons.photo_camera_rounded
                        : Icons.check_circle_rounded),
                    label: Text(receipt.isEmpty
                        ? "Attach payment receipt *"
                        : "Payment receipt attached"),
                  ),
                  const SizedBox(height: 14),
                  primaryButton(
                      saving ? "Saving..." : "Mark as received",
                      saving
                          ? null
                          : () async {
                              if (receipt.isEmpty) {
                                toast(ctx, "Attach the payment receipt",
                                    error: true);
                                return;
                              }
                              if (payerType == "company" &&
                                  sourceCompanyId == null) {
                                toast(ctx, "Choose the company that paid",
                                    error: true);
                                return;
                              }
                              set(() => saving = true);
                              final result = await LedgerService.pay(
                                  expense["_id"].toString(), {
                                "userId": s.userId,
                                "payer":
                                    payerType == "person" ? "person" : "borrow",
                                if (payerType == "person")
                                  "paidByUserId": payerId,
                                if (payerType == "company")
                                  "sourceCompanyId": sourceCompanyId,
                                if (payerType == "company")
                                  "sourceFundId": "cash",
                                "method": method,
                                "paymentReceipt": receipt,
                              });
                              if (!ctx.mounted) return;
                              set(() => saving = false);
                              final success =
                                  result["awaitingConfirmation"] == true
                                      ? "Waiting for company confirmation"
                                      : "Expense payment recorded";
                              if (handleResult(ctx, result, success)) {
                                final paidExpense = result["expense"];
                                final expenseId = expense["_id"].toString();
                                setState(() {
                                  final idx = _expenses.indexWhere(
                                      (x) => x["_id"].toString() == expenseId);
                                  if (idx != -1) {
                                    if (paidExpense is Map<String, dynamic>) {
                                      _expenses[idx] = {
                                        ..._expenses[idx],
                                        ...Map<String, dynamic>.from(
                                            paidExpense),
                                      };
                                    } else {
                                      _expenses[idx]["lifecycle"] =
                                          "paid_by_person";
                                      _expenses[idx]["status"] = "paid";
                                    }
                                  }
                                });
                                ExpenseCompanyService
                                    .updateCachedExpenseLifecycle(
                                  s.companyId,
                                  expenseId,
                                  paidExpense is Map
                                      ? paidExpense["lifecycle"]
                                      : "paid_by_person",
                                );
                                Navigator.pop(ctx);
                                notifyLedgerChanged();
                                _load(silent: true);
                              }
                            }),
                ],
              ),
            ));
  }

  Future<void> _loadReceipt(
      String expenseId, String key, String? cached) async {
    if (cached != null && cached.isNotEmpty) {
      _showReceipt(cached);
      return;
    }
    final res = await LedgerService.expenseReceipts(expenseId, s.userId);
    if (!mounted) return;
    if (res["success"] != true) {
      toast(context, res["message"]?.toString() ?? "Could not load receipt",
          error: true);
      return;
    }
    final data = res[key]?.toString() ?? "";
    if (data.isEmpty) {
      toast(context, "Receipt is unavailable", error: true);
      return;
    }
    _showReceipt(data);
  }

  void _showReceipt(String data) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        child: data.startsWith("data:image")
            ? Image.memory(base64Decode(data.split(",").last))
            : Padding(padding: const EdgeInsets.all(20), child: Text(data)),
      ),
    );
  }

  void _editVisibility(Map<String, dynamic> expense) {
    final selected = <String>{
      ...List<dynamic>.from(expense["visibleTo"] ?? const []).map(idOf),
    };
    showDialog<void>(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, set) => AlertDialog(
                  backgroundColor: Colors.white,
                  title: const Text("Expense visibility"),
                  content: SizedBox(
                      width: 360,
                      child: SingleChildScrollView(
                          child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: s.members
                                  .where((m) => m["role"] != "admin")
                                  .map((m) {
                                final id = m["userId"].toString();
                                return CheckboxListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(m["name"].toString()),
                                    value: selected.contains(id),
                                    onChanged: (v) => set(() {
                                          if (v == true) {
                                            selected.add(id);
                                          } else {
                                            selected.remove(id);
                                          }
                                        }));
                              }).toList()))),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text("Cancel")),
                    TextButton(
                        onPressed: () async {
                          final result =
                              await LedgerService.setExpenseVisibility(
                                  expense["_id"].toString(),
                                  s.userId,
                                  selected.toList());
                          if (!ctx.mounted) return;
                          if (handleResult(ctx, result, "Visibility updated")) {
                            Navigator.pop(ctx);
                            _load();
                          }
                        },
                        child: const Text("Save")),
                  ],
                )));
  }

  bool _needsVerification(num amount) {
    final t = s.company["verificationThreshold"] as num?;
    return t != null && amount > t && s.admins.length > 1;
  }

  Future<void> _openPay(Map<String, dynamic> e, String initial) async {
    String payer = initial;
    String? fund;
    String? sourceId;
    bool addingCompany = false;
    bool saving = false;
    String method = "UPI";
    String paymentReceipt = "";
    final ref = TextEditingController();
    final newName = TextEditingController();
    final newGstin = TextEditingController();
    final amount = (e["amount"] as num?) ?? 0;

    List<Map<String, dynamic>> sources = [];
    final src = await LedgerService.borrowSources(s.companyId, s.userId);
    sources = List<Map<String, dynamic>>.from(src["companies"] ?? const []);
    if (!mounted) return;

    showLedgerSheet(
        context,
        "Pay expense",
        (ctx) => StatefulBuilder(
              builder: (ctx, set) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      "${e["category"]} · ${inr(amount)} — ${s.companyName} · posted by ${nameOf(e["createdBy"])}",
                      style: GoogleFonts.inter(
                          color: kDark.withValues(alpha: 0.7), fontSize: 12.5)),
                  const SizedBox(height: 14),
                  if (s.isAdmin) ...[
                    Text("Who pays?", style: labelStyle),
                    const SizedBox(height: 6),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                            value: "admin", label: Text("Paid by me")),
                        ButtonSegment(
                            value: "company", label: Text("By company")),
                        ButtonSegment(value: "borrow", label: Text("Borrow")),
                      ],
                      selected: {payer},
                      onSelectionChanged: (v) => set(() => payer = v.first),
                    ),
                  ] else
                    Text("Paid by you", style: labelStyle),
                  const SizedBox(height: 12),
                  if (payer == "company")
                    fundDropdown(s, fund, (v) => set(() => fund = v),
                        hint: "Pay from"),
                  if (payer == "borrow") ...[
                    Text("Source company", style: labelStyle),
                    const SizedBox(height: 6),
                    if (!addingCompany && sources.isEmpty)
                      Text(
                          "No other companies yet — tap “Add new company” below.",
                          style: GoogleFonts.inter(
                              color: kTerracotta, fontSize: 12.5)),
                    if (!addingCompany && sources.isNotEmpty)
                      DropdownButtonFormField<String>(
                        initialValue: sourceId,
                        isExpanded: true,
                        decoration: fieldDecoration("Select company",
                            icon: Icons.business_rounded),
                        items: sources
                            .map((c) => DropdownMenuItem(
                                value: c["_id"].toString(),
                                child: Text(c["name"].toString())))
                            .toList(),
                        onChanged: (v) => set(() => sourceId = v),
                      ),
                    TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: kForest),
                      onPressed: () => set(() {
                        addingCompany = !addingCompany;
                        sourceId = null;
                      }),
                      icon: Icon(
                          addingCompany
                              ? Icons.close_rounded
                              : Icons.add_rounded,
                          size: 18),
                      label: Text(addingCompany
                          ? "Pick an existing company"
                          : "Add new company"),
                    ),
                    if (addingCompany) ...[
                      Text("New company, saved on pay",
                          style: GoogleFonts.inter(
                              fontSize: 12,
                              color: kDark.withValues(alpha: 0.6))),
                      const SizedBox(height: 6),
                      TextField(
                          controller: newName,
                          decoration: fieldDecoration("Company name",
                              icon: Icons.business_rounded)),
                      const SizedBox(height: 8),
                      TextField(
                          controller: newGstin,
                          decoration: fieldDecoration("GSTIN *",
                              icon: Icons.badge_rounded)),
                    ],
                  ],
                  const SizedBox(height: 12),
                  Text("Method", style: labelStyle),
                  const SizedBox(height: 6),
                  methodChips(method, (m) => set(() => method = m)),
                  const SizedBox(height: 10),
                  TextField(
                      controller: ref,
                      decoration: fieldDecoration("Reference no.",
                          icon: Icons.tag_rounded)),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                        foregroundColor: kForest,
                        side: const BorderSide(color: kForest)),
                    onPressed: () async {
                      final img = await ImagePicker().pickImage(
                          source: ImageSource.gallery,
                          maxWidth: 1200,
                          imageQuality: 70);
                      if (img == null) return;
                      final bytes = await File(img.path).readAsBytes();
                      set(() => paymentReceipt =
                          "data:image/jpeg;base64,${base64Encode(bytes)}");
                    },
                    icon: Icon(paymentReceipt.isEmpty
                        ? Icons.photo_camera_rounded
                        : Icons.check_circle_rounded),
                    label: Text(paymentReceipt.isEmpty
                        ? "Attach payment receipt *"
                        : "Payment receipt attached"),
                  ),
                  if (_needsVerification(amount)) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(12)),
                      child: Text("Above threshold: 2nd admin must verify",
                          style: GoogleFonts.inter(
                              color: kAmber, fontWeight: FontWeight.bold)),
                    ),
                  ],
                  const SizedBox(height: 16),
                  primaryButton(
                      saving ? "Recording payment..." : "Confirm payment",
                      saving
                          ? null
                          : () async {
                              if (paymentReceipt.isEmpty) {
                                toast(ctx, "Attach the payment receipt",
                                    error: true);
                                return;
                              }
                              set(() => saving = true);
                              final body = <String, dynamic>{
                                "userId": s.userId,
                                "payer": payer,
                                "method": method,
                                "reference": ref.text.trim(),
                                "paymentReceipt": paymentReceipt
                              };
                              if (payer == "company") body["fundId"] = fund;
                              if (payer == "borrow") {
                                if (addingCompany) {
                                  if (newName.text.trim().isEmpty ||
                                      newGstin.text.trim().isEmpty) {
                                    set(() => saving = false);
                                    toast(ctx,
                                        "Enter the outside company name and GSTIN",
                                        error: true);
                                    return;
                                  }
                                  body["newCompany"] = {
                                    "name": newName.text.trim(),
                                    "gstin": newGstin.text.trim()
                                  };
                                } else {
                                  body["sourceCompanyId"] = sourceId;
                                  body["sourceFundId"] = "cash";
                                }
                              }
                              final res = await LedgerService.pay(
                                  e["_id"].toString(), body);
                              if (!ctx.mounted) return;
                              set(() => saving = false);
                              if (handleResult(ctx, res, "Payment recorded")) {
                                final paidExpense = res["expense"];
                                final expenseId = e["_id"].toString();
                                setState(() {
                                  final idx = _expenses.indexWhere(
                                      (x) => x["_id"].toString() == expenseId);
                                  if (idx != -1) {
                                    if (paidExpense is Map<String, dynamic>) {
                                      _expenses[idx] = {
                                        ..._expenses[idx],
                                        ...Map<String, dynamic>.from(
                                            paidExpense),
                                      };
                                    } else {
                                      _expenses[idx]["lifecycle"] =
                                          payer == "admin"
                                              ? "paid_by_admin"
                                              : (payer == "person"
                                                  ? "paid_by_person"
                                                  : "paid_by_company");
                                      _expenses[idx]["status"] = "paid";
                                    }
                                  }
                                });
                                ExpenseCompanyService
                                    .updateCachedExpenseLifecycle(
                                  s.companyId,
                                  expenseId,
                                  paidExpense is Map
                                      ? paidExpense["lifecycle"]
                                      : (payer == "admin"
                                          ? "paid_by_admin"
                                          : (payer == "person"
                                              ? "paid_by_person"
                                              : "paid_by_company")),
                                );
                                Navigator.pop(ctx);
                                notifyLedgerChanged();
                                _load(silent: true);
                              }
                            }),
                  if (payer == "borrow")
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Center(
                          child: Text("Admins of both companies are notified",
                              style: GoogleFonts.inter(
                                  fontSize: 11.5,
                                  color: kDark.withValues(alpha: 0.5)))),
                    ),
                ],
              ),
            ));
  }

  void _openPost() {
    showPostExpenseSheet(context, s, onDone: _load);
  }
}

Future<void> showPostExpenseSheet(BuildContext context, LedgerScope s,
    {VoidCallback? onDone}) async {
  final amount = TextEditingController();
  final desc = TextEditingController();
  String category = "General";
  final otherCtrl = TextEditingController();
  final categories = <String>{
    ...kCategories.where((c) => c != "Other"),
    ...List<String>.from(s.company["customCategories"] ?? const []),
    "Other",
  }.toList();
  DateTime date = DateTime.now();
  String receipt = "";
  bool saving = false;
  final visibleTo = <String>{};

  showLedgerSheet(
      context,
      "Post expense",
      (ctx) => StatefulBuilder(
            builder: (ctx, set) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (s.isAdmin) ...[
                  const SizedBox(height: 8),
                  Text("Visible to staff", style: labelStyle),
                  ...s.members
                      .where((m) =>
                          m["role"] != "admin" &&
                          m["userId"].toString() != s.userId)
                      .map((m) => CheckboxListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(m["name"].toString(),
                                style: GoogleFonts.inter(
                                    color: kDark, fontSize: 13)),
                            value: visibleTo.contains(m["userId"].toString()),
                            onChanged: (v) => set(() {
                              if (v == true) {
                                visibleTo.add(m["userId"].toString());
                              } else {
                                visibleTo.remove(m["userId"].toString());
                              }
                            }),
                          )),
                ],
                DropdownButtonFormField<String>(
                  initialValue: category,
                  decoration:
                      fieldDecoration("Category", icon: Icons.category_rounded),
                  items: categories
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) => set(() => category = v ?? "General"),
                ),
                if (category == "Other") ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: otherCtrl,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: fieldDecoration("Specify the category *",
                        icon: Icons.edit_rounded),
                  ),
                ],
                const SizedBox(height: 10),
                TextField(
                    controller: amount,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: fieldDecoration("Amount ₹",
                        icon: Icons.currency_rupee_rounded)),
                const SizedBox(height: 10),
                TextField(
                    controller: desc,
                    decoration: fieldDecoration("Description",
                        icon: Icons.notes_rounded)),
                const SizedBox(height: 10),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                        context: ctx,
                        initialDate: date,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now());
                    if (picked != null) set(() => date = picked);
                  },
                  child: InputDecorator(
                    decoration: fieldDecoration("Date",
                        icon: Icons.calendar_today_rounded),
                    child: Text(DateFormat("dd MMM yyyy").format(date)),
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      foregroundColor: kForest,
                      side: const BorderSide(color: kForest)),
                  onPressed: () async {
                    final img = await ImagePicker().pickImage(
                        source: ImageSource.gallery,
                        maxWidth: 1200,
                        imageQuality: 70);
                    if (img == null) return;
                    final bytes = await File(img.path).readAsBytes();
                    set(() => receipt =
                        "data:image/jpeg;base64,${base64Encode(bytes)}");
                  },
                  icon: Icon(receipt.isEmpty
                      ? Icons.photo_camera_rounded
                      : Icons.check_circle_rounded),
                  label: Text(receipt.isEmpty
                      ? "Attach receipt photo"
                      : "Receipt attached"),
                ),
                const SizedBox(height: 16),
                primaryButton(
                    saving ? "Saving..." : "Submit expense",
                    saving
                        ? null
                        : () async {
                            if (category == "Other" &&
                                otherCtrl.text.trim().isEmpty) {
                              toast(ctx,
                                  "Please specify what the “Other” category is",
                                  error: true);
                              return;
                            }
                            set(() => saving = true);
                            final res = await LedgerService.createExpense({
                              "companyId": s.companyId,
                              "userId": s.userId,
                              "amount":
                                  double.tryParse(amount.text.trim()) ?? 0,
                              "description": desc.text.trim(),
                              "category": category == "Other"
                                  ? otherCtrl.text.trim()
                                  : category,
                              "date": date.toIso8601String(),
                              "attachment": receipt,
                              "visibleTo": visibleTo.toList(),
                            });
                            if (!ctx.mounted) return;
                            set(() => saving = false);
                            final lifecycle =
                                res["expense"]?["lifecycle"]?.toString();
                            final successMessage = lifecycle == "approved"
                                ? "Expense added and approved"
                                : "Expense submitted for approval";
                            if (handleResult(ctx, res, successMessage)) {
                              Navigator.pop(ctx);
                              notifyLedgerChanged();
                              onDone?.call();
                            }
                          }),
              ],
            ),
          ));
}
