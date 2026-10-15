import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/ledger_service.dart';
import 'ledger_common.dart';

class LedgerIntercoTab extends StatefulWidget {
  final LedgerScope scope;
  const LedgerIntercoTab({super.key, required this.scope});

  @override
  State<LedgerIntercoTab> createState() => _LedgerIntercoTabState();
}

class _LedgerIntercoTabState extends State<LedgerIntercoTab> with LedgerAutoRefresh {
  @override
  void onLedgerChanged() => _load();

  LedgerScope get s => widget.scope;
  List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _sources = [];
  num _net = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await Future.wait([
      LedgerService.intercompanyBalances(s.companyId, s.userId),
      LedgerService.borrowSources(s.companyId, s.userId),
    ]);
    if (!mounted) return;
    setState(() {
      _rows = List<Map<String, dynamic>>.from(r[0]["balances"] ?? const []);
      _net = (r[0]["net"] as num?) ?? 0;
      _sources = List<Map<String, dynamic>>.from(r[1]["companies"] ?? const []);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: Colors.white));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 30),
        children: [
          ledgerCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("INTER-COMPANY NET", style: GoogleFonts.ibmPlexMono(color: const Color(0xFF6B7280), fontSize: 10.5, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text("${_net >= 0 ? "+" : ""}${inr(_net)}", style: GoogleFonts.fraunces(fontSize: 26, fontWeight: FontWeight.bold, color: _net >= 0 ? kForest : kTerracotta)),
                Text(_net >= 0 ? "Other companies owe ${s.companyName}" : "${s.companyName} owes other companies",
                    style: GoogleFonts.inter(fontSize: 12, color: kDark.withValues(alpha: 0.6))),
              ],
            ),
          ),
          Row(
            children: [
              Expanded(child: primaryButton("Record transfer", _openTransfer, color: kForestDark)),
              const SizedBox(width: 10),
              Expanded(child: primaryButton("Routed payment", _openRouted, color: kForestDark)),
            ],
          ),
          sectionTitle("Who owes whom"),
          if (_rows.isEmpty) emptyState("No inter-company activity yet"),
          ..._rows.map((r) {
            final net = (r["net"] as num?) ?? 0;
            return ledgerCard(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r["name"].toString(), style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: kDark)),
                        Text(net == 0 ? "Settled" : (net > 0 ? "They owe us" : "We owe them"),
                            style: GoogleFonts.inter(fontSize: 12, color: kDark.withValues(alpha: 0.6))),
                        if (r["mismatch"] == true) ...[const SizedBox(height: 4), statusPill("Books don't match", kTerracotta)],
                      ],
                    ),
                  ),
                  Text(inr(net.abs()), style: GoogleFonts.fraunces(fontWeight: FontWeight.bold, fontSize: 16, color: net >= 0 ? kForest : kTerracotta)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _companyPicker(String? value, ValueChanged<String?> onChanged) => _sources.isEmpty
      ? Text("No other companies yet — tap “Add new company” below.", style: GoogleFonts.inter(color: kTerracotta, fontSize: 12.5))
      : DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        decoration: fieldDecoration("Other company", icon: Icons.business_rounded),
        items: _sources.map((c) => DropdownMenuItem(value: c["_id"].toString(), child: Text(c["name"].toString()))).toList(),
        onChanged: onChanged,
      );

  void _openTransfer() {
    String direction = "in";
    String? other;
    String? fund;
    String method = "Bank";
    final amount = TextEditingController();
    final ref = TextEditingController();
    showLedgerSheet(context, "Record transfer", (ctx) => StatefulBuilder(
          builder: (ctx, set) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: "in", label: Text("They paid us")),
                  ButtonSegment(value: "out", label: Text("We paid them")),
                ],
                selected: {direction},
                onSelectionChanged: (v) => set(() => direction = v.first),
              ),
              const SizedBox(height: 12),
              _companyPicker(other, (v) => set(() => other = v)),
              const SizedBox(height: 10),
              TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: fieldDecoration("Amount ₹", icon: Icons.currency_rupee_rounded)),
              const SizedBox(height: 10),
              fundDropdown(s, fund, (v) => set(() => fund = v), hint: direction == "in" ? "Received into" : "Paid from"),
              const SizedBox(height: 10),
              methodChips(method, (m) => set(() => method = m)),
              const SizedBox(height: 10),
              TextField(controller: ref, decoration: fieldDecoration("Reference no.", icon: Icons.tag_rounded)),
              const SizedBox(height: 16),
              primaryButton("Record transfer", () async {
                final incoming = direction == "in";
                final res = await LedgerService.intercompany({
                  "userId": s.userId,
                  "fromCompanyId": incoming ? other : s.companyId,
                  "toCompanyId": incoming ? s.companyId : other,
                  "fromFundId": incoming ? "cash" : fund,
                  "toFundId": incoming ? fund : "cash",
                  "amount": double.tryParse(amount.text.trim()) ?? 0,
                  "method": method,
                  "reference": ref.text.trim(),
                });
                if (!ctx.mounted) return;
                if (handleResult(ctx, res, "Transfer recorded in both companies")) {
                  Navigator.pop(ctx);
                  _load();
                }
              }),
            ],
          ),
        ));
  }

  void _openRouted() {
    final admins = s.admins.where((a) => a["userId"].toString() != s.userId || s.isSuperAdmin).toList();
    String? adminId = admins.isNotEmpty ? admins.first["userId"].toString() : null;
    String? source;
    bool adding = false;
    String method = "Bank";
    final amount = TextEditingController();
    final ref = TextEditingController();
    final newName = TextEditingController();
    final newGstin = TextEditingController();
    showLedgerSheet(context, "Routed payment", (ctx) => StatefulBuilder(
          builder: (ctx, set) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Another company pays an admin of ${s.companyName}. Booked as company → ${s.companyName} → admin.",
                  style: GoogleFonts.inter(fontSize: 12.5, color: kDark.withValues(alpha: 0.6))),
              const SizedBox(height: 12),
              if (!adding) _companyPicker(source, (v) => set(() => source = v)),
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: kForest),
                onPressed: () => set(() {
                  adding = !adding;
                  source = null;
                }),
                icon: Icon(adding ? Icons.close_rounded : Icons.add_rounded, size: 18),
                label: Text(adding ? "Pick an existing company" : "Add new company"),
              ),
              if (adding) ...[
                TextField(controller: newName, decoration: fieldDecoration("Company name", icon: Icons.business_rounded)),
                const SizedBox(height: 8),
                TextField(controller: newGstin, decoration: fieldDecoration("GSTIN (optional)", icon: Icons.badge_rounded)),
                const SizedBox(height: 10),
              ],
              DropdownButtonFormField<String>(
                initialValue: adminId,
                decoration: fieldDecoration("Admin being paid", icon: Icons.person_rounded),
                items: admins.map((a) => DropdownMenuItem(value: a["userId"].toString(), child: Text(a["name"].toString()))).toList(),
                onChanged: (v) => set(() => adminId = v),
              ),
              const SizedBox(height: 10),
              TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: fieldDecoration("Amount ₹", icon: Icons.currency_rupee_rounded)),
              const SizedBox(height: 10),
              methodChips(method, (m) => set(() => method = m)),
              const SizedBox(height: 10),
              TextField(controller: ref, decoration: fieldDecoration("Reference no.", icon: Icons.tag_rounded)),
              const SizedBox(height: 16),
              primaryButton("Confirm routed payment", () async {
                final body = <String, dynamic>{
                  "userId": s.userId,
                  "companyId": s.companyId,
                  "adminUserId": adminId,
                  "amount": double.tryParse(amount.text.trim()) ?? 0,
                  "method": method,
                  "reference": ref.text.trim(),
                };
                if (adding) {
                  body["newCompany"] = {"name": newName.text.trim(), "gstin": newGstin.text.trim()};
                } else {
                  body["sourceCompanyId"] = source;
                  body["sourceFundId"] = "cash";
                }
                final res = await LedgerService.routed(body);
                if (!ctx.mounted) return;
                if (handleResult(ctx, res, "Routed payment recorded")) {
                  Navigator.pop(ctx);
                  _load();
                }
              }),
            ],
          ),
        ));
  }
}
