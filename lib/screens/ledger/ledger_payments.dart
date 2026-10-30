import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../services/ledger_service.dart';
import 'ledger_common.dart';
import 'ledger_fund_topup.dart';
import 'ledger_dashboard_tab.dart' show BillsPreview;
import 'ledger_period_filter.dart';
import 'ledger_own_outstanding.dart';
import 'ledger_funds.dart';

num _round(num n) => (n * 100).round() / 100;
num _max(num a, num b) => a > b ? a : b;
num _min(num a, num b) => a < b ? a : b;

/// One person the company may owe money to.
class _Person {
  final String userId;
  final String name;
  final String email;
  final String role; // admin | manager | staff | role:<custom role id> | former
  final String label; // the role's name as shown
  final num owed;
  final num claims;
  final num advance;
  const _Person(this.userId, this.name, this.email, this.role, this.owed, this.claims, this.advance, this.label);
}

/// Managers (web's Payments page): pay off what the company owes any staff member or manager, from company
/// funds or out of their own pocket ("by self": the company then owes the paying manager). One person or many,
/// full or part amounts, plus the payment history.
class PaymentsPage extends StatefulWidget {
  final LedgerScope scope;
  /// Opened from the Home "My outstanding" tile: start with "Name (You)" picked in Payment history.
  final bool focusOwn;
  /// Shown as a bottom-nav tab (the home screen already has the app bar), so no app bar of its own.
  final bool embedded;
  /// Only my own: what the company owes me for my expenses, paying it, and my payment history (the Payments tab).
  final bool mineOnly;
  const PaymentsPage({super.key, required this.scope, this.focusOwn = false, this.embedded = false, this.mineOnly = false});

  @override
  State<PaymentsPage> createState() => _PaymentsPageState();
}

class _PaymentsPageState extends State<PaymentsPage> with LedgerAutoRefresh {
  @override
  void onLedgerChanged() => _load();

  @override
  Set<String> get ledgerTopics => const {"balances", "expenses", "ledger"};

  LedgerScope get s => widget.scope;
  Map<String, dynamic>? _balances;
  List<Map<String, dynamic>> _txs = [];
  final _search = TextEditingController();
  // people filter: all | me | managers | staff — "me" shows my own outstanding (pay it here) instead of the list;
  // starts on my own bills; the filter shows everyone else's
  late String _role = "me";
  int _peoplePage = 1;
  int _historyPage = 1;
  String _show = "owed"; // owed | all
  String _sort = "owed"; // owed | claims | name
  final Set<String> _selected = {};
  final _historySearch = TextEditingController();
  String _historyPerson = "all";
  String _historyFrom = "";
  String _historyTo = "";

  @override
  void initState() {
    super.initState();
    ListPaging.load().then((_) { if (mounted) setState(() {}); });
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    _historySearch.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final r = await Future.wait([LedgerService.balances(s.companyId, s.userId), LedgerService.transactions(s.companyId, s.userId)]);
    if (!mounted) return;
    setState(() {
      if (r[0]["success"] == true) _balances = r[0];
      if (r[1]["success"] == true) _txs = List<Map<String, dynamic>>.from(r[1]["transactions"] ?? const []);
    });
    if (r[0]["success"] != true) toast(context, r[0]["message"]?.toString() ?? "Could not load balances", error: true);
  }

  // everyone in the company (plus anyone still owed who has left), with what they're owed
  List<_Person> get _people {
    final rows = {for (final a in List<Map<String, dynamic>>.from(_balances?["admins"] ?? const [])) idOf(a["userId"]): a};
    final list = <_Person>[];
    for (final m in s.members) {
      final id = m["userId"].toString();
      final row = rows.remove(id);
      // Admin (the creator or made Admin) apart from managers; custom roles by name
      final admin = idOf(s.company["createdBy"]) == id || m["isAdmin"] == true;
      final custom = (m["customRoleId"]?.toString() ?? "").isNotEmpty;
      final group = admin ? "admin" : custom ? "role:${m["customRoleId"]}" : m["role"] == "admin" ? "manager" : "staff";
      final label = admin ? s.adminName : custom ? (m["customRoleName"]?.toString() ?? "Custom role") : m["role"] == "admin" ? s.managerName : s.staffName;
      list.add(_Person(id, m["name"]?.toString() ?? "Member", m["email"]?.toString() ?? "", group,
          (row?["owed"] as num?) ?? 0, (row?["claims"] as num?) ?? 0, _max(0, (row?["advance"] as num?) ?? 0), label));
    }
    for (final e in rows.entries) {
      list.add(_Person(e.key, e.value["name"]?.toString() ?? "Former member", "", "former", (e.value["owed"] as num?) ?? 0,
          (e.value["claims"] as num?) ?? 0, _max(0, (e.value["advance"] as num?) ?? 0), "Former"));
    }
    return list;
  }

  List<_Person> _visible(List<_Person> people) {
    final q = _search.text.trim().toLowerCase();
    final list = people
        .where((p) => _role == "all" ? true : _role.startsWith("person:") ? p.userId == _role.substring(7) : p.role == _role)
        .where((p) => _show == "owed" ? p.owed > 0 : true)
        .where((p) => q.isEmpty || "${p.name} ${p.email}".toLowerCase().contains(q))
        .toList();
    list.sort((a, b) => _sort == "name"
        ? a.name.toLowerCase().compareTo(b.name.toLowerCase())
        : _sort == "claims"
            ? b.claims.compareTo(a.claims)
            : b.owed.compareTo(a.owed));
    return list;
  }

