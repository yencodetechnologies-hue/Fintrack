import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../services/ledger_service.dart';
import 'ledger_common.dart';
import 'ledger_fund_topup.dart';
import 'ledger_expenses_tab.dart' show showPostExpenseSheet;
import 'ledger_vouchers.dart';
import 'ledger_funds.dart';
import 'ledger_payments.dart';
import 'ledger_interco_tab.dart' show showLoanDetail;

/// Company Home, same content per role as the web's Home tab.
/// One Home figure: label, amount (null while loading), colour, a short line under it, and where a tap goes.
typedef _Stat = ({String label, String? value, Color color, String? sub, VoidCallback? onTap, Widget? trailing});

class LedgerDashboardTab extends StatefulWidget {
  final LedgerScope scope;
  final VoidCallback onOpenExpenses;
  /// Opens the Inter-co tab (null when that tab is hidden).
  final VoidCallback? onOpenInterco;
  /// Opens one expense's details; falls back to the Expenses tab when not given.
  final void Function(Map<String, dynamic> expense)? onOpenExpense;
  const LedgerDashboardTab({super.key, required this.scope, required this.onOpenExpenses, this.onOpenInterco, this.onOpenExpense});

  @override
  State<LedgerDashboardTab> createState() => _LedgerDashboardTabState();
}

class _LedgerDashboardTabState extends State<LedgerDashboardTab> with LedgerAutoRefresh {
  @override
  void onLedgerChanged() => _load();

  @override
  Set<String> get ledgerTopics => const {"expenses", "balances", "funds", "loans", "vouchers", "ledger"};

