import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/ledger_service.dart';
import 'ledger_common.dart';
import 'ledger_period_filter.dart';

/// Managers only: the web's Reports (with Outstanding) and Analysis pages.
class LedgerReportsTab extends StatefulWidget {
  final LedgerScope scope;
  const LedgerReportsTab({super.key, required this.scope});

  @override
  State<LedgerReportsTab> createState() => _LedgerReportsTabState();
}

class _LedgerReportsTabState extends State<LedgerReportsTab> {
  String _view = "report";

  @override
  Widget build(BuildContext context) {
    final s = widget.scope;
    // Report + Outstanding need "Reports & CSV export"; Analysis has its own switch
    final views = [if (s.can("reports")) "report", if (s.can("reports")) "outstanding", if (s.can("analysis")) "analysis"];
    if (views.isEmpty) return const SizedBox.shrink();
    final view = views.contains(_view) ? _view : views.first;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: SizedBox(
          width: double.infinity,
          child: SegmentedButton<String>(
            style: SegmentedButton.styleFrom(
              backgroundColor: kForestDark,
              foregroundColor: Colors.white,
              selectedBackgroundColor: Colors.white,
              selectedForegroundColor: kForest,
            ),
            segments: [
              if (views.contains("report")) const ButtonSegment(value: "report", label: Text("Report")),
              if (views.contains("outstanding")) const ButtonSegment(value: "outstanding", label: Text("Outstanding")),
              if (views.contains("analysis")) const ButtonSegment(value: "analysis", label: Text("Analysis")),
            ],
            selected: {view},
            showSelectedIcon: false,
            onSelectionChanged: (v) => setState(() => _view = v.first),
          ),
        ),
      ),
      Expanded(
        child: IndexedStack(index: views.indexOf(view), children: [
          if (views.contains("report")) _ReportView(scope: widget.scope),
          if (views.contains("outstanding")) _OutstandingView(scope: widget.scope),
          if (views.contains("analysis")) _AnalysisView(scope: widget.scope),
        ]),
      ),
    ]);
  }
}

Widget _panel({String? title, Widget? action, required Widget child}) => Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              Expanded(child: Text(title, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: kDark))),
              if (action != null) action,
            ]),
          ),
        child,
      ]),
    );

Widget _statTile(String label, num value, {Color color = kDark, String? sub, Color? subColor, String? text}) => Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: kDark.withValues(alpha: 0.55))),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(text ?? inr(value), style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
        ),
        if (sub != null && sub.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 11, color: subColor ?? kDark.withValues(alpha: 0.55))),
        ],
      ]),
    );

/// Two per row; a lone last tile spans the row.
Widget _grid(List<Widget> tiles) => Column(children: [
      for (var i = 0; i < tiles.length; i += 2)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: tiles[i]),
              if (i + 1 < tiles.length) ...[const SizedBox(width: 8), Expanded(child: tiles[i + 1])],
            ]),
          ),
        ),
    ]);

// ---------------- Report ----------------
class _ReportView extends StatefulWidget {
  final LedgerScope scope;
  const _ReportView({required this.scope});

  @override
  State<_ReportView> createState() => _ReportViewState();
}

class _ReportViewState extends State<_ReportView> with LedgerAutoRefresh {
  @override
  void onLedgerChanged() => _load(quiet: true);

  @override
  Set<String> get ledgerTopics => const {"expenses", "balances", "loans", "funds"};

