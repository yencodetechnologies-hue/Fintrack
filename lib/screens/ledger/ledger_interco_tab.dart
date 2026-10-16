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
  List<Map<String, dynamic>> _sources = [];
  List<Map<String, dynamic>> _loans = [];
  List<Map<String, dynamic>> _requests = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await Future.wait([
      LedgerService.borrowSources(s.companyId, s.userId),
      LedgerService.loans(s.companyId, s.userId),
      s.isAdmin ? LedgerService.payerConfirmations(s.companyId, s.userId) : Future.value({"expenses": <dynamic>[]}),
    ]);
    if (!mounted) return;
    setState(() {
      _sources = List<Map<String, dynamic>>.from(r[0]["companies"] ?? const []);
      _loans = List<Map<String, dynamic>>.from(r[1]["loans"] ?? const []);
      _requests = List<Map<String, dynamic>>.from(r[2]["expenses"] ?? const []);
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
          if (s.isAdmin) ...[
            const SizedBox(height: 8),
            primaryButton("Borrow from a company", _openLoan, color: kForestDark),
            const SizedBox(height: 8),
            primaryButton("Routed payment to admin", _openRouted, color: kForestDark),
          ],
          if (s.isAdmin) ...[
            sectionTitle("Payment confirmations"),
            if (_requests.isEmpty) emptyState("No expenses waiting for your company"),
            ..._requests.map((e) => ledgerCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text("${e["description"]} · ${inr(e["amount"])}", style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: kDark)),
              Text("${nameOf(e["companyId"], "Another company")} · requested by ${nameOf(e["createdBy"])}", style: GoogleFonts.inter(fontSize: 12, color: kDark.withValues(alpha: 0.65))),
              Row(children: [
                Expanded(child: OutlinedButton(onPressed: () => _respondToRequest(e, false), child: const Text("Reject"))),
                const SizedBox(width: 8),
                Expanded(child: ElevatedButton(onPressed: () => _respondToRequest(e, true), child: const Text("Accept"))),
              ]),
            ]))),
          ],
          sectionTitle("Company loans"),
          if (_loans.isEmpty) emptyState("No company loans yet"),
          ..._loans.map((loan) {
            final borrower = loan["borrowerCompanyId"] is Map ? loan["borrowerCompanyId"]["name"] : "Borrower";
            final lender = loan["lenderCompanyId"] is Map ? loan["lenderCompanyId"]["name"] : "Lender";
            final borrowedHere = idOf(loan["borrowerCompanyId"]) == s.companyId;
            final balance = (loan["balance"] as num?) ?? 0;
            return ledgerCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Expanded(child: Text(borrowedHere ? "Borrowed from $lender" : "Lent to $borrower", style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: kDark))), statusPill(loan["status"]?.toString() ?? "Outstanding", balance == 0 ? kMint : kAmber)]),
              const SizedBox(height: 5),
              Text("Balance ${inr(balance)} · Original ${inr(loan["amount"])}", style: GoogleFonts.inter(fontSize: 12, color: kDark.withValues(alpha: 0.65))),
              if (borrowedHere && balance > 0 && s.isAdmin) Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => _openRepay(loan), child: const Text("Repay"))),
            ]));
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

  Future<void> _respondToRequest(Map<String, dynamic> expense, bool accept) async {
    if (!accept) {
      final res = await LedgerService.confirmPayer(expense["_id"].toString(), s.userId, false);
      if (!mounted) return;
      if (handleResult(context, res, "Payment declined")) _load();
      return;
    }
    String? fund;
    showLedgerSheet(context, "Accept payment", (ctx) => StatefulBuilder(builder: (ctx, set) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text("This confirms ${expense["description"]} and records a company loan.", style: GoogleFonts.inter(color: kDark)),
      const SizedBox(height: 12),
      fundDropdown(s, fund, (v) => set(() => fund = v), hint: "Paid from cash / bank"),
      const SizedBox(height: 16),
      primaryButton("Confirm payment", () async {
        if (fund == null) { toast(ctx, "Choose the paying fund", error: true); return; }
        final res = await LedgerService.confirmPayer(expense["_id"].toString(), s.userId, true, fundId: fund);
        if (!ctx.mounted) return;
        if (handleResult(ctx, res, "Payment accepted and loan recorded")) { Navigator.pop(ctx); _load(); }
      }),
    ])));
  }

  void _openLoan() {
    String? lender;
    String? fund;
    String method = "Bank";
    final amount = TextEditingController();
    final ref = TextEditingController();
    final note = TextEditingController();
    showLedgerSheet(context, "Borrow from a company", (ctx) => StatefulBuilder(builder: (ctx, set) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _companyPicker(lender, (v) => set(() => lender = v)),
      const SizedBox(height: 10),
      TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: fieldDecoration("Amount ₹", icon: Icons.currency_rupee_rounded)),
      const SizedBox(height: 10),
      fundDropdown(s, fund, (v) => set(() => fund = v), hint: "Borrow into"),
      const SizedBox(height: 10),
      methodChips(method, (m) => set(() => method = m)),
      const SizedBox(height: 10),
      TextField(controller: ref, decoration: fieldDecoration("Reference")),
      const SizedBox(height: 8),
      TextField(controller: note, decoration: fieldDecoration("Note")),
      const SizedBox(height: 16),
      primaryButton("Record loan", () async {
        final res = await LedgerService.createLoan({"userId": s.userId, "borrowerCompanyId": s.companyId, "lenderCompanyId": lender, "amount": double.tryParse(amount.text.trim()) ?? 0, "fundId": fund, "method": method, "reference": ref.text.trim(), "note": note.text.trim()});
        if (!ctx.mounted) return;
        if (handleResult(ctx, res, "Company loan recorded")) { Navigator.pop(ctx); _load(); }
      }),
    ])));
  }

  void _openRepay(Map<String, dynamic> loan) {
    final amount = TextEditingController();
    final ref = TextEditingController();
    String? fund;
    String method = "Bank";
    showLedgerSheet(context, "Repay loan", (ctx) => StatefulBuilder(builder: (ctx, set) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text("Outstanding balance: ${inr(loan["balance"])}", style: labelStyle),
      const SizedBox(height: 10),
      TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: fieldDecoration("Repayment amount ₹")),
      const SizedBox(height: 10),
      fundDropdown(s, fund, (v) => set(() => fund = v), hint: "Paid from"),
      const SizedBox(height: 10),
      methodChips(method, (m) => set(() => method = m)),
      const SizedBox(height: 8),
      TextField(controller: ref, decoration: fieldDecoration("Reference")),
      const SizedBox(height: 16),
      primaryButton("Record repayment", () async {
        final res = await LedgerService.repayLoan(loan["_id"].toString(), {"userId": s.userId, "amount": double.tryParse(amount.text.trim()) ?? 0, "fundId": fund, "method": method, "reference": ref.text.trim()});
        if (!ctx.mounted) return;
        if (handleResult(ctx, res, "Repayment recorded")) { Navigator.pop(ctx); _load(); }
      }),
    ])));
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
                TextField(controller: newGstin, decoration: fieldDecoration("GSTIN *", icon: Icons.badge_rounded)),
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
                if (adding && (newName.text.trim().isEmpty || newGstin.text.trim().isEmpty)) {
                  toast(ctx, "Enter the outside company name and GSTIN", error: true);
                  return;
                }
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
