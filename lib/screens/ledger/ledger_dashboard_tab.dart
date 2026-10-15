import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/ledger_service.dart';
import 'ledger_common.dart';

class LedgerDashboardTab extends StatefulWidget {
  final LedgerScope scope;
  final VoidCallback onOpenExpenses;
  const LedgerDashboardTab({super.key, required this.scope, required this.onOpenExpenses});

  @override
  State<LedgerDashboardTab> createState() => _LedgerDashboardTabState();
}

class _LedgerDashboardTabState extends State<LedgerDashboardTab> with LedgerAutoRefresh {
  @override
  void onLedgerChanged() => _load();

  LedgerScope get s => widget.scope;
  Map<String, dynamic>? _balances;
  num _intercoNet = 0;
  List<Map<String, dynamic>> _pending = [];
  List<Map<String, dynamic>> _today = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final calls = <Future<Map<String, dynamic>>>[
      LedgerService.balances(s.companyId, s.userId),
      LedgerService.expenses(s.companyId, s.userId),
      if (s.isAdmin) LedgerService.transactions(s.companyId, s.userId),
      if (s.isAdmin) LedgerService.intercompanyBalances(s.companyId, s.userId),
    ];
    final r = await Future.wait(calls);
    if (!mounted) return;
    final now = DateTime.now();
    final expenses = List<Map<String, dynamic>>.from(r[1]["expenses"] ?? const []);
    setState(() {
      _balances = r[0];
      _today = expenses.where((e) {
        final d = DateTime.tryParse(e["createdAt"]?.toString() ?? "")?.toLocal();
        return d != null && d.year == now.year && d.month == now.month && d.day == now.day;
      }).toList();
      if (s.isAdmin) {
        _pending = List<Map<String, dynamic>>.from(r[2]["transactions"] ?? const [])
            .where((t) => t["verification"] == "pending" && t["reversedBy"] == null)
            .toList();
        _intercoNet = (r[3]["net"] as num?) ?? 0;
      }
      _loading = false;
    });
  }

  Future<void> _changed() async {
    await s.reload();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: Colors.white));
    final myOwed = _balances?["myOwed"] ?? 0;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 30),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("COMPANY OWES YOU", style: GoogleFonts.ibmPlexMono(color: const Color(0xFF6B7280), fontSize: 10.5, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
                const SizedBox(height: 6),
                Text(inr(myOwed), style: GoogleFonts.fraunces(color: kForest, fontSize: 30, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          if (s.isAdmin) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _tile("Owed to all admins", inr(_balances?["totalOwedToAdmins"] ?? 0), kTerracotta)),
                const SizedBox(width: 10),
                Expanded(child: _tile("Inter-company net", "${_intercoNet >= 0 ? "+" : ""}${inr(_intercoNet)}", _intercoNet >= 0 ? kForest : kTerracotta)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _action(Icons.savings_rounded, "Lend to company", _openLend)),
                const SizedBox(width: 10),
                Expanded(child: _action(Icons.payments_rounded, "Reimburse admin", _openReimburse)),
              ],
            ),
            sectionTitle("Pending verification"),
            if (_pending.isEmpty) emptyState("Nothing waiting for verification"),
            ..._pending.map(_pendingCard),
          ],
          sectionTitle("Today"),
          if (_today.isEmpty) emptyState("No activity today"),
          ..._today.map((e) => ledgerCard(
                child: InkWell(
                  onTap: widget.onOpenExpenses,
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("${e["category"] ?? "General"} · ${inr(e["amount"])}", style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: kDark)),
                            Text("${e["description"]} — ${nameOf(e["createdBy"])}", style: GoogleFonts.inter(fontSize: 12, color: kDark.withValues(alpha: 0.6))),
                          ],
                        ),
                      ),
                      statusPill(kLifecycleLabels[e["lifecycle"]] ?? "", lifecycleColor(e["lifecycle"])),
                    ],
                  ),
                ),
              )),
          if (s.isAdmin)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text("Day-close summary goes to all admins", textAlign: TextAlign.center, style: GoogleFonts.inter(color: Colors.white54, fontSize: 11.5)),
            ),
        ],
      ),
    );
  }

  Widget _tile(String label, String value, Color color) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: GoogleFonts.inter(color: kDark.withValues(alpha: 0.6), fontSize: 11.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            FittedBox(child: Text(value, style: GoogleFonts.fraunces(color: color, fontSize: 18, fontWeight: FontWeight.bold))),
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
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
            child: Row(
              children: [
                Icon(icon, color: kMint, size: 20),
                const SizedBox(width: 8),
                Flexible(child: Text(label, style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
              ],
            ),
          ),
        ),
      );

  Widget _pendingCard(Map<String, dynamic> t) {
    final amount = (t["entries"] as List? ?? const []).fold<num>(0, (sum, e) => sum + ((e["debit"] as num?) ?? 0));
    final mine = idOf(t["createdBy"]) == s.userId;
    return ledgerCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("${t["memo"]} · ${inr(amount)}", style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: kDark)),
                Text("Paid by ${nameOf(t["createdBy"])} · to check", style: GoogleFonts.inter(fontSize: 12, color: kDark.withValues(alpha: 0.6))),
              ],
            ),
          ),
          if (!mine)
            TextButton(
              onPressed: () async {
                final res = await LedgerService.verify(t["_id"].toString(), s.userId);
                if (!mounted) return;
                if (handleResult(context, res, "Payment verified")) _load();
              },
              child: Text("Verify", style: GoogleFonts.inter(color: kForest, fontWeight: FontWeight.bold)),
            )
          else
            statusPill("Awaiting 2nd admin", kAmber),
        ],
      ),
    );
  }

  void _openLend() {
    final amount = TextEditingController();
    final ref = TextEditingController();
    String? fund;
    String method = "UPI";
    showLedgerSheet(context, "Lend to ${s.companyName}", (ctx) => StatefulBuilder(
          builder: (ctx, set) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("The company will owe you this amount until it pays you back.", style: GoogleFonts.inter(fontSize: 12.5, color: kDark.withValues(alpha: 0.6))),
              const SizedBox(height: 12),
              TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: fieldDecoration("Amount ₹", icon: Icons.currency_rupee_rounded)),
              const SizedBox(height: 10),
              fundDropdown(s, fund, (v) => set(() => fund = v), hint: "Paid into"),
              const SizedBox(height: 10),
              methodChips(method, (m) => set(() => method = m)),
              const SizedBox(height: 10),
              TextField(controller: ref, decoration: fieldDecoration("Reference no.", icon: Icons.tag_rounded)),
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
    final admins = s.admins.where((a) => a["userId"].toString() != s.userId || s.isSuperAdmin).toList();
    final amount = TextEditingController();
    final ref = TextEditingController();
    String? adminId = admins.isNotEmpty ? admins.first["userId"].toString() : null;
    String? fund;
    String method = "UPI";
    final owedById = {
      for (final a in List<Map<String, dynamic>>.from(_balances?["admins"] ?? const [])) idOf(a["userId"]): a["owed"],
    };
    showLedgerSheet(context, "Reimburse admin", (ctx) => StatefulBuilder(
          builder: (ctx, set) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (admins.isEmpty)
                Text("No other admin to reimburse. Another admin must record your reimbursement.", style: GoogleFonts.inter(color: kTerracotta))
              else ...[
                DropdownButtonFormField<String>(
                  initialValue: adminId,
                  decoration: fieldDecoration("Admin", icon: Icons.person_rounded),
                  items: admins.map((a) => DropdownMenuItem(value: a["userId"].toString(), child: Text(a["name"].toString()))).toList(),
                  onChanged: (v) => set(() => adminId = v),
                ),
                const SizedBox(height: 8),
                Text("Open balance: ${inr(owedById[adminId] ?? 0)}", style: GoogleFonts.inter(color: kForest, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: fieldDecoration("Amount ₹ (partial allowed)", icon: Icons.currency_rupee_rounded)),
                const SizedBox(height: 10),
                fundDropdown(s, fund, (v) => set(() => fund = v), hint: "Pay from"),
                const SizedBox(height: 10),
                methodChips(method, (m) => set(() => method = m)),
                const SizedBox(height: 10),
                TextField(controller: ref, decoration: fieldDecoration("Reference no.", icon: Icons.tag_rounded)),
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
