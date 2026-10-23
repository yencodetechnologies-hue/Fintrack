import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../services/ledger_service.dart';
import 'ledger_common.dart';
import 'ledger_expense_detail.dart' show dataImage, showImageViewer;

/// Inter-company: payment confirmations, balances with other companies, loans (web's Inter-co tab).
class LedgerIntercoTab extends StatefulWidget {
  final LedgerScope scope;
  const LedgerIntercoTab({super.key, required this.scope});

  @override
  State<LedgerIntercoTab> createState() => _LedgerIntercoTabState();
}

class _LedgerIntercoTabState extends State<LedgerIntercoTab> with LedgerAutoRefresh {
  @override
  void onLedgerChanged() => _load();

  @override
  Set<String> get ledgerTopics => const {"loans", "balances", "expenses"};

  LedgerScope get s => widget.scope;
  List<Map<String, dynamic>> _sources = [];
  List<Map<String, dynamic>> _loans = [];
  List<Map<String, dynamic>> _balances = [];
  List<Map<String, dynamic>> _requests = [];
  final Map<String, String> _requestFunds = {};
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
      LedgerService.intercompanyBalances(s.companyId, s.userId),
      s.isAdmin ? LedgerService.payerConfirmations(s.companyId, s.userId) : Future.value(<String, dynamic>{"expenses": <dynamic>[]}),
    ]);
    if (!mounted) return;
    setState(() {
      _sources = List<Map<String, dynamic>>.from(r[0]["companies"] ?? const []);
      _loans = List<Map<String, dynamic>>.from(r[1]["loans"] ?? const []);
      _balances = List<Map<String, dynamic>>.from(r[2]["balances"] ?? const []);
      _requests = List<Map<String, dynamic>>.from(r[3]["expenses"] ?? const []);
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
          if (s.isAdmin && s.can("intercompany"))
            Row(children: [
              Expanded(child: _headerButton("Routed payment to manager", Icons.alt_route_rounded, _openRouted, outlined: true)),
              const SizedBox(width: 8),
              Expanded(child: _headerButton("Borrow from a company", Icons.handshake_rounded, _openLoan)),
            ]),
          if (s.isAdmin && s.can("intercompany") && _requests.isNotEmpty) ...[
            sectionTitle("Payment confirmations"),
            ..._requests.map(_requestCard),
          ],
          sectionTitle("Company balances"),
          if (_balances.isEmpty) _emptyCard("No inter-company balances yet."),
          if (_balances.isNotEmpty)
            _listCard(_balances.map((b) {
              final net = (b["net"] as num?) ?? 0;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(b["name"]?.toString() ?? "Company", style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: kDark)),
                      Text.rich(TextSpan(children: [
                        TextSpan(text: net > 0 ? "They owe this company" : net < 0 ? "This company owes them" : "Settled"),
                        if (b["mismatch"] == true) const TextSpan(text: " · Balance mismatch", style: TextStyle(color: kTerracotta, fontWeight: FontWeight.w600)),
                      ]), style: GoogleFonts.inter(fontSize: 12, color: kDark.withValues(alpha: 0.6))),
                    ]),
                  ),
                  Text(inr(net.abs()),
                      style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: net < 0 ? kTerracotta : net > 0 ? kForest : kDark.withValues(alpha: 0.5))),
                ]),
              );
            }).toList()),
          sectionTitle("Company loans"),
          if (_loans.isEmpty) _emptyCard("No company loans yet."),
          if (_loans.isNotEmpty) _listCard(_loans.map(_loanRow).toList()),
        ],
      ),
    );
  }

  Widget _headerButton(String label, IconData icon, VoidCallback onTap, {bool outlined = false}) => Material(
        color: outlined ? Colors.transparent : kForestDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: outlined ? const BorderSide(color: Colors.white54) : BorderSide.none),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, color: kMint, size: 18),
              const SizedBox(width: 6),
              Flexible(child: Text(label, textAlign: TextAlign.center, style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12.5))),
            ]),
          ),
        ),
      );

  Widget _emptyCard(String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
        child: Text(text, style: GoogleFonts.inter(color: kDark.withValues(alpha: 0.6), fontSize: 13)),
      );

  Widget _listCard(List<Widget> rows) => Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          for (var i = 0; i < rows.length; i++) ...[if (i > 0) const Divider(height: 1, color: Color(0xFFF1F5F9)), rows[i]],
        ]),
      );

  Widget _requestCard(Map<String, dynamic> e) {
    final id = e["_id"].toString();
    final fund = _requestFunds[id] ?? "cash";
    return ledgerCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(e["description"]?.toString() ?? "Expense", style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: kDark))),
          Text(inr(e["amount"]), style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: kDark)),
        ]),
        Text("${nameOf(e["companyId"], "Another company")} asks ${s.companyName} to pay · ${dateLabel(e["createdAt"])}",
            style: GoogleFonts.inter(fontSize: 12, color: kDark.withValues(alpha: 0.6))),
        const SizedBox(height: 10),
        fundDropdown(s, fund, (v) => setState(() => _requestFunds[id] = v ?? "cash"), hint: "Paid from"),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: () => _respond(e, false), child: const Text("Reject"))),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: kForest, foregroundColor: Colors.white),
              onPressed: () => _respond(e, true),
              child: const Text("Accept"),
            ),
          ),
        ]),
      ]),
    );
  }

  Future<void> _respond(Map<String, dynamic> e, bool accept) async {
    final id = e["_id"].toString();
    final res = await LedgerService.confirmPayer(id, s.userId, accept, fundId: accept ? (_requestFunds[id] ?? "cash") : null);
    if (!mounted) return;
    if (handleResult(context, res, accept ? "Payment confirmed and loan recorded" : "Payment declined")) notifyLedgerChanged();
  }

  Widget _loanRow(Map<String, dynamic> loan) {
    final weBorrowed = idOf(loan["borrowerCompanyId"]) == s.companyId;
    final lender = nameOf(loan["lenderCompanyId"], "Another company");
    final borrower = nameOf(loan["borrowerCompanyId"], "Another company");
    final balance = (loan["balance"] as num?) ?? 0;
    final repaid = (loan["repaid"] as num?) ?? 0;
    final open = balance > 0;
    final canReceive = s.isAdmin && s.can("intercompany") && !weBorrowed && open && !isExternal(loan["borrowerCompanyId"]);
    final source = loan["source"] == "expense" ? "Paid an expense" : loan["source"] == "group" ? "Paid a group's expenses" : "Direct loan";
    return InkWell(
      onTap: () => showLoanDetail(context, s, loan, onRepay: _openRepay, onReceive: _openReceive),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _tag(weBorrowed ? "Borrowed" : "Lent", weBorrowed),
            const SizedBox(width: 6),
            Expanded(child: Text("$lender → $borrower", style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: kDark))),
            Text(open ? "${inr(balance)} due" : "Repaid", style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: open ? kTerracotta : kDark.withValues(alpha: 0.5))),
          ]),
          const SizedBox(height: 3),
          Text(
            "$source · ${dateLabel(loan["createdAt"])} · Original ${inr(loan["amount"])}${repaid > 0 ? " · Repaid ${inr(repaid)}" : ""}${(loan["note"]?.toString() ?? "").isNotEmpty ? " · ${loan["note"]}" : ""}",
            style: GoogleFonts.inter(fontSize: 12, color: kDark.withValues(alpha: 0.6)),
          ),
          if ((s.isAdmin && s.can("intercompany") && weBorrowed && open) || canReceive || canDeleteLoan(s, loan))
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(spacing: 6, children: [
                if (canDeleteLoan(s, loan))
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: kTerracotta, side: const BorderSide(color: kTerracotta)),
                    onPressed: () => deleteLoanFlow(context, s, loan),
                    child: const Text("Delete"),
                  ),
                if (s.isAdmin && s.can("intercompany") && weBorrowed && open)
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: kForest, side: const BorderSide(color: kForest)),
                    onPressed: () => _openRepay(loan),
                    child: const Text("Repay"),
                  ),
                if (canReceive)
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: kForest, side: const BorderSide(color: kForest)),
                    onPressed: () => _openReceive(loan),
                    child: const Text("Received"),
                  ),
              ]),
            ),
        ]),
      ),
    );
  }

  Widget _companyPicker(String? value, ValueChanged<String?> onChanged, String label) => _sources.isEmpty
      ? Text("No other companies yet.", style: GoogleFonts.inter(color: kTerracotta, fontSize: 12.5))
      : DropdownButtonFormField<String>(
          initialValue: value,
          isExpanded: true,
          decoration: fieldDecoration(label, icon: Icons.business_rounded),
          items: _sources.map((c) => DropdownMenuItem(value: c["_id"].toString(), child: Text(c["name"].toString()))).toList(),
          onChanged: onChanged,
        );

  void _openLoan() {
    String? lender;
    String fund = "cash";
    String method = "UPI";
    final amount = TextEditingController();
    final ref = TextEditingController();
    final note = TextEditingController();
    showLedgerSheet(context, "Borrow from a company", (ctx) => StatefulBuilder(builder: (ctx, set) {
          final lenderName = _sources.where((c) => c["_id"].toString() == lender).firstOrNull?["name"];
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _companyPicker(lender, (v) => set(() => lender = v), "Lender company"),
            const SizedBox(height: 6),
            Text("${lenderName ?? "Lender company"} → ${s.companyName}. The amount is added to the fund you pick below and shows as owed to the lender.",
                style: GoogleFonts.inter(fontSize: 12, color: kDark.withValues(alpha: 0.6))),
            const SizedBox(height: 10),
            TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: fieldDecoration("Amount ₹", icon: Icons.currency_rupee_rounded)),
            const SizedBox(height: 10),
            fundDropdown(s, fund, (v) => set(() => fund = v ?? "cash"), hint: "Receive into (${s.companyName})"),
            const SizedBox(height: 10),
            methodChips(method, (m) => set(() => method = m)),
            const SizedBox(height: 10),
            TextField(controller: ref, decoration: fieldDecoration("Reference (optional)", icon: Icons.tag_rounded)),
            const SizedBox(height: 10),
            TextField(
              controller: note,
              maxLength: 200,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: fieldDecoration("Reason for borrowing (optional)", icon: Icons.notes_rounded),
            ),
            const SizedBox(height: 8),
            primaryButton("Record loan", () async {
              final value = double.tryParse(amount.text.trim()) ?? 0;
              if (lender == null) return toast(ctx, "Choose the lender company", error: true);
              if (!(value > 0)) return toast(ctx, "Enter a valid amount", error: true);
              final res = await LedgerService.createLoan({
                "userId": s.userId,
                "borrowerCompanyId": s.companyId,
                "lenderCompanyId": lender,
                "amount": value,
                "fundId": fund,
                "method": method,
                "reference": ref.text.trim(),
                "note": note.text.trim(),
              });
              if (!ctx.mounted) return;
              if (handleResult(ctx, res, "Company loan recorded")) {
                Navigator.pop(ctx);
                notifyLedgerChanged();
              }
            }),
          ]);
        }));
  }

  void _openRepay(Map<String, dynamic> loan) {
    final amount = TextEditingController();
    final ref = TextEditingController();
    String fund = "cash";
    String method = "UPI";
    showLedgerSheet(context, "Repay company loan", (ctx) => StatefulBuilder(builder: (ctx, set) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text("${nameOf(loan["lenderCompanyId"], "Lender")} · outstanding ${inr(loan["balance"])}", style: labelStyle),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: fieldDecoration("Repayment ₹", icon: Icons.currency_rupee_rounded)),
            ),
            TextButton(onPressed: () => set(() => amount.text = (loan["balance"] ?? "").toString()), child: const Text("Full")),
          ]),
          const SizedBox(height: 10),
          fundDropdown(s, fund, (v) => set(() => fund = v ?? "cash"), hint: "Paid from"),
          const SizedBox(height: 10),
          methodChips(method, (m) => set(() => method = m)),
          const SizedBox(height: 10),
          TextField(controller: ref, decoration: fieldDecoration("Reference (optional)", icon: Icons.tag_rounded)),
          const SizedBox(height: 16),
          primaryButton("Record repayment", () async {
            final value = double.tryParse(amount.text.trim()) ?? 0;
            if (!(value > 0)) return toast(ctx, "Enter a valid amount", error: true);
            final res = await LedgerService.repayLoan(loan["_id"].toString(), {"userId": s.userId, "amount": value, "fundId": fund, "method": method, "reference": ref.text.trim()});
            if (!ctx.mounted) return;
            if (handleResult(ctx, res, "Loan repayment recorded")) {
              Navigator.pop(ctx);
              notifyLedgerChanged();
            }
          }),
        ])));
  }

  /// Lender side: the borrower paid us back; pick which of THEIR Cash/Bank it came from.
  Future<void> _openReceive(Map<String, dynamic> loan) async {
    final res = await LedgerService.loanBorrowerFunds(loan["_id"].toString(), s.userId);
    if (!mounted) return;
    if (res["success"] != true) return toast(context, res["message"]?.toString() ?? "Could not load the borrower's accounts", error: true);
    final funds = List<Map<String, dynamic>>.from(res["funds"] ?? const []);
    final borrowerName = nameOf(loan["borrowerCompanyId"], "Borrower");
    final amount = TextEditingController();
    final ref = TextEditingController();
    String fund = funds.isEmpty ? "cash" : funds.first["fundId"].toString();
    String method = "UPI";
    showLedgerSheet(context, "Mark repayment received", (ctx) => StatefulBuilder(builder: (ctx, set) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text("$borrowerName · outstanding ${inr(loan["balance"])}", style: labelStyle),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: fieldDecoration("Received ₹", icon: Icons.currency_rupee_rounded)),
            ),
            TextButton(onPressed: () => set(() => amount.text = (loan["balance"] ?? "").toString()), child: const Text("Full")),
          ]),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: fund,
            isExpanded: true,
            decoration: fieldDecoration("Paid from ($borrowerName's account)", icon: Icons.account_balance_rounded),
            items: funds.map((f) => DropdownMenuItem(value: f["fundId"].toString(), child: Text(f["name"].toString(), overflow: TextOverflow.ellipsis))).toList(),
            onChanged: (v) => set(() => fund = v ?? "cash"),
          ),
          const SizedBox(height: 10),
          methodChips(method, (m) => set(() => method = m)),
          const SizedBox(height: 10),
          TextField(controller: ref, decoration: fieldDecoration("Reference (optional)", icon: Icons.tag_rounded)),
          const SizedBox(height: 16),
          primaryButton("Mark received", () async {
            final value = double.tryParse(amount.text.trim()) ?? 0;
            if (!(value > 0)) return toast(ctx, "Enter a valid amount", error: true);
            final r = await LedgerService.receiveLoan(loan["_id"].toString(), {"userId": s.userId, "amount": value, "borrowerFundId": fund, "method": method, "reference": ref.text.trim()});
            if (!ctx.mounted) return;
            final short = (r["borrowerShort"] as num?) ?? 0;
            if (handleResult(ctx, r, short > 0 ? "Marked as received · $borrowerName's account is now ${inr(short)} below zero" : "Marked as received")) {
              Navigator.pop(ctx);
              notifyLedgerChanged();
            }
          }),
        ])));
  }

  void _openRouted() {
    final managers = s.admins.where((m) => m["userId"].toString() != s.userId).toList();
    String? source;
    String? managerId = managers.length == 1 ? managers.first["userId"].toString() : null;
    String method = "UPI";
    final amount = TextEditingController();
    final ref = TextEditingController();
    showLedgerSheet(context, "Routed payment to manager", (ctx) => StatefulBuilder(builder: (ctx, set) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text("Another company pays a manager of ${s.companyName} on its behalf. Booked as that company → ${s.companyName} → manager.",
              style: GoogleFonts.inter(fontSize: 12.5, color: kDark.withValues(alpha: 0.6))),
          const SizedBox(height: 12),
          _companyPicker(source, (v) => set(() => source = v), "Paying company"),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: managerId,
            isExpanded: true,
            decoration: fieldDecoration("Manager being paid", icon: Icons.person_rounded),
            items: managers.map((m) => DropdownMenuItem(value: m["userId"].toString(), child: Text(m["name"].toString()))).toList(),
            onChanged: (v) => set(() => managerId = v),
          ),
          const SizedBox(height: 10),
          TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: fieldDecoration("Amount ₹", icon: Icons.currency_rupee_rounded)),
          const SizedBox(height: 10),
          methodChips(method, (m) => set(() => method = m)),
          const SizedBox(height: 10),
          TextField(controller: ref, decoration: fieldDecoration("Reference (optional)", icon: Icons.tag_rounded)),
          const SizedBox(height: 16),
          primaryButton("Record routed payment", () async {
            final value = double.tryParse(amount.text.trim()) ?? 0;
            if (source == null) return toast(ctx, "Choose the paying company", error: true);
            if (managerId == null) return toast(ctx, "Choose the manager being paid", error: true);
            if (!(value > 0)) return toast(ctx, "Enter a valid amount", error: true);
            final res = await LedgerService.routed({
              "userId": s.userId,
              "companyId": s.companyId,
              "adminUserId": managerId,
              "amount": value,
              "sourceCompanyId": source,
              "sourceFundId": "cash",
              "method": method,
              "reference": ref.text.trim(),
            });
            if (!ctx.mounted) return;
            if (handleResult(ctx, res, "Routed payment recorded")) {
              Navigator.pop(ctx);
              notifyLedgerChanged();
            }
          }),
        ])));
  }
}

