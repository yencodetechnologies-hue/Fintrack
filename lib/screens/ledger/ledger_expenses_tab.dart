import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../services/ledger_service.dart';
import 'ledger_common.dart';
import 'ledger_fund_topup.dart';
import 'ledger_description_field.dart';
import 'ledger_expense_detail.dart';
import 'ledger_filters.dart';

/// Kept for screens that list categories without a company (older imports).
const List<String> kCategories = kBaseCategories;

String _dayKey(Map<String, dynamic> e) {
  final d = DateTime.tryParse((e["date"] ?? e["createdAt"])?.toString() ?? "")?.toLocal();
  return d == null ? "" : DateFormat("yyyy-MM-dd").format(d);
}

/// The company's expenses with the web's filters: status, search, posted by, day / month / year / custom.
class LedgerExpensesTab extends StatefulWidget {
  final LedgerScope scope;
  const LedgerExpensesTab({super.key, required this.scope});

  @override
  State<LedgerExpensesTab> createState() => _LedgerExpensesTabState();
}

class _LedgerExpensesTabState extends State<LedgerExpensesTab> with LedgerAutoRefresh, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  void onLedgerChanged() => _load(silent: true);

  @override
  Set<String> get ledgerTopics => const {"expenses", "balances"};

  LedgerScope get s => widget.scope;
  List<Map<String, dynamic>> _expenses = [];
  bool _loading = true;
  String? _error;
  num _myAdvance = 0;

  String _status = "All";
  final _search = TextEditingController();
  String _postedBy = "all"; // all | company | managers | staff | <userId>
  String _from = "";
  String _to = "";

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

  Future<void> _load({bool silent = false}) async {
    if (!silent && _expenses.isEmpty) setState(() => _loading = true);
    final r = await Future.wait([
      LedgerService.expenses(s.companyId, s.userId),
      if (!s.isAdmin) LedgerService.balances(s.companyId, s.userId),
    ]);
    if (!mounted) return;
    setState(() {
      if (r[0]["success"] == true) {
        _expenses = List<Map<String, dynamic>>.from(r[0]["expenses"] ?? const []);
        _error = null;
      } else if (_expenses.isEmpty) {
        _error = r[0]["message"]?.toString() ?? "Could not load expenses. Please try again.";
      }
      if (!s.isAdmin) _myAdvance = (r[1]["myAdvance"] as num?) ?? 0;
      _loading = false;
    });
  }

  List<Map<String, dynamic>> get _filtered {
    final managerIds = s.admins.map((m) => m["userId"].toString()).toSet();
    final q = _search.text.trim().toLowerCase();
    return _expenses.where((e) {
      if (_status != "All") {
        if (_status == "Verify" ? e["verification"] != "pending" : e["lifecycle"] != _status.toLowerCase()) return false;
      }
      final companyPost = e["logAs"] == "company" || e["postedAs"] == "company";
      final creator = idOf(e["createdBy"]);
      if (_postedBy == "company" && !companyPost) return false;
      if (_postedBy == "managers" && (companyPost || !managerIds.contains(creator))) return false;
      if (_postedBy == "staff" && (companyPost || managerIds.contains(creator))) return false;
      if (!{"all", "company", "managers", "staff"}.contains(_postedBy) && (companyPost || creator != _postedBy)) return false;
      if (q.isNotEmpty) {
        final hay = "${e["description"]} ${e["category"]} ${postedByName(e, s.companyName)} ${e["amount"]}".toLowerCase();
        if (!hay.contains(q)) return false;
      }
      final k = _dayKey(e);
      if (_from.isNotEmpty && k.compareTo(_from) < 0) return false;
      if (_to.isNotEmpty && k.compareTo(_to) > 0) return false;
      return true;
    }).toList()
      ..sort((a, b) => _dayKey(b).compareTo(_dayKey(a)));
  }

  bool get _filtering => _search.text.isNotEmpty || _from.isNotEmpty || _to.isNotEmpty || _status != "All" || _postedBy != "all";

  void _reset() {
    setState(() {
      _search.clear();
      _status = "All";
      _postedBy = "all";
      _from = "";
      _to = "";
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final list = _filtered;
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final e in list) {
      groups.putIfAbsent(_dayKey(e), () => []).add(e);
    }

    return Scaffold(
      backgroundColor: kForest,
      floatingActionButton: !s.can("post_expenses") ? null : FloatingActionButton.extended(
        heroTag: "post-expense-expenses",
        backgroundColor: kForestDark,
        onPressed: () => showPostExpenseSheet(context, s, existing: _expenses, advance: _myAdvance),
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: Text("Post Expense", style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: ["All", "Submitted", "Approved", if (s.isAdmin) "Verify"]
                          .map((f) => Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(f),
                                  selected: _status == f,
                                  selectedColor: Colors.white,
                                  backgroundColor: kForestDark,
                                  showCheckmark: false,
                                  labelStyle: GoogleFonts.inter(color: _status == f ? kForest : Colors.white, fontWeight: FontWeight.w700),
                                  onSelected: (_) => setState(() => _status = f),
                                ),
                              ))
                          .toList(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _filterCard(),
                  // total of everything the filters show (dates, period, search, status, posted by)
                  if (list.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(children: [
                        Text("${list.length} ${list.length == 1 ? "expense" : "expenses"} · Total",
                            style: GoogleFonts.inter(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.w600)),
                        const Spacer(),
                        Text(inr(list.fold<num>(0, (sum, e) => sum + ((e["amount"] as num?) ?? 0))),
                            style: GoogleFonts.inter(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                      ]),
                    ),
                  if (_error != null)
                    Column(children: [
                      const SizedBox(height: 40),
                      Text(_error!, textAlign: TextAlign.center, style: GoogleFonts.inter(color: Colors.white)),
                      TextButton.icon(onPressed: _load, icon: const Icon(Icons.refresh_rounded, color: Colors.white), label: const Text("Retry", style: TextStyle(color: Colors.white))),
                    ])
                  else if (list.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 30),
                      child: Column(children: [
                        Text(
                          _expenses.isEmpty ? (s.isAdmin ? "No expenses yet." : "You haven't posted any expenses yet.") : "No expenses match your search or filters.",
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(color: Colors.white70),
                        ),
                        if (_filtering) TextButton(onPressed: _reset, child: const Text("Reset filters", style: TextStyle(color: Colors.white))),
                      ]),
                    )
                  else
                    ...groups.entries.map((g) => _group(g.key, g.value)),
                ],
              ),
            ),
    );
  }

  Widget _filterCard() {
    final postedBy = <String, String>{
      "all": "Everyone",
      "company": "${s.companyName} (company)",
      "managers": "All ${s.managersName.toLowerCase()}",
      "staff": "All ${s.staffsName.toLowerCase()}",
      for (final m in s.admins) m["userId"].toString(): "${s.managerName} · ${m["name"]}",
      for (final m in s.staff) m["userId"].toString(): "${s.staffName} · ${m["name"]}",
    };
    return filterCard(
      margin: const EdgeInsets.only(bottom: 12),
      search: FilterSearchField(controller: _search, hint: "Search description, staff, amount", onChanged: () => setState(() {})),
      pills: [
        filterPill(
          icon: Icons.person_outline_rounded,
          value: postedBy.containsKey(_postedBy) ? _postedBy : "all",
          defaultValue: "all",
          options: postedBy,
          onSelected: (v) => setState(() => _postedBy = v),
          label: _postedBy == "all" ? "Posted by: Everyone" : null,
        ),
        periodPill(
          context,
          from: _from,
          to: _to,
          dates: _expenses.map(_dayKey),
          onChanged: (from, to) => setState(() {
            _from = from;
            _to = to;
          }),
        ),
      ],
      onClear: _filtering ? _reset : null,
    );
  }

  Widget _group(String key, List<Map<String, dynamic>> items) {
    final total = items.fold<num>(0, (sum, e) => sum + ((e["amount"] as num?) ?? 0));
    final d = DateTime.tryParse(key);
    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));
    bool same(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
    final label = d == null
        ? "Undated"
        : same(d, now)
            ? "Today · ${DateFormat("dd MMM yyyy").format(d)}"
            : same(d, yesterday)
                ? "Yesterday · ${DateFormat("dd MMM yyyy").format(d)}"
                : DateFormat("dd MMM yyyy").format(d);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(0, 10, 0, 8),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.calendar_today_rounded, size: 12, color: Colors.white),
              const SizedBox(width: 5),
              Text(label, style: GoogleFonts.inter(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700)),
            ]),
          ),
          const Spacer(),
          Text("${items.length} ${items.length == 1 ? "expense" : "expenses"} · ${inr(total)}",
              style: GoogleFonts.inter(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w600)),
        ]),
      ),
      Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: Color(0xFFF1F5F9)),
            _row(items[i]),
          ],
        ]),
      ),
    ]);
  }

  Widget _row(Map<String, dynamic> e) {
    final lifecycle = e["lifecycle"]?.toString();
    final hasReceipt = e["hasAttachment"] == true || e["hasPaymentReceipt"] == true;
    Widget? action;
    if (s.isAdmin && lifecycle == "submitted") {
      if (s.can("approve_expenses")) {
        action = _quick("Approve", () async {
          final res = await LedgerService.approve(e["_id"].toString(), s.userId);
          if (!mounted) return;
          if (handleResult(context, res, "Expense approved")) notifyLedgerChanged();
        });
      }
    } else if (canMarkReceived(s, e)) {
      action = _quick("✓ Mark received", () => showReceivedSheet(context, s, e));
    } else if (lifecycle == "approved" && payerOptions(s, e).isNotEmpty) {
      action = _quick("Pay", () => showPaySheet(context, s, e));
    }
    return InkWell(
      onTap: () => showExpenseDetail(context, s, e),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Text(e["description"]?.toString() ?? "Expense",
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: kDark)),
            ),
            const SizedBox(width: 10),
            Text(inr(e["amount"]), style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: kDark)),
          ]),
          const SizedBox(height: 2),
          Text(
            "${e["category"] ?? "General"} · ${postedByName(e, s.companyName)} · ${dateLabel(e["date"] ?? e["createdAt"])}${hasReceipt ? " · 📎 Receipt" : ""}",
            style: GoogleFonts.inter(fontSize: 12, color: kDark.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 6),
          Row(children: [
            Container(width: 6, height: 6, decoration: BoxDecoration(color: statusTone(lifecycle), shape: BoxShape.circle)),
            const SizedBox(width: 5),
            Expanded(
              child: Text(expenseStatusLabel(e, s.companyName),
                  style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600, color: kDark.withValues(alpha: 0.65))),
            ),
            if (action != null) action,
          ]),
        ]),
      ),
    );
  }

  Widget _quick(String label, VoidCallback onTap) => SizedBox(
        height: 30,
        child: ElevatedButton(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: kForest,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: Text(label, style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.bold)),
        ),
      );
}