  LedgerScope get s => widget.scope;
  bool _full = false;
  String _from = "";
  String _to = "";
  String _category = "All";
  Map<String, dynamic>? _report;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) setState(() => _loading = true);
    final res = await LedgerService.report(s.companyId, s.userId,
        from: _from.isEmpty ? null : _from, to: _to.isEmpty ? null : _to, category: _category);
    if (!mounted) return;
    setState(() {
      _report = res["report"];
      _loading = false;
    });
  }

  Future<void> _export() async {
    final url = LedgerService.exportUrl(s.companyId, s.userId,
        full: _full, from: _from.isEmpty ? null : _from, to: _to.isEmpty ? null : _to);
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && mounted) toast(context, "Could not open the download", error: true);
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 30), children: [
        if (s.isSuperAdmin)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SegmentedButton<bool>(
              style: SegmentedButton.styleFrom(backgroundColor: kForestDark, foregroundColor: Colors.white, selectedBackgroundColor: Colors.white, selectedForegroundColor: kForest),
              segments: const [ButtonSegment(value: false, label: Text("Company report")), ButtonSegment(value: true, label: Text("Full audit"))],
              selected: {_full},
              showSelectedIcon: false,
              onSelectionChanged: (v) => setState(() => _full = v.first),
            ),
          ),
        _panel(
          child: Column(children: [
            PeriodFilter(
              from: _from,
              to: _to,
              labelWidth: 64,
              decoration: fieldDecoration(""),
              onChanged: (from, to) {
                setState(() {
                  _from = from;
                  _to = to;
                });
                // custom range waits for both ends before reloading
                if (from.isEmpty == to.isEmpty) _load();
              },
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _category,
              isExpanded: true,
              decoration: fieldDecoration("Category", icon: Icons.category_rounded),
              items: ["All", ...companyCategories(s.company)].map((c) => DropdownMenuItem(value: c, child: Text(c == "All" ? "All Categories" : c))).toList(),
              onChanged: (v) {
                setState(() => _category = v ?? "All");
                _load();
              },
            ),
            if (_from.isNotEmpty || _to.isNotEmpty || _category != "All")
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    setState(() {
                      _from = "";
                      _to = "";
                      _category = "All";
                    });
                    _load();
                  },
                  child: const Text("Clear filters"),
                ),
              ),
          ]),
        ),
        if (!_full)
          _loading
              ? const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator(color: Colors.white)))
              : _panel(
                  child: Column(children: [
                    _row("Expenses", _report?["expenses"]),
                    _row("Paid by managers", _report?["paidByAdmins"]),
                    _row("Owed to ${s.managersName.toLowerCase()}", _report?["owedToAdmins"]),
                    _row("Inter-company net", _report?["intercompanyNet"]),
                  ]),
                )
        else
          _panel(
            title: "Full audit includes",
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final line in ["All companies, every ledger entry", "Inter-company trail and reversals", "Audit log: who did what, when"])
                Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text("• $line", style: GoogleFonts.inter(color: kDark))),
            ]),
          ),
        primaryButton("Export CSV (opens in Excel)", _export, color: kForestDark),
      ]),
    );
  }

  Widget _row(String label, dynamic value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Expanded(child: Text(label, style: GoogleFonts.inter(color: kDark, fontWeight: FontWeight.w600))),
          Text(inr(value), style: GoogleFonts.inter(color: kForest, fontWeight: FontWeight.bold, fontSize: 17)),
        ]),
      );
}

// ---------------- Outstanding ----------------
class _OutstandingView extends StatefulWidget {
  final LedgerScope scope;
  const _OutstandingView({required this.scope});

  @override
  State<_OutstandingView> createState() => _OutstandingViewState();
}

class _OutstandingViewState extends State<_OutstandingView> with LedgerAutoRefresh {
  @override
  void onLedgerChanged() => _load();

  @override
  Set<String> get ledgerTopics => const {"expenses", "balances", "loans", "funds"};