  LedgerScope get s => widget.scope;
  Map<String, dynamic>? _balances;
  String? _balancesError;
  List<Map<String, dynamic>> _expenses = [];
  List<Map<String, dynamic>> _loans = [];
  List<Map<String, dynamic>> _pending = [];
  bool _loading = true;
  bool _secondaryLoading = true;
  // Total expenses tile: all | week | month | custom (by each expense's date)
  String _totalPeriod = "month"; // default: this month
  DateTimeRange? _totalRange;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await Future.wait([
      LedgerService.balances(s.companyId, s.userId),
      LedgerService.expenses(s.companyId, s.userId),
    ]);
    if (!mounted) return;
    setState(() {
      if (r[0]["success"] == true) {
        _balances = r[0];
        _balancesError = null;
      } else if (_balances == null) {
        _balancesError = r[0]["message"]?.toString() ?? "Could not load balances";
      }
      if (r[1]["success"] == true) _expenses = List<Map<String, dynamic>>.from(r[1]["expenses"] ?? const []);
      _loading = false;
    });
    unawaited(_loadSecondary());
  }

  Future<void> _loadSecondary() async {
    final r = await Future.wait([
      LedgerService.loans(s.companyId, s.userId),
      if (s.isAdmin) LedgerService.transactions(s.companyId, s.userId),
    ]);
    if (!mounted) return;
    setState(() {
      _loans = List<Map<String, dynamic>>.from(r[0]["loans"] ?? const []);
      if (s.isAdmin) {
        _pending = List<Map<String, dynamic>>.from(r[1]["transactions"] ?? const [])
            .where((t) => t["verification"] == "pending" && t["reversedBy"] == null)
            .toList();
      }
      _secondaryLoading = false;
    });
  }

  // Open loans per counterpart company: what we still owe (borrowed) or are owed (lent).
  List<({String name, num balance})> _loanTotals({required bool borrowed}) {
    final byName = <String, num>{};
    for (final l in _loans) {
      final weBorrowed = idOf(l["borrowerCompanyId"]) == s.companyId;
      if (weBorrowed != borrowed) continue;
      final balance = (l["balance"] as num?) ?? 0;
      if (!(balance > 0)) continue;
      final name = nameOf(borrowed ? l["lenderCompanyId"] : l["borrowerCompanyId"], "Another company");
      byName[name] = (byName[name] ?? 0) + balance;
    }
    return byName.entries.map((e) => (name: e.key, balance: e.value)).toList();
  }

  // Today = the expense's own date is today (not when it was posted), same as the Expenses tab
  bool _isToday(Map<String, dynamic> e) {
    final d = DateTime.tryParse((e["date"] ?? e["createdAt"])?.toString() ?? "")?.toLocal();
    final now = DateTime.now();
    return d != null && d.year == now.year && d.month == now.month && d.day == now.day;
  }

  /// Expenses in the Total expenses tile's period (this week starts Monday).
  List<Map<String, dynamic>> get _periodExpenses {
    if (_totalPeriod == "all") return _expenses;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    late DateTime start, end;
    if (_totalPeriod == "week") {
      start = today.subtract(Duration(days: now.weekday - 1));
      end = start.add(const Duration(days: 7));
    } else if (_totalPeriod == "month") {
      start = DateTime(now.year, now.month, 1);
      end = DateTime(now.year, now.month + 1, 1);
    } else {
      final r = _totalRange;
      if (r == null) return _expenses;
      start = DateTime(r.start.year, r.start.month, r.start.day);
      end = DateTime(r.end.year, r.end.month, r.end.day + 1);
    }
    return _expenses.where((e) {
      final d = DateTime.tryParse((e["date"] ?? e["createdAt"])?.toString() ?? "")?.toLocal();
      return d != null && !d.isBefore(start) && d.isBefore(end);
    }).toList();
  }

  String get _periodLabel => switch (_totalPeriod) {
        "week" => "This week",
        "month" => "This month",
        "custom" when _totalRange != null =>
          "${DateFormat("dd MMM").format(_totalRange!.start)} – ${DateFormat("dd MMM").format(_totalRange!.end)}",
        _ => "All time",
      };

  Future<void> _choosePeriod(String period) async {
    if (period != "custom") return setState(() => _totalPeriod = period);
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: _totalRange ?? DateTimeRange(start: DateTime(now.year, now.month, 1), end: now),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _totalPeriod = "custom";
      _totalRange = picked;
    });
  }

  // small "All time ▾" pill inside the Total expenses tile
  Widget _periodPill() => PopupMenuButton<String>(
        tooltip: "Period",
        position: PopupMenuPosition.under,
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onSelected: _choosePeriod,
        itemBuilder: (_) => const {"all": "All time", "week": "This week", "month": "This month", "custom": "Custom dates…"}
            .entries
            .map((o) => PopupMenuItem(
                  value: o.key,
                  height: 38,
                  child: Row(children: [
                    Expanded(
                      child: Text(o.value,
                          style: GoogleFonts.inter(
                              fontSize: 14, fontWeight: o.key == _totalPeriod ? FontWeight.w700 : FontWeight.w500, color: o.key == _totalPeriod ? kForest : kForest)),
                    ),
                    if (o.key == _totalPeriod) const Icon(Icons.check_rounded, size: 18, color: kForest),
                  ]),
                ))
            .toList(),
        child: Container(
          padding: const EdgeInsets.only(left: 8, right: 3, top: 2, bottom: 2),
          decoration: BoxDecoration(
            color: _totalPeriod == "month" ? kForest.withValues(alpha: 0.08) : kForest.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(_periodLabel, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: _totalPeriod == "month" ? kForest.withValues(alpha: 0.7) : kForest)),
            Icon(Icons.expand_more_rounded, size: 15, color: _totalPeriod == "month" ? kForest.withValues(alpha: 0.6) : kForest),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final periodExpenses = _periodExpenses;
    final totalSpent = periodExpenses.fold<num>(0, (sum, e) => sum + ((e["amount"] as num?) ?? 0));
    final myOwed = (_balances?["myOwed"] as num?) ?? 0;
    final myAdvance = (_balances?["myAdvance"] as num?) ?? 0;
    final borrowed = _loanTotals(borrowed: true);
    final lent = _loanTotals(borrowed: false);
    final borrowedTotal = borrowed.fold<num>(0, (sum, r) => sum + r.balance);
    final lentTotal = lent.fold<num>(0, (sum, r) => sum + r.balance);
    final cash = s.cashBalance;
    final bank = s.bankAccounts.fold<num>(0, (sum, b) => sum + ((b["balance"] as num?) ?? 0));
    final balancesReady = _balances != null;
    final today = _expenses.where(_isToday).toList();

    // one figure: the hero card at the top, or a cell in the small grid under it (null value = still loading)
    _Stat stat(String label, String? value, {Color color = kForest, String? sub, VoidCallback? onTap, Widget? trailing}) =>
        (label: label, value: value, color: color, sub: sub, onTap: onTap, trailing: trailing);

    final hero = s.isAdmin
        ? stat(s.companyName.trim().toLowerCase().endsWith("s") ? "${s.companyName}' balance" : "${s.companyName}'s balance", inr(cash + bank),
            sub: "${s.cashName} ${inr(cash)} · Bank ${inr(bank)}",
            onTap: s.can("funds") ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => FundsPage(scope: s))) : null)
        : stat("Company owes you", balancesReady ? inr(myOwed) : null, color: kForest, sub: "Paid by you, not yet reimbursed");

    final grid = <_Stat>[
      stat("Expenses", _loading ? null : inr(totalSpent),
          sub: "${periodExpenses.length} expense${periodExpenses.length == 1 ? "" : "s"}", onTap: widget.onOpenExpenses, trailing: _periodPill()),
      if (s.isAdmin) ...[
        // everything the company owes people; what it owes me in the line under it
        stat("Company outstanding", balancesReady ? inr(_balances?["totalOwedToAdmins"] ?? 0) : null, color: kForest,
            sub: "Owed to you ${inr(myOwed)}",
            onTap: s.can("reimburse") ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => PaymentsPage(scope: s))) : null),
        stat("Borrowed", _secondaryLoading ? null : inr(borrowedTotal), color: kForest,
            sub: borrowed.isEmpty ? "Nothing to repay" : null, onTap: widget.onOpenInterco),
        stat("Lent", _secondaryLoading ? null : inr(lentTotal),
            sub: lent.isEmpty ? "Nothing to collect" : null, onTap: widget.onOpenInterco),
      ] else
        stat("Voucher balance", balancesReady ? inr(myAdvance > 0 ? myAdvance : 0) : null,
            sub: myAdvance > 0 ? "Tap to hand back" : "None with you",
            onTap: myAdvance > 0 && s.can("vouchers") ? () => showHandBackSheet(context, s, myAdvance, onDone: _load) : null),
    ];

    final actions = [
      if (s.isAdmin && s.can("reimburse")) (icon: Icons.savings_rounded, label: "Lend", onTap: _openLend),
      if (s.isAdmin && s.can("reimburse")) (icon: Icons.payments_rounded, label: "Reimburse", onTap: _openReimburse),
      if (s.isAdmin && s.can("vouchers")) (icon: Icons.confirmation_number_rounded, label: "Voucher", onTap: () => showCreateVoucherSheet(context, s, onDone: _load)),
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      // same "Post Expense" button as the Expenses tab, a little smaller
      floatingActionButton: !s.can("post_expenses") ? null : FloatingActionButton.extended(
        // every tab stays alive in the same route, so each button needs its own hero tag
        heroTag: "post-expense-home",
        backgroundColor: Colors.white,
        extendedPadding: const EdgeInsets.symmetric(horizontal: 16),
        onPressed: () => showPostExpenseSheet(context, s, existing: _expenses, advance: myAdvance, onDone: _load),
        icon: const Icon(Icons.add_rounded, color: kForest, size: 20),
        label: Text("Expense", style: GoogleFonts.inter(color: kForest, fontWeight: FontWeight.w700, fontSize: 14)),
      ),
      body: RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        // extra room at the bottom so the button never covers the last row
        padding: const EdgeInsets.fromLTRB(14, 2, 14, 90),
        children: [
          if (_balancesError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                Expanded(child: Text(_balancesError!, style: GoogleFonts.inter(color: Colors.white, fontSize: 12))),
                TextButton(onPressed: _load, child: Text("Retry", style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold))),
              ]),
            ),
          _heroCard(hero),
          const SizedBox(height: 8),
          _statGrid(grid),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(children: [
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: _action(actions[i].icon, actions[i].label, actions[i].onTap)),
              ],
            ]),
          ],
          StaffVoucherSection(scope: s),
          // Home lists only expenses dated today; the rest live on the Expenses tab
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 16, 0, 6),
            child: Row(children: [
              Text("Today", style: GoogleFonts.inter(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
              Text("  ·  ${DateFormat("dd MMM").format(DateTime.now())}", style: GoogleFonts.inter(color: Colors.white60, fontSize: 12)),
              const Spacer(),
              // today's total: what's listed below, rejected ones left out
              Text(inr(today.where((e) => e["lifecycle"] != "rejected").fold<num>(0, (sum, e) => sum + ((e["amount"] as num?) ?? 0))),
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: widget.onOpenExpenses,
                child: Text("See all", style: GoogleFonts.inter(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
          if (today.isEmpty)
            _loading ? _todayShimmer() : _compactEmpty("No expenses today.")
          else
            _listCard([for (final e in today) _todayRow(e)]),
          // loans recorded today (borrowed or lent); only shown when there are some
          ..._todayLoans(),
          // only shown when something is waiting for a second manager
          if (s.isAdmin && s.can("verify") && _pending.isNotEmpty) ...[
            _sectionTitle("Pending verification"),
            ..._pending.map(_pendingCard),
          ],
        ],
      ),
      ),
    );
  }

  List<Widget> _todayLoans() {
    final now = DateTime.now();
    final loans = _loans.where((l) {
      final d = DateTime.tryParse(l["createdAt"]?.toString() ?? "")?.toLocal();
      return d != null && d.year == now.year && d.month == now.month && d.day == now.day;
    }).toList();
    if (loans.isEmpty) return const [];
    return [
      _sectionTitle("Loans today"),
      _listCard([
        for (final l in loans)
          Builder(builder: (context) {
            final weBorrowed = idOf(l["borrowerCompanyId"]) == s.companyId;
            final other = nameOf(weBorrowed ? l["lenderCompanyId"] : l["borrowerCompanyId"], "Another company");
            final source = l["source"] == "expense" ? "Paid an expense" : l["source"] == "group" ? "Paid a group's expenses" : "Direct loan";
            final due = (l["balance"] as num?) ?? 0;
            return InkWell(
              onTap: () => showLoanDetail(context, s, l),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text("${weBorrowed ? "Borrowed from" : "Lent to"} $other", style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: kDark)),
                      Text([(l["note"]?.toString() ?? "").isNotEmpty ? l["note"].toString() : source, l["method"]?.toString() ?? ""].where((x) => x.isNotEmpty).join(" · "),
                          style: GoogleFonts.inter(fontSize: 12, color: kDark.withValues(alpha: 0.55))),
                    ]),
                  ),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(inr(l["amount"]), style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w800, color: weBorrowed ? kTerracotta : kForest)),
                    Text(due > 0 ? "${inr(due)} due" : "Repaid", style: GoogleFonts.inter(fontSize: 11, color: kDark.withValues(alpha: 0.55))),
                  ]),
                ]),
              ),
            );
          }),
      ]),
    ];
  }

  /// Rows inside one white card, split by thin lines.
  Widget _listCard(List<Widget> rows) => Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, indent: 12, endIndent: 12, color: kForest.withValues(alpha: 0.06)),
            rows[i],
          ],
        ]),
      );

  Widget _todayRow(Map<String, dynamic> e) {
    return InkWell(
      onTap: () => widget.onOpenExpense != null ? widget.onOpenExpense!(e) : widget.onOpenExpenses(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(color: kForest, shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e["description"]?.toString() ?? "Expense",
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13, color: kForest)),
              const SizedBox(height: 1),
              Text("${postedByName(e, s.companyName)} · ${expenseStatusLabel(e, s.companyName)}",
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 11, color: kForest.withValues(alpha: 0.55))),
            ]),
          ),
          const SizedBox(width: 10),
          Text(inr(e["amount"]), style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13, color: kForest)),
        ]),
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 16, 2, 6),
        child: Text(text, style: GoogleFonts.inter(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
      );

  Widget _compactEmpty(String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
        child: Text(text, style: GoogleFonts.inter(color: Colors.white70, fontSize: 13)),
      );

  Widget _todayShimmer() => Column(
        children: [
          for (var i = 0; i < 2; i++)
            Container(
              margin: const EdgeInsets.only(bottom: 5),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(10)),
              child: const Row(children: [
                Expanded(child: _ShimmerBox(height: 11, dark: true)),
                SizedBox(width: 18),
                _ShimmerBox(width: 56, height: 11, dark: true),
              ]),
            ),
        ],
      );

  static TextStyle get _statLabel =>
      GoogleFonts.inter(color: kForest.withValues(alpha: 0.5), fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5);

  /// The one big figure at the top (company balance for managers, what the company owes staff).
  Widget _heroCard(_Stat h) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: h.onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(h.label.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: _statLabel),
                  const SizedBox(height: 3),
                  if (h.value == null)
                    const _ShimmerBox(width: 110, height: 22)
                  else
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(h.value!, style: GoogleFonts.inter(color: h.color, fontSize: 20, fontWeight: FontWeight.w800)),
                    ),
                  if (h.sub != null)
                    Text(h.sub!, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(color: kForest.withValues(alpha: 0.55), fontSize: 11)),
                ]),
              ),
              if (h.onTap != null) Icon(Icons.chevron_right_rounded, color: kForest.withValues(alpha: 0.3)),
            ]),
          ),
        ),
      );

  /// The other figures in one white card, two per row with thin dividers.
  Widget _statGrid(List<_Stat> stats) {
    final divider = Container(width: 1, color: kForest.withValues(alpha: 0.06));
    final rows = <Widget>[];
    for (var i = 0; i < stats.length; i += 2) {
      if (i > 0) rows.add(Divider(height: 1, thickness: 1, color: kForest.withValues(alpha: 0.06)));
      rows.add(IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: _statCell(stats[i])),
          divider,
          Expanded(child: i + 1 < stats.length ? _statCell(stats[i + 1]) : const SizedBox.shrink()),
        ]),
      ));
    }
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: Column(children: rows),
    );
  }

  Widget _statCell(_Stat c) => InkWell(
        onTap: c.onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              height: 18,
              child: Row(children: [
                Expanded(child: Text(c.label.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: _statLabel)),
                if (c.trailing != null) c.trailing!,
              ]),
            ),
            const SizedBox(height: 2),
            if (c.value == null)
              const _ShimmerBox(width: 70, height: 15)
            else
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(c.value!, style: GoogleFonts.inter(color: c.color, fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            if (c.sub != null)
              Text(c.sub!, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(color: kForest.withValues(alpha: 0.5), fontSize: 11)),
          ]),
        ),
      );

  /// Small quick action: icon over a short label.
  Widget _action(IconData icon, String label, VoidCallback onTap) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, color: kForest, size: 18),
              const SizedBox(height: 3),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(color: kForest, fontWeight: FontWeight.w600, fontSize: 12)),
            ]),
          ),
        ),
      );

  Widget _pendingCard(Map<String, dynamic> t) {
    final amount = (t["entries"] as List? ?? const []).fold<num>(0, (sum, e) => sum + ((e["debit"] as num?) ?? 0));
    final mine = idOf(t["createdBy"]) == s.userId;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: kForest.withValues(alpha: 0.06))),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(t["memo"]?.toString() ?? "Transaction",
                maxLines: 2, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13, color: kForest)),
            const SizedBox(height: 2),
            Text("${nameOf(t["createdBy"], "Manager")} · ${dateLabel(t["createdAt"])}",
                style: GoogleFonts.inter(fontSize: 11, color: kForest.withValues(alpha: 0.6))),
          ]),
        ),
        Text(inr(amount), style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13, color: kForest)),
        const SizedBox(width: 6),
        if (!mine)
          TextButton(
            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(0, 32), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            onPressed: () async {
              final res = await LedgerService.verify(t["_id"].toString(), s.userId);
              if (!mounted) return;
              if (handleResult(context, res, "Transaction verified")) notifyLedgerChanged();
            },
            child: Text("Verify", style: GoogleFonts.inter(color: kForest, fontWeight: FontWeight.bold, fontSize: 12)),
          )
        else
          statusPill("Another manager verifies", kAmber),
      ]),
    );
  }

  void _openLend() {
    final amount = TextEditingController();
    final ref = TextEditingController();
    String fund = "cash";
    String method = "UPI";
    showLedgerSheet(
        context,
        "Lend to company",
        (ctx) => StatefulBuilder(
              builder: (ctx, set) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text("You put your own money into ${s.companyName}. The company owes you this amount until it pays you back.",
                    style: GoogleFonts.inter(fontSize: 13, color: kDark.withValues(alpha: 0.6))),
                const SizedBox(height: 12),
                TextField(
                    controller: amount,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: fieldDecoration("Amount ₹", icon: Icons.currency_rupee_rounded)),
                const SizedBox(height: 10),
                fundDropdown(s, fund, (v) => set(() => fund = v ?? "cash"), hint: "Paid into"),
                const SizedBox(height: 10),
                methodChips(method, (m) => set(() => method = m)),
                const SizedBox(height: 10),
                TextField(controller: ref, decoration: fieldDecoration("Reference (optional)", icon: Icons.tag_rounded)),
                const SizedBox(height: 16),
                primaryButton("Record transaction", () async {
                  final value = double.tryParse(amount.text.trim()) ?? 0;
                  if (!(value > 0)) return toast(ctx, "Enter a valid amount", error: true);
                  final res = await LedgerService.lend({
                    "companyId": s.companyId,
                    "userId": s.userId,
                    "amount": value,
                    "fundId": fund,
                    "method": method,
                    "reference": ref.text.trim(),
                  });
                  if (!ctx.mounted) return;
                  if (handleResult(ctx, res, "Money lent to company")) {
                    Navigator.pop(ctx);
                    notifyLedgerChanged();
                  }
                }),
              ]),
            ));
  }

  void _openReimburse() {
    final payees = List<Map<String, dynamic>>.from(_balances?["admins"] ?? const [])
        .where((a) => idOf(a["userId"]) != s.userId && ((a["owed"] as num?) ?? 0) > 0)
        .toList();
    final amount = TextEditingController();
    final ref = TextEditingController();
    String? payeeId;
    String fund = "cash";
    String method = "UPI";
    bool offset = false;
    bool billsLoading = false;
    num owed = 0;
    List<Map<String, dynamic>> bills = [];

    showLedgerSheet(
        context,
        "Reimburse person",
        (ctx) => StatefulBuilder(builder: (ctx, set) {
              final payee = payees.where((p) => idOf(p["userId"]) == payeeId).firstOrNull;
              final held = ((payee?["advance"] as num?) ?? 0) > 0 ? (payee!["advance"] as num) : 0;
              final cashPaid = double.tryParse(amount.text.trim()) ?? 0;
              final offsetAmount = offset ? _min(held, _max(0, owed - cashPaid)) : 0;
              num full() => _max(0, owed - (offset ? held : 0));

              Future<void> selectPayee(String? id) async {
                set(() {
                  payeeId = id;
                  amount.text = "";
                  offset = false;
                  bills = [];
                  owed = 0;
                  billsLoading = id != null;
                });
                if (id == null) return;
                final res = await LedgerService.payableBills(s.companyId, id, s.userId);
                if (!ctx.mounted) return;
                set(() {
                  billsLoading = false;
                  bills = List<Map<String, dynamic>>.from(res["bills"] ?? const []);
                  owed = (res["owed"] as num?) ?? 0;
                });
                if (res["success"] != true) toast(ctx, res["message"]?.toString() ?? "Could not load open bills", error: true);
              }

              if (payees.isEmpty) {
                return Text("Nobody is owed money right now.", style: GoogleFonts.inter(color: kDark.withValues(alpha: 0.7)));
              }
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                DropdownButtonFormField<String>(
                  initialValue: payeeId,
                  isExpanded: true,
                  decoration: fieldDecoration("Pay to", icon: Icons.person_rounded),
                  items: payees
                      .map((a) => DropdownMenuItem(value: idOf(a["userId"]), child: Text("${a["name"]} · owed ${inr(a["owed"])}", overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: selectPayee,
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Text("Amount ₹", style: labelStyle),
                  const Spacer(),
                  if (payeeId != null && owed > 0)
                    TextButton(
                      onPressed: () => set(() => amount.text = _round(full()).toString()),
                      child: Text("Pay full balance · ${inr(full())}", style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                ]),
                TextField(
                  controller: amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => set(() {}),
                  decoration: fieldDecoration("Amount paid now", icon: Icons.currency_rupee_rounded),
                ),
                if (payeeId != null && held > 0)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: offset,
                    onChanged: (v) => set(() {
                      offset = v == true;
                      amount.text = _round(full()).toString();
                    }),
                    title: Text("Set off the voucher balance they hold (${inr(held)})", style: GoogleFonts.inter(fontSize: 13, color: kDark)),
                    subtitle: offsetAmount > 0
                        ? Text("${inr(offsetAmount)} taken from their balance · ${inr(cashPaid)} paid now", style: GoogleFonts.inter(fontSize: 12))
                        : null,
                  ),
                if (payeeId != null) BillsPreview(bills: bills, loading: billsLoading, amount: cashPaid + offsetAmount),
                const SizedBox(height: 10),
                fundDropdown(s, fund, (v) => set(() => fund = v ?? "cash"), hint: "Paid from"),
                const SizedBox(height: 10),
                methodChips(method, (m) => set(() => method = m)),
                const SizedBox(height: 10),
                TextField(controller: ref, decoration: fieldDecoration("Reference (optional)", icon: Icons.tag_rounded)),
                const SizedBox(height: 16),
                primaryButton("Record transaction", () async {
                  if (payeeId == null) return toast(ctx, "Choose who to reimburse", error: true);
                  if (!(cashPaid > 0) && !(offsetAmount > 0)) return toast(ctx, "Enter a valid amount", error: true);
                  final paidFrom = s.funds.firstWhere((f) => f.id == fund, orElse: () => s.funds.first);
                  if (paidFrom.balance < cashPaid && !await topUpFund(ctx, s, paidFrom, cashPaid)) return;
                  if (!ctx.mounted) return;
                  final res = await LedgerService.reimburse({
                    "companyId": s.companyId,
                    "userId": s.userId,
                    "adminUserId": payeeId,
                    "amount": cashPaid,
                    "fundId": fund,
                    "method": method,
                    "reference": ref.text.trim(),
                    "offsetAdvance": offset,
                  });
                  if (!ctx.mounted) return;
                  final name = payee?["name"] ?? "person";
                  final closed = (res["billsClosed"] as num?) ?? 0;
                  final setOff = (res["offset"] as num?) ?? 0;
                  final msg = [
                    cashPaid > 0 ? "Paid ${inr(cashPaid)} to $name" : "Settled $name",
                    if (setOff > 0) "${inr(setOff)} set off from voucher balance",
                    if (closed > 0) "$closed bill${closed == 1 ? "" : "s"} closed",
                  ].join(" · ");
                  if (handleResult(ctx, res, msg)) {
                    Navigator.pop(ctx);
                    notifyLedgerChanged();
                  }
                }),
              ]);
            }));
  }
}

