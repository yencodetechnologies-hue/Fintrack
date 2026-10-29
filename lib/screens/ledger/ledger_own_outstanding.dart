import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../services/ledger_service.dart';
import 'ledger_common.dart';
import 'ledger_description_field.dart';
import 'ledger_fund_topup.dart';
import 'ledger_payments.dart' show PaymentsPage;

num _round(num n) => (n * 100).round() / 100;
String _keyOf(Map<String, dynamic> b) => b["transactionId"] != null ? "tx:${b["transactionId"]}" : "exp:${b["expenseId"]}";

/// Payments screen, managers (web's "Your outstanding"): what the company owes ME, bill by bill. Pay all or just
/// the ticked bills — always from company Cash/Bank, never "by self"; exactly those bills close.
class OwnOutstandingCard extends StatefulWidget {
  final LedgerScope scope;
  final VoidCallback? onPaid;
  /// Show a short "nothing owed" card instead of nothing (the Payments tab, where this card is all there is).
  final bool showEmpty;
  const OwnOutstandingCard({super.key, required this.scope, this.onPaid, this.showEmpty = false});

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
  // typed amount: goes to the oldest bills first; typing and ticking are two ways to choose (one clears the other)
  final _amount = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

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
    if (bills == null) {
      return SliverToBoxAdapter(
        child: widget.showEmpty ? const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: Colors.white))) : const SizedBox.shrink(),
      );
    }
    final total = _sum(bills);
    if (!(total > 0)) {
      if (!widget.showEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
      return SliverToBoxAdapter(
        child: ledgerCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
          child: Column(children: [
            const Icon(Icons.check_circle_rounded, color: kForest, size: 34),
            const SizedBox(height: 8),
            Text("Nothing outstanding", style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: kDark)),
            const SizedBox(height: 4),
            Text("${s.companyName} has paid back all your approved expenses.",
                textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 13, color: kDark.withValues(alpha: 0.6))),
            // next step after paying myself: other people's bills (also in More → Pay people)
            if (paymentsInNav(s)) ...[
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PaymentsPage(scope: s))),
                icon: const Icon(Icons.groups_rounded, size: 18),
                label: const Text("Pay other people"),
              ),
            ],
          ]),
        ),
      );
    }
    final chosen = bills.where((b) => _selected.contains(_keyOf(b))).toList();
    final allOn = chosen.length == bills.length;

    // bills oldest first (by bill date) — the order a typed amount is applied in
    DateTime when(Map<String, dynamic> b) => DateTime.tryParse((b["date"] ?? b["postedAt"] ?? "").toString()) ?? DateTime(2000);
    final sorted = [...bills]..sort((a, b) => when(a).compareTo(when(b)));
    final typed = _round(num.tryParse(_amount.text.trim()) ?? 0);
    final byAmount = typed > 0;
    final tooMuch = typed > total + 0.001;
    final plan = <String, ({num take, String state})>{};
    var left = typed < total ? typed : total;
    for (final b in sorted) {
      final remaining = (b["remaining"] as num?) ?? 0;
      final take = _round(left <= 0 ? 0 : (left < remaining ? left : remaining));
      left = _round(left - take);
      plan[_keyOf(b)] = (take: take, state: take <= 0 ? "open" : (take < remaining ? "part" : "closed"));
    }
    final paidNow = byAmount ? (typed < total ? typed : total) : _sum(chosen);
    void tick(Map<String, dynamic> b) => setState(() {
          _amount.clear();
          _selected.contains(_keyOf(b)) ? _selected.remove(_keyOf(b)) : _selected.add(_keyOf(b));
        });

    final header = ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text("YOUR OUTSTANDING", style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: kDark.withValues(alpha: 0.55))),
          const SizedBox(height: 3),
          // what's chosen (typed amount or ticked bills) comes off the total: what would still be owed after
          Text(inr(_round(total - paidNow)), style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w800, color: kTerracotta)),
          Text(
            tooMuch
                ? "You're owed only ${inr(total)}"
                : byAmount
                    ? "${inr(typed)} to your oldest bills · left after paying"
                    : chosen.isEmpty
                        ? "${s.companyName} owes you this · paid from company Cash/Bank"
                        : "${inr(_sum(chosen))} selected · left after paying the selected bills",
            style: GoogleFonts.inter(fontSize: 12, color: tooMuch ? kTerracotta : kDark.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 12),
          // pay an amount: type it, the bills it covers show below, then Pay
          Container(
            height: 50,
            padding: const EdgeInsets.only(left: 12, right: 5),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: tooMuch ? kTerracotta : kForest, width: 1.5),
            ),
            child: Row(children: [
              Text("₹", style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, color: kForest)),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(_selected.clear),
                  style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: kDark),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: "Enter amount",
                    hintStyle: GoogleFonts.inter(fontSize: 14, color: kDark.withValues(alpha: 0.4)),
                  ),
                ),
              ),
              SizedBox(
                height: 38,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kForest,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: !byAmount || tooMuch ? null : () => _payAmount(typed),
                  child: Text("Pay", style: GoogleFonts.inter(fontWeight: FontWeight.w800)),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: _softButton(
                Icons.checklist_rounded,
                chosen.isEmpty ? "Pay selected" : "Pay selected (${chosen.length})",
                chosen.isEmpty ? null : () => _pay(chosen),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SizedBox(
                height: 46,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kForest,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () => _pay(bills),
                  icon: const Icon(Icons.account_balance_wallet_rounded, size: 18),
                  label: FittedBox(child: Text("Pay all · ${inr(total)}", style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w800))),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
        ]),
      ),
    );

    Widget planTag(String state, num take, num remaining) {
      final (bg, fg, text) = switch (state) {
        "closed" => (const Color(0xFFD1FAE5), const Color(0xFF047857), "Closes"),
        "part" => (const Color(0xFFFFEDD5), const Color(0xFFC2410C), "${inr(take)} of ${inr(remaining)}"),
        _ => (const Color(0xFFF1F5F9), kDark.withValues(alpha: 0.55), "Stays owed"),
      };
      return Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
        child: Text(text, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
      );
    }

    final list = Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(bottom: Radius.circular(16))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: byAmount ? false : allOn,
          onChanged: byAmount
              ? null
              : (_) => setState(() {
                    _amount.clear();
                    allOn ? _selected.clear() : _selected.addAll(bills.map(_keyOf));
                  }),
          title: Text(byAmount ? "Covered by the amount (oldest first)" : "Select all (${bills.length})",
              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: kDark)),
        ),
        for (final b in sorted) ...[
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          Builder(builder: (_) {
            final p = plan[_keyOf(b)]!;
            final showPlan = byAmount && !tooMuch;
            final on = byAmount ? showPlan && p.state != "open" : _selected.contains(_keyOf(b));
            return InkWell(
              onTap: byAmount ? null : () => tick(b),
              child: Container(
                color: showPlan && p.state == "part" ? const Color(0xFFFFF7ED) : (on ? const Color(0xFFF0FDF6) : null),
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  Checkbox(value: on, onChanged: byAmount ? null : (_) => tick(b)),
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
                        style: GoogleFonts.inter(fontSize: 12, color: kDark.withValues(alpha: 0.6)),
                      ),
                      if (showPlan) Padding(padding: const EdgeInsets.only(top: 4), child: planTag(p.state, p.take, (b["remaining"] as num?) ?? 0)),
                    ]),
                  ),
                  Text(inr(b["remaining"]), style: GoogleFonts.inter(fontWeight: FontWeight.w800, color: kDark)),
                ]),
              ),
            );
          }),
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
        label: FittedBox(child: Text(label, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700))),
      ),
    );
  }

  /// Pays the amount typed on the card (its bills are already shown there, oldest first): asks only where
  /// the money comes from, the method and a reference.
  Future<void> _payAmount(num amount) async {
    final ref = TextEditingController();
    final note = TextEditingController(); // description saved with the payment
    var fund = s.funds.first.id;
    // the method follows the account paid from (Cash -> "Cash", a bank -> "Bank") until it is picked by hand
    var method = fund == "cash" ? "Cash" : "Bank";
    var methodPicked = false;
    var date = DateTime.now();
    await showLedgerSheet(context, "Pay ${inr(amount)}", (ctx) => StatefulBuilder(builder: (ctx, set) {
          final selected = s.funds.firstWhere((f) => f.id == fund, orElse: () => s.funds.first);
          final short = selected.balance < amount;
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("From company funds to you, applied to your oldest bills first (shown on the card).",
                style: GoogleFonts.inter(fontSize: 13, color: kDark.withValues(alpha: 0.7))),
            const SizedBox(height: 12),
            fundDropdown(s, fund, (v) => set(() {
                  fund = v ?? "cash";
                  if (!methodPicked) method = fund == "cash" ? "Cash" : "Bank";
                }), hint: "Paid from"),
            if (short)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text("Only ${inr(selected.balance)} available in ${selected.name}. You can add money when you pay.",
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: kTerracotta)),
              ),
            const SizedBox(height: 10),
            methodChips(method, (m) => set(() {
                  method = m;
                  methodPicked = true;
                })),
            const SizedBox(height: 10),
            InkWell(
              onTap: () async {
                final picked = await showDatePicker(context: ctx, initialDate: date, firstDate: DateTime(2020), lastDate: DateTime.now());
                if (picked != null) set(() => date = picked);
              },
              child: InputDecorator(decoration: fieldDecoration("Payment date", icon: Icons.calendar_today_rounded), child: Text(DateFormat("dd MMM yyyy").format(date))),
            ),
            const SizedBox(height: 10),
            TextField(controller: ref, decoration: fieldDecoration("Reference (optional) · UTR / cheque no.", icon: Icons.tag_rounded)),
            const SizedBox(height: 10),
            DescriptionField(
              companyId: s.companyId,
              userId: s.userId,
              kind: "payment",
              controller: note,
              maxLength: 200,
              hint: "Description, e.g. Reimbursed for October site visits",
            ),
            const SizedBox(height: 16),
            primaryButton(
              "Pay ${inr(amount)}",
              () async {
                      if (short && !await topUpFund(ctx, s, selected, amount)) return;
                      if (!ctx.mounted) return;
                      final res = await LedgerService.payOwnOutstanding(s.companyId, {
                        "userId": s.userId,
                        "amount": amount,
                        "fundId": fund,
                        "method": method,
                        "reference": ref.text.trim(),
                        "note": note.text.trim(),
                        "date": DateFormat("yyyy-MM-dd").format(date),
                      });
                      if (!ctx.mounted) return;
                      final closed = (res["closed"] as num?) ?? 0;
                      final part = ((res["bills"] as num?) ?? 0) > closed;
                      if (handleResult(ctx, res, "${inr(res["paid"] ?? amount)} paid to you from company · $closed bill${closed == 1 ? "" : "s"} closed${part ? " · 1 part-paid" : ""}")) {
                        Navigator.pop(ctx);
                        _selected.clear();
                        _amount.clear();
                        notifyLedgerChanged();
                        widget.onPaid?.call();
                      }
                    },
            ),
          ]);
        }));
    ref.dispose();
    note.dispose();
  }

  Future<void> _pay(List<Map<String, dynamic>> bills) async {
    final total = _sum(bills);
    var fund = s.funds.first.id;
    var method = "Bank";
    var date = DateTime.now();
    final ref = TextEditingController();
    final note = TextEditingController(); // description saved with the payment
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
                child: Text("Only ${inr(selected.balance)} available in ${selected.name}. You can add money when you pay.",
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: kTerracotta)),
              ),
            const SizedBox(height: 10),
            methodChips(method, (m) => set(() => method = m)),
            const SizedBox(height: 10),
            InkWell(
              onTap: () async {
                final picked = await showDatePicker(context: ctx, initialDate: date, firstDate: DateTime(2020), lastDate: DateTime.now());
                if (picked != null) set(() => date = picked);
              },
              child: InputDecorator(decoration: fieldDecoration("Payment date", icon: Icons.calendar_today_rounded), child: Text(DateFormat("dd MMM yyyy").format(date))),
            ),
            const SizedBox(height: 10),
            TextField(controller: ref, decoration: fieldDecoration("Reference (optional) · UTR / cheque no.", icon: Icons.tag_rounded)),
            const SizedBox(height: 10),
            DescriptionField(
              companyId: s.companyId,
              userId: s.userId,
              kind: "payment",
              controller: note,
              maxLength: 200,
              hint: "Description, e.g. Reimbursed for October site visits",
            ),
            const SizedBox(height: 16),
            primaryButton(
              "Pay ${inr(total)}",
              () async {
                      if (short && !await topUpFund(ctx, s, selected, total)) return;
                      if (!ctx.mounted) return;
                      final res = await LedgerService.payOwnOutstanding(s.companyId, {
                        "userId": s.userId,
                        "items": bills.map((b) => b["transactionId"] != null ? {"transactionId": b["transactionId"]} : {"expenseId": b["expenseId"]}).toList(),
                        "fundId": fund,
                        "method": method,
                        "reference": ref.text.trim(),
                        "note": note.text.trim(),
                        "date": DateFormat("yyyy-MM-dd").format(date),
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
    note.dispose();
  }
}