  Map<String, dynamic>? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await LedgerService.outstanding(widget.scope.companyId, widget.scope.userId);
    if (!mounted) return;
    setState(() {
      if (res["success"] == true) {
        _data = res;
        _error = null;
      } else {
        _error = res["message"]?.toString() ?? "Could not load outstanding report";
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return Center(child: Text(_error!, style: GoogleFonts.inter(color: Colors.white)));
    final d = _data;
    if (d == null) return const Center(child: CircularProgressIndicator(color: Colors.white));
    final t = Map<String, dynamic>.from(d["totals"] ?? const {});
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 30), children: [
        _grid([
          _statTile("OWED TO MANAGERS", (t["owedToManagers"] as num?) ?? 0, color: kTerracotta),
          _statTile("OWED TO STAFF", (t["owedToStaff"] as num?) ?? 0, color: kTerracotta),
          _statTile("WE OWE COMPANIES", (t["weOweCompanies"] as num?) ?? 0, color: kTerracotta),
          _statTile("COMPANIES OWE US", (t["companiesOweUs"] as num?) ?? 0, color: kForest),
          _statTile("AWAITING APPROVAL", (t["awaitingApproval"] as num?) ?? 0),
          _statTile("VOUCHER MONEY WITH STAFF", (t["advanceHeld"] as num?) ?? 0),
        ]),
        _people(widget.scope.managersName, List<Map<String, dynamic>>.from(d["managers"] ?? const [])),
        _people(widget.scope.staffsName, List<Map<String, dynamic>>.from(d["staff"] ?? const [])),
        _panel(
          title: "Companies",
          child: (d["companies"] as List? ?? const []).isEmpty
              ? Text("No open company loans.", style: GoogleFonts.inter(color: kDark.withValues(alpha: 0.6), fontSize: 13))
              : Column(children: [
                  for (final c in List<Map<String, dynamic>>.from(d["companies"]))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(c["name"]?.toString() ?? "", style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: kDark)),
                            Text("${c["loans"]} open loan${c["loans"] == 1 ? "" : "s"}${c["external"] == true ? " · outside company" : ""} · we owe ${inr(c["weOwe"])} · they owe ${inr(c["theyOwe"])}",
                                style: GoogleFonts.inter(fontSize: 11.5, color: kDark.withValues(alpha: 0.55))),
                          ]),
                        ),
                        Text(
                          ((c["net"] as num?) ?? 0) < 0 ? "We owe ${inr(-((c["net"] as num?) ?? 0))}" : ((c["net"] as num?) ?? 0) > 0 ? "They owe ${inr(c["net"])}" : "Settled",
                          style: GoogleFonts.inter(fontWeight: FontWeight.w800, color: ((c["net"] as num?) ?? 0) < 0 ? kTerracotta : kForest),
                        ),
                      ]),
                    ),
                ]),
        ),
        Text(
          "\"Company owes\" = paid out of pocket and not yet reimbursed + approved claims not yet paid. Awaiting approval is shown separately and not counted. \"Voucher money held\" is company money staff still have from vouchers.",
          style: GoogleFonts.inter(color: Colors.white70, fontSize: 11.5),
        ),
      ]),
    );
  }

  Widget _people(String title, List<Map<String, dynamic>> rows) => _panel(
        title: title,
        child: rows.isEmpty
            ? Text("Nothing outstanding.", style: GoogleFonts.inter(color: kDark.withValues(alpha: 0.6), fontSize: 13))
            : Column(children: [
                for (final r in rows)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(r["name"]?.toString() ?? "", style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: kDark)),
                          Text(
                            [
                              "Paid, not reimbursed ${inr(r["recorded"])}",
                              "Approved claims ${inr(r["claims"])}${((r["claimCount"] as num?) ?? 0) > 0 ? " (${r["claimCount"]})" : ""}",
                              if (((r["awaitingApproval"] as num?) ?? 0) != 0) "Awaiting approval ${inr(r["awaitingApproval"])}",
                              if (((r["advanceHeld"] as num?) ?? 0) > 0) "Voucher money held ${inr(r["advanceHeld"])}",
                            ].join(" · "),
                            style: GoogleFonts.inter(fontSize: 11.5, color: kDark.withValues(alpha: 0.55)),
                          ),
                        ]),
                      ),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text("COMPANY OWES", style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w700, color: kDark.withValues(alpha: 0.5))),
                        Text(inr(r["owed"]), style: GoogleFonts.inter(fontWeight: FontWeight.w800, color: ((r["owed"] as num?) ?? 0) > 0 ? kTerracotta : kDark)),
                      ]),
                    ]),
                  ),
              ]),
      );
}

// ---------------- Analysis ----------------
class _AnalysisView extends StatefulWidget {
  final LedgerScope scope;
  const _AnalysisView({required this.scope});

  @override
  State<_AnalysisView> createState() => _AnalysisViewState();
}

class _AnalysisViewState extends State<_AnalysisView> with LedgerAutoRefresh {
  @override
  void onLedgerChanged() => _load();

  @override
  Set<String> get ledgerTopics => const {"expenses", "balances", "loans", "funds"};

