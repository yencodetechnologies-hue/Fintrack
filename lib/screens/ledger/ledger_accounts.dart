import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../services/ledger_service.dart';
import 'ledger_common.dart';
import 'ledger_expense_detail.dart' show showExpenseDetail;

/// Accounts: a statement of every money movement — each payment out of Cash/Bank, each income in, each transfer —
/// newest first, with the Cash + Bank balance after it. Searched and paged on the server. Same as the web.
class AccountsPage extends StatefulWidget {
  final LedgerScope scope;
  const AccountsPage({super.key, required this.scope});

  @override
  State<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends State<AccountsPage> with LedgerAutoRefresh {
  LedgerScope get s => widget.scope;
  final _fmt = DateFormat("yyyy-MM-dd");
  final _search = TextEditingController();
  Timer? _searchDebounce;
  String _query = "";
  int _page = 1;
  // the Period pill: yyyy-MM-dd range, "" = open-ended (All time); starts on this month
  late String _from = DateFormat("yyyy-MM-01").format(DateTime.now());
  late String _to = DateFormat("yyyy-MM-dd").format(DateTime.now());
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = false;
  int _request = 0;

  @override
  Set<String> get ledgerTopics => const {"balances", "expenses"};

  @override
  void onLedgerChanged() => _load();

  @override
  void initState() {
    super.initState();
    ListPaging.load().then((_) => _load());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
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
      _loading = true;
      _error = null;
    });
    final res = await LedgerService.accountsEntries(s.companyId, s.userId,
        from: _fmt.format(from), to: _fmt.format(to), q: _query, page: _page, limit: ListPaging.size);
    if (!mounted || id != _request) return; // a newer period / page / search was picked meanwhile
    setState(() {
      _loading = false;
      if (res["success"] == true) {
        _data = res;
        _page = (res["page"] as num?)?.toInt() ?? _page;
      } else {
        _error = res["message"]?.toString() ?? "Could not load accounts";
      }
    });
  }

  void _goTo(int page) {
    setState(() => _page = page);
    _load();
  }

  void _onSearch(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      _query = _search.text.trim();
      _page = 1;
      _load();
    });
  }

  // ---- the small period pill: All time / Day / This week / Month / Year / Custom ----
  String _mode = "month";

  void _setRange(String mode, DateTime from, DateTime to) {
    setState(() {
      _mode = mode;
      _page = 1;
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
          _page = 1;
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
                      style: GoogleFonts.inter(fontSize: 14, fontWeight: o.key == _mode ? FontWeight.w700 : FontWeight.w500, color: o.key == _mode ? kForest : kDark)),
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
    final entries = List<Map<String, dynamic>>.from(_data?["entries"] ?? const []);
    final total = (_data?["total"] as num?)?.toInt() ?? 0;
    final pages = (_data?["pages"] as num?)?.toInt() ?? 1;

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
                    onChanged: _onSearch,
                    style: GoogleFonts.inter(fontSize: 14, color: kDark),
                    decoration: InputDecoration(
                      hintText: "Search…",
                      hintStyle: GoogleFonts.inter(fontSize: 14, color: kDark.withValues(alpha: 0.4)),
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
              if (total == 0)
                ledgerCard(
                  child: Center(
                    child: Text(_query.isNotEmpty ? "Nothing matches your search in this period." : "No money in or out in this period.",
                        textAlign: TextAlign.center, style: GoogleFonts.inter(color: kDark.withValues(alpha: 0.6))),
                  ),
                )
              else
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: _loading ? 0.5 : 1,
                  child: Container(
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                    clipBehavior: Clip.antiAlias,
                    child: Column(children: [
                      for (var i = 0; i < entries.length; i++) ...[
                        if (i == 0 || dayKey(entries[i - 1]["at"]) != dayKey(entries[i]["at"]))
                          listDayRow(dayKey(entries[i]["at"]), _dayTotals(entries, dayKey(entries[i]["at"])))
                        else
                          Divider(height: 1, color: kDark.withValues(alpha: 0.06)),
                        _entryTile(entries[i]),
                      ],
                    ]),
                  ),
                ),
              pagerBar(
                page: _page,
                pages: pages,
                total: total,
                onPage: (p) {
                  if (!_loading) _goTo(p);
                },
                onSize: (n) async {
                  await ListPaging.setSize(n);
                  setState(() => _page = 1);
                  _load();
                },
              ),
              const SizedBox(height: 10),
              Text("Balance is Cash + all bank accounts after each entry. A transfer between your own accounts doesn't change it.",
                  style: GoogleFonts.inter(color: Colors.white60, fontSize: 12)),
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
              Text(label.toUpperCase(), style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: kDark.withValues(alpha: 0.5))),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, color: color)),
              ),
            ]),
          ),
        );
    final line = Divider(height: 1, color: kDark.withValues(alpha: 0.06));
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(children: [
        Row(children: [
          // nothing to carry in (e.g. All time from the start): no opening balance
          if (((summary["opening"] as num?) ?? 0) != 0) cell("Opening balance", inr(summary["opening"] ?? 0)),
          cell("Closing balance", inr(summary["closing"] ?? 0)),
        ]),
        line,
        Row(children: [
          cell("Debit (out)", inr(summary["moneyOut"] ?? 0), color: kTerracotta),
          cell("Credit (in)", inr(summary["moneyIn"] ?? 0)),
        ]),
      ]),
    );
  }

  /// One money movement: when, what, which account, + in / − out, and the balance after it.
  Widget _entryTile(Map<String, dynamic> r) {
    final at = DateTime.tryParse(r["at"]?.toString() ?? "")?.toLocal();
    final amount = (r["amount"] as num?) ?? 0;
    final transfer = r["kind"] == "transfer";
    final details = r["details"]?.toString() ?? "";
    final title = details.isNotEmpty ? details : r["label"]?.toString() ?? "Entry";
    final sub = [
      if (details.isNotEmpty) r["label"],
      r["account"],
      if ((r["category"]?.toString() ?? "").isNotEmpty) r["category"],
      if ((r["method"]?.toString() ?? "").isNotEmpty) r["method"],
      if ((r["reference"]?.toString() ?? "").isNotEmpty) "Ref ${r["reference"]}",
      if ((r["by"]?.toString() ?? "").isNotEmpty) "by ${r["by"]}",
    ].join(" · ");
    final amountText = transfer ? "⇄ ${inr(r["transferAmount"] ?? 0)}" : inr(amount.abs());
    final amountColor = transfer ? kDark.withValues(alpha: 0.5) : (amount > 0 ? kForest : kTerracotta);

    return InkWell(
      onTap: () => _openRow(r),
      child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          margin: const EdgeInsets.only(top: 2),
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(color: amountColor.withValues(alpha: 0.10), shape: BoxShape.circle),
          child: Icon(transfer ? Icons.swap_horiz_rounded : (amount > 0 ? Icons.south_west_rounded : Icons.north_east_rounded), size: 15, color: amountColor),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: kDark)),
            const SizedBox(height: 1),
            Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 11, color: kDark.withValues(alpha: 0.55))),
            if (at != null)
              Text(timeLabel(r["at"]), style: GoogleFonts.inter(fontSize: 11, color: kDark.withValues(alpha: 0.45))),
          ]),
        ),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(amountText, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w800, color: amountColor)),
          const SizedBox(height: 2),
          Text("Bal ${inr(r["balance"] ?? 0)}", style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: kDark.withValues(alpha: 0.55))),
        ]),
      ]),
      ),
    );
  }

  /// A tap: an expense row opens that expense in full (with its Edit); anything else shows its details here.
  Future<void> _openRow(Map<String, dynamic> r) async {
    final expenseId = r["kind"] == "company_paid" ? (r["expenseId"]?.toString() ?? "") : "";
    if (expenseId.isNotEmpty) {
      final res = await LedgerService.expenses(s.companyId, s.userId);
      if (!mounted) return;
      final expense = List<Map<String, dynamic>>.from(res["expenses"] ?? const []).where((x) => x["_id"].toString() == expenseId).firstOrNull;
      if (expense != null) {
        await showExpenseDetail(context, s, expense);
        if (mounted) _load();
        return;
      }
    }
    if (!mounted) return;
    final transfer = r["kind"] == "transfer";
    final amount = (r["amount"] as num?) ?? 0;
    final at = DateTime.tryParse(r["at"]?.toString() ?? "")?.toLocal();
    final editable = s.canEditEntries && (r["editId"]?.toString() ?? "").isNotEmpty;
    final lines = <(String, String)>[
      if (at != null) ("Date", DateFormat("dd MMM yyyy · h:mm a").format(at)),
      ("Type", r["label"]?.toString() ?? ""),
      if ((r["category"]?.toString() ?? "").isNotEmpty) ("Category", r["category"].toString()),
      ("Account", r["account"]?.toString() ?? "—"),
      if ((r["method"]?.toString() ?? "").isNotEmpty) ("Method", r["method"].toString()),
      if ((r["reference"]?.toString() ?? "").isNotEmpty) ("Reference", r["reference"].toString()),
      if ((r["by"]?.toString() ?? "").isNotEmpty) ("Recorded by", r["by"].toString()),
      ("Balance after", inr(r["balance"] ?? 0)),
    ];
    final details = r["details"]?.toString() ?? "";
    await showLedgerSheet(context, details.isNotEmpty ? details : r["label"]?.toString() ?? "Entry", (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(transfer ? "⇄ ${inr(r["transferAmount"] ?? 0)}" : inr(amount.abs()),
              style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w800, color: transfer ? kDark.withValues(alpha: 0.5) : (amount > 0 ? kForest : kTerracotta))),
          const SizedBox(height: 10),
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 110, child: Text(l.$1, style: GoogleFonts.inter(fontSize: 13, color: kDark.withValues(alpha: 0.55)))),
                Expanded(child: Text(l.$2, textAlign: TextAlign.right, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: kDark))),
              ]),
            ),
          if (editable) ...[
            const SizedBox(height: 12),
            primaryButton("Edit", () {
              Navigator.pop(ctx);
              _editAmount(r);
            }),
            // money added / a transfer can be removed (the money comes back out of that account)
            if (r["editId"].toString().startsWith("income:"))
              Center(
                child: TextButton(
                  onPressed: () async {
                    final ok = await confirmDialog(ctx, "Delete this entry?", "${inr(transfer ? (r["transferAmount"] ?? 0) : amount.abs())} will be taken back out of ${r["account"] ?? "that account"}, and the entry removed.",
                        confirmLabel: "Delete", danger: true);
                    if (!ok || !ctx.mounted) return;
                    final res = await LedgerService.deleteAccountsEntry(s.companyId, s.userId, r["editId"].toString());
                    if (!ctx.mounted) return;
                    if (handleResult(ctx, res, "Deleted · balances adjusted")) {
                      Navigator.pop(ctx);
                      notifyLedgerChanged();
                      _load();
                    }
                  },
                  child: const Text("Delete this entry", style: TextStyle(color: kTerracotta, fontWeight: FontWeight.w600)),
                ),
              ),
          ],
        ]));
  }

  /// The Admin edits an entry: its amount (in place, where that kind allows it; the balances after it move by the
  /// difference), description, method, reference and date & time.
  Future<void> _editAmount(Map<String, dynamic> r) async {
    final transfer = r["kind"] == "transfer";
    final income = r["editId"].toString().startsWith("income:");
    final amountEditable = r["amountEditable"] == true;
    final current = transfer ? ((r["transferAmount"] as num?) ?? 0) : ((r["amount"] as num?) ?? 0).abs();
    final amount = TextEditingController(text: current.toString());
    final details = TextEditingController(text: r["details"]?.toString() ?? "");
    final reference = TextEditingController(text: r["reference"]?.toString() ?? "");
    String method = r["method"]?.toString() ?? "";
    DateTime when = DateTime.tryParse(r["at"]?.toString() ?? "")?.toLocal() ?? DateTime.now();
    final saved = await showLedgerSheet<bool>(context, "Edit entry", (ctx) => StatefulBuilder(builder: (ctx, set) {
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (amountEditable) ...[
              TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: fieldDecoration("Amount ₹", icon: Icons.currency_rupee_rounded)),
              const SizedBox(height: 10),
            ],
            TextField(controller: details, decoration: fieldDecoration("Description", icon: Icons.notes_rounded)),
            if (!income) ...[
              const SizedBox(height: 10),
              methodChips(method, (m) => set(() => method = m)),
              const SizedBox(height: 10),
              TextField(controller: reference, decoration: fieldDecoration("Reference", icon: Icons.tag_rounded)),
            ],
            const SizedBox(height: 10),
            OutlinedButton.icon(
              icon: const Icon(Icons.event_rounded, size: 18),
              label: Text(DateFormat("dd MMM yyyy · h:mm a").format(when)),
              onPressed: () async {
                final d = await showDatePicker(context: ctx, initialDate: when, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 1)));
                if (d == null || !ctx.mounted) return;
                final t = await showTimePicker(context: ctx, initialTime: TimeOfDay.fromDateTime(when));
                set(() => when = DateTime(d.year, d.month, d.day, t?.hour ?? when.hour, t?.minute ?? when.minute));
              },
            ),
            const SizedBox(height: 6),
            Text(amountEditable ? "A new amount is changed in place; the balances after it move by the difference." : "This kind of entry keeps its amount; the other details can be changed.",
                style: GoogleFonts.inter(fontSize: 11, color: kDark.withValues(alpha: 0.5))),
            const SizedBox(height: 12),
            primaryButton("Save", () async {
              final changes = <String, dynamic>{"details": details.text.trim(), "date": DateFormat("yyyy-MM-dd'T'HH:mm").format(when)};
              if (amountEditable) {
                final v = double.tryParse(amount.text.trim()) ?? 0;
                if (!(v > 0)) return toast(ctx, "Enter an amount greater than zero", error: true);
                changes["amount"] = v;
              }
              if (!income) {
                changes["method"] = method;
                changes["reference"] = reference.text.trim();
              }
              final res = await LedgerService.editAccountsEntry(s.companyId, s.userId, r["editId"].toString(), changes);
              if (!ctx.mounted) return;
              if (handleResult(ctx, res, "Saved · balances adjusted")) Navigator.pop(ctx, true);
            }),
          ]);
        }));
    if (saved == true && mounted) {
      notifyLedgerChanged();
      _load();
    }
  }

  /// "3 entries · out ₹200.00 · in ₹500.00" for one day on this page (transfers between my accounts not counted).
  String _dayTotals(List<Map<String, dynamic>> entries, String day) {
    final rows = entries.where((e) => dayKey(e["at"]) == day).toList();
    num into = 0, out = 0;
    for (final e in rows) {
      if (e["kind"] == "transfer") continue;
      final a = (e["amount"] as num?) ?? 0;
      if (a > 0) into += a;
      if (a < 0) out -= a;
    }
    return [
      "${rows.length} ${rows.length == 1 ? "entry" : "entries"}",
      if (out > 0) "out ${inr(out)}",
      if (into > 0) "in ${inr(into)}",
    ].join(" · ");
  }
}
