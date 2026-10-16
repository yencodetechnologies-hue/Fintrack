import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/ledger_service.dart';
import 'ledger_common.dart';

class LedgerDashboardTab extends StatefulWidget {
  final LedgerScope scope;
  final VoidCallback onOpenExpenses;
  const LedgerDashboardTab(
      {super.key, required this.scope, required this.onOpenExpenses});

  @override
  State<LedgerDashboardTab> createState() => _LedgerDashboardTabState();
}

class _LedgerDashboardTabState extends State<LedgerDashboardTab>
    with LedgerAutoRefresh {
  @override
  void onLedgerChanged() => _load();

  LedgerScope get s => widget.scope;
  Map<String, dynamic>? _balances;
  num _owedToOtherCompanies = 0;
  List<Map<String, dynamic>> _pending = [];
  List<Map<String, dynamic>> _today = [];
  bool _loading = true;
  bool _secondaryLoading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await Future.wait([
      LedgerService.balances(s.companyId, s.userId),
      LedgerService.dashboardExpenses(s.companyId, s.userId),
    ]);
    if (!mounted) return;
    final now = DateTime.now();
    final expenses =
        List<Map<String, dynamic>>.from(r[1]["expenses"] ?? const []);
    setState(() {
      _balances = r[0];
      _today = expenses.where((e) {
        final d =
            DateTime.tryParse(e["createdAt"]?.toString() ?? "")?.toLocal();
        return d != null &&
            d.year == now.year &&
            d.month == now.month &&
            d.day == now.day;
      }).toList();
      _loading = false;
    });
    unawaited(_loadSecondary());
  }

  Future<void> _loadSecondary() async {
    if (_secondaryLoading) return;
    _secondaryLoading = true;
    try {
      final r = await Future.wait([
        LedgerService.loans(s.companyId, s.userId),
        if (s.isAdmin) LedgerService.transactions(s.companyId, s.userId),
      ]);
      if (!mounted) return;
      setState(() {
        final loans =
            List<Map<String, dynamic>>.from(r[0]["loans"] ?? const []);
        _owedToOtherCompanies = loans
            .where((l) => idOf(l["borrowerCompanyId"]) == s.companyId)
            .fold<num>(0, (sum, l) => sum + ((l["balance"] as num?) ?? 0));
        if (s.isAdmin) {
          _pending =
              List<Map<String, dynamic>>.from(r[1]["transactions"] ?? const [])
                  .where((t) =>
                      t["verification"] == "pending" && t["reversedBy"] == null)
                  .toList();
        }
      });
    } finally {
      _secondaryLoading = false;
    }
  }

  Future<void> _changed() async {
    await s.reload();
  }

  @override
  Widget build(BuildContext context) {
    final myOwed = _balances?["myOwed"];

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(20)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("COMPANY OWES YOU",
                    style: GoogleFonts.ibmPlexMono(
                        color: const Color(0xFF6B7280),
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8)),
                const SizedBox(height: 6),
                Text(myOwed == null ? "Loading…" : inr(myOwed),
                    style: GoogleFonts.fraunces(
                        color: kForest,
                        fontSize: 27,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(height: 6),
          _tile(
              "Owed to other companies",
              _loading || _secondaryLoading
                  ? "Loading…"
                  : inr(_owedToOtherCompanies),
              _owedToOtherCompanies > 0 ? kTerracotta : kForest),
          if (s.isAdmin) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                    child: _tile(
                        "Owed to people",
                        _balances == null
                            ? "Loading…"
                            : inr(_balances?["totalOwedToPeople"] ??
                                _balances?["totalOwedToAdmins"] ??
                                0),
                        kTerracotta)),
                const SizedBox(width: 6),
                Expanded(
                    child: _tile(
                        "Cash / bank",
                        _balances == null
                            ? "Loading…"
                            : inr((_balances?["funds"] as List? ?? const [])
                                .fold<num>(
                                    0,
                                    (total, fund) =>
                                        total +
                                        ((fund["balance"] as num?) ?? 0))),
                        kForest)),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                    child: _action(
                        Icons.savings_rounded, "Lend to company", _openLend)),
                const SizedBox(width: 6),
                Expanded(
                    child: _action(Icons.payments_rounded, "Reimburse person",
                        _openReimburse)),
              ],
            ),
            _sectionTitle("Pending verification"),
            if (_pending.isEmpty)
              _compactEmpty(_secondaryLoading
                  ? "Checking pending verification…"
                  : "Nothing waiting for verification"),
            ..._pending.map(_pendingCard),
          ],
          _sectionTitle("Today"),
          if (_today.isEmpty)
            _compactEmpty(
                _loading ? "Loading today's activity…" : "No activity today"),
          ..._today.map((e) {
            final status = e["lifecycle"]?.toString();
            final statusLabel = switch (status) {
              "paid_by_admin" ||
              "paid_by_person" ||
              "paid_by_company" =>
                "Paid",
              "awaiting_confirmation" => "Waiting",
              "reimbursed" => "Repaid",
              _ => kLifecycleLabels[status] ?? "",
            };
            return Container(
              margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: kDark.withValues(alpha: 0.06)),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: widget.onOpenExpenses,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                            color: kForest.withValues(alpha: 0.10),
                            shape: BoxShape.circle),
                        child: const Icon(Icons.receipt_long_rounded,
                            color: kForest, size: 16),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(e["description"]?.toString() ?? "Expense",
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12.5,
                                    color: kDark)),
                            const SizedBox(height: 2),
                            Text(
                                "${e["category"] ?? "General"} · ${nameOf(e["createdBy"])}",
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                    fontSize: 10.5,
                                    color: kDark.withValues(alpha: 0.6))),
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
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11.5,
                                  color: kDark)),
                          const SizedBox(height: 2),
                          statusPill(statusLabel, lifecycleColor(status)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          if (s.isAdmin)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text("Day-close summary goes to all admins",
                  textAlign: TextAlign.center,
                  style:
                      GoogleFonts.inter(color: Colors.white54, fontSize: 11.5)),
            ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 12, 2, 4),
        child: Text(
          text,
          style: GoogleFonts.fraunces(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      );

  Widget _compactEmpty(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Center(
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(color: Colors.white70, fontSize: 13),
          ),
        ),
      );

  Widget _tile(String label, String value, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: GoogleFonts.inter(
                    color: kDark.withValues(alpha: 0.6),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            FittedBox(
                child: Text(value,
                    style: GoogleFonts.fraunces(
                        color: color,
                        fontSize: 18,
                        fontWeight: FontWeight.bold))),
          ],
        ),
      );

  Widget _action(IconData icon, String label, VoidCallback onTap) => Material(
        color: kForestDark,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            child: Row(
              children: [
                Icon(icon, color: kMint, size: 20),
                const SizedBox(width: 8),
                Flexible(
                    child: Text(label,
                        style: GoogleFonts.inter(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13))),
              ],
            ),
          ),
        ),
      );

  Widget _pendingCard(Map<String, dynamic> t) {
    final amount = (t["entries"] as List? ?? const [])
        .fold<num>(0, (sum, e) => sum + ((e["debit"] as num?) ?? 0));
    final mine = idOf(t["createdBy"]) == s.userId;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kDark.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
                color: kAmber.withValues(alpha: 0.12), shape: BoxShape.circle),
            child:
                const Icon(Icons.fact_check_outlined, color: kAmber, size: 16),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(t["memo"]?.toString() ?? "Transaction",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                        color: kDark)),
                const SizedBox(height: 2),
                Text("Paid by ${nameOf(t["createdBy"])} · ${inr(amount)}",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                        fontSize: 10.5, color: kDark.withValues(alpha: 0.6))),
              ],
            ),
          ),
          const SizedBox(width: 4),
          if (!mine)
            TextButton(
              style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              onPressed: () async {
                final res =
                    await LedgerService.verify(t["_id"].toString(), s.userId);
                if (!mounted) return;
                if (handleResult(context, res, "Payment verified")) _load();
              },
              child: Text("Verify",
                  style: GoogleFonts.inter(
                      color: kForest,
                      fontWeight: FontWeight.bold,
                      fontSize: 12)),
            )
          else
            statusPill("Awaiting admin", kAmber),
        ],
      ),
    );
  }

  void _openLend() {
    final amount = TextEditingController();
    final ref = TextEditingController();
    String? fund;
    String method = "UPI";
    showLedgerSheet(
        context,
        "Lend to ${s.companyName}",
        (ctx) => StatefulBuilder(
              builder: (ctx, set) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      "The company will owe you this amount until it pays you back.",
                      style: GoogleFonts.inter(
                          fontSize: 12.5, color: kDark.withValues(alpha: 0.6))),
                  const SizedBox(height: 12),
                  TextField(
                      controller: amount,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: fieldDecoration("Amount ₹",
                          icon: Icons.currency_rupee_rounded)),
                  const SizedBox(height: 10),
                  fundDropdown(s, fund, (v) => set(() => fund = v),
                      hint: "Paid into"),
                  const SizedBox(height: 10),
                  methodChips(method, (m) => set(() => method = m)),
                  const SizedBox(height: 10),
                  TextField(
                      controller: ref,
                      decoration: fieldDecoration("Reference no.",
                          icon: Icons.tag_rounded)),
                  const SizedBox(height: 16),
                  primaryButton("Confirm loan", () async {
                    final res = await LedgerService.lend({
                      "companyId": s.companyId,
                      "userId": s.userId,
                      "amount": double.tryParse(amount.text.trim()) ?? 0,
                      "fundId": fund,
                      "method": method,
                      "reference": ref.text.trim(),
                    });
                    if (!ctx.mounted) return;
                    if (handleResult(ctx, res, "Loan recorded")) {
                      Navigator.pop(ctx);
                      _changed();
                    }
                  }),
                ],
              ),
            ));
  }

  void _openReimburse() {
    final payees =
        List<Map<String, dynamic>>.from(_balances?["admins"] ?? const [])
            .where((a) =>
                idOf(a["userId"]) != s.userId && ((a["owed"] as num?) ?? 0) > 0)
            .toList();
    final amount = TextEditingController();
    final ref = TextEditingController();
    String? adminId = payees.isNotEmpty ? idOf(payees.first["userId"]) : null;
    String? fund;
    String method = "UPI";
    final owedById = {
      for (final a in payees) idOf(a["userId"]): a["owed"],
    };
    showLedgerSheet(
        context,
        "Reimburse person",
        (ctx) => StatefulBuilder(
              builder: (ctx, set) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (payees.isEmpty)
                    Text("No outstanding person payable to reimburse.",
                        style: GoogleFonts.inter(color: kTerracotta))
                  else ...[
                    DropdownButtonFormField<String>(
                      initialValue: adminId,
                      decoration:
                          fieldDecoration("Person", icon: Icons.person_rounded),
                      items: payees
                          .map((a) => DropdownMenuItem(
                              value: idOf(a["userId"]),
                              child: Text(a["name"].toString())))
                          .toList(),
                      onChanged: (v) => set(() => adminId = v),
                    ),
                    const SizedBox(height: 8),
                    Text("Open balance: ${inr(owedById[adminId] ?? 0)}",
                        style: GoogleFonts.inter(
                            color: kForest, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    TextField(
                        controller: amount,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: fieldDecoration(
                            "Amount ₹ (partial allowed)",
                            icon: Icons.currency_rupee_rounded)),
                    const SizedBox(height: 10),
                    fundDropdown(s, fund, (v) => set(() => fund = v),
                        hint: "Pay from"),
                    const SizedBox(height: 10),
                    methodChips(method, (m) => set(() => method = m)),
                    const SizedBox(height: 10),
                    TextField(
                        controller: ref,
                        decoration: fieldDecoration("Reference no.",
                            icon: Icons.tag_rounded)),
                    const SizedBox(height: 16),
                    primaryButton("Confirm reimbursement", () async {
                      final res = await LedgerService.reimburse({
                        "companyId": s.companyId,
                        "userId": s.userId,
                        "adminUserId": adminId,
                        "amount": double.tryParse(amount.text.trim()) ?? 0,
                        "fundId": fund,
                        "method": method,
                        "reference": ref.text.trim(),
                      });
                      if (!ctx.mounted) return;
                      if (handleResult(ctx, res, "Reimbursement recorded")) {
                        Navigator.pop(ctx);
                        _changed();
                      }
                    }),
                  ],
                ],
              ),
            ));
  }
}