/// The person who recorded a borrow may delete it while nothing has been repaid.
bool canDeleteLoan(LedgerScope s, Map<String, dynamic> loan) =>
    s.can("intercompany") && idOf(loan["createdBy"]) == s.userId && !(((loan["repaid"] as num?) ?? 0) > 0);

/// Asks first, then deletes the borrow: reversed in both companies, a paid bill or settled group reopened.
Future<bool> deleteLoanFlow(BuildContext context, LedgerScope s, Map<String, dynamic> loan) async {
  final lender = nameOf(loan["lenderCompanyId"], "Lender");
  final borrower = nameOf(loan["borrowerCompanyId"], "the borrower");
  final extra = loan["source"] == "expense"
      ? " The bill it paid goes back to Approved · unpaid."
      : loan["source"] == "group"
          ? " The group it settled is reopened."
          : " $borrower's Cash/Bank is put back.";
  final ok = await confirmDialog(context, "Delete this borrow?",
      "$lender → $borrower · ${inr(loan["amount"])} will be reversed in both companies' books.$extra This can't be undone.",
      confirmLabel: "Delete borrow", danger: true);
  if (!ok || !context.mounted) return false;
  final res = await LedgerService.deleteLoan(loan["_id"].toString(), s.userId);
  if (!context.mounted) return false;
  final done = handleResult(context, res, "Borrow deleted and reversed in both companies");
  if (done) notifyLedgerChanged();
  return done;
}

