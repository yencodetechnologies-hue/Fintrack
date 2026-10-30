import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../services/ledger_service.dart';
import 'ledger_common.dart';
import 'ledger_description_field.dart';

/// Managers: Cash and bank balances, add income, add/remove bank accounts, rename Cash,
/// and per-account statements (Cash by default; tap any bank to view its statement).
class FundsPage extends StatefulWidget {
  final LedgerScope scope;
  const FundsPage({super.key, required this.scope});

  @override
  State<FundsPage> createState() => _FundsPageState();
}

class _FundsPageState extends State<FundsPage> with LedgerAutoRefresh {
  final _fmt = DateFormat("yyyy-MM-dd");

  LedgerScope get s => widget.scope;
  late List<Map<String, dynamic>> _accounts = s.bankAccounts;
  late num _cash = s.cashBalance;
  late String _cashName = s.cashName == "Cash" ? (s.company["cashAccountName"]?.toString() ?? "InCash") : s.cashName;

  // Selected account: "cash" (default) or a bank account _id
  String _selectedFund = "cash";

  String get _selectedFundName {
    if (_selectedFund == "cash") return _cashName;
    for (final b in _accounts) {
      if (b["_id"].toString() == _selectedFund) {
        return b["bankName"]?.toString() ?? "Bank";
      }
    }
    return "Bank";
  }

  // Statement query state
  final _search = TextEditingController();
  Timer? _searchDebounce;
  String _query = "";
  int _page = 1;
  late String _from = DateFormat("yyyy-MM-01").format(DateTime.now());
  late String _to = DateFormat("yyyy-MM-dd").format(DateTime.now());
  String _mode = "month";

  Map<String, dynamic>? _statementData;
  String? _statementError;
  bool _statementLoading = false;
  int _request = 0;

  @override
  Set<String> get ledgerTopics => const {"balances", "expenses", "funds"};

  @override
  void onLedgerChanged() {
    _loadBalances();
    _loadStatement();
  }