/// Post a new expense: the web's Add Expense form for both roles.
Future<void> showPostExpenseSheet(BuildContext context, LedgerScope s,
    {List<Map<String, dynamic>> existing = const [], num advance = 0, VoidCallback? onDone}) async {
  final amount = TextEditingController();
  final desc = TextEditingController();
  final newCategory = TextEditingController();
  final added = <String>[];
  String category = "General";
  DateTime date = DateTime.now();
  String receipt = "";
  String postAs = "self";
  String fund = "cash";
  bool useAdvance = false;
  // "Paid from" → Borrowed from another company (same as the web): the lender, or a new outside company
  const borrow = "__borrow__", outside = "__outside__";
  List<Map<String, dynamic>>? lenders; // loaded the first time Borrowed is picked
  String? lenderId;
  final outsideName = TextEditingController();
  final outsideGstin = TextEditingController();
  final hidden = s.hiddenStaffIds.toSet();
  final visibleTo = s.members.map((m) => m["userId"].toString()).where((id) => !hidden.contains(id)).toSet();

  Future<void> submit(BuildContext ctx, {bool confirmDuplicate = false}) async {
    final amt = double.tryParse(amount.text.trim()) ?? 0;
    if (!(amt > 0) || desc.text.trim().isEmpty) return toast(ctx, "Enter a valid amount and description", error: true);
    // "co:<companyId>:<fundId>" = another company I run pays it (booked as borrowed from that company)
    final other = fund.startsWith("co:") ? fund.split(":") : null;
    final isBorrow = s.isAdmin && postAs == "company" && (fund == borrow || other != null);
    if (isBorrow && other == null) {
      if (lenderId == null) return toast(ctx, "Choose the company you borrowed from", error: true);
      if (lenderId == outside && (outsideName.text.trim().isEmpty || outsideGstin.text.trim().isEmpty)) {
        return toast(ctx, "Enter the outside company's name and GSTIN", error: true);
      }
    }
    final res = await LedgerService.createExpense({
      if (other != null) ...{"sourceCompanyId": other[1], "sourceFundId": other[2]},
      if (isBorrow && other == null && lenderId == outside) "newCompany": {"name": outsideName.text.trim(), "gstin": outsideGstin.text.trim().toUpperCase()},
      if (isBorrow && other == null && lenderId != outside) "sourceCompanyId": lenderId,
      "companyId": s.companyId,
      "userId": s.userId,
      "amount": amt,
      "description": desc.text.trim(),
      "category": category,
      "date": date.toIso8601String(),
      "attachment": receipt,
      "visibleTo": visibleTo.toList(),
      "postAs": isBorrow ? "borrow" : s.isAdmin ? postAs : "self",
      if (s.isAdmin && postAs == "company" && !isBorrow) "fundId": fund,
      "checkDuplicate": true,
      "confirmDuplicate": confirmDuplicate,
      "useAdvance": !s.isAdmin && advance > 0 && useAdvance,
    });
    if (!ctx.mounted) return;
    if (res["code"] == "DUPLICATE_EXPENSE") {
      final d = res["duplicate"] is Map ? res["duplicate"] as Map : const {};
      final again = await confirmDialog(
        ctx,
        "Duplicate expense?",
        "An expense \"${d["description"] ?? desc.text.trim()}\" for ${inr(d["amount"] ?? amt)} already exists"
            "${d["createdBy"] is Map ? " (posted by ${d["createdBy"]["name"]})" : ""}"
            "${(d["date"] ?? d["createdAt"]) != null ? " on ${dateLabel(d["date"] ?? d["createdAt"])}" : ""}. Post it again anyway?",
        confirmLabel: "Post anyway",
      );
      if (again && ctx.mounted) await submit(ctx, confirmDuplicate: true);
      return;
    }
    if (handleResult(ctx, res, res["awaitingConfirmation"] == true ? "Expense added · sent to the lender company to confirm" : "Expense added successfully!")) {
      Navigator.pop(ctx);
      notifyLedgerChanged();
      onDone?.call();
    }
  }

  await showLedgerSheet(context, "Add Expense", (ctx) => StatefulBuilder(builder: (ctx, set) {
        final amt = double.tryParse(amount.text.trim()) ?? 0;
        final options = {...companyCategories(s.company), ...added}.toList();
        final selectedFund = s.funds.firstWhere((f) => f.id == fund, orElse: () => s.funds.first);
        // another company I run pays it ("co:<companyId>:<fundId>"), booked as borrowed from that company
        final otherCo = fund.startsWith("co:")
            ? s.managedOtherCompanies.where((c) => c["_id"].toString() == fund.split(":")[1]).firstOrNull
            : null;
        final isBorrow = s.isAdmin && postAs == "company" && (fund == borrow || otherCo != null);
        // borrowed money doesn't come out of this company's own funds
        final insufficient = s.isAdmin && postAs == "company" && !isBorrow && amt > 0 && selectedFund.balance < amt;
        final dup = amt > 0 && desc.text.trim().isNotEmpty
            ? existing
                .where((x) =>
                    x["lifecycle"] != "rejected" &&
                    ((x["amount"] as num?) ?? 0) == amt &&
                    (x["description"]?.toString() ?? "").trim().toLowerCase() == desc.text.trim().toLowerCase())
                .firstOrNull
            : null;

        Future<void> addCategory() async {
          final name = newCategory.text.trim();
          if (name.isEmpty) return;
          final match = options.where((c) => c.toLowerCase() == name.toLowerCase()).firstOrNull;
          set(() {
            if (match == null) added.add(name);
            category = match ?? name;
            newCategory.clear();
          });
          if (match != null) return;
          final res = await LedgerService.addCategory(s.companyId, s.userId, name);
          if (res["success"] != true && ctx.mounted) toast(ctx, res["message"]?.toString() ?? "Category will be saved with the expense", error: true);
        }

        void toggleMember(String id) {
          set(() => visibleTo.contains(id) ? visibleTo.remove(id) : visibleTo.add(id));
          final hiddenNow = s.members.map((m) => m["userId"].toString()).where((m) => !visibleTo.contains(m)).toList();
          LedgerService.saveVisibilityPreference(s.companyId, s.userId, hiddenNow).then((res) {
            if (res["success"] != true && ctx.mounted) toast(ctx, res["message"]?.toString() ?? "Couldn't save your visibility choice", error: true);
          });
        }

        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text("Record a new expense for ${s.companyName}", style: GoogleFonts.inter(fontSize: 12.5, color: kDark.withValues(alpha: 0.6))),
          const SizedBox(height: 12),
          if (s.isAdmin && s.can("post_as_company")) ...[
            Text("Post expense as", style: labelStyle),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: "self", label: Text("${s.myRoleLabel} (Self)"), icon: const Icon(Icons.person_outline_rounded, size: 16)),
                const ButtonSegment(value: "company", label: Text("Company"), icon: Icon(Icons.business_rounded, size: 16)),
              ],
              selected: {postAs},
              onSelectionChanged: (v) => set(() => postAs = v.first),
            ),
            const SizedBox(height: 6),
            Text(postAs == "company" ? "Paid straight from ${s.companyName}'s Cash or Bank." : "Logged under your account as payable to you.",
                style: GoogleFonts.inter(fontSize: 12, color: kDark.withValues(alpha: 0.6))),
            if (postAs == "company") ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: fund,
                isExpanded: true,
                decoration: fieldDecoration("Paid from", icon: Icons.account_balance_rounded),
                items: [
                  ...s.funds.map((f) => DropdownMenuItem(value: f.id, child: Text("${f.name} · ${inr(f.balance)}", overflow: TextOverflow.ellipsis))),
                  // my other companies' Cash/Bank: paying from one books it as borrowed from that company
                  if (s.can("intercompany"))
                    for (final c in s.managedOtherCompanies) ...[
                      DropdownMenuItem(
                        value: "co:${c["_id"]}:cash",
                        child: Text("${c["name"]} · ${c["cashAccountName"] ?? "Cash"} · ${inr(c["cashBalance"] ?? 0)}", overflow: TextOverflow.ellipsis),
                      ),
                      for (final b in List<Map<String, dynamic>>.from(c["bankAccounts"] ?? const []))
                        DropdownMenuItem(
                          value: "co:${c["_id"]}:${b["_id"]}",
                          child: Text("${c["name"]} · ${bankLabel(b)} · ${inr(b["balance"] ?? 0)}", overflow: TextOverflow.ellipsis),
                        ),
                    ],
                  if (s.can("intercompany")) const DropdownMenuItem(value: borrow, child: Text("Borrowed from another company…")),
                ],
                onChanged: (v) {
                  set(() => fund = v ?? "cash");
                  if (v == borrow && lenders == null) {
                    LedgerService.borrowSources(s.companyId, s.userId).then((r) {
                      if (ctx.mounted) {
                        set(() => lenders = List<Map<String, dynamic>>.from(r["companies"] ?? const [])
                            .where((c) => c["_id"].toString() != s.companyId)
                            .toList());
                      }
                    });
                  }
                },
              ),
              if (otherCo != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text("${otherCo["name"]} pays this, so ${s.companyName} borrows ${amt > 0 ? inr(amt) : "the amount"} from it. It shows under Borrowed here and Lent there until repaid.",
                      style: GoogleFonts.inter(fontSize: 11.5, color: kDark.withValues(alpha: 0.6))),
                ),
              if (fund == borrow) ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: lenderId,
                  isExpanded: true,
                  decoration: fieldDecoration(lenders == null ? "Loading companies…" : "Lender company *", icon: Icons.business_rounded),
                  items: [
                    ...(lenders ?? const []).map((c) => DropdownMenuItem(value: c["_id"].toString(), child: Text(c["name"].toString(), overflow: TextOverflow.ellipsis))),
                    const DropdownMenuItem(value: outside, child: Text("An outside company…")),
                  ],
                  onChanged: (v) => set(() => lenderId = v),
                ),
                if (lenderId == outside) ...[
                  const SizedBox(height: 8),
                  TextField(controller: outsideName, decoration: fieldDecoration("Company name *", icon: Icons.business_rounded)),
                  const SizedBox(height: 8),
                  TextField(controller: outsideGstin, textCapitalization: TextCapitalization.characters, decoration: fieldDecoration("GSTIN *", icon: Icons.badge_rounded)),
                ],
                const SizedBox(height: 6),
                Text("${s.companyName} borrows ${amt > 0 ? inr(amt) : "the amount"} from this company to pay the expense; it shows under Borrowed until repaid. A registered company you don't manage confirms it first.",
                    style: GoogleFonts.inter(fontSize: 11.5, color: kDark.withValues(alpha: 0.6))),
              ],
              if (insufficient)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text("Insufficient balance: ${inr(selectedFund.balance)} available. You can add money when you submit.",
                      style: GoogleFonts.inter(color: kTerracotta, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
            ],
            const SizedBox(height: 12),
          ],
          Row(children: [
            Expanded(
              child: TextField(
                controller: amount,
                onChanged: (_) => set(() {}),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: fieldDecoration("Amount ₹ *", icon: Icons.currency_rupee_rounded),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: InkWell(
                onTap: () async {
                  final picked = await showDatePicker(context: ctx, initialDate: date, firstDate: DateTime(2020), lastDate: DateTime.now());
                  if (picked != null) set(() => date = picked);
                },
                child: InputDecorator(decoration: fieldDecoration("Date", icon: Icons.calendar_today_rounded), child: Text(DateFormat("dd MMM yyyy").format(date))),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          // opens the category sheet (search + chips; typing a new name offers "+ Add")
          categoryField(category, () async {
            final pick = await pickCategory(ctx, options, category);
            if (pick == null) return;
            if (pick.isNew) {
              newCategory.text = pick.name;
              await addCategory();
            } else {
              set(() => category = pick.name);
            }
          }),
          const SizedBox(height: 10),
          DescriptionField(
            companyId: s.companyId,
            userId: s.userId,
            kind: "expense",
            controller: desc,
            onChanged: (_) => set(() {}),
            hint: "Description / Purpose *",
          ),
          if (dup != null)
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: const Color(0xFFFFF7ED), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFFED7AA))),
              child: Text(
                "⚠️ Possible duplicate: \"${dup["description"]}\" for ${inr(dup["amount"])} was already posted"
                "${dup["createdBy"] is Map ? " by ${dup["createdBy"]["name"]}" : ""} on ${dateLabel(dup["date"] ?? dup["createdAt"])}.",
                style: GoogleFonts.inter(color: const Color(0xFFC2410C), fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          if (!s.isAdmin && advance > 0)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: useAdvance,
              onChanged: (v) => set(() => useAdvance = v == true),
              title: Text("Use my voucher balance (${inr(advance)})", style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13.5, color: kDark)),
              subtitle: Text(
                amt > 0
                    ? (amt > advance ? "${inr(advance)} from your balance, company owes you ${inr(amt - advance)}." : "All ${inr(amt)} comes from your balance.")
                    : "Taken from your balance when a manager approves this expense.",
                style: GoogleFonts.inter(fontSize: 12),
              ),
            ),
          if (s.isAdmin && s.members.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text("Visible to", style: labelStyle),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: s.members.map((m) {
                final id = m["userId"].toString();
                return FilterChip(
                  label: Text("${m["name"]}${id == s.userId ? " (You)" : ""}"),
                  selected: visibleTo.contains(id),
                  onSelected: (_) => toggleMember(id),
                  selectedColor: kForest.withValues(alpha: 0.12),
                  checkmarkColor: kForest,
                );
              }).toList(),
            ),
            Text("Choose which staff can view this expense in their list.", style: GoogleFonts.inter(fontSize: 11.5, color: kDark.withValues(alpha: 0.55))),
          ],
          const SizedBox(height: 10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: kForest, side: const BorderSide(color: kForest)),
            onPressed: () async {
              final img = await pickReceiptImage(ctx);
              if (img != null) set(() => receipt = img);
            },
            icon: Icon(receipt.isEmpty ? Icons.photo_camera_rounded : Icons.check_circle_rounded),
            label: Text(receipt.isEmpty ? "Receipt / attachment (optional)" : "Receipt selected · tap to replace"),
          ),
          if (receipt.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(children: [
                ClipRRect(borderRadius: BorderRadius.circular(8), child: SizedBox(width: 56, height: 56, child: dataImage(receipt, fit: BoxFit.cover))),
                TextButton(onPressed: () => set(() => receipt = ""), child: const Text("Remove")),
              ]),
            ),
          const SizedBox(height: 16),
          primaryButton(insufficient ? "Add money & submit" : "Submit Expense", () async {
            if (!(amt > 0) || desc.text.trim().isEmpty) return toast(ctx, "Enter a valid amount and description", error: true);
            if (insufficient && !await topUpFund(ctx, s, selectedFund, amt)) return;
            if (!ctx.mounted) return;
            await submit(ctx);
          }),
        ]);
      }));
}