Widget _tag(String text, bool bad) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: bad ? const Color(0xFFFEE2E2) : const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.bold, color: bad ? kTerracotta : const Color(0xFF047857))),
    );

String _initials(String? name) => (name ?? "?").trim().split(RegExp(r"\s+")).take(2).map((w) => w.isEmpty ? "" : w[0]).join().toUpperCase();

/// One loan in full: money flow, balance, who initiated/confirmed, the bill it paid, repayments (web's LoanDetailModal).
Future<void> showLoanDetail(BuildContext context, LedgerScope s, Map<String, dynamic> initial, {void Function(Map<String, dynamic> loan)? onRepay, void Function(Map<String, dynamic> loan)? onReceive}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Theme(data: sheetTheme, child: _LoanDetailSheet(scope: s, initial: initial, onRepay: onRepay, onReceive: onReceive)),
  );
}

class _LoanDetailSheet extends StatefulWidget {
  final LedgerScope scope;
  final Map<String, dynamic> initial;
  final void Function(Map<String, dynamic> loan)? onRepay;
  final void Function(Map<String, dynamic> loan)? onReceive;
  const _LoanDetailSheet({required this.scope, required this.initial, this.onRepay, this.onReceive});

  @override
  State<_LoanDetailSheet> createState() => _LoanDetailSheetState();
}

