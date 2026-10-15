import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../services/ledger_service.dart';
import 'ledger_common.dart';

const List<String> kCategories = ["General", "Travel", "Food & Dining", "Rent", "Software", "Office Supplies", "Utilities", "Other"];

class LedgerExpensesTab extends StatefulWidget {
  final LedgerScope scope;
  const LedgerExpensesTab({super.key, required this.scope});

  @override
  State<LedgerExpensesTab> createState() => _LedgerExpensesTabState();
}

class _LedgerExpensesTabState extends State<LedgerExpensesTab> with LedgerAutoRefresh {
  @override
  void onLedgerChanged() => _load();

  LedgerScope get s => widget.scope;
  List<Map<String, dynamic>> _expenses = [];
  bool _loading = true;
  String _filter = "All";

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await LedgerService.expenses(s.companyId, s.userId);
    if (!mounted) return;
    setState(() {
      _expenses = List<Map<String, dynamic>>.from(res["expenses"] ?? const []);
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

  Future<void> _run(Future<Map<String, dynamic>> call, String ok) async {
    final res = await call;
    if (!mounted) return;
    if (handleResult(context, res, ok)) _load();
  }

  @override
  Widget build(BuildContext context) {
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
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                children: [
                  Wrap(
                    spacing: 8,
                    children: ["All", "Submitted", "Approved", if (s.isAdmin) "Verify"]
                        .map((f) => ChoiceChip(
                              label: Text(f),
                              selected: _filter == f,
                              selectedColor: Colors.white,
                              backgroundColor: kForestDark,
                              labelStyle: GoogleFonts.inter(color: _filter == f ? kForest : Colors.white, fontWeight: FontWeight.w700),
                              onSelected: (_) => setState(() => _filter = f),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                  if (_visible.isEmpty) emptyState(s.isAdmin ? "No expenses here" : "You haven't posted any expenses yet"),
                  ..._visible.map(_card),
                ],
              ),
            ),
    );
  }

  Widget _card(Map<String, dynamic> e) {
    final status = e["lifecycle"]?.toString();
    final mine = idOf(e["createdBy"]) == s.userId;
    final subtitle = switch (status) {
      "approved" => "Approved by ${nameOf(e["approvedBy"], "admin")}",
      "paid_by_admin" || "reimbursed" => "Paid by ${nameOf(e["paidByAdminId"], "admin")}",
      _ => "Posted by ${mine ? "you" : nameOf(e["createdBy"])} · ${dateLabel(e["date"])}",
    };
    return ledgerCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text("${e["category"] ?? "General"}  ${inr(e["amount"])}", style: GoogleFonts.fraunces(fontWeight: FontWeight.bold, fontSize: 16, color: kDark))),
              statusPill(kLifecycleLabels[status] ?? "", lifecycleColor(status)),
            ],
          ),
          const SizedBox(height: 4),
          Text(e["description"]?.toString() ?? "", style: GoogleFonts.inter(color: kDark, fontWeight: FontWeight.w600)),
          Text(subtitle, style: GoogleFonts.inter(fontSize: 12, color: kDark.withValues(alpha: 0.6))),
          if (e["verification"] == "pending") ...[const SizedBox(height: 6), statusPill("Pending verification", kAmber)],
          if (e["verification"] == "verified") ...[const SizedBox(height: 6), statusPill("Verified", kMint)],
          if (e["attachment"] != null && e["attachment"].toString().isNotEmpty)
            TextButton.icon(
              style: TextButton.styleFrom(padding: EdgeInsets.zero, foregroundColor: kForest),
              onPressed: () => _showReceipt(e["attachment"].toString()),
              icon: const Icon(Icons.attach_file_rounded, size: 16),
              label: const Text("View receipt"),
            ),
          ..._actions(e, status, mine),
        ],
      ),
    );
  }

  List<Widget> _actions(Map<String, dynamic> e, String? status, bool mine) {
    final id = e["_id"].toString();
    Widget btn(String label, VoidCallback onTap, {bool filled = false, Color color = kForest, IconData? icon}) {
      final content = FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 16), const SizedBox(width: 5)],
            Text(label, maxLines: 1, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
      );
      final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
      const padding = EdgeInsets.symmetric(horizontal: 8);
      const size = Size.fromHeight(44);
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: filled
              ? ElevatedButton(
                  onPressed: onTap,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: padding,
                    minimumSize: size,
                    shape: shape,
                  ),
                  child: content,
                )
              : OutlinedButton(
                  onPressed: onTap,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: color,
                    backgroundColor: color.withValues(alpha: 0.06),
                    side: BorderSide(color: color.withValues(alpha: 0.6)),
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
      row.add(btn("Approve", () => _run(LedgerService.approve(id, s.userId), "Expense approved"), filled: true, icon: Icons.check_rounded));
      row.add(btn("Reject", () => _run(LedgerService.reject(id, s.userId), "Expense rejected"), color: kTerracotta, icon: Icons.close_rounded));
    }
    if (status == "submitted" && mine) {
      row.add(btn("Delete", () => _run(LedgerService.deleteExpense(id, s.userId), "Expense deleted"), color: kTerracotta, icon: Icons.delete_outline_rounded));
    }
    if (status == "approved" && s.isAdmin) {
      row.add(btn("Paid by me", () => _openPay(e, "admin"), filled: true, icon: Icons.person_rounded));
      row.add(btn("Company", () => _openPay(e, "company"), icon: Icons.business_rounded));
      row.add(btn("Borrow", () => _openPay(e, "borrow"), icon: Icons.swap_horiz_rounded));
    }
    if (row.isEmpty) return const [];
    return [const SizedBox(height: 12), Row(children: row)];
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

  bool _needsVerification(num amount) {
    final t = s.company["verificationThreshold"] as num?;
    return t != null && amount > t && s.admins.length > 1;
  }

  Future<void> _openPay(Map<String, dynamic> e, String initial) async {
    String payer = initial;
    String? fund;
    String? sourceId;
    bool addingCompany = false;
    String method = "UPI";
    final ref = TextEditingController();
    final newName = TextEditingController();
    final newGstin = TextEditingController();
    final amount = (e["amount"] as num?) ?? 0;

    List<Map<String, dynamic>> sources = [];
    final src = await LedgerService.borrowSources(s.companyId, s.userId);
    sources = List<Map<String, dynamic>>.from(src["companies"] ?? const []);
    if (!mounted) return;

    showLedgerSheet(context, "Pay expense", (ctx) => StatefulBuilder(
          builder: (ctx, set) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("${e["category"]} · ${inr(amount)} — ${s.companyName} · posted by ${nameOf(e["createdBy"])}",
                  style: GoogleFonts.inter(color: kDark.withValues(alpha: 0.7), fontSize: 12.5)),
              const SizedBox(height: 14),
              Text("Who pays?", style: labelStyle),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: "admin", label: Text("Paid by me")),
                  ButtonSegment(value: "company", label: Text("By company")),
                  ButtonSegment(value: "borrow", label: Text("Borrow")),
                ],
                selected: {payer},
                onSelectionChanged: (v) => set(() => payer = v.first),
              ),
              const SizedBox(height: 12),
              if (payer == "company") fundDropdown(s, fund, (v) => set(() => fund = v), hint: "Pay from"),
              if (payer == "borrow") ...[
                Text("Source company", style: labelStyle),
                const SizedBox(height: 6),
                if (!addingCompany && sources.isEmpty)
                  Text("No other companies yet — tap “Add new company” below.", style: GoogleFonts.inter(color: kTerracotta, fontSize: 12.5)),
                if (!addingCompany && sources.isNotEmpty)
                  DropdownButtonFormField<String>(
                    initialValue: sourceId,
                    isExpanded: true,
                    decoration: fieldDecoration("Select company", icon: Icons.business_rounded),
                    items: sources.map((c) => DropdownMenuItem(value: c["_id"].toString(), child: Text(c["name"].toString()))).toList(),
                    onChanged: (v) => set(() => sourceId = v),
                  ),
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: kForest),
                  onPressed: () => set(() {
                    addingCompany = !addingCompany;
                    sourceId = null;
                  }),
                  icon: Icon(addingCompany ? Icons.close_rounded : Icons.add_rounded, size: 18),
                  label: Text(addingCompany ? "Pick an existing company" : "Add new company"),
                ),
                if (addingCompany) ...[
                  Text("New company, saved on pay", style: GoogleFonts.inter(fontSize: 12, color: kDark.withValues(alpha: 0.6))),
                  const SizedBox(height: 6),
                  TextField(controller: newName, decoration: fieldDecoration("Company name", icon: Icons.business_rounded)),
                  const SizedBox(height: 8),
                  TextField(controller: newGstin, decoration: fieldDecoration("GSTIN (optional)", icon: Icons.badge_rounded)),
                ],
              ],
              const SizedBox(height: 12),
              Text("Method", style: labelStyle),
              const SizedBox(height: 6),
              methodChips(method, (m) => set(() => method = m)),
              const SizedBox(height: 10),
              TextField(controller: ref, decoration: fieldDecoration("Reference no.", icon: Icons.tag_rounded)),
              if (_needsVerification(amount)) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(12)),
                  child: Text("Above threshold: 2nd admin must verify", style: GoogleFonts.inter(color: kAmber, fontWeight: FontWeight.bold)),
                ),
              ],
              const SizedBox(height: 16),
              primaryButton("Confirm payment", () async {
                final body = <String, dynamic>{"userId": s.userId, "payer": payer, "method": method, "reference": ref.text.trim()};
                if (payer == "company") body["fundId"] = fund;
                if (payer == "borrow") {
                  if (addingCompany) {
                    body["newCompany"] = {"name": newName.text.trim(), "gstin": newGstin.text.trim()};
                  } else {
                    body["sourceCompanyId"] = sourceId;
                    body["sourceFundId"] = "cash";
                  }
                }
                final res = await LedgerService.pay(e["_id"].toString(), body);
                if (!ctx.mounted) return;
                if (handleResult(ctx, res, "Payment recorded")) {
                  Navigator.pop(ctx);
                  _load();
                }
              }),
              if (payer == "borrow")
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Center(child: Text("Admins of both companies are notified", style: GoogleFonts.inter(fontSize: 11.5, color: kDark.withValues(alpha: 0.5)))),
                ),
            ],
          ),
        ));
  }

  void _openPost() => showPostExpenseSheet(context, s, onDone: _load);
}