  bool _payable(_Person p) => p.owed > 0 && p.userId != s.userId;

  // payments made: company reimbursements, payments by a manager personally, and voucher set-offs
  ({String name, String how, num amount, String date, String by, String method, String reference, Map<String, dynamic> tx})? _historyRow(Map<String, dynamic> t) {
    if ((t["type"] != "reimburse" && t["type"] != "advance_offset") || t["reversedBy"] != null) return null;
    final entries = List<Map<String, dynamic>>.from(t["entries"] ?? const []);
    String acct(Map<String, dynamic> e) => e["accountId"] is Map ? (e["accountId"]["name"]?.toString() ?? "") : "";
    final debit = entries.where((e) => ((e["debit"] as num?) ?? 0) > 0 && acct(e).startsWith("Payable to ")).firstOrNull;
    final credit = entries.where((e) => ((e["credit"] as num?) ?? 0) > 0).firstOrNull;
    final memo = t["memo"]?.toString() ?? "";
    final how = t["type"] == "advance_offset"
        ? "Set off from voucher balance"
        : memo.endsWith("personally")
            ? memo
            : "Company · ${credit == null ? "fund" : acct(credit)}";
    return (
      name: debit == null ? "Someone" : acct(debit).replaceFirst("Payable to ", ""),
      how: how,
      amount: (debit?["debit"] as num?) ?? 0,
      date: (t["date"] ?? t["createdAt"])?.toString() ?? "",
      // who paid: the company (its name), or the manager who paid out of their own pocket
      by: memo.endsWith("personally")
          ? (RegExp(r"^Paid by (.+) personally$").firstMatch(memo)?.group(1) ?? nameOf(t["createdBy"], "Manager"))
          : s.companyName,
      method: t["method"]?.toString() ?? "",
      reference: t["reference"]?.toString() ?? "",
      tx: t,
    );
  }

  Future<void> _exportPayments() async {
    final list = _people;
    if (list.isEmpty && _txs.isEmpty) {
      toast(context, "Nothing to export", error: true);
      return;
    }
    final rows = [
      ["Type", "Name / Person", "Role / Paid By", "How / Details", "Method", "Reference", "Amount Owed / Paid", "Date"],
      for (final p in list)
        ["Owed", p.name, p.label, "${p.claims} claims", "", "", p.owed.toStringAsFixed(2), ""],
      for (final h in _txs.map(_historyRow).whereType<({String name, String how, num amount, String date, String by, String method, String reference, Map<String, dynamic> tx})>())
        ["History", h.name, h.by, h.how, h.method, h.reference, h.amount.toStringAsFixed(2), csvDate(h.date)],
    ];
    await shareCsv(context, "${s.companyName}-payments.csv", rows);
  }

