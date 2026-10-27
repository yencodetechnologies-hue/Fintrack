import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../services/ledger_service.dart';
import 'ledger_common.dart';

/// Accounts: every day's money in / out, its expenses, and the Cash + Bank balance at the end of the day.
/// Tap a day to see what happened that day. Same as the web's Accounts page.
class AccountsPage extends StatefulWidget {
  final LedgerScope scope;
  const AccountsPage({super.key, required this.scope});

  @override
  State<AccountsPage> createState() => _AccountsPageState();
}

const Map<String, String> _status = {
  "submitted": "Waiting for approval",
  "approved": "Approved · unpaid",
  "paid_by_company": "Paid by company",
  "paid_by_admin": "Paid by manager",
  "paid_by_person": "Paid by a person",
  "awaiting_confirmation": "Awaiting lender",
  "reimbursed": "Reimbursed",
};

class _AccountsPageState extends State<AccountsPage> with LedgerAutoRefresh {
  LedgerScope get s => widget.scope;
  final _fmt = DateFormat("yyyy-MM-dd");
  final _search = TextEditingController();
  // the Period dropdown (same as the web): yyyy-MM-dd range, "" = open-ended (All time); starts on this month
  late String _from = DateFormat("yyyy-MM-01").format(DateTime.now());
  late String _to = DateFormat("yyyy-MM-dd").format(DateTime.now());
  Map<String, dynamic>? _data;
  String? _error;
  final Set<String> _open = {};
  int _request = 0;

  @override
  Set<String> get ledgerTopics => const {"balances", "expenses"};

  @override
  void onLedgerChanged() => _load();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// The chosen period as (from, to); All time = from the very start up to today.
  (DateTime, DateTime) get _range {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return (DateTime.tryParse(_from) ?? DateTime(2000), DateTime.tryParse(_to) ?? today);
  }

  Future<void> _load() async {
    final (from, to) = _range;
    final id = ++_request;
    setState(() {
      _data = null;
      _error = null;
    });
    final res = await LedgerService.accountsDays(s.companyId, s.userId, _fmt.format(from), _fmt.format(to));
    if (!mounted || id != _request) return; // a newer period was picked meanwhile
    setState(() {
      if (res["success"] == true) {
        _data = res;
      } else {
        _error = res["message"]?.toString() ?? "Could not load accounts";
      }
    });
  }

  String _dayLabel(String day) {
    final d = DateTime.parse(day);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (d == today) return "Today · ${DateFormat("dd MMM").format(d)}";
    if (d == today.subtract(const Duration(days: 1))) return "Yesterday · ${DateFormat("dd MMM").format(d)}";
    return DateFormat("EEE · dd MMM yyyy").format(d);
  }

  /// Search narrows each day to matching items; days with no match are hidden.
  List<Map<String, dynamic>> get _days {
    final all = List<Map<String, dynamic>>.from(_data?["days"] ?? const []);
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return all;
    bool hit(List<dynamic> parts) => parts.map((p) => p?.toString() ?? "").join(" ").toLowerCase().contains(q);
    return all
        .map((d) => {
              ...d,
              "expenses": List.from(d["expenses"] ?? const []).where((x) => hit([x["description"], x["category"], x["by"], x["amount"]])).toList(),
              "income": List.from(d["income"] ?? const []).where((x) => hit([x["description"], x["to"], x["from"], x["by"], x["amount"]])).toList(),
              "movements": List.from(d["movements"] ?? const [])
                  .where((x) => hit([x["label"], x["memo"], x["note"], x["account"], x["by"], x["reference"], (x["amount"] as num?)?.abs()]))
                  .toList(),
            })
        .where((d) => (d["expenses"] as List).isNotEmpty || (d["income"] as List).isNotEmpty || (d["movements"] as List).isNotEmpty)
        .toList();
  }

  // ---- the small period pill: All time / Day / This week / Month / Year / Custom ----
  String _mode = "month";