void showPostExpenseSheet(BuildContext context, LedgerScope s, {String? groupId, String? groupName, VoidCallback? onDone}) {
    final amount = TextEditingController();
    final desc = TextEditingController();
    String category = "General";
    DateTime date = DateTime.now();
    String receipt = "";
    bool saving = false;

    showLedgerSheet(context, groupName == null ? "Post expense" : "Post to ${groupName}", (ctx) => StatefulBuilder(
          builder: (ctx, set) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                initialValue: category,
                decoration: fieldDecoration("Category", icon: Icons.category_rounded),
                items: kCategories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (v) => set(() => category = v ?? "General"),
              ),
              const SizedBox(height: 10),
              TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: fieldDecoration("Amount ₹", icon: Icons.currency_rupee_rounded)),
              const SizedBox(height: 10),
              TextField(controller: desc, decoration: fieldDecoration("Description", icon: Icons.notes_rounded)),
              const SizedBox(height: 10),
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(context: ctx, initialDate: date, firstDate: DateTime(2020), lastDate: DateTime.now());
                  if (picked != null) set(() => date = picked);
                },
                child: InputDecorator(
                  decoration: fieldDecoration("Date", icon: Icons.calendar_today_rounded),
                  child: Text(DateFormat("dd MMM yyyy").format(date)),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: kForest, side: const BorderSide(color: kForest)),
                onPressed: () async {
                  final img = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1200, imageQuality: 70);
                  if (img == null) return;
                  final bytes = await File(img.path).readAsBytes();
                  set(() => receipt = "data:image/jpeg;base64,${base64Encode(bytes)}");
                },
                icon: Icon(receipt.isEmpty ? Icons.photo_camera_rounded : Icons.check_circle_rounded),
                label: Text(receipt.isEmpty ? "Attach receipt photo" : "Receipt attached"),
              ),
              const SizedBox(height: 16),
              primaryButton(saving ? "Saving..." : "Submit expense", saving
                  ? null
                  : () async {
                      set(() => saving = true);
                      final res = await LedgerService.createExpense({
                        "companyId": s.companyId,
                        "userId": s.userId,
                        "amount": double.tryParse(amount.text.trim()) ?? 0,
                        "description": desc.text.trim(),
                        "category": category,
                        "date": date.toIso8601String(),
                        "attachment": receipt,
                        if (groupId != null) "groupId": groupId,
                      });
                      if (!ctx.mounted) return;
                      set(() => saving = false);
                      if (handleResult(ctx, res, "Expense submitted")) {
                        Navigator.pop(ctx);
                        onDone?.call();
                      }
                    }),
            ],
          ),
        ));
  }