num _round(num n) => (n * 100).round() / 100;
num _min(num a, num b) => a < b ? a : b;
num _max(num a, num b) => a > b ? a : b;

/// A person's open bills oldest first and which ones the amount will close (same FIFO rule as the server).
class BillsPreview extends StatelessWidget {
  final List<Map<String, dynamic>> bills;
  final bool loading;
  final num amount;
  const BillsPreview({super.key, required this.bills, required this.loading, required this.amount});

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text("Loading open bills…", style: GoogleFonts.inter(fontSize: 13, fontStyle: FontStyle.italic, color: kDark.withValues(alpha: 0.6))),
      );
    }
    if (bills.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text("No open bills.", style: GoogleFonts.inter(fontSize: 13, color: kDark.withValues(alpha: 0.6))),
      );
    }
    var left = amount;
    final rows = bills.map((b) {
      final remaining = (b["remaining"] as num?) ?? 0;
      final applied = _min(remaining, _max(0, left));
      left = _round(left - applied);
      final state = applied >= remaining ? "closed" : applied > 0 ? "partial" : "open";
      return (bill: b, remaining: remaining, applied: applied, state: state);
    }).toList();
    final closing = rows.where((r) => r.state == "closed").length;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text("Open bills (oldest first)", style: labelStyle)),
          if (amount > 0) Text("$closing of ${rows.length} will be closed", style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: kForest)),
        ]),
        if (rows.any((r) => r.bill["claim"] == true))
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text("Approved claims this payment reaches are recorded as paid by this person, then closed.",
                style: GoogleFonts.inter(fontSize: 12, color: kDark.withValues(alpha: 0.6))),
          ),
        const SizedBox(height: 6),
        Container(
          constraints: const BoxConstraints(maxHeight: 220),
          decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE2E8F0)), borderRadius: BorderRadius.circular(10)),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: rows.length,
            separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
            itemBuilder: (_, i) {
              final r = rows[i];
              final amountTotal = (r.bill["amount"] as num?) ?? r.remaining;
              final bg = r.state == "closed" ? const Color(0xFFECFDF5) : r.state == "partial" ? const Color(0xFFFFF7ED) : Colors.transparent;
              final stateColor = r.state == "closed" ? const Color(0xFF047857) : r.state == "partial" ? const Color(0xFFC2410C) : kDark.withValues(alpha: 0.55);
              return Container(
                color: bg,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(r.bill["description"]?.toString() ?? "Payable",
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: kDark)),
                      Text(
                        [
                          dateLabel(r.bill["date"]),
                          if (r.remaining < amountTotal) "${inr(amountTotal - r.remaining)} already paid",
                          if (r.bill["claim"] == true) "Approved claim (not yet marked paid)",
                        ].join(" · "),
                        style: GoogleFonts.inter(fontSize: 11, color: kDark.withValues(alpha: 0.6)),
                      ),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(inr(r.remaining), style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: kDark)),
                    Text(r.state == "closed" ? "✓ Will be closed" : r.state == "partial" ? "Partly paid ${inr(r.applied)}" : "Stays open",
                        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: stateColor)),
                  ]),
                ]),
              );
            },
          ),
        ),
      ]),
    );
  }
}

class _ShimmerBox extends StatefulWidget {
  final double width;
  final double height;
  final bool dark;


  const _ShimmerBox({
    this.width = double.infinity,
    required this.height,
    this.dark = false,

  });

  @override
  State<_ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<_ShimmerBox> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: widget.width,
        height: widget.height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment(-1.5 + 3 * _controller.value, 0),
                  end: Alignment(-0.5 + 3 * _controller.value, 0),
                  colors: widget.dark
                      ? [
                          Colors.white.withValues(alpha: 0.08),
                          Colors.white.withValues(alpha: 0.24),
                          Colors.white.withValues(alpha: 0.08),
                        ]
                      : const [
                          Color(0xFFE7ECEA),
                          Color(0xFFF7F9F8),
                          Color(0xFFE7ECEA),
                        ],
                ),
              ),
            ),
          ),
        ),
      );
}