  void _setRange(String mode, DateTime from, DateTime to) {
    setState(() {
      _mode = mode;
      _from = _fmt.format(from);
      _to = _fmt.format(to);
    });
    _load();
  }

  String get _periodLabel {
    final f = DateTime.tryParse(_from), t = DateTime.tryParse(_to);
    return switch (_mode) {
      "all" => "All time",
      "week" => "This week",
      "day" when f != null => DateFormat("dd MMM").format(f),
      "month" when f != null => DateFormat("MMM yyyy").format(f),
      "year" when f != null => "${f.year}",
      "custom" when f != null && t != null => "${DateFormat("dd MMM").format(f)} – ${DateFormat("dd MMM").format(t)}",
      _ => "Period",
    };
  }

  /// A short list sheet (months / years) that returns the picked value.
  Future<T?> _pickFromList<T>(String title, List<(T, String)> options) => showLedgerSheet<T>(
        context,
        title,
        (ctx) => Column(children: [
          for (final o in options)
            ListTile(dense: true, title: Text(o.$2, style: GoogleFonts.inter(fontSize: 14, color: kDark)), onTap: () => Navigator.pop(ctx, o.$1)),
        ]),
      );

  Future<void> _choosePeriod(String mode) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (mode) {
      case "all":
        setState(() {
          _mode = "all";
          _from = "";
          _to = "";
        });
        _load();
      case "week":
        _setRange("week", today.subtract(Duration(days: now.weekday - 1)), today);
      case "day":
        final d = await showDatePicker(context: context, initialDate: DateTime.tryParse(_from) ?? today, firstDate: DateTime(2020), lastDate: today);
        if (d != null) _setRange("day", d, d);
      case "month":
        final m = await _pickFromList<DateTime>("Month", [
          for (var i = 0; i < 24; i++) (DateTime(now.year, now.month - i, 1), DateFormat("MMMM yyyy").format(DateTime(now.year, now.month - i, 1))),
        ]);
        if (m != null) _setRange("month", m, DateTime(m.year, m.month + 1, 0));
      case "year":
        final y = await _pickFromList<int>("Year", [for (var i = 0; i < 6; i++) (now.year - i, "${now.year - i}")]);
        if (y != null) _setRange("year", DateTime(y), DateTime(y, 12, 31));
      case "custom":
        final r = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2020),
          lastDate: today,
          initialDateRange: DateTimeRange(start: DateTime.tryParse(_from) ?? DateTime(now.year, now.month), end: DateTime.tryParse(_to) ?? today),
        );
        if (r != null) _setRange("custom", r.start, r.end);
    }
  }

  Widget _periodPill() => PopupMenuButton<String>(
        tooltip: "Period",
        position: PopupMenuPosition.under,
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onSelected: _choosePeriod,
        itemBuilder: (_) => const {"all": "All time", "day": "Day…", "week": "This week", "month": "Month…", "year": "Year…", "custom": "Custom…"}
            .entries
            .map((o) => PopupMenuItem(
                  value: o.key,
                  height: 40,
                  child: Text(o.value,
                      style: GoogleFonts.inter(fontSize: 13.5, fontWeight: o.key == _mode ? FontWeight.w700 : FontWeight.w500, color: o.key == _mode ? kForest : kDark)),
                ))
            .toList(),
        child: Container(
          height: 40,
          padding: const EdgeInsets.only(left: 12, right: 8),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.calendar_today_rounded, size: 15, color: kForest),
            const SizedBox(width: 6),
            Text(_periodLabel, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: kForest)),
            const Icon(Icons.expand_more_rounded, size: 18, color: kForest),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final summary = _data?["summary"] as Map?;
    final days = _days;
    final searching = _search.text.trim().isNotEmpty;

    return Theme(
      data: sheetTheme,
      child: Scaffold(
        backgroundColor: kForest,
        appBar: AppBar(
          backgroundColor: kForest,
          foregroundColor: Colors.white,
          elevation: 0,
          title: Text("Accounts", style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
        ),
        body: RefreshIndicator(
          onRefresh: _load,
          child: ListView(padding: const EdgeInsets.fromLTRB(14, 4, 14, 30), children: [
            // one slim row: search + a small period pill
            Row(children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    style: GoogleFonts.inter(fontSize: 13.5, color: kDark),
                    decoration: InputDecoration(
                      hintText: "Search…",
                      hintStyle: GoogleFonts.inter(fontSize: 13.5, color: kDark.withValues(alpha: 0.4)),
                      prefixIcon: const Icon(Icons.search_rounded, size: 19, color: kForest),
                      prefixIconConstraints: const BoxConstraints(minWidth: 38),
                      isDense: true,
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _periodPill(),
            ]),
            const SizedBox(height: 10),
            if (_error != null)
              ledgerCard(child: Text(_error!, style: GoogleFonts.inter(color: kTerracotta)))
            else if (_data == null)
              const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: Colors.white)))
            else ...[
              _summaryCard(summary ?? const {}),
              const SizedBox(height: 10),
              if (days.isEmpty)
                ledgerCard(
                  child: Center(
                    child: Text(searching ? "Nothing matches your search in this period." : "No money in, money out or expenses in this period.",
                        textAlign: TextAlign.center, style: GoogleFonts.inter(color: kDark.withValues(alpha: 0.6))),
                  ),
                )
              else
                Container(
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                  clipBehavior: Clip.antiAlias,
                  child: Column(children: [
                    for (var i = 0; i < days.length; i++) ...[
                      if (i > 0) Divider(height: 1, color: kDark.withValues(alpha: 0.06)),
                      _dayTile(days[i], searching),
                    ],
                  ]),
                ),
              const SizedBox(height: 10),
              Text("Balances are Cash + all bank accounts. Expenses are listed on their own date; only those paid from Cash/Bank change the balance.",
                  style: GoogleFonts.inter(color: Colors.white60, fontSize: 11.5)),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _summaryCard(Map summary) {
    Widget cell(String label, String value, {Color color = kForest}) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label.toUpperCase(), style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: kDark.withValues(alpha: 0.5))),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w800, color: color)),
              ),
            ]),
          ),
        );
    final line = Divider(height: 1, color: kDark.withValues(alpha: 0.06));
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(children: [
        Row(children: [cell("Opening balance", inr(summary["opening"] ?? 0)), cell("Closing balance", inr(summary["closing"] ?? 0))]),
        line,
        Row(children: [
          cell("Money in", "+${inr(summary["moneyIn"] ?? 0)}"),
          cell("Money out", "−${inr(summary["moneyOut"] ?? 0)}", color: kTerracotta),
        ]),
        line,
        Row(children: [cell("Expenses · ${summary["expenseCount"] ?? 0}", inr(summary["expensesTotal"] ?? 0))]),
      ]),
    );
  }

  Widget _dayTile(Map<String, dynamic> d, bool searching) {
    final date = d["date"].toString();
    final open = searching || _open.contains(date);
    final moneyIn = (d["moneyIn"] as num?) ?? 0;
    final moneyOut = (d["moneyOut"] as num?) ?? 0;
    final count = (d["expenseCount"] as num?) ?? 0;
    final parts = [
      if (moneyIn > 0) "+${inr(moneyIn)} in",
      if (moneyOut > 0) "−${inr(moneyOut)} out",
      if (count > 0) "$count expense${count == 1 ? "" : "s"} · ${inr(d["expensesTotal"])}",
      if (moneyIn == 0 && moneyOut == 0 && count == 0) "Transfers only",
    ];
    return Column(children: [
      InkWell(
        onTap: () => setState(() => _open.contains(date) ? _open.remove(date) : _open.add(date)),
        child: Container(
          color: open ? const Color(0xFFF8FAFC) : null,
          padding: const EdgeInsets.fromLTRB(14, 11, 8, 11),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_dayLabel(date), style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13.5, color: kDark)),
                const SizedBox(height: 2),
                Text(parts.join("  ·  "), style: GoogleFonts.inter(fontSize: 11, color: kDark.withValues(alpha: 0.55))),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text("CLOSING", style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w700, color: kDark.withValues(alpha: 0.45))),
              Text(inr(d["closing"] ?? 0), style: GoogleFonts.inter(fontSize: 14.5, fontWeight: FontWeight.w800, color: kForest)),
            ]),
            Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: kDark.withValues(alpha: 0.4)),
          ]),
        ),
      ),
      if (open) _dayBody(d),
    ]);
  }

  Widget _dayBody(Map<String, dynamic> d) {
    final income = List<Map<String, dynamic>>.from(d["income"] ?? const []);
    final moves = List<Map<String, dynamic>>.from(d["movements"] ?? const []);
    final expenses = List<Map<String, dynamic>>.from(d["expenses"] ?? const []);

    Widget balanceLine(String label, dynamic value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Text(label, style: GoogleFonts.inter(fontSize: 12.5, color: kDark.withValues(alpha: 0.6))),
            const Spacer(),
            Text(inr(value ?? 0), style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: kDark)),
          ]),
        );
    Widget item(String title, String sub, String amount, Color color) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: kDark)),
                Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 10.5, color: kDark.withValues(alpha: 0.55))),
              ]),
            ),
            const SizedBox(width: 8),
            Text(amount, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
          ]),
        );
    Widget section(String title, List<Widget> rows) => Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: kDark.withValues(alpha: 0.06))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title.toUpperCase(), style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: kDark.withValues(alpha: 0.5))),
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) Divider(height: 1, color: kDark.withValues(alpha: 0.06)),
              rows[i],
            ],
          ]),
        );

    return Container(
      color: const Color(0xFFF8FAFC),
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        balanceLine("Opening balance", d["opening"]),
        if (income.isNotEmpty)
          section("Income & transfers", [
            for (final i in income)
              item(
                (i["description"]?.toString().isNotEmpty ?? false) ? i["description"].toString() : (i["kind"] == "transfer" ? "Transfer to ${i["to"]}" : "Added to ${i["to"]}"),
                "${i["to"]} ← ${i["from"]}${(i["by"]?.toString().isNotEmpty ?? false) ? " · by ${i["by"]}" : ""}${i["kind"] == "transfer" ? " · between your accounts" : ""}",
                i["kind"] == "transfer" ? inr(i["amount"]) : "+${inr(i["amount"])}",
                i["kind"] == "transfer" ? kDark : kForest,
              ),
          ]),
        if (moves.isNotEmpty)
          section("Money moved", [
            for (final m in moves)
              Builder(builder: (_) {
                final amt = (m["amount"] as num?) ?? 0;
                final title = [m["note"], m["memo"], m["label"]].map((x) => x?.toString() ?? "").firstWhere((x) => x.isNotEmpty, orElse: () => "Movement");
                final sub = [
                  m["label"],
                  m["account"],
                  if ((m["method"]?.toString() ?? "").isNotEmpty) m["method"],
                  if ((m["reference"]?.toString() ?? "").isNotEmpty) "Ref ${m["reference"]}",
                  if ((m["by"]?.toString() ?? "").isNotEmpty) "by ${m["by"]}",
                ].join(" · ");
                return item(title, sub, "${amt > 0 ? "+" : "−"}${inr(amt.abs())}", amt > 0 ? kForest : kTerracotta);
              }),
          ]),
        if (expenses.isNotEmpty)
          section("Expenses · ${inr(expenses.fold<num>(0, (a, x) => a + ((x["amount"] as num?) ?? 0)))}", [
            for (final x in expenses)
              item(x["description"]?.toString() ?? "Expense", "${x["category"]} · ${x["by"]} · ${_status[x["lifecycle"]] ?? x["lifecycle"]}", inr(x["amount"]), kDark),
          ]),
        const SizedBox(height: 4),
        balanceLine("Closing balance", d["closing"]),
      ]),
    );
  }
}
