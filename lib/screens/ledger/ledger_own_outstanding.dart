import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/ledger_service.dart';
import 'ledger_common.dart';

num _round(num n) => (n * 100).round() / 100;
String _keyOf(Map<String, dynamic> b) => b["transactionId"] != null ? "tx:${b["transactionId"]}" : "exp:${b["expenseId"]}";

/// Payments screen, managers (web's "Your outstanding"): what the company owes ME, bill by bill. Pay all or just
/// the ticked bills — always from company Cash/Bank, never "by self"; exactly those bills close.
class OwnOutstandingCard extends StatefulWidget {
  final LedgerScope scope;
  final VoidCallback? onPaid;
  const OwnOutstandingCard({super.key, required this.scope, this.onPaid});

  @override
  State<OwnOutstandingCard> createState() => _OwnOutstandingCardState();
}

class _OwnOutstandingCardState extends State<OwnOutstandingCard> with LedgerAutoRefresh {
  @override
  void onLedgerChanged() => _load();

  @override
  Set<String> get ledgerTopics => const {"balances", "expenses"};

  LedgerScope get s => widget.scope;
  List<Map<String, dynamic>>? _bills;
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await LedgerService.payableBills(s.companyId, s.userId, s.userId);
    if (!mounted) return;
    setState(() {
      _bills = res["success"] == true ? List<Map<String, dynamic>>.from(res["bills"] ?? const []) : const [];
      _selected.removeWhere((k) => !_bills!.any((b) => _keyOf(b) == k));
    });
  }

  num _sum(Iterable<Map<String, dynamic>> list) => _round(list.fold<num>(0, (a, b) => a + ((b["remaining"] as num?) ?? 0)));

  // Returns slivers: the top (amount + Pay buttons) stays pinned while the bill list scrolls under it, then
  // scrolls away with the card — same as the web. Used inside a CustomScrollView (Payments screen).
  @override
  Widget build(BuildContext context) {
    final bills = _bills;
    if (bills == null) return const SliverToBoxAdapter(child: SizedBox.shrink());
    final total = _sum(bills);
    if (!(total > 0)) return const SliverToBoxAdapter(child: SizedBox.shrink());
    final chosen = bills.where((b) => _selected.contains(_keyOf(b))).toList();
    final allOn = chosen.length == bills.length;

    final header = ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text("YOUR OUTSTANDING", style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: kDark.withValues(alpha: 0.55))),
          const SizedBox(height: 3),
          // ticked bills come off the total: what would still be owed after paying them
          Text(inr(_round(total - _sum(chosen))), style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w800, color: kTerracotta)),
          Text(
            chosen.isEmpty
                ? "${s.companyName} owes you this · paid from company Cash/Bank"
                : "${inr(_sum(chosen))} selected · left after paying the selected bills",
            style: GoogleFonts.inter(fontSize: 12, color: kDark.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 12),
          // two soft actions side by side, the main one full width underneath
          Row(children: [
            Expanded(child: _softButton(Icons.currency_rupee_rounded, "Pay an amount", () => _payAmount(bills))),
            const SizedBox(width: 10),
            Expanded(
              child: _softButton(
                Icons.checklist_rounded,
                chosen.isEmpty ? "Pay selected" : "Pay selected (${chosen.length})",
                chosen.isEmpty ? null : () => _pay(chosen),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: kForest,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () => _pay(bills),
              icon: const Icon(Icons.account_balance_wallet_rounded, size: 19),
              label: Text("Pay all · ${inr(total)}", style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
        ]),
      ),
    );

    final list = Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(bottom: Radius.circular(16))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: allOn,
          onChanged: (_) => setState(() => allOn ? _selected.clear() : _selected.addAll(bills.map(_keyOf))),
          title: Text("Select all (${bills.length})", style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: kDark)),
        ),
        for (final b in bills) ...[
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          InkWell(
            onTap: () => setState(() => _selected.contains(_keyOf(b)) ? _selected.remove(_keyOf(b)) : _selected.add(_keyOf(b))),
            child: Container(
              color: _selected.contains(_keyOf(b)) ? const Color(0xFFF0FDF6) : null,
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                Checkbox(
                  value: _selected.contains(_keyOf(b)),
                  onChanged: (_) => setState(() => _selected.contains(_keyOf(b)) ? _selected.remove(_keyOf(b)) : _selected.add(_keyOf(b))),
                ),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(b["description"]?.toString() ?? "Bill", style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: kDark)),
                    Text(
                      [
                        if ((b["category"]?.toString() ?? "").isNotEmpty) b["category"],
                        dateLabel(b["date"] ?? b["postedAt"]),
                        b["claim"] == true
                            ? "approved, not yet paid"
                            : (((b["remaining"] as num?) ?? 0) < ((b["amount"] as num?) ?? 0) ? "part paid · ${inr(b["amount"])} in all" : "paid by you"),
                      ].join(" · "),
                      style: GoogleFonts.inter(fontSize: 11.5, color: kDark.withValues(alpha: 0.6)),
                    ),
                  ]),
                ),
                Text(inr(b["remaining"]), style: GoogleFonts.inter(fontWeight: FontWeight.w800, color: kDark)),
              ]),
            ),
          ),
        ],
      ]),
    );

    // the group keeps the pinned top inside this card: once the card scrolls past, the top goes with it
    return SliverMainAxisGroup(slivers: [
      PinnedHeaderSliver(child: header),
      SliverToBoxAdapter(child: list),
    ]);
  }

  /// Light mint button (forest text); greyed out when [onTap] is null.
  Widget _softButton(IconData icon, String label, VoidCallback? onTap) {
    final enabled = onTap != null;
    return SizedBox(
      height: 46,
      child: TextButton.icon(
        style: TextButton.styleFrom(
          backgroundColor: enabled ? const Color(0xFFE8F7EF) : const Color(0xFFF1F5F9),
          foregroundColor: kForest,
          disabledForegroundColor: kDark.withValues(alpha: 0.35),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: enabled ? const Color(0xFFCBEBD9) : const Color(0xFFE2E8F0)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ),
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: FittedBox(child: Text(label, style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700))),
      ),
    );
  }

  /// Type an amount: it goes to the oldest bills first (by bill date); the last one may be part-paid.
  Future<void> _payAmount(List<Map<String, dynamic>> bills) async {
    final owed = _sum(bills);
    final sorted = [...bills]..sort((a, b) => (DateTime.tryParse((a["date"] ?? a["postedAt"] ?? "").toString()) ?? DateTime(2000))
        .compareTo(DateTime.tryParse((b["date"] ?? b["postedAt"] ?? "").toString()) ?? DateTime(2000)));
    final amount = TextEditingController();
    final ref = TextEditingController();
    var fund = s.funds.first.id;
    var method = "Bank";
    await showLedgerSheet(context, "Pay an amount", (ctx) => StatefulBuilder(builder: (ctx, set) {
          final typed = _round(num.tryParse(amount.text.trim()) ?? 0);
          final tooMuch = typed > owed + 0.001;
          final selected = s.funds.firstWhere((f) => f.id == fund, orElse: () => s.funds.first);
          final short = selected.balance < typed;
          var left = typed;
          final plan = sorted.map((b) {
            final remaining = (b["remaining"] as num?) ?? 0;
            final take = _round(left <= 0 ? 0 : (left < remaining ? left : remaining));
            left = _round(left - take);
            return (bill: b, take: take, state: take <= 0 ? "open" : (take < remaining ? "part" : "closed"));
          }).toList();
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("Goes to your oldest bills first. You're owed ${inr(owed)}.", style: GoogleFonts.inter(fontSize: 13, color: kDark.withValues(alpha: 0.7))),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: amount,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => set(() {}),
                  decoration: fieldDecoration("Amount ₹", icon: Icons.currency_rupee_rounded),
                ),
              ),
              TextButton(onPressed: () => set(() => amount.text = owed.toString()), child: const Text("Full")),
            ]),
            if (tooMuch)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text("You're owed only ${inr(owed)}.", style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: kTerracotta)),
              ),
            if (typed > 0 && !tooMuch)
              Container(
                margin: const EdgeInsets.only(top: 10),
                constraints: const BoxConstraints(maxHeight: 220),
                decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE2E8F0)), borderRadius: BorderRadius.circular(10)),
                child: ListView(shrinkWrap: true, children: [
                  for (final p in plan)
                    Container(
                      color: p.state == "closed" ? const Color(0xFFECFDF5) : p.state == "part" ? const Color(0xFFFFF7ED) : null,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(p.bill["description"]?.toString() ?? "Bill", style: GoogleFonts.inter(fontSize: 12.5, color: kDark)),
                            Text(dateLabel(p.bill["date"] ?? p.bill["postedAt"]), style: GoogleFonts.inter(fontSize: 11, color: kDark.withValues(alpha: 0.55))),
                          ]),
                        ),
                        Text(
                          p.state == "closed" ? "Closes · ${inr(p.take)}" : p.state == "part" ? "${inr(p.take)} of ${inr(p.bill["remaining"])}" : "Stays owed",
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: p.state == "closed" ? const Color(0xFF047857) : p.state == "part" ? const Color(0xFFC2410C) : kDark.withValues(alpha: 0.5),
                          ),
                        ),
                      ]),
                    ),
                ]),
              ),
            const SizedBox(height: 12),
            fundDropdown(s, fund, (v) => set(() => fund = v ?? "cash"), hint: "Paid from"),
            if (short)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text("Only ${inr(selected.balance)} available in ${selected.name}.",
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: kTerracotta)),
              ),
            const SizedBox(height: 10),
            methodChips(method, (m) => set(() => method = m)),
            const SizedBox(height: 10),
            TextField(controller: ref, decoration: fieldDecoration("Reference (optional) · UTR / cheque no.", icon: Icons.tag_rounded)),
            const SizedBox(height: 16),
            primaryButton(
              "Pay ${inr(typed)}",
              !(typed > 0) || tooMuch || short
                  ? null
                  : () async {
                      final res = await LedgerService.payOwnOutstanding(s.companyId, {
                        "userId": s.userId,
                        "amount": typed,
                        "fundId": fund,
                        "method": method,
                        "reference": ref.text.trim(),
                      });
                      if (!ctx.mounted) return;
                      final closed = (res["closed"] as num?) ?? 0;
                      final part = ((res["bills"] as num?) ?? 0) > closed;
                      if (handleResult(ctx, res, "${inr(res["paid"] ?? typed)} paid to you from company · $closed bill${closed == 1 ? "" : "s"} closed${part ? " · 1 part-paid" : ""}")) {
                        Navigator.pop(ctx);
                        _selected.clear();
                        notifyLedgerChanged();
                        widget.onPaid?.call();
                      }
                    },
            ),
          ]);
        }));
    amount.dispose();
    ref.dispose();
  }

  Future<void> _pay(List<Map<String, dynamic>> bills) async {
    final total = _sum(bills);
    var fund = s.funds.first.id;
    var method = "Bank";
    final ref = TextEditingController();
    await showLedgerSheet(context, "Pay your outstanding", (ctx) => StatefulBuilder(builder: (ctx, set) {
          final selected = s.funds.firstWhere((f) => f.id == fund, orElse: () => s.funds.first);
          final short = selected.balance < total;
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("${bills.length} bill${bills.length == 1 ? "" : "s"} · ${inr(total)} from company funds to you.",
                style: GoogleFonts.inter(fontSize: 13, color: kDark.withValues(alpha: 0.7))),
            const SizedBox(height: 12),
            fundDropdown(s, fund, (v) => set(() => fund = v ?? "cash"), hint: "Paid from"),
            if (short)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text("Only ${inr(selected.balance)} available in ${selected.name}.",
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: kTerracotta)),
              ),
            const SizedBox(height: 10),
            methodChips(method, (m) => set(() => method = m)),
            const SizedBox(height: 10),
            TextField(controller: ref, decoration: fieldDecoration("Reference (optional) · UTR / cheque no.", icon: Icons.tag_rounded)),
            const SizedBox(height: 16),
            primaryButton(
              "Pay ${inr(total)}",
              short
                  ? null
                  : () async {
                      final res = await LedgerService.payOwnOutstanding(s.companyId, {
                        "userId": s.userId,
                        "items": bills.map((b) => b["transactionId"] != null ? {"transactionId": b["transactionId"]} : {"expenseId": b["expenseId"]}).toList(),
                        "fundId": fund,
                        "method": method,
                        "reference": ref.text.trim(),
                      });
                      if (!ctx.mounted) return;
                      final closed = (res["bills"] as num?) ?? 0;
                      if (handleResult(ctx, res, "${inr(res["paid"] ?? total)} paid to you from company · $closed bill${closed == 1 ? "" : "s"} closed")) {
                        Navigator.pop(ctx);
                        _selected.clear();
                        notifyLedgerChanged();
                        widget.onPaid?.call();
                      }
                    },
            ),
          ]);
        }));
    ref.dispose();
  }
}