  int _months = 12;
  bool _table = false;
  Map<String, dynamic>? _data;
  String? _error;
  static const _weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await LedgerService.analysis(widget.scope.companyId, widget.scope.userId, months: _months);
    if (!mounted) return;
    setState(() {
      if (res["success"] == true) {
        _data = res;
        _error = null;
      } else {
        _error = res["message"]?.toString() ?? "Could not load analysis";
      }
    });
  }

  String _monthLabel(String ym, {bool full = false}) {
    final d = DateTime.tryParse("$ym-01");
    return d == null ? ym : DateFormat(full ? "MMM yyyy" : "MMM").format(d);
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 30), children: [
        Text("Spending patterns for managers. Rejected and group expenses are excluded.", style: GoogleFonts.inter(color: Colors.white70, fontSize: 12.5)),
        const SizedBox(height: 8),
        Row(children: [
          for (final m in [3, 6, 12])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text("$m months"),
                selected: _months == m,
                selectedColor: Colors.white,
                backgroundColor: kForestDark,
                showCheckmark: false,
                labelStyle: GoogleFonts.inter(color: _months == m ? kForest : Colors.white, fontWeight: FontWeight.w700),
                onSelected: (_) {
                  setState(() {
                    _months = m;
                    _data = null;
                  });
                  _load();
                },
              ),
            ),
        ]),
        const SizedBox(height: 10),
        if (_error != null)
          Text(_error!, style: GoogleFonts.inter(color: Colors.white))
        else if (d == null)
          const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator(color: Colors.white)))
        else
          ..._content(d),
      ]),
    );
  }

  List<Widget> _content(Map<String, dynamic> d) {
    final sm = Map<String, dynamic>.from(d["summary"] ?? const {});
    final change = sm["changePct"] as num?;
    final largest = sm["largest"] as Map?;
    final monthly = List<Map<String, dynamic>>.from(d["monthly"] ?? const []);
    final weekday = List<Map<String, dynamic>>.from(d["weekday"] ?? const []);
    final unusual = List<Map<String, dynamic>>.from(d["unusual"] ?? const []);
    final recurring = List<Map<String, dynamic>>.from(d["recurring"] ?? const []);
    return [
      _grid([
        _statTile("THIS MONTH", (sm["thisMonth"] as num?) ?? 0,
            sub: change == null
                ? "No spend last month"
                : "${change > 0 ? "▲" : change < 0 ? "▼" : "■"} ${change.abs()}% vs last month (${inr(sm["lastMonth"])})",
            subColor: change == null ? null : (change > 0 ? kTerracotta : change < 0 ? kForest : null)),
        _statTile("TOTAL · ${d["months"] ?? _months} MONTHS", (sm["total"] as num?) ?? 0, sub: "${sm["count"] ?? 0} expenses"),
        _statTile("MONTHLY AVERAGE", (sm["monthlyAverage"] as num?) ?? 0, sub: "Avg expense ${inr(sm["average"])}"),
        _statTile("LARGEST EXPENSE", (largest?["amount"] as num?) ?? 0,
            text: largest == null ? "—" : null, sub: largest == null ? "" : "${largest["description"]} · ${dateLabel(largest["date"])}"),
      ]),
      _panel(
        title: "Monthly spend",
        action: TextButton(onPressed: () => setState(() => _table = !_table), child: Text(_table ? "Chart" : "Table")),
        child: _table
            ? Column(children: [
                for (final m in monthly)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(children: [
                      Expanded(child: Text(_monthLabel(m["month"].toString(), full: true), style: GoogleFonts.inter(color: kDark))),
                      SizedBox(width: 40, child: Text("${m["count"]}", textAlign: TextAlign.right, style: GoogleFonts.inter(color: kDark.withValues(alpha: 0.6)))),
                      SizedBox(width: 110, child: Text(inr(m["total"]), textAlign: TextAlign.right, style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: kDark))),
                    ]),
                  ),
              ])
            : _columns(monthly.map((m) => (label: _monthLabel(m["month"].toString()), value: (m["total"] as num?) ?? 0)).toList(), highlightLast: true),
      ),
      _panel(title: "By category", child: _ranked(List<Map<String, dynamic>>.from(d["categories"] ?? const []), "category", (r) => "avg ${inr(r["avg"])}")),
      _panel(title: "Top spenders", child: _ranked(List<Map<String, dynamic>>.from(d["people"] ?? const []), "name", (r) => "${r["count"]} exp")),
      _panel(
        title: "Spend by day of week",
        child: _columns(weekday.map((w) => (label: _weekdays[((w["day"] as num?) ?? 0).toInt() % 7], value: (w["total"] as num?) ?? 0)).toList(), height: 110),
      ),
      _panel(
        title: "Unusual expenses",
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text("At least 2× the average for their category.", style: GoogleFonts.inter(fontSize: 12, color: kDark.withValues(alpha: 0.55))),
          const SizedBox(height: 6),
          if (unusual.isEmpty) Text("Nothing unusual in this period.", style: GoogleFonts.inter(fontSize: 13, color: kDark.withValues(alpha: 0.6))),
          for (final u in unusual)
            _line(u["description"]?.toString() ?? "", "${u["category"]} · ${u["by"] ?? "—"} · ${dateLabel(u["date"])}", inr(u["amount"]),
                "⚠ ${u["ratio"]}× avg (${inr(u["categoryAvg"])})", kTerracotta),
        ]),
      ),
      _panel(
        title: "Recurring expenses",
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text("Same description in 3 or more different months.", style: GoogleFonts.inter(fontSize: 12, color: kDark.withValues(alpha: 0.55))),
          const SizedBox(height: 6),
          if (recurring.isEmpty) Text("No recurring expenses found yet.", style: GoogleFonts.inter(fontSize: 13, color: kDark.withValues(alpha: 0.6))),
          for (final r in recurring)
            _line(r["description"]?.toString() ?? "", "${r["months"]} months · ${r["count"]} times · last ${dateLabel(r["lastDate"])}", "${inr(r["avgAmount"])} avg",
                "${inr(r["total"])} total", kDark.withValues(alpha: 0.55)),
        ]),
      ),
    ];
  }

  Widget _line(String title, String sub, String right, String rightSub, Color rightSubColor) => Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFF1F5F9)))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: kDark)),
              Text(sub, style: GoogleFonts.inter(fontSize: 11.5, color: kDark.withValues(alpha: 0.55))),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(right, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: kDark)),
            Text(rightSub, style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600, color: rightSubColor)),
          ]),
        ]),
      );

  /// Simple column chart: one bar per row, value above, label below.
  Widget _columns(List<({String label, num value})> rows, {double height = 150, bool highlightLast = false}) {
    final max = rows.fold<num>(0, (m, r) => r.value > m ? r.value : m);
    return SizedBox(
      height: height + 34,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (var i = 0; i < rows.length; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                Container(
                  height: max > 0 ? (rows[i].value / max * height).toDouble().clamp(2, height) : 2,
                  decoration: BoxDecoration(
                    color: highlightLast && i == rows.length - 1 ? kForest : kMint.withValues(alpha: 0.55),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                  ),
                ),
                const SizedBox(height: 4),
                Text(rows[i].label, maxLines: 1, overflow: TextOverflow.clip, style: GoogleFonts.inter(fontSize: 9.5, color: kDark.withValues(alpha: 0.6))),
              ]),
            ),
          ),
      ]),
    );
  }

  /// Horizontal bars ranked by total, with share of the whole.
  Widget _ranked(List<Map<String, dynamic>> rows, String nameKey, String Function(Map<String, dynamic>) extra) {
    if (rows.isEmpty) return Text("No data in this period.", style: GoogleFonts.inter(fontSize: 13, color: kDark.withValues(alpha: 0.6)));
    final total = rows.fold<num>(0, (sum, r) => sum + ((r["total"] as num?) ?? 0));
    final max = rows.fold<num>(0, (m, r) => ((r["total"] as num?) ?? 0) > m ? (r["total"] as num) : m);
    return Column(children: [
      for (final r in rows)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(r[nameKey]?.toString() ?? "—", maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 12.5, color: kDark))),
              Text(inr(r["total"]), style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.bold, color: kDark)),
            ]),
            const SizedBox(height: 3),
            Row(children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: max > 0 ? (((r["total"] as num?) ?? 0) / max).toDouble() : 0,
                    minHeight: 6,
                    backgroundColor: const Color(0xFFF1F5F9),
                    color: kForest,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text("${total > 0 ? ((((r["total"] as num?) ?? 0) / total) * 100).round() : 0}% · ${extra(r)}",
                  style: GoogleFonts.inter(fontSize: 10.5, color: kDark.withValues(alpha: 0.55))),
            ]),
          ]),
        ),
    ]);
  }
}