  @override
  void initState() {
    super.initState();
    ListPaging.load().then((_) { if (mounted) setState(() {}); });
    _loadStatement();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _changed() {
    notifyLedgerChanged();
    s.reload();
  }

  (DateTime, DateTime) get _range {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return (DateTime.tryParse(_from) ?? DateTime(2000), DateTime.tryParse(_to) ?? today);
  }

  Future<void> _loadBalances() async {
    final res = await LedgerService.companyDetails(s.companyId, s.userId);
    if (!mounted) return;
    if (res["success"] == true && res["company"] != null) {
      final c = res["company"];
      setState(() {
        _accounts = List<Map<String, dynamic>>.from(c["bankAccounts"] ?? const []);
        _cash = (c["cashBalance"] as num?) ?? _cash;
        if (c["cashAccountName"] != null) _cashName = c["cashAccountName"].toString();
      });
    }
  }

  Future<void> _loadStatement() async {
    final (from, to) = _range;
    final id = ++_request;
    setState(() {
      _statementLoading = true;
      _statementError = null;
    });

    final res = await LedgerService.accountsEntries(
      s.companyId,
      s.userId,
      from: _from.isEmpty ? "2000-01-01" : _fmt.format(from),
      to: _to.isEmpty ? _fmt.format(DateTime.now()) : _fmt.format(to),
      q: _query,
      page: _page,
      limit: ListPaging.size,
      fund: _selectedFund,
      movesOnly: true,
    );

    if (!mounted || id != _request) return;
    setState(() {
      _statementLoading = false;
      if (res["success"] == true) {
        _statementData = res;
        _page = (res["page"] as num?)?.toInt() ?? _page;
      } else {
        _statementError = res["message"]?.toString() ?? "Could not load statement";
      }
    });
  }

  void _selectFund(String fundId) {
    if (_selectedFund == fundId) return;
    setState(() {
      _selectedFund = fundId;
      _page = 1;
    });
    _loadStatement();
  }

  void _goTo(int page) {
    setState(() => _page = page);
    _loadStatement();
  }

  void _onSearch(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      _query = _search.text.trim();
      _page = 1;
      _loadStatement();
    });
  }

  void _setRange(String mode, DateTime from, DateTime to) {
    setState(() {
      _mode = mode;
      _page = 1;
      _from = _fmt.format(from);
      _to = _fmt.format(to);
    });
    _loadStatement();
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
        _loadStatement();
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
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.calendar_today_rounded, size: 15, color: kForest),
            const SizedBox(width: 6),
            Text(_periodLabel, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: kDark)),
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down_rounded, size: 18, color: kDark.withValues(alpha: 0.6)),
          ]),
        ),
      );

  void _renameCash() {
    final name = TextEditingController(text: _cashName);
    showLedgerSheet(context, "Rename cash account", (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(controller: name, autofocus: true, decoration: fieldDecoration("Name, e.g. InCash or Petty cash", icon: Icons.payments_rounded)),
          const SizedBox(height: 16),
          primaryButton("Save", () async {
            final value = name.text.trim();
            if (value.isEmpty) return toast(ctx, "Enter a name", error: true);
            final res = await LedgerService.updateCashAccountName(s.companyId, s.userId, value);
            if (!ctx.mounted) return;
            if (handleResult(ctx, res, "Cash account renamed")) {
              setState(() => _cashName = value);
              Navigator.pop(ctx);
              _changed();
            }
          }),
        ]));
  }

  void _addBank() {
    final bank = TextEditingController();
    final holder = TextEditingController();
    final number = TextEditingController();
    final ifsc = TextEditingController();
    showLedgerSheet(context, "New bank account", (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(controller: bank, decoration: fieldDecoration("Bank name *", icon: Icons.account_balance_rounded)),
          const SizedBox(height: 10),
          TextField(controller: holder, decoration: fieldDecoration("Account holder name", icon: Icons.person_rounded)),
          const SizedBox(height: 10),
          TextField(controller: number, keyboardType: TextInputType.number, decoration: fieldDecoration("Account number *", icon: Icons.numbers_rounded)),
          const SizedBox(height: 10),
          TextField(controller: ifsc, textCapitalization: TextCapitalization.characters, decoration: fieldDecoration("IFSC code", icon: Icons.tag_rounded)),
          const SizedBox(height: 16),
          primaryButton("Save account", () async {
            if (bank.text.trim().isEmpty || number.text.trim().isEmpty) return toast(ctx, "Bank name and account number are required", error: true);
            final res = await LedgerService.addBankAccount(s.companyId, {
              "userId": s.userId,
              "bankName": bank.text.trim(),
              "accountHolder": holder.text.trim(),
              "accountNumber": number.text.trim(),
              "ifsc": ifsc.text.trim().toUpperCase(),
            });
            if (!ctx.mounted) return;
            if (handleResult(ctx, res, "Bank account added")) {
              setState(() => _accounts = List<Map<String, dynamic>>.from(res["bankAccounts"] ?? _accounts));
              Navigator.pop(ctx);
              _changed();
            }
          }),
        ]));
  }

  Future<void> _deleteBank(Map<String, dynamic> b) async {
    final ok = await confirmDialog(context, "Remove bank account?", "${bankLabel(b)} will be removed from ${s.companyName}.", confirmLabel: "Remove", danger: true);
    if (!ok || !mounted) return;
    final res = await LedgerService.deleteBankAccount(s.companyId, b["_id"].toString(), s.userId);
    if (!mounted) return;
    if (handleResult(context, res, "Bank account removed")) {
      setState(() {
        _accounts = List<Map<String, dynamic>>.from(res["bankAccounts"] ?? const []);
        if (_selectedFund == b["_id"].toString()) {
          _selectedFund = "cash";
        }
      });
      _changed();
      _loadStatement();
    }
  }

  void _addIncome() {
    final amount = TextEditingController();
    final desc = TextEditingController();
    String? destination = _selectedFund;
    String? sourceBank;
    showLedgerSheet(context, "Add income", (ctx) => StatefulBuilder(builder: (ctx, set) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: fieldDecoration("Amount ₹ *", icon: Icons.currency_rupee_rounded)),
          const SizedBox(height: 10),
          DescriptionField(companyId: s.companyId, userId: s.userId, kind: "fund", controller: desc, hint: "Description (optional)"),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: destination,
            isExpanded: true,
            decoration: fieldDecoration("Add to *", icon: Icons.south_west_rounded),
            items: [
              DropdownMenuItem(value: "cash", child: Text("$_cashName (${inr(_cash)})")),
              ..._accounts.map((b) => DropdownMenuItem(value: b["_id"].toString(), child: Text("${bankLabel(b)} · ${inr(b["balance"] ?? 0)}", overflow: TextOverflow.ellipsis))),
            ],
            onChanged: (v) => set(() {
              destination = v;
              sourceBank = null;
            }),
          ),
          if (destination != null) ...[
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              key: ValueKey(destination),
              initialValue: sourceBank,
              isExpanded: true,
              decoration: fieldDecoration("Money coming from *", icon: Icons.account_balance_rounded),
              items: [
                DropdownMenuItem(value: "direct", child: Text(destination == "cash" ? "Direct cash (new money)" : "Direct income (new money)")),
                ..._accounts
                    .where((b) => b["_id"].toString() != destination)
                    .map((b) => DropdownMenuItem(value: b["_id"].toString(), child: Text("${bankLabel(b)} · ${inr(b["balance"] ?? 0)}", overflow: TextOverflow.ellipsis))),
              ],
              onChanged: (v) => set(() => sourceBank = v),
            ),
            if (sourceBank != null) ...[
              const SizedBox(height: 4),
              Text(
                  sourceBank == "direct"
                      ? "This amount is added as new money; no other balance changes."
                      : "This amount is taken out of the selected bank's balance and moved here.",
                  style: GoogleFonts.inter(fontSize: 12, fontStyle: FontStyle.italic, color: kDark.withValues(alpha: 0.55))),
            ],
          ],
          const SizedBox(height: 16),
          primaryButton("Save", () async {
            final amt = double.tryParse(amount.text.trim()) ?? 0;
            if (!(amt > 0)) return toast(ctx, "Enter a valid amount", error: true);
            if (destination == null) return toast(ctx, "Select a bank account or $_cashName", error: true);
            if (sourceBank == null) return toast(ctx, "Select where the money is coming from", error: true);
            final res = await LedgerService.addIncome(s.companyId, {
              "userId": s.userId,
              "amount": amt,
              "destination": destination,
              "sourceBankAccountId": sourceBank,
              "description": desc.text.trim(),
            });
            if (!ctx.mounted) return;
            if (handleResult(ctx, res, "Income added")) {
              setState(() {
                _accounts = List<Map<String, dynamic>>.from(res["bankAccounts"] ?? _accounts);
                _cash = (res["cashBalance"] as num?) ?? _cash;
              });
              Navigator.pop(ctx);
              _changed();
              _loadStatement();
            }
          }),
        ])));
  }  Future<void> _exportStatement() async {
    final entries = List<Map<String, dynamic>>.from(_statementData?["entries"] ?? const []);
    if (entries.isEmpty) {
      toast(context, "No entries to export", error: true);
      return;
    }
    final rows = [
      ["Date", "Time", "Details", "Category", "Account", "Debit (Out)", "Credit (In)", "Balance After", "Recorded By"]
    ];
    for (final e in entries) {
      final at = DateTime.tryParse(e["at"]?.toString() ?? "")?.toLocal();
      final amount = (e["amount"] as num?) ?? 0;
      rows.add([
        csvDate(at),
        csvTime(at),
        e["details"]?.toString().isNotEmpty == true ? e["details"] : (e["label"] ?? ""),
        e["category"] ?? "",
        e["account"] ?? "",
        amount < 0 ? (-amount).toStringAsFixed(2) : "",
        amount > 0 ? amount.toStringAsFixed(2) : "",
        ((e["balance"] as num?) ?? 0).toStringAsFixed(2),
        e["by"] ?? "",
      ]);
    }
    await shareCsv(context, "${_selectedFundName.replaceAll(" ", "-")}-statement.csv", rows);
  }



  @override
  Widget build(BuildContext context) {
    final summary = _statementData?["summary"] as Map<String, dynamic>?;
    final entries = List<Map<String, dynamic>>.from(_statementData?["entries"] ?? const []);
    final total = (_statementData?["total"] as num?)?.toInt() ?? 0;
    final pages = (_statementData?["pages"] as num?)?.toInt() ?? 1;

    Widget fundCard({
      required String id,
      required String emoji,
      required String title,
      required String sub,
      required num balance,
      Widget? action,
    }) {
      final isSelected = _selectedFund == id;
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _selectFund(id),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? kForestDark : Colors.transparent,
                width: 2,
              ),
              boxShadow: isSelected
                  ? [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 10, offset: const Offset(0, 4))]
                  : null,
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(emoji, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16, color: kDark))),
                    if (isSelected)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: kForest.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                        child: Text("Active", style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: kForest)),
                      ),
                  ]),
                  Text(sub, style: GoogleFonts.inter(fontSize: 12, color: kDark.withValues(alpha: 0.55))),
                  const SizedBox(height: 6),
                  Text(inr(balance), style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.bold, color: kForest)),
                ]),
              ),
              if (action != null) action,
            ]),
          ),
        ),
      );
    }

    return Theme(
      data: sheetTheme,
      child: Scaffold(
        backgroundColor: kForest,
        appBar: AppBar(
          backgroundColor: kForest,
          foregroundColor: Colors.white,
          elevation: 0,
          title: Text("Company funds", style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: exportCsvButton(_exportStatement),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: () async {
            await Future.wait([_loadBalances(), _loadStatement()]);
          },
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 30), children: [
            Text("Track $_cashName and bank balances, and where company money moves.", style: GoogleFonts.inter(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 12),
            fundCard(
              id: "cash",
              emoji: "💵",
              title: _cashName,
              sub: "Cash in hand",
              balance: _cash,
              action: IconButton(tooltip: "Rename", onPressed: _renameCash, icon: const Icon(Icons.edit_rounded, color: kForest, size: 20)),
            ),
            ..._accounts.map((b) => fundCard(
                  id: b["_id"].toString(),
                  emoji: "🏦",
                  title: b["bankName"]?.toString() ?? "Bank",
                  sub: [
                    if ((b["accountHolder"]?.toString() ?? "").isNotEmpty) b["accountHolder"],
                    "A/C ${b["accountNumber"] ?? ""}",
                    if ((b["ifsc"]?.toString() ?? "").isNotEmpty) "IFSC ${b["ifsc"]}",
                  ].join(" • "),
                  balance: (b["balance"] as num?) ?? 0,
                  action: IconButton(tooltip: "Remove", onPressed: () => _deleteBank(b), icon: const Icon(Icons.delete_outline_rounded, color: kTerracotta, size: 20)),
                )),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(child: primaryButton("↗ Add Income", _addIncome, color: kForestDark)),
              const SizedBox(width: 8),
              Expanded(child: primaryButton("+ Add Bank Account", _addBank, color: kForestDark)),
            ]),
            const SizedBox(height: 18),

            // Per-account statement header
            Row(children: [
              Text("$_selectedFundName statement", style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 17, color: Colors.white)),
              const Spacer(),
              exportCsvButton(_exportStatement),
            ]),
            const SizedBox(height: 10),

            // Search + Period pill
            Row(children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    controller: _search,
                    onChanged: _onSearch,
                    style: GoogleFonts.inter(fontSize: 14, color: kDark),
                    decoration: InputDecoration(
                      hintText: "Search details, person…",
                      hintStyle: GoogleFonts.inter(fontSize: 13, color: kDark.withValues(alpha: 0.4)),
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

            if (_statementError != null)
              ledgerCard(child: Text(_statementError!, style: GoogleFonts.inter(color: kTerracotta)))
            else if (_statementLoading && _statementData == null)
              const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: Colors.white)))
            else ...[
              if (summary != null) _summaryCard(summary),
              const SizedBox(height: 10),
              if (total == 0)
                ledgerCard(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        _query.isNotEmpty
                            ? "Nothing matches your search in this period."
                            : "No money in or out of $_selectedFundName in this period.",
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(color: kDark.withValues(alpha: 0.6)),
                      ),
                    ),
                  ),
                )
              else
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: _statementLoading ? 0.5 : 1,
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
                  if (!_statementLoading) _goTo(p);
                },
                onSize: (n) async {
                  await ListPaging.setSize(n);
                  setState(() => _page = 1);
                  _loadStatement();
                },
              ),
              const SizedBox(height: 10),
              Text(
                "Balance is what $_selectedFundName holds after each entry. Payments and expenses from it are on the Accounts page.",
                style: GoogleFonts.inter(color: Colors.white60, fontSize: 12),
              ),
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
    final opening = (summary["opening"] as num?) ?? 0;
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(children: [
        Row(children: [
          if (opening != 0) cell("Opening balance", inr(opening)),
          cell("Closing balance", inr(summary["closing"] ?? 0)),
        ]),
        line,
        Row(children: [
          cell("Debit (out)", "−${inr(summary["moneyOut"] ?? 0)}", color: kTerracotta),
          cell("Credit (in)", "+${inr(summary["moneyIn"] ?? 0)}"),
          cell("Entries", "${summary["count"] ?? 0}", color: kDark),
        ]),
      ]),
    );
  }

  Widget _entryTile(Map<String, dynamic> r) {
    final at = DateTime.tryParse(r["at"]?.toString() ?? "")?.toLocal();
    final amount = (r["amount"] as num?) ?? 0;
    final transfer = r["kind"] == "transfer";
    final details = r["details"]?.toString() ?? "";
    final title = details.isNotEmpty ? details : r["label"]?.toString() ?? "Entry";
    final sub = [
      if (details.isNotEmpty) r["label"],
      r["account"],
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

  Future<void> _openRow(Map<String, dynamic> r) async {
    final transfer = r["kind"] == "transfer";
    final amount = (r["amount"] as num?) ?? 0;
    final at = DateTime.tryParse(r["at"]?.toString() ?? "")?.toLocal();
    final editable = s.canEditEntries && (r["editId"]?.toString() ?? "").isNotEmpty;
    final isIncome = r["editId"]?.toString().startsWith("income:") == true;
    final lines = <(String, String)>[
      if (at != null) ("Date", DateFormat("dd MMM yyyy · h:mm a").format(at)),
      ("Type", r["label"]?.toString() ?? ""),
      ("Account", r["account"]?.toString() ?? "—"),
      if ((r["method"]?.toString() ?? "").isNotEmpty) ("Method", r["method"].toString()),
      if ((r["reference"]?.toString() ?? "").isNotEmpty) ("Reference", r["reference"].toString()),
      if ((r["by"]?.toString() ?? "").isNotEmpty) ("Recorded by", r["by"].toString()),
      ("Balance after", inr(r["balance"] ?? 0)),
    ];
    final details = r["details"]?.toString() ?? "";

    await showLedgerSheet(
      context,
      details.isNotEmpty ? details : r["label"]?.toString() ?? "Entry",
      (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
          const SizedBox(height: 14),
          primaryButton("Edit", () {
            Navigator.pop(ctx);
            _editAmount(r);
          }),
          if (isIncome) ...[
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: () async {
                  final amtVal = transfer ? ((r["transferAmount"] as num?) ?? 0) : amount.abs();
                  final ok = await confirmDialog(ctx, "Delete this entry?", "${inr(amtVal)} will be taken back out of ${r["account"] ?? "the account"}, and the entry removed.", confirmLabel: "Delete", danger: true);
                  if (!ok || !ctx.mounted) return;
                  final res = await LedgerService.deleteAccountsEntry(s.companyId, s.userId, r["editId"].toString());
                  if (!ctx.mounted) return;
                  if (handleResult(ctx, res, "Deleted · balances adjusted")) {
                    Navigator.pop(ctx);
                    _changed();
                    _loadBalances();
                    _loadStatement();
                  }
                },
                child: const Text("Delete this entry", style: TextStyle(color: kTerracotta, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ],
      ]),
    );
  }

  Future<void> _editAmount(Map<String, dynamic> r) async {
    final transfer = r["kind"] == "transfer";
    final isIncome = r["editId"].toString().startsWith("income:");
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
            if (!isIncome) ...[
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
              if (!isIncome) {
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
      _changed();
      _loadBalances();
      _loadStatement();
    }
  }

  /// "2 entries · out ₹200.00 · in ₹500.00" for one day on this page.
  String _dayTotals(List<Map<String, dynamic>> entries, String day) {
    final rows = entries.where((e) => dayKey(e["at"]) == day).toList();
    num into = 0, out = 0;
    for (final e in rows) {
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