  @override
  Widget build(BuildContext context) {
    final people = _people;
    // Pay people lists everyone but me: my own expenses are paid from the Payments tab
    final others = people.where((p) => p.userId != s.userId).toList();
    final visible = _visible(others);
    final peoplePage = ListPaging.slice(visible, _peoplePage);
    final payableVisible = visible.where(_payable).toList();
    final selectedPeople = people.where((p) => _selected.contains(p.userId) && _payable(p)).toList();
    final selectedTotal = _round(selectedPeople.fold<num>(0, (a, p) => a + p.owed));
    final allSelected = payableVisible.isNotEmpty && payableVisible.every((p) => _selected.contains(p.userId));
    num sum(Iterable<_Person> list) => _round(list.fold<num>(0, (a, p) => a + _max(0, p.owed)));

    final totalOwed = sum(people);
    final waitingCount = people.where((p) => p.owed > 0).length;

    final groups = <({String key, String label, num owed, int waiting, int count})>[
      (
        key: "admin",
        label: "Owed to ${pluralRole(s.adminName).toLowerCase()}",
        owed: sum(people.where((p) => p.role == "admin")),
        waiting: people.where((p) => p.role == "admin" && p.owed > 0).length,
        count: people.where((p) => p.role == "admin").length,
      ),
      (
        key: "manager",
        label: "Owed to ${s.managersName.toLowerCase()}",
        owed: sum(people.where((p) => p.role == "manager")),
        waiting: people.where((p) => p.role == "manager" && p.owed > 0).length,
        count: people.where((p) => p.role == "manager").length,
      ),
      (
        key: "staff",
        label: "Owed to ${s.staffsName.toLowerCase()}",
        owed: sum(people.where((p) => p.role == "staff")),
        waiting: people.where((p) => p.role == "staff" && p.owed > 0).length,
        count: people.where((p) => p.role == "staff").length,
      ),
      for (final r in List<Map<String, dynamic>>.from(s.company["customRoles"] ?? const []))
        (
          key: "role:${r["_id"]}",
          label: "Owed to ${(r["name"]?.toString() ?? "Custom role").toLowerCase()}",
          owed: sum(people.where((p) => p.role == "role:${r["_id"]}")),
          waiting: people.where((p) => p.role == "role:${r["_id"]}" && p.owed > 0).length,
          count: people.where((p) => p.role == "role:${r["_id"]}").length,
        ),
      (
        key: "former",
        label: "Owed to former members",
        owed: sum(people.where((p) => p.role == "former")),
        waiting: people.where((p) => p.role == "former" && p.owed > 0).length,
        count: people.where((p) => p.role == "former").length,
      ),
    ].where((g) => g.key != "former" || g.owed > 0).toList();

    final totalFunds = s.cashBalance + s.bankAccounts.fold<num>(0, (prev, b) => prev + ((b["balance"] as num?) ?? 0));
    final fundsSub = [
      "Cash ${inr(s.cashBalance)}",
      for (final b in s.bankAccounts) "${b["bankName"] ?? "Bank"} ${inr(b["balance"] ?? 0)}"
    ].take(2).join(" · ");

    final allHistory = _txs.map(_historyRow).whereType<({String name, String how, num amount, String date, String by, String method, String reference, Map<String, dynamic> tx})>().toList()
      // newest payment date first (a payment can be backdated)
      ..sort((a, b) => (DateTime.tryParse(b.date) ?? DateTime(0)).compareTo(DateTime.tryParse(a.date) ?? DateTime(0)));
    final historyNames = allHistory.map((h) => h.name).toSet().toList()..sort();
    final hq = _historySearch.text.trim().toLowerCase();
    final history = allHistory.where((h) {
      final day = h.date.length >= 10 ? h.date.substring(0, 10) : h.date;
      if (widget.mineOnly && h.name != s.userName) return false;
      if (_historyPerson != "all" && h.name != _historyPerson) return false;
      if (_historyFrom.isNotEmpty && day.compareTo(_historyFrom) < 0) return false;
      if (_historyTo.isNotEmpty && day.compareTo(_historyTo) > 0) return false;
      if (hq.isNotEmpty && !"${h.name} ${h.how} ${h.by} ${h.reference}".toLowerCase().contains(hq)) return false;
      return true;
    }).toList();
    final historyPage = ListPaging.slice(history, _historyPage);


    final input = InputDecoration(
      isDense: true,
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
    );

    return Theme(
      data: sheetTheme,
      child: Scaffold(
        backgroundColor: kForest,
        appBar: widget.embedded
            ? null
            : AppBar(
                backgroundColor: kForest,
                foregroundColor: Colors.white,
                elevation: 0,
                title: Text("Payments", style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                actions: [
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: exportCsvButton(_exportPayments),
                  ),
                ],
              ),
        bottomNavigationBar: selectedPeople.isEmpty || _role == "me"
            ? null
            : SafeArea(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
                  decoration: BoxDecoration(color: kForestDark, borderRadius: BorderRadius.circular(16)),
                  child: Row(children: [
                    Expanded(
                      child: Text("${selectedPeople.length} selected · ${inr(selectedTotal)}",
                          style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w700)),
                    ),
                    TextButton(onPressed: () => setState(_selected.clear), child: Text("Clear", style: GoogleFonts.inter(color: Colors.white70))),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: kForest),
                      onPressed: () => _pay(selectedPeople),
                      child: const Text("Pay selected"),
                    ),
                  ]),
                ),
              ),
        body: _balances == null
            ? const Center(child: CircularProgressIndicator(color: Colors.white))
            : RefreshIndicator(
                onRefresh: _load,
                // a CustomScrollView so "Your outstanding" can keep its top pinned while its bills scroll
                child: CustomScrollView(slivers: [
                  // Payments tab (mineOnly): just the Your outstanding card; everything below is the Pay people page
                  if (!widget.mineOnly) SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    sliver: SliverToBoxAdapter(
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(widget.mineOnly
                                    ? "What ${s.companyName} owes you for your expenses. Pay yourself from company funds, all at once or bill by bill."
                                    : "Pay off what the company owes each person, from company funds or out of your own pocket.",
                                style: GoogleFonts.inter(color: Colors.white70, fontSize: 13)),
                          ),
                          if (widget.embedded) ...[
                            const SizedBox(width: 8),
                            exportCsvButton(_exportPayments),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (!widget.mineOnly)
                    SliverToBoxAdapter(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                        child: Row(
                          children: [
                            _summaryTile(
                              label: "Total owed",
                              value: inr(totalOwed),
                              sub: "$waitingCount ${waitingCount == 1 ? "person" : "people"} waiting",
                              color: totalOwed > 0 ? kTerracotta : kForest,
                              isSelected: _role == "all",
                              onTap: () => setState(() => _role = "all"),
                            ),
                            for (final g in groups)
                              _summaryTile(
                                label: g.label,
                                value: inr(g.owed),
                                sub: g.waiting > 0
                                    ? "${g.waiting} ${g.waiting == 1 ? "person" : "people"} waiting"
                                    : g.count > 0
                                        ? "Nothing owed"
                                        : "No one in this role",
                                color: g.owed > 0 ? kTerracotta : null,
                                isSelected: _role == g.key,
                                onTap: () => setState(() => _role = _role == g.key ? "all" : g.key),
                              ),
                            _summaryTile(
                              label: "Company funds",
                              value: inr(totalFunds),
                              sub: fundsSub.isEmpty ? "Tap to view funds" : fundsSub,
                              color: kDark,
                              isSelected: false,
                              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FundsPage(scope: s))),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (!widget.mineOnly)
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverList(delegate: SliverChildListDelegate([
                        const SizedBox(height: 4),
                        _filterCard(
                          _searchField(_search, "Search by name or email"),
                          [
                            _pill(Icons.group_outlined, _role, "all", {
                              "all": "Everyone",
                              "me": "${s.userName} (You)",
                              "admin": pluralRole(s.adminName),
                              "manager": s.managersName,
                              "staff": s.staffsName,
                              for (final r in List<Map<String, dynamic>>.from(s.company["customRoles"] ?? const [])) "role:${r["_id"]}": r["name"]?.toString() ?? "Custom role",
                              for (final p in ([..._people.where((p) => p.userId != s.userId)]..sort((a, b) => a.name.compareTo(b.name))))
                                "person:${p.userId}": "${p.name} (${p.label})",
                            }, (v) => _role = v),
                            _pill(Icons.filter_list_rounded, _show, "owed", {"owed": "Owed only", "all": "Include settled"}, (v) => _show = v),
                            _pill(Icons.swap_vert_rounded, _sort, "owed", {"owed": "Highest owed", "claims": "Most claims", "name": "Name A–Z"}, (v) => _sort = v),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ])),
                    ),
                  // "Name (You)": what the company owes me, payable right here (amount / selected / all)
                  if (_role == "me") SliverPadding(padding: EdgeInsets.fromLTRB(16, widget.mineOnly ? 4 : 0, 16, widget.mineOnly ? 24 : 0), sliver: OwnOutstandingCard(scope: s, onPaid: _load, showEmpty: widget.mineOnly)),
                  if (!widget.mineOnly) SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 30),
                    sliver: SliverList(delegate: SliverChildListDelegate([
                  if (_role == "me")
                    const SizedBox.shrink()
                  else if (visible.isEmpty)
                    ledgerCard(
                      child: Center(
                        child: Text(_show == "owed" ? "Nobody is owed money right now." : "No one matches your search.",
                            style: GoogleFonts.inter(color: kDark.withValues(alpha: 0.6))),
                      ),
                    )
                  else
                    Container(
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                      child: Column(children: [
                        if (payableVisible.isNotEmpty)
                          CheckboxListTile(
                            dense: true,
                            controlAffinity: ListTileControlAffinity.leading,
                            value: allSelected,
                            onChanged: (_) => setState(() {
                              final ids = payableVisible.map((p) => p.userId);
                              allSelected ? _selected.removeAll(ids) : _selected.addAll(ids);
                            }),
                            title: Text("Select all owed (${payableVisible.length})", style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: kDark)),
                          ),
                        for (var i = 0; i < peoplePage.rows.length; i++) ...[
                          if (i > 0 || payableVisible.isNotEmpty) const Divider(height: 1, color: Color(0xFFF1F5F9)),
                          _personRow(peoplePage.rows[i]),
                        ],
                      ]),
                    ),
                  if (visible.isNotEmpty)
                    pagerBar(
                      page: peoplePage.page,
                      pages: peoplePage.pages,
                      total: visible.length,
                      onPage: (p) => setState(() => _peoplePage = p),
                      onSize: (n) async {
                        await ListPaging.setSize(n);
                        setState(() => _peoplePage = 1);
                      },
                    ),
                  sectionTitle(widget.mineOnly ? "My payment history" : "Payment history"),
                  _filterCard(
                    _searchField(_historySearch, "Search payments"),
                    [
                      if (!widget.mineOnly) _pill(Icons.person_outline_rounded, _historyPerson, "all", {"all": "Everyone", for (final n in historyNames) n: n == s.userName ? "$n (You)" : n}, (v) => _historyPerson = v),
                      _periodPill(input, allHistory.map((h) => h.date)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (history.isEmpty)
                    ledgerCard(child: Center(child: Text("No payments match.", style: GoogleFonts.inter(color: kDark.withValues(alpha: 0.6)))))
                  else
                    Container(
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                      child: Column(children: [
                        for (var i = 0; i < historyPage.rows.length; i++) ...[
                          if (i > 0) const Divider(height: 1, color: Color(0xFFF1F5F9)),
                          InkWell(
                            onTap: s.canEditEntries && historyPage.rows[i].tx["type"] == "reimburse" ? () => _editPayment(historyPage.rows[i]) : null,
                            child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                            child: Row(children: [
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(historyPage.rows[i].name, style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: kDark)),
                                  const SizedBox(height: 2),
                                  Text(
                                    [
                                      dateLabel(historyPage.rows[i].date),
                                      historyPage.rows[i].how,
                                      if (historyPage.rows[i].method.isNotEmpty) historyPage.rows[i].method,
                                      if (historyPage.rows[i].reference.isNotEmpty) "Ref ${historyPage.rows[i].reference}",
                                      "by ${historyPage.rows[i].by}",
                                    ].join(" · "),
                                    style: GoogleFonts.inter(fontSize: 12, color: kDark.withValues(alpha: 0.6)),
                                  ),
                                ]),
                              ),
                              const SizedBox(width: 10),
                              Text(inr(historyPage.rows[i].amount), style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: kForest)),
                              if (s.canEditEntries && historyPage.rows[i].tx["type"] == "reimburse") ...[
                                const SizedBox(width: 6),
                                Icon(Icons.edit_rounded, size: 14, color: kDark.withValues(alpha: 0.35)),
                              ],
                            ]),
                          ),
                          ),
                        ],
                      ]),
                    ),
                  if (history.isNotEmpty)
                    pagerBar(
                      page: historyPage.page,
                      pages: historyPage.pages,
                      total: history.length,
                      onPage: (p) => setState(() => _historyPage = p),
                      onSize: (n) async {
                        await ListPaging.setSize(n);
                        setState(() => _historyPage = 1);
                      },
                    ),
                    ])),
                  ),
                ]),
              ),
      ),
    );
  }

  // ---- search + filter pills ----
  Widget _filterCard(Widget search, List<Widget> pills) => Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          search,
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (var i = 0; i < pills.length; i++) ...[if (i > 0) const SizedBox(width: 8), pills[i]],
            ]),
          ),
        ]),
      );

  Widget _searchField(TextEditingController controller, String hint) => SizedBox(
        height: 44,
        child: TextField(
          controller: controller,
          onChanged: (_) => setState(() {}),
          style: GoogleFonts.inter(fontSize: 14, color: kDark),
          textAlignVertical: TextAlignVertical.center,
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: const Color(0xFFF1F5F9),
            hintText: hint,
            hintStyle: GoogleFonts.inter(fontSize: 14, color: kDark.withValues(alpha: 0.45)),
            prefixIcon: Icon(Icons.search_rounded, size: 20, color: kDark.withValues(alpha: 0.5)),
            suffixIcon: controller.text.isEmpty
                ? null
                : IconButton(
                    icon: Icon(Icons.close_rounded, size: 18, color: kDark.withValues(alpha: 0.5)),
                    onPressed: () => setState(controller.clear),
                  ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kForest, width: 1.2)),
          ),
        ),
      );

  /// A rounded chip showing the current choice; green once it differs from the default.
  Widget _chip(IconData icon, String label, bool active) => Container(
        height: 36,
        padding: const EdgeInsets.only(left: 10, right: 6),
        decoration: BoxDecoration(
          color: active ? kForest.withValues(alpha: 0.08) : Colors.white,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: active ? kForest.withValues(alpha: 0.45) : const Color(0xFFE2E8F0)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: active ? kForest : kDark.withValues(alpha: 0.55)),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: Text(label,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: active ? kForest : kDark)),
          ),
          Icon(Icons.expand_more_rounded, size: 18, color: active ? kForest : kDark.withValues(alpha: 0.5)),
        ]),
      );

  Widget _pill(IconData icon, String value, String defaultValue, Map<String, String> options, ValueChanged<String> onChanged) => PopupMenuButton<String>(
        tooltip: "",
        position: PopupMenuPosition.under,
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onSelected: (v) => setState(() => onChanged(v)),
        itemBuilder: (_) => options.entries
            .map((e) => PopupMenuItem(
                  value: e.key,
                  height: 40,
                  child: Row(children: [
                    Expanded(
                      child: Text(e.value,
                          style: GoogleFonts.inter(fontSize: 14, fontWeight: e.key == value ? FontWeight.w700 : FontWeight.w500, color: e.key == value ? kForest : kDark)),
                    ),
                    if (e.key == value) const Icon(Icons.check_rounded, size: 18, color: kForest),
                  ]),
                ))
            .toList(),
        child: _chip(icon, options[value] ?? options.values.first, value != defaultValue),
      );

  String get _periodLabel {
    final from = _historyFrom, to = _historyTo;
    if (from.isEmpty && to.isEmpty) return "All time";
    final f = DateTime.tryParse(from), t = DateTime.tryParse(to);
    if (f != null && t != null) {
      if (from == to) return DateFormat("dd MMM yyyy").format(f);
      if (f.day == 1 && f.month == t.month && f.year == t.year && t.day == DateTime(t.year, t.month + 1, 0).day) return DateFormat("MMM yyyy").format(f);
      if (from.endsWith("-01-01") && to.endsWith("-12-31") && f.year == t.year) return "${f.year}";
      return "${DateFormat("dd MMM").format(f)} – ${DateFormat("dd MMM yyyy").format(t)}";
    }
    if (f != null) return "From ${DateFormat("dd MMM yyyy").format(f)}";
    return "Until ${DateFormat("dd MMM yyyy").format(t!)}";
  }

  // the Day / Month / Year / Custom picker lives in a small sheet behind the chip
  Widget _periodPill(InputDecoration input, Iterable<String> dates) => GestureDetector(
        onTap: () {
          var from = _historyFrom, to = _historyTo;
          showLedgerSheet(context, "Period", (ctx) => StatefulBuilder(builder: (ctx, set) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                PeriodFilter(
                  from: from,
                  to: to,
                  decoration: input,
                  labelWidth: 60,
                  dates: dates,
                  onChanged: (f, t) {
                    set(() {
                      from = f;
                      to = t;
                    });
                    setState(() {
                      _historyFrom = f;
                      _historyTo = t;
                    });
                  },
                ),
                const SizedBox(height: 16),
                primaryButton("Done", () => Navigator.pop(ctx)),
              ])));
        },
        child: _chip(Icons.calendar_today_rounded, _periodLabel, _historyFrom.isNotEmpty || _historyTo.isNotEmpty),
      );

  Widget _summaryTile({
    required String label,
    required String value,
    required String sub,
    Color? color,
    bool isSelected = false,
    VoidCallback? onTap,
  }) =>
      Container(
        width: 168,
        margin: const EdgeInsets.only(right: 10),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isSelected ? kForest : const Color(0xFFE2E8F0),
                  width: isSelected ? 2 : 1,
                ),
                boxShadow: isSelected
                    ? [BoxShadow(color: kForest.withValues(alpha: 0.12), blurRadius: 8, offset: const Offset(0, 2))]
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(label.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                              color: isSelected ? kForest : kDark.withValues(alpha: 0.55))),
                    ),
                    if (isSelected)
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(color: kForest, shape: BoxShape.circle),
                      ),
                  ]),
                  const SizedBox(height: 6),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(value, style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w800, color: color ?? kDark)),
                  ),
                  const SizedBox(height: 4),
                  Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 11, color: kDark.withValues(alpha: 0.55))),
                ],
              ),
            ),
          ),
        ),
      );


  Widget _personRow(_Person p) {
    final me = p.userId == s.userId;
    final roleColor = p.role == "admin"
        ? kForestDark
        : p.role == "manager"
            ? const Color(0xFF1D4ED8)
            : p.role == "staff"
                ? kForest
                : p.role.startsWith("role:")
                    ? const Color(0xFFB45309)
                    : kDark.withValues(alpha: 0.5);
    final meta = [
      p.claims > 0 ? "${inr(p.claims)} in approved claims" : p.owed > 0 ? "Paid out of pocket" : "Nothing owed",
      if (p.advance > 0) "holds ${inr(p.advance)} voucher money",
      if (me && p.owed > 0) 'pick "${s.userName} (You)" above to pay it',
    ].join(" · ");
    return InkWell(
      onTap: _payable(p) ? () => setState(() => _selected.contains(p.userId) ? _selected.remove(p.userId) : _selected.add(p.userId)) : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
        child: Row(children: [
          Checkbox(
            value: _selected.contains(p.userId) && _payable(p),
            onChanged: _payable(p) ? (_) => setState(() => _selected.contains(p.userId) ? _selected.remove(p.userId) : _selected.add(p.userId)) : null,
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, children: [
                Text("${p.name}${me ? " (you)" : ""}", style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: kDark)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: roleColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(99)),
                  child: Text(p.label,
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: roleColor)),
                ),
              ]),
              const SizedBox(height: 2),
              Text(meta, style: GoogleFonts.inter(fontSize: 12, color: kDark.withValues(alpha: 0.6))),
            ]),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(inr(p.owed), style: GoogleFonts.inter(fontWeight: FontWeight.w800, color: p.owed > 0 ? kTerracotta : kDark.withValues(alpha: 0.5))),
            if (p.owed > 0)
              Row(mainAxisSize: MainAxisSize.min, children: [
                TextButton(
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 6)),
                  onPressed: () => _showBills(p),
                  child: const Text("Bills"),
                ),
                if (_payable(p))
                  TextButton(
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 6)),
                    onPressed: () => _pay([p]),
                    child: const Text("Pay", style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
              ]),
          ]),
        ]),
      ),
    );
  }

  // One person's open bills, oldest first; all of them close when the full balance is paid.
  Future<void> _showBills(_Person p) async {
    var loading = true;
    var bills = <Map<String, dynamic>>[];
    num owed = p.owed;
    var started = false;
    await showLedgerSheet(context, p.name, (ctx) => StatefulBuilder(builder: (ctx, set) {
          if (!started) {
            started = true;
            LedgerService.payableBills(s.companyId, p.userId, s.userId).then((res) {
              if (!ctx.mounted) return;
              set(() {
                loading = false;
                bills = List<Map<String, dynamic>>.from(res["bills"] ?? const []);
                owed = (res["owed"] as num?) ?? p.owed;
              });
            });
          }
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text.rich(TextSpan(style: GoogleFonts.inter(fontSize: 13, color: kDark.withValues(alpha: 0.7)), children: [
              const TextSpan(text: "Company owes "),
              TextSpan(text: inr(owed), style: const TextStyle(color: kTerracotta, fontWeight: FontWeight.w800)),
            ])),
            BillsPreview(bills: bills, loading: loading, amount: owed),
            if (_payable(p)) ...[
              const SizedBox(height: 16),
              primaryButton("Pay…", () {
                Navigator.pop(ctx);
                _pay([p]);
              }),
            ],
          ]);
        }));
  }

  // Pays each person: the full balance is filled in and can be lowered to pay part of it.
  Future<void> _pay(List<_Person> people) async {
    var paidBy = "company";
    var fund = s.funds.first.id;
    var method = "UPI";
    var offset = false;
    final ref = TextEditingController();
    final amounts = {for (final p in people) p.userId: TextEditingController(text: _round(p.owed).toString())};
    final single = people.length == 1 ? people.first : null;
    var billsLoading = single != null;
    var bills = <Map<String, dynamic>>[];
    var started = false;
    final anyHeld = people.any((p) => p.advance > 0);

    num maxFor(_Person p) => _round(_max(0, p.owed - (offset ? _min(p.advance, p.owed) : 0)));
    num cashFor(_Person p) => _round(_max(0, num.tryParse(amounts[p.userId]!.text.trim()) ?? 0));
    num settledFor(_Person p) => _round(cashFor(p) + (offset ? _min(p.advance, _max(0, p.owed - cashFor(p))) : 0));

    await showLedgerSheet(context, single != null ? "Pay ${single.name}" : "Pay ${people.length} people", (ctx) => StatefulBuilder(builder: (ctx, set) {
          if (!started && single != null) {
            started = true;
            LedgerService.payableBills(s.companyId, single.userId, s.userId).then((res) {
              if (!ctx.mounted) return;
              set(() {
                billsLoading = false;
                bills = List<Map<String, dynamic>>.from(res["bills"] ?? const []);
              });
            });
          }
          final total = _round(people.fold<num>(0, (a, p) => a + cashFor(p)));
          final fullTotal = _round(people.fold<num>(0, (a, p) => a + maxFor(p)));
          final selectedFund = s.funds.firstWhere((f) => f.id == fund, orElse: () => s.funds.first);
          final short = paidBy == "company" && selectedFund.balance < total;
          final tooMuch = people.where((p) => cashFor(p) > maxFor(p) + 0.001).firstOrNull;
          final nothing = people.every((p) => !(cashFor(p) > 0) && !(offset && p.advance > 0));

          Widget choice(String value, String title, String sub) => Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => set(() => paidBy = value),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: paidBy == value ? kForest.withValues(alpha: 0.08) : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: paidBy == value ? kForest : const Color(0xFFE2E8F0), width: paidBy == value ? 1.5 : 1),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: kDark)),
                      const SizedBox(height: 2),
                      Text(sub, style: GoogleFonts.inter(fontSize: 12, color: kDark.withValues(alpha: 0.6))),
                    ]),
                  ),
                ),
              );

          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("The full balance is filled in. Lower any amount to pay part of it — the oldest bills close first and the rest stays owed.",
                style: GoogleFonts.inter(fontSize: 13, color: kDark.withValues(alpha: 0.65))),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE2E8F0)), borderRadius: BorderRadius.circular(12)),
              child: Column(children: [
                for (final p in people)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(p.name, style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: kDark)),
                          Builder(builder: (_) {
                            final over = cashFor(p) > maxFor(p) + 0.001;
                            final left = _round(p.owed - settledFor(p));
                            final fromHeld = offset && p.advance > 0 ? " · ${inr(_min(p.advance, _max(0, p.owed - cashFor(p))))} from voucher balance" : "";
                            return Text(
                              over ? "Owed only ${inr(maxFor(p))}" : (left > 0 ? "Part payment · ${inr(left)} stays owed" : "Clears all ${inr(p.owed)}") + fromHeld,
                              style: GoogleFonts.inter(fontSize: 12, color: over ? kTerracotta : kDark.withValues(alpha: 0.6)),
                            );
                          }),
                        ]),
                      ),
                      SizedBox(
                        width: 110,
                        child: TextField(
                          controller: amounts[p.userId],
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          textAlign: TextAlign.right,
                          onChanged: (_) => set(() {}),
                          decoration: fieldDecoration("0").copyWith(prefixText: "₹ ", isDense: true),
                        ),
                      ),
                      if (cashFor(p) != maxFor(p))
                        TextButton(
                          style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 6)),
                          onPressed: () => set(() => amounts[p.userId]!.text = maxFor(p).toString()),
                          child: const Text("Full"),
                        ),
                    ]),
                  ),
                const Divider(height: 1, color: Color(0xFFF1F5F9)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(children: [
                    Expanded(
                      child: Text(total != fullTotal ? "Total · full balance ${inr(fullTotal)}" : "Total",
                          style: GoogleFonts.inter(fontSize: 13, color: kDark.withValues(alpha: 0.7))),
                    ),
                    Text(inr(total), style: GoogleFonts.inter(fontWeight: FontWeight.w800, color: kDark)),
                  ]),
                ),
              ]),
            ),
            if (single != null) BillsPreview(bills: bills, loading: billsLoading, amount: settledFor(single)),
            const SizedBox(height: 14),
            Text("Paid by", style: labelStyle),
            const SizedBox(height: 6),
            Row(children: [
              choice("company", s.companyName, "From Cash or Bank"),
              const SizedBox(width: 8),
              choice("self", "Me (self)", "The company will owe you ${inr(total)}"),
            ]),
            if (paidBy == "company") ...[
              const SizedBox(height: 10),
              fundDropdown(s, fund, (v) => set(() => fund = v ?? "cash"), hint: "Paid from"),
              if (short)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text("Only ${inr(selectedFund.balance)} available in ${selectedFund.name}. You can add money when you pay.",
                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: kTerracotta)),
                ),
            ],
            const SizedBox(height: 10),
            methodChips(method, (m) => set(() => method = m)),
            const SizedBox(height: 10),
            TextField(controller: ref, decoration: fieldDecoration("Reference (optional) · UTR / cheque no.", icon: Icons.tag_rounded)),
            if (anyHeld)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: offset,
                onChanged: (v) => set(() {
                  offset = v == true;
                  // refill each amount with the new full figure; it can still be lowered afterwards
                  for (final p in people) {
                    amounts[p.userId]!.text = maxFor(p).toString();
                  }
                }),
                title: Text("Set off voucher money they hold", style: GoogleFonts.inter(fontSize: 13, color: kDark)),
                subtitle: Text("Their held voucher balance counts towards what they're owed, so less is paid now.", style: GoogleFonts.inter(fontSize: 12)),
              ),
            const SizedBox(height: 16),
            primaryButton(
              "Pay ${inr(total)}",
              tooMuch != null || nothing
                  ? null
                  : () async {
                      if (short && !await topUpFund(ctx, s, selectedFund, total)) return;
                      if (!ctx.mounted) return;
                      final failed = <String>[];
                      var paid = 0;
                      for (final p in people) {
                        if (!(cashFor(p) > 0) && !(offset && p.advance > 0)) continue; // left at ₹0: skip this person
                        final res = await LedgerService.reimburse({
                          "companyId": s.companyId,
                          "userId": s.userId,
                          "adminUserId": p.userId,
                          "amount": cashFor(p),
                          if (paidBy == "company") "fundId": fund,
                          "paidBy": paidBy,
                          "method": method,
                          "reference": ref.text.trim(),
                          "offsetAdvance": offset && p.advance > 0,
                        });
                        if (res["success"] == true) {
                          paid += 1;
                        } else {
                          failed.add("${p.name}: ${res["message"] ?? "failed"}");
                        }
                      }
                      if (!ctx.mounted) return;
                      if (failed.isNotEmpty) toast(ctx, "Not paid — ${failed.join("; ")}", error: true);
                      if (paid > 0) {
                        Navigator.pop(ctx);
                        if (mounted) toast(context, "$paid ${paid == 1 ? "person" : "people"} paid${paidBy == "self" ? " by you · the company now owes you ${inr(total)}" : ""}");
                        setState(_selected.clear);
                        notifyLedgerChanged();
                      }
                    },
            ),
          ]);
        }));
    ref.dispose();
    for (final c in amounts.values) {
      c.dispose();
    }
  }

  /// The Admin edits a payment: amount, the account it was paid from (company payments), method, reference, date &
  /// time and description. Balances and what the person is owed follow.
  Future<void> _editPayment(({String name, String how, num amount, String date, String by, String method, String reference, Map<String, dynamic> tx}) h) async {
    final t = h.tx;
    final company = !(t["memo"]?.toString() ?? "").endsWith("personally");
    final amount = TextEditingController(text: h.amount.toString());
    final reference = TextEditingController(text: h.reference);
    final note = TextEditingController(text: t["note"]?.toString() ?? "");
    String method = h.method;
    String? fund; // null = leave it where it is
    DateTime when = DateTime.tryParse(h.date)?.toLocal() ?? DateTime.now();
    final saved = await showLedgerSheet<bool>(context, "Edit payment", (ctx) => StatefulBuilder(builder: (ctx, set) {
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("To ${h.name} · ${h.how}", style: GoogleFonts.inter(fontSize: 13, color: kDark.withValues(alpha: 0.6))),
            const SizedBox(height: 10),
            TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: fieldDecoration("Amount ₹", icon: Icons.currency_rupee_rounded)),
            if (company) ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<String?>(
                initialValue: fund,
                isExpanded: true,
                decoration: fieldDecoration("Paid from", icon: Icons.account_balance_wallet_rounded),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text("Keep the same account")),
                  for (final f in s.funds) DropdownMenuItem<String?>(value: f.id, child: Text("${f.name} · ${inr(f.balance)}", overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => set(() => fund = v),
              ),
            ],
            const SizedBox(height: 10),
            methodChips(method, (m) => set(() => method = m)),
            const SizedBox(height: 10),
            TextField(controller: reference, decoration: fieldDecoration("Reference", icon: Icons.tag_rounded)),
            const SizedBox(height: 10),
            TextField(controller: note, decoration: fieldDecoration("Description (optional)", icon: Icons.notes_rounded)),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              icon: const Icon(Icons.event_rounded, size: 18),
              label: Text(DateFormat("dd MMM yyyy · h:mm a").format(when)),
              onPressed: () async {
                final d = await showDatePicker(context: ctx, initialDate: when, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 1)));
                if (d == null || !ctx.mounted) return;
                final tm = await showTimePicker(context: ctx, initialTime: TimeOfDay.fromDateTime(when));
                set(() => when = DateTime(d.year, d.month, d.day, tm?.hour ?? when.hour, tm?.minute ?? when.minute));
              },
            ),
            const SizedBox(height: 12),
            primaryButton("Save", () async {
              final v = double.tryParse(amount.text.trim()) ?? 0;
              if (!(v > 0)) return toast(ctx, "Enter an amount greater than zero", error: true);
              final res = await LedgerService.editAccountsEntry(s.companyId, s.userId, t["_id"].toString(), {
                "amount": v,
                "method": method,
                "reference": reference.text.trim(),
                "details": note.text.trim(),
                "date": DateFormat("yyyy-MM-dd'T'HH:mm").format(when),
                if (company && fund != null) "fundId": fund,
              });
              if (!ctx.mounted) return;
              if (handleResult(ctx, res, "Payment updated")) Navigator.pop(ctx, true);
            }),
          ]);
        }));
    if (saved == true && mounted) {
      notifyLedgerChanged();
      _load();
    }
  }
}