class _LoanDetailSheetState extends State<_LoanDetailSheet> {
  Map<String, dynamic>? _data;
  Map<String, dynamic>? _receipts;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = widget.initial["_id"].toString();
    final res = await LedgerService.loanDetail(id, widget.scope.userId);
    if (!mounted) return;
    if (res["success"] != true) return setState(() => _error = res["message"]?.toString() ?? "Could not load loan details");
    setState(() => _data = res);
    final bill = res["bill"];
    if (bill is Map && (bill["hasAttachment"] == true || bill["hasPaymentReceipt"] == true)) {
      final r = await LedgerService.loanReceipts(id, widget.scope.userId);
      if (mounted && r["success"] == true) setState(() => _receipts = r);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scope;
    final loan = Map<String, dynamic>.from(_data?["loan"] ?? widget.initial);
    final bill = _data?["bill"] as Map?;
    final group = _data?["group"] as Map?;
    final initiatedBy = _data?["initiatedBy"] as Map?;
    final confirmedBy = _data?["confirmedBy"] as Map?;
    final repayments = List<Map<String, dynamic>>.from(_data?["repayments"] ?? const []);
    final lender = nameOf(loan["lenderCompanyId"], "Another company");
    final borrower = nameOf(loan["borrowerCompanyId"], "Another company");
    final weBorrowed = idOf(loan["borrowerCompanyId"]) == s.companyId;
    final amount = (loan["amount"] as num?) ?? 0;
    final balance = (loan["balance"] as num?) ?? 0;
    final repaid = (amount - balance) < 0 ? 0 : amount - balance;
    final open = balance > 0;
    final pct = amount > 0 ? (repaid / amount).clamp(0, 1).toDouble() : 0.0;
    final source = loan["source"] == "expense" ? "Paid an expense" : loan["source"] == "group" ? "Paid a group's expenses" : "Direct loan";
    final method = (bill?["method"] ?? loan["method"])?.toString() ?? "";
    final reference = (bill?["reference"] ?? loan["reference"])?.toString() ?? "";
    final note = loan["note"]?.toString() ?? "";

    Widget box({required Widget child, Color? color}) => Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: color ?? Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFF1F5F9))),
          child: child,
        );
    Widget label(String t) => Text(t.toUpperCase(), style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: kDark.withValues(alpha: 0.5)));
    Widget person(String role, Map who, String company) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFF1F5F9))),
            child: Row(children: [
              CircleAvatar(radius: 18, backgroundColor: kForest.withValues(alpha: 0.1), child: Text(_initials(who["name"]?.toString()), style: GoogleFonts.inter(color: kForest, fontWeight: FontWeight.w800, fontSize: 12))),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  label(role),
                  Text(who["name"]?.toString() ?? "", style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: kDark)),
                  Text("Manager of $company", style: GoogleFonts.inter(fontSize: 11, color: kDark.withValues(alpha: 0.55))),
                ]),
              ),
            ]),
          ),
        );

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.92),
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + MediaQuery.of(context).padding.bottom),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 38, height: 4, decoration: BoxDecoration(color: kDark.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)))),
          const SizedBox(height: 12),
          Wrap(spacing: 6, children: [_tag(weBorrowed ? "Borrowed" : "Lent", weBorrowed), statusPill(source, kDark), if (!open) _tag("Repaid", false)]),
          const SizedBox(height: 8),
          Text(weBorrowed ? "Loan from $lender" : "Loan to $borrower", style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.bold, color: kDark)),
          Text("Recorded ${DateTime.tryParse(loan["createdAt"]?.toString() ?? "") == null ? "" : DateFormat("dd MMM yyyy, hh:mm a").format(DateTime.parse(loan["createdAt"].toString()).toLocal())}",
              style: GoogleFonts.inter(fontSize: 12.5, color: kDark.withValues(alpha: 0.55))),
          if (note.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              decoration: BoxDecoration(color: kForest.withValues(alpha: 0.05), border: const Border(left: BorderSide(color: kForest, width: 3))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                label(loan["source"] == "direct" ? "Reason for borrowing" : "Note"),
                const SizedBox(height: 2),
                Text(note, style: GoogleFonts.inter(color: kDark, fontSize: 13.5)),
              ]),
            ),
          box(
            color: const Color(0xFFF8FAFC),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [label("Paid by"), Text(lender, style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: kDark))])),
              Column(children: [
                Text(inr(amount), style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: kForest)),
                const Icon(Icons.arrow_right_alt_rounded, color: kForest, size: 30),
              ]),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  label("Borrowed by"),
                  Text(borrower, textAlign: TextAlign.right, style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: kDark)),
                ]),
              ),
            ]),
          ),
          box(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    label(open ? "Still due" : "Fully repaid"),
                    Text(inr(open ? balance : amount), style: GoogleFonts.inter(fontSize: 26, fontWeight: FontWeight.bold, color: open ? kTerracotta : kForest)),
                  ]),
                ),
                Text("${inr(repaid)} repaid\nof ${inr(amount)}", textAlign: TextAlign.right, style: GoogleFonts.inter(fontSize: 12, color: kDark.withValues(alpha: 0.55))),
              ]),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(value: pct, minHeight: 6, backgroundColor: const Color(0xFFF1F5F9), color: kMint),
              ),
              if (method.isNotEmpty || reference.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Wrap(spacing: 6, children: [
                    if (method.isNotEmpty) Chip(label: Text(method), visualDensity: VisualDensity.compact),
                    if (reference.isNotEmpty) Chip(label: Text("Ref $reference"), visualDensity: VisualDensity.compact),
                  ]),
                ),
            ]),
          ),
          if (_data == null && _error == null)
            const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(color: kForest))),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: GoogleFonts.inter(color: kTerracotta))),
          if (initiatedBy != null || confirmedBy != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(children: [
                if (initiatedBy != null) person("Payment initiated by", initiatedBy, borrower),
                if (initiatedBy != null && confirmedBy != null) const SizedBox(width: 8),
                if (confirmedBy != null) person("Confirmed by", confirmedBy, lender),
              ]),
            ),
          if (bill != null) ...[
            const SizedBox(height: 14),
            Text("Bill paid", style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: kDark)),
            box(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(bill["description"]?.toString() ?? "", style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 15, color: kDark))),
                  Text(inr(bill["amount"]), style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 17, color: kForest)),
                ]),
                Text("${bill["category"] ?? "General"} · ${dateLabel(bill["date"])}", style: GoogleFonts.inter(fontSize: 12.5, color: kDark.withValues(alpha: 0.55))),
                if ((bill["postedBy"]?.toString() ?? "").isNotEmpty || (bill["approvedBy"]?.toString() ?? "").isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      [if ((bill["postedBy"]?.toString() ?? "").isNotEmpty) "Posted by ${bill["postedBy"]}", if ((bill["approvedBy"]?.toString() ?? "").isNotEmpty) "Approved by ${bill["approvedBy"]}"].join(" · "),
                      style: GoogleFonts.inter(fontSize: 12.5, color: kDark.withValues(alpha: 0.65)),
                    ),
                  ),
                if (bill["hasAttachment"] == true || bill["hasPaymentReceipt"] == true)
                  _receipts == null
                      ? Padding(padding: const EdgeInsets.only(top: 8), child: Text("Loading receipts…", style: GoogleFonts.inter(fontSize: 12.5, color: kDark.withValues(alpha: 0.55))))
                      : Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Wrap(spacing: 10, children: [
                            for (final r in [("attachment", "Bill receipt"), ("paymentReceipt", "Payment proof")])
                              if ((_receipts![r.$1]?.toString() ?? "").isNotEmpty)
                                InkWell(
                                  onTap: () => showImageViewer(context, _receipts![r.$1].toString(), r.$2),
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    ClipRRect(borderRadius: BorderRadius.circular(10), child: SizedBox(width: 110, height: 90, child: dataImage(_receipts![r.$1].toString(), fit: BoxFit.cover))),
                                    Text(r.$2, style: GoogleFonts.inter(fontSize: 11.5, color: kDark.withValues(alpha: 0.6))),
                                  ]),
                                ),
                          ]),
                        ),
              ]),
            ),
          ],
          if (group != null) ...[
            const SizedBox(height: 14),
            Text("Group settled", style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: kDark)),
            box(
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(group["name"]?.toString() ?? "", style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: kDark)),
                    Text([if ((group["createdBy"]?.toString() ?? "").isNotEmpty) "Group admin ${group["createdBy"]}", if (group["settledAt"] != null) "Settled ${dateLabel(group["settledAt"])}"].join(" · "),
                        style: GoogleFonts.inter(fontSize: 12, color: kDark.withValues(alpha: 0.55))),
                  ]),
                ),
                if (group["amount"] != null) Text(inr(group["amount"]), style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 17, color: kForest)),
              ]),
            ),
          ],
          if (_data != null) ...[
            const SizedBox(height: 14),
            Text("Repayments", style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: kDark)),
            const SizedBox(height: 6),
            if (repayments.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0))),
                child: Text("No repayments yet${!open ? "." : weBorrowed ? " — use Repay below when you pay it back." : " — use Received below when they pay you back."}", style: GoogleFonts.inter(fontSize: 13, color: kDark.withValues(alpha: 0.6))),
              )
            else
              ...repayments.map((r) => Opacity(
                    opacity: r["reversed"] == true ? 0.5 : 1,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.only(left: 12),
                      decoration: const BoxDecoration(border: Border(left: BorderSide(color: kMint, width: 2))),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(
                            child: Text(inr(r["amount"]),
                                style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: kDark, decoration: r["reversed"] == true ? TextDecoration.lineThrough : null)),
                          ),
                          Text(dateLabel(r["date"]), style: GoogleFonts.inter(fontSize: 12, color: kDark.withValues(alpha: 0.55))),
                        ]),
                        Text(
                          [if ((r["by"]?.toString() ?? "").isNotEmpty) "by ${r["by"]}", if (r["byLender"] == true) "marked received by lender", r["method"], if ((r["reference"]?.toString() ?? "").isNotEmpty) "Ref ${r["reference"]}", if (r["reversed"] == true) "reversed"]
                              .where((x) => x != null && x.toString().isNotEmpty)
                              .join(" · "),
                          style: GoogleFonts.inter(fontSize: 12, color: kDark.withValues(alpha: 0.55)),
                        ),
                      ]),
                    ),
                  )),
          ],
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text("Close"))),
            if (s.isAdmin && s.can("intercompany") && weBorrowed && open && widget.onRepay != null) ...[
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: kForest, foregroundColor: Colors.white),
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onRepay!(loan);
                  },
                  child: Text("Repay ${inr(balance)}"),
                ),
              ),
            ],
            if (s.isAdmin && s.can("intercompany") && !weBorrowed && open && !isExternal(loan["borrowerCompanyId"]) && widget.onReceive != null) ...[
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: kForest, foregroundColor: Colors.white),
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onReceive!(loan);
                  },
                  child: const Text("Mark received"),
                ),
              ),
            ],
          ]),
          // only the person who recorded the borrow, and only before any repayment
          if (canDeleteLoan(s, loan) && repayments.where((r) => r["reversed"] != true).isEmpty)
            Center(
              child: TextButton(
                onPressed: () async {
                  // confirm on top of this sheet, then close it once the borrow is gone
                  if (await deleteLoanFlow(context, s, loan) && context.mounted) Navigator.pop(context);
                },
                child: const Text("Delete this borrow", style: TextStyle(color: kTerracotta, fontWeight: FontWeight.w600)),
              ),
            ),
        ]),
      ),
    );
  }
}

bool isExternal(dynamic company) => company is Map && company["external"] == true;
