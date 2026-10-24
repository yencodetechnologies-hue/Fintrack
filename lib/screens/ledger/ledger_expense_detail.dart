import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../services/ledger_service.dart';
import 'ledger_common.dart';
import 'ledger_fund_topup.dart';
import 'ledger_description_field.dart';

String _sid(dynamic ref) => idOf(ref);

/// One expense in full, same rows and actions as the web's ExpenseDetailModal.
Future<void> showExpenseDetail(BuildContext context, LedgerScope s, Map<String, dynamic> e) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Theme(data: sheetTheme, child: _ExpenseDetailSheet(scope: s, expense: e, parent: context)),
  );
}

class _ExpenseDetailSheet extends StatefulWidget {
  final LedgerScope scope;
  final Map<String, dynamic> expense;
  /// The screen that opened the sheet; follow-up sheets open from it once this one closes.
  final BuildContext parent;
  const _ExpenseDetailSheet({required this.scope, required this.expense, required this.parent});

  @override
  State<_ExpenseDetailSheet> createState() => _ExpenseDetailSheetState();
}

class _ExpenseDetailSheetState extends State<_ExpenseDetailSheet> {
  LedgerScope get s => widget.scope;
  Map<String, dynamic> get e => widget.expense;
  String _attachment = "";
  String _paymentReceipt = "";
  bool _loadingReceipts = false;
  String _uploading = "";

  @override
  void initState() {
    super.initState();
    if (e["hasAttachment"] == true || e["hasPaymentReceipt"] == true) _loadReceipts();
  }

  Future<void> _loadReceipts() async {
    setState(() => _loadingReceipts = true);
    final res = await LedgerService.expenseReceipts(e["_id"].toString(), s.userId);
    if (!mounted) return;
    String url(dynamic d) {
      final v = d?.toString() ?? "";
      if (v.isEmpty) return "";
      return v.startsWith("data:") ? v : "data:image/jpeg;base64,$v";
    }

    setState(() {
      _loadingReceipts = false;
      if (res["success"] == true) {
        _attachment = url(res["attachment"]);
        _paymentReceipt = url(res["paymentReceipt"]);
      }
    });
  }

  Future<void> _replace(String field) async {
    final img = await pickReceiptImage(context);
    if (img == null || !mounted) return;
    setState(() => _uploading = field);
    final res = await LedgerService.updateReceipts(e["_id"].toString(), s.userId,
        attachment: field == "attachment" ? img : null, paymentReceipt: field == "paymentReceipt" ? img : null);
    if (!mounted) return;
    setState(() => _uploading = "");
    if (handleResult(context, res, field == "attachment" ? "Bill receipt updated" : "Payment proof updated")) {
      setState(() => field == "attachment" ? _attachment = img : _paymentReceipt = img);
      notifyLedgerChanged();
    }
  }

  // managers only: an expense may stay without any receipt
  Future<void> _remove(String field) async {
    final what = field == "attachment" ? "bill receipt" : "payment proof";
    final ok = await confirmDialog(context, "Remove $what?",
        "The $what image is deleted from \"${e["description"]}\". The expense itself stays as it is; you can add a new image any time.",
        confirmLabel: "Remove", danger: true);
    if (!ok || !mounted) return;
    setState(() => _uploading = field);
    final res = await LedgerService.updateReceipts(e["_id"].toString(), s.userId,
        attachment: field == "attachment" ? "" : null, paymentReceipt: field == "paymentReceipt" ? "" : null);
    if (!mounted) return;
    setState(() => _uploading = "");
    if (handleResult(context, res, field == "attachment" ? "Bill receipt removed" : "Payment proof removed")) {
      setState(() => field == "attachment" ? _attachment = "" : _paymentReceipt = "");
      notifyLedgerChanged();
    }
  }

  void _close() => Navigator.pop(context);

  @override
  Widget build(BuildContext context) {
    final lifecycle = e["lifecycle"]?.toString() ?? "submitted";
    final isCreator = _sid(e["createdBy"]) == s.userId;
    final isApproved = lifecycle == "approved";
    final isSubmitted = lifecycle == "submitted";
    final isRejected = lifecycle == "rejected";
    final isPaid = lifecycle.startsWith("paid") || e["status"] == "paid";
    final isAwaitingPayer = lifecycle == "awaiting_confirmation";
    final paidByMe = lifecycle == "paid_by_admin" && _sid(e["paidByAdminId"]) == s.userId;
    final creatorCanSwitchPayer = s.isAdmin && isCreator && (isApproved || lifecycle == "paid_by_company" || paidByMe);
    final canEdit = (s.can("edit_expenses") && ((s.isAdmin && !isPaid && !isAwaitingPayer) || (!s.isAdmin && isSubmitted && isCreator && !isPaid))) ||
        (creatorCanSwitchPayer && (s.can("edit_expenses") || s.can("record_payments")));
    final canDelete = s.can("edit_expenses") && ((s.isAdmin && !isPaid) || (!s.isAdmin && isSubmitted && isCreator));
    final canReplaceReceipts = s.isAdmin && s.can("edit_expenses");
    final canRemoveReceipts = s.isAdmin && s.can("remove_receipts");
    final canPay = isApproved && payerOptions(s, e).isNotEmpty;
    final isCompanyPost = e["logAs"] == "company" || e["postedAs"] == "company";
    final borrowedFrom = e["payerType"] == "other_company" ? nameOf(e["payerCompanyId"], "") : "";
    final companyName = e["companyId"] is Map ? (e["companyId"]["name"]?.toString() ?? s.companyName) : s.companyName;
    final paymentText = [e["payerMethod"], e["fundName"]].where((v) => v != null && v.toString().isNotEmpty).join(" · ");
    final pillColor = isApproved || isPaid ? kMint : isRejected ? kTerracotta : kAmber;

    final rows = <(String, Widget)>[
      ("Expense date", _val(dateLabel(e["date"] ?? e["createdAt"]))),
      isCompanyPost
          ? ("Posted by", _val(postedByName(e, s.companyName), sub: "Entered by ${nameOf(e["createdBy"], "a manager")}"))
          : ("Posted by", _val(nameOf(e["createdBy"], "Staff"), sub: e["createdBy"] is Map ? (e["createdBy"]["email"]?.toString() ?? "") : "")),
      ("Posted on", _val(_dateTime(e["createdAt"]))),
      ("Type", _val(isCompanyPost ? "Company expense" : "Personal expense (reimbursable)")),
      ("Company", _val(companyName)),
      if (e["approvedBy"] != null) ("Approved by", _val(nameOf(e["approvedBy"], "Manager"))),
      if (isPaid && e["paidByUserId"] != null) ("Paid by", _val(nameOf(e["paidByUserId"], "Member"))),
      if (lifecycle == "paid_by_company")
        ("Paid by", _val(borrowedFrom.isNotEmpty ? borrowedFrom : companyName, sub: borrowedFrom.isNotEmpty ? "Borrowed by $companyName" : null)),
      if (lifecycle == "paid_by_voucher" && e["voucherId"] != null) ("Paid by", _val("Voucher money given in advance")),
      if (((e["advanceUsed"] as num?) ?? 0) > 0) ("From voucher balance", _val(inr(e["advanceUsed"]))),
      if (!isPaid && e["useAdvance"] == true) ("Voucher balance", _val("Will be used when approved")),
      if (isPaid && paymentText.isNotEmpty) ("Payment", _val(paymentText)),
      if ((e["payerReference"]?.toString() ?? "").isNotEmpty) ("Reference / UTR", _val(e["payerReference"].toString())),
      if (s.isAdmin && e["visibleTo"] is List)
        ("${s.staffName} visibility", _val((e["visibleTo"] as List).isEmpty ? "All ${s.staffsName.toLowerCase()}" : "${(e["visibleTo"] as List).length} selected staff")),
    ];

    final canReceive = canMarkReceived(s, e);
    final primary = s.isAdmin && isSubmitted && s.can("approve_expenses")
        ? _button("Approve", kForest, filled: true, onTap: () => _decide(true))
        : canReceive
            ? _button("Received", kForest, filled: true, onTap: () {
                _close();
                showReceivedSheet(widget.parent, s, e);
              })
        : canPay
            ? _button("Record payment", kForest, filled: true, onTap: () {
                _close();
                showPaySheet(widget.parent, s, e);
              })
            : _button("Done", kForestDark, filled: true, onTap: _close);

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.92),
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + MediaQuery.of(context).padding.bottom),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 38, height: 4, decoration: BoxDecoration(color: kDark.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)))),
          const SizedBox(height: 14),
          Wrap(spacing: 6, runSpacing: 6, children: [
            statusPill(expenseStatusLabel(e, s.companyName), pillColor),
            statusPill(e["category"]?.toString() ?? "General", kDark),
            if (e["verification"] == "verified") statusPill("✓ Verified", kMint),
            if (e["verification"] == "pending") statusPill("Verification pending", kAmber),
          ]),
          const SizedBox(height: 10),
          Text(e["description"]?.toString() ?? "Expense", style: GoogleFonts.inter(fontSize: 19, fontWeight: FontWeight.w700, color: kDark)),
          Text(inr(e["amount"]), style: GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.bold, color: kForest)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFF1F5F9))),
            child: Column(children: [
              for (var i = 0; i < rows.length; i++)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(border: i == 0 ? null : const Border(top: BorderSide(color: Color(0xFFF1F5F9)))),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(rows[i].$1.toUpperCase(),
                        style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: kDark.withValues(alpha: 0.5))),
                    const SizedBox(width: 12),
                    Expanded(child: Align(alignment: Alignment.centerRight, child: rows[i].$2)),
                  ]),
                ),
            ]),
          ),
          if (_loadingReceipts || _attachment.isNotEmpty || _paymentReceipt.isNotEmpty || canReplaceReceipts || canRemoveReceipts) ...[
            const SizedBox(height: 14),
            Text("RECEIPTS", style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: kDark.withValues(alpha: 0.5))),
            const SizedBox(height: 8),
            if (_loadingReceipts)
              Text("Loading receipts…", style: GoogleFonts.inter(fontSize: 12.5, fontStyle: FontStyle.italic, color: kDark.withValues(alpha: 0.6)))
            else
              Wrap(spacing: 10, runSpacing: 10, children: [
                if (_attachment.isNotEmpty) _thumb(_attachment, "Bill / receipt"),
                if (_paymentReceipt.isNotEmpty) _thumb(_paymentReceipt, "Payment proof"),
              ]),
            if ((canReplaceReceipts || canRemoveReceipts) && !_loadingReceipts)
              Wrap(spacing: 8, children: [
                if (canReplaceReceipts) TextButton.icon(
                  onPressed: _uploading.isNotEmpty ? null : () => _replace("attachment"),
                  icon: const Icon(Icons.upload_rounded, size: 16),
                  label: Text(_uploading == "attachment" ? "Uploading…" : (_attachment.isNotEmpty ? "Replace bill receipt" : "Add bill receipt")),
                ),
                if (canReplaceReceipts && (isPaid || _paymentReceipt.isNotEmpty))
                  TextButton.icon(
                    onPressed: _uploading.isNotEmpty ? null : () => _replace("paymentReceipt"),
                    icon: const Icon(Icons.upload_rounded, size: 16),
                    label: Text(_uploading == "paymentReceipt" ? "Uploading…" : (_paymentReceipt.isNotEmpty ? "Replace payment proof" : "Add payment proof")),
                  ),
                if (canRemoveReceipts && _attachment.isNotEmpty)
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: kTerracotta),
                    onPressed: _uploading.isNotEmpty ? null : () => _remove("attachment"),
                    icon: const Icon(Icons.delete_outline_rounded, size: 16),
                    label: const Text("Remove bill receipt"),
                  ),
                if (canRemoveReceipts && _paymentReceipt.isNotEmpty)
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: kTerracotta),
                    onPressed: _uploading.isNotEmpty ? null : () => _remove("paymentReceipt"),
                    icon: const Icon(Icons.delete_outline_rounded, size: 16),
                    label: const Text("Remove payment proof"),
                  ),
              ]),
          ],
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: [
            if (canDelete) _button("Delete", kTerracotta, onTap: _delete),
            if (s.isAdmin && s.can("edit_expenses")) _button("Visibility", kForest, onTap: () {
              _close();
              showVisibilitySheet(widget.parent, s, e);
            }),
            if (canEdit) _button("Edit", kForest, onTap: () {
              _close();
              showEditExpenseSheet(widget.parent, s, e);
            }),
            if (s.isAdmin && isSubmitted && s.can("approve_expenses")) _button("Reject", kTerracotta, onTap: () => _decide(false)),
            // own expense: Received is the main action; recording who paid stays available
            if (canReceive && canPay)
              _button("Record payment", kForest, onTap: () {
                _close();
                showPaySheet(widget.parent, s, e);
              }),
            primary,
          ]),
        ]),
      ),
    );
  }

  Future<void> _decide(bool approve) async {
    final id = e["_id"].toString();
    final res = approve ? await LedgerService.approve(id, s.userId) : await LedgerService.reject(id, s.userId);
    if (!mounted) return;
    if (handleResult(context, res, approve ? "Expense approved" : "Expense rejected")) {
      notifyLedgerChanged();
      _close();
    }
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(context, "Delete expense?", "\"${e["description"]}\" for ${inr(e["amount"])} will be removed. This can't be undone.",
        confirmLabel: "Delete", danger: true);
    if (!ok || !mounted) return;
    final res = await LedgerService.deleteExpense(e["_id"].toString(), s.userId);
    if (!mounted) return;
    if (handleResult(context, res, "Expense deleted")) {
      notifyLedgerChanged();
      _close();
    }
  }

  Widget _val(String text, {String? sub}) => Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(text, textAlign: TextAlign.right, style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w600, color: kDark)),
        if (sub != null && sub.isNotEmpty) Text(sub, textAlign: TextAlign.right, style: GoogleFonts.inter(fontSize: 11.5, color: kDark.withValues(alpha: 0.55))),
      ]);

  Widget _thumb(String url, String label) => InkWell(
        onTap: () => showImageViewer(context, url, label),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 140,
          decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE2E8F0)), borderRadius: BorderRadius.circular(10)),
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            SizedBox(height: 100, width: 140, child: dataImage(url, fit: BoxFit.cover)),
            Padding(
              padding: const EdgeInsets.all(6),
              child: Row(children: [
                Expanded(child: Text(label, style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600, color: kDark))),
                Text("View ↗", style: GoogleFonts.inter(fontSize: 11, color: kDark.withValues(alpha: 0.55))),
              ]),
            ),
          ]),
        ),
      );
}

String _dateTime(dynamic raw) {
  final d = raw == null ? null : DateTime.tryParse(raw.toString())?.toLocal();
  return d == null ? "" : DateFormat("dd MMM yyyy, hh:mm a").format(d);
}

Widget _button(String label, Color color, {bool filled = false, required VoidCallback onTap}) => filled
    ? ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        child: Text(label, style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
      )
    : OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(foregroundColor: color, side: BorderSide(color: color.withValues(alpha: 0.6)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        child: Text(label, style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
      );

/// Renders a data:image URL.
Widget dataImage(String url, {BoxFit fit = BoxFit.contain}) {
  try {
    final comma = url.indexOf(",");
    return Image.memory(base64Decode(comma >= 0 ? url.substring(comma + 1) : url), fit: fit, gaplessPlayback: true);
  } catch (_) {
    return const Center(child: Icon(Icons.broken_image_rounded, color: Color(0xFF94A3B8)));
  }
}

/// Full-screen zoomable receipt.
void showImageViewer(BuildContext context, String url, String label) {
  showDialog(
    context: context,
    barrierColor: Colors.black87,
    builder: (ctx) => GestureDetector(
      onTap: () => Navigator.pop(ctx),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text("$label · tap to close", style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600)),
            ),
            Expanded(child: InteractiveViewer(maxScale: 5, child: Center(child: dataImage(url)))),
          ]),
        ),
      ),
    ),
  );
}

/// Record who paid an approved expense (same choices as the web's Record payment popup).
/// A manager's own expense: they got the money back — from company Cash/Bank, or from another member who paid
/// them personally (the company then owes that member). Closes the expense.
Future<void> showReceivedSheet(BuildContext context, LedgerScope s, Map<String, dynamic> e) {
  final amount = (e["amount"] as num?) ?? 0;
  final others = s.members.where((m) => m["userId"].toString() != s.userId).toList();
  var from = "company";
  var fund = s.funds.first.id;
  String? personId;
  var method = "UPI";
  final ref = TextEditingController();

  Widget choice(String value, String title, String sub, String current, VoidCallback onTap) => Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: current == value ? kForest.withValues(alpha: 0.08) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: current == value ? kForest : const Color(0xFFE2E8F0), width: current == value ? 1.5 : 1),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: kDark)),
              const SizedBox(height: 2),
              Text(sub, style: GoogleFonts.inter(fontSize: 11.5, color: kDark.withValues(alpha: 0.6))),
            ]),
          ),
        ),
      );

  return showLedgerSheet(context, "Mark received", (ctx) => StatefulBuilder(builder: (ctx, set) {
        final selected = s.funds.firstWhere((f) => f.id == fund, orElse: () => s.funds.first);
        final short = from == "company" && selected.balance < amount;
        final person = others.where((m) => m["userId"].toString() == personId).firstOrNull;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text("${e["description"]} · ${inr(amount)} — you got this money back, so the expense closes.",
              style: GoogleFonts.inter(fontSize: 13, color: kDark.withValues(alpha: 0.65))),
          const SizedBox(height: 12),
          Text("Received from", style: labelStyle),
          const SizedBox(height: 6),
          Row(children: [
            choice("company", s.companyName, "From Cash or Bank", from, () => set(() => from = "company")),
            const SizedBox(width: 8),
            choice("person", "A person", "They paid you; the company owes them", from, () => set(() => from = "person")),
          ]),
          const SizedBox(height: 10),
          if (from == "company") ...[
            fundDropdown(s, fund, (v) => set(() => fund = v ?? "cash"), hint: "Paid from"),
            if (short)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text("Only ${inr(selected.balance)} available in ${selected.name}. You can add money when you mark it received.",
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: kTerracotta)),
              ),
          ] else ...[
            DropdownButtonFormField<String>(
              initialValue: personId,
              isExpanded: true,
              decoration: fieldDecoration("Who paid you?", icon: Icons.person_rounded),
              items: others
                  .map((m) => DropdownMenuItem(
                        value: m["userId"].toString(),
                        child: Text("${m["name"]} · ${s.roleLabel(m["role"])}", overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: (v) => set(() => personId = v),
            ),
            if (person != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text("${s.companyName} will owe ${person["name"]} ${inr(amount)}.",
                    style: GoogleFonts.inter(fontSize: 12, color: kDark.withValues(alpha: 0.6))),
              ),
          ],
          const SizedBox(height: 10),
          methodChips(method, (m) => set(() => method = m)),
          const SizedBox(height: 10),
          TextField(controller: ref, decoration: fieldDecoration("Reference (optional) · UTR / cheque no.", icon: Icons.tag_rounded)),
          const SizedBox(height: 16),
          primaryButton(
            "Mark received",
            from == "person" && personId == null
                ? null
                : () async {
                    if (short && !await topUpFund(ctx, s, selected, amount)) return;
                    if (!ctx.mounted) return;
                    final res = await LedgerService.markReceived(e["_id"].toString(), {
                      "userId": s.userId,
                      "from": from,
                      if (from == "company") "fundId": fund,
                      if (from == "person") "personId": personId,
                      "method": method,
                      "reference": ref.text.trim(),
                    });
                    if (!ctx.mounted) return;
                    final msg = from == "person"
                        ? "Marked received · ${s.companyName} now owes ${person?["name"] ?? "them"} ${inr(amount)}"
                        : "Marked received · ${inr(amount)} from ${selected.name}";
                    if (handleResult(ctx, res, msg)) {
                      Navigator.pop(ctx);
                      notifyLedgerChanged();
                    }
                  },
          ),
        ]);
      }));
}

Future<void> showPaySheet(BuildContext context, LedgerScope s, Map<String, dynamic> e) async {
  final src = await LedgerService.borrowSources(s.companyId, s.userId);
  if (!context.mounted) return;
  final sources = List<Map<String, dynamic>>.from(src["companies"] ?? const []);
  final amount = (e["amount"] as num?) ?? 0;
  final options = payerOptions(s, e);
  if (options.isEmpty) return;
  String payer = options.first.value;
  String fund = "cash";
  String payingCompanyId = s.companyId;
  String? sourceId;
  bool addingCompany = false;
  String method = "UPI";
  String receipt = "";
  final ref = TextEditingController();
  final newName = TextEditingController();
  final newGstin = TextEditingController();
  final needsVerify = () {
    final t = s.company["verificationThreshold"] as num?;
    return t != null && amount > t && s.admins.length > 1;
  }();

  await showLedgerSheet(context, "Record payment", (ctx) => StatefulBuilder(builder: (ctx, set) {
        final otherCompany = payingCompanyId != s.companyId;
        final payingCo = s.managedOtherCompanies.where((c) => c["_id"].toString() == payingCompanyId).firstOrNull;
        final selected = s.funds.firstWhere((f) => f.id == fund, orElse: () => s.funds.first);
        final insufficient = payer == "company" && !otherCompany && selected.balance < amount;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text("${e["description"]} · ${inr(amount)}", style: GoogleFonts.inter(color: kDark.withValues(alpha: 0.65))),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: payer,
            isExpanded: true,
            decoration: fieldDecoration("Who paid?", icon: Icons.person_rounded),
            items: options.map((o) => DropdownMenuItem(value: o.value, child: Text(o.label))).toList(),
            onChanged: (v) => set(() => payer = v ?? payer),
          ),
          if (payer == "company") ...[
            if (s.isAdmin && s.managedOtherCompanies.isNotEmpty) ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: payingCompanyId,
                isExpanded: true,
                decoration: fieldDecoration("Paying company", icon: Icons.business_rounded),
                items: [
                  DropdownMenuItem(value: s.companyId, child: Text("${s.companyName} (this company)")),
                  ...s.managedOtherCompanies.map((c) => DropdownMenuItem(value: c["_id"].toString(), child: Text(c["name"].toString()))),
                ],
                onChanged: (v) => set(() {
                  payingCompanyId = v ?? s.companyId;
                  fund = "cash";
                }),
              ),
              if (otherCompany)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                      "${payingCo?["name"]} → ${s.companyName}: ${inr(amount)} will be recorded as borrowed by ${s.companyName} from ${payingCo?["name"]}. Neither company's Cash/Bank changes; it shows in the Borrowed / Lent tiles.",
                      style: GoogleFonts.inter(fontSize: 12, color: kTerracotta, height: 1.4)),
                ),
            ],
            if (!otherCompany) ...[
              const SizedBox(height: 10),
              fundDropdown(s, fund, (v) => set(() => fund = v ?? "cash"), hint: "Paid from"),
            ],
            if (insufficient)
              Container(
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFFECACA))),
                child: Text("Insufficient balance: ${inr(selected.balance)} available (${inr(amount)} required). You can add money when you pay.",
                    style: GoogleFonts.inter(color: const Color(0xFFDC2626), fontSize: 12, fontWeight: FontWeight.w600)),
              ),
          ],
          if (payer == "borrow") ...[
            const SizedBox(height: 10),
            if (!addingCompany)
              sources.isEmpty
                  ? Text(s.isAdmin ? "No other companies yet — add one below." : "No other companies are available to borrow from.",
                      style: GoogleFonts.inter(color: kTerracotta, fontSize: 12.5))
                  : DropdownButtonFormField<String>(
                      initialValue: sourceId,
                      isExpanded: true,
                      decoration: fieldDecoration("Source company", icon: Icons.business_rounded),
                      items: sources.map((c) => DropdownMenuItem(value: c["_id"].toString(), child: Text(c["name"].toString()))).toList(),
                      onChanged: (v) => set(() => sourceId = v),
                    ),
            if (s.isAdmin)
              TextButton.icon(
                onPressed: () => set(() {
                  addingCompany = !addingCompany;
                  sourceId = null;
                }),
                icon: Icon(addingCompany ? Icons.close_rounded : Icons.add_rounded, size: 18),
                label: Text(addingCompany ? "Pick an existing company" : "Add an outside company"),
              ),
            if (addingCompany) ...[
              TextField(controller: newName, decoration: fieldDecoration("Company name", icon: Icons.business_rounded)),
              const SizedBox(height: 8),
              TextField(controller: newGstin, decoration: fieldDecoration("GSTIN *", icon: Icons.badge_rounded)),
            ],
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                  s.isAdmin
                      ? "A registered company's managers confirm the payment before it is booked; an outside company is booked straight away."
                      : "Recorded straight away as money borrowed from that company.",
                  style: GoogleFonts.inter(fontSize: 11.5, color: kDark.withValues(alpha: 0.6))),
            ),
          ],
          const SizedBox(height: 12),
          Text("Payment method", style: labelStyle),
          const SizedBox(height: 6),
          methodChips(method, (m) => set(() => method = m)),
          const SizedBox(height: 10),
          TextField(controller: ref, decoration: fieldDecoration("Reference (optional)", icon: Icons.tag_rounded)),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: kForest, side: const BorderSide(color: kForest)),
            onPressed: () async {
              final img = await pickReceiptImage(ctx);
              if (img != null) set(() => receipt = img);
            },
            icon: Icon(receipt.isEmpty ? Icons.photo_camera_rounded : Icons.check_circle_rounded),
            label: Text(receipt.isEmpty ? "Payment receipt (optional)" : "Payment receipt attached"),
          ),
          if (needsVerify)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(10)),
              child: Text("Above the verification limit: another manager must verify this payment.",
                  style: GoogleFonts.inter(color: kAmber, fontWeight: FontWeight.bold, fontSize: 12.5)),
            ),
          const SizedBox(height: 16),
          primaryButton(insufficient ? "Add money & pay" : "Record payment", () async {
                  if (insufficient && !await topUpFund(ctx, s, selected, amount)) return;
                  if (!ctx.mounted) return;
                  final body = <String, dynamic>{"userId": s.userId, "payer": payer, "method": method, "reference": ref.text.trim()};
                  if (receipt.isNotEmpty) body["paymentReceipt"] = receipt;
                  if (payer == "company" && otherCompany) {
                    // paid by another company this manager runs = this company borrows from it
                    body.addAll({"payer": "borrow", "sourceCompanyId": payingCompanyId, "sourceFundId": "cash"});
                  } else if (payer == "company") {
                    body["fundId"] = fund;
                  } else if (payer == "borrow") {
                    if (addingCompany) {
                      if (newName.text.trim().isEmpty || newGstin.text.trim().isEmpty) return toast(ctx, "Enter the outside company name and GSTIN", error: true);
                      body["newCompany"] = {"name": newName.text.trim(), "gstin": newGstin.text.trim()};
                    } else {
                      if (sourceId == null) return toast(ctx, "Choose the company paying", error: true);
                      body.addAll({"sourceCompanyId": sourceId, "sourceFundId": "cash"});
                    }
                  }
                  final res = await LedgerService.pay(e["_id"].toString(), body);
                  if (!ctx.mounted) return;
                  if (handleResult(ctx, res, res["awaitingConfirmation"] == true ? "Payment request sent for confirmation" : "Payment recorded")) {
                    Navigator.pop(ctx);
                    notifyLedgerChanged();
                  }
                }),
        ]);
      }));
}

/// Edit details (before payment) and, for the manager who posted it, switch who paid (web's EditExpenseModal).
Future<void> showEditExpenseSheet(BuildContext context, LedgerScope s, Map<String, dynamic> e) {
  final lifecycle = e["lifecycle"]?.toString() ?? "";
  final isCreator = _sid(e["createdBy"]) == s.userId;
  String? startPayer;
  if (lifecycle == "paid_by_company" && e["payerType"] == "company") {
    startPayer = "company";
  } else if (lifecycle == "paid_by_admin" && _sid(e["paidByAdminId"]) == s.userId) {
    startPayer = "manager";
  } else if (lifecycle == "approved") {
    startPayer = "unpaid";
  }
  final canSwitchPayer = s.isAdmin && isCreator && startPayer != null;
  final shownPayer = startPayer == "unpaid" ? "manager" : startPayer;
  final detailsLocked = lifecycle.startsWith("paid") || e["status"] == "paid";
  final amount = TextEditingController(text: (e["amount"] ?? "").toString());
  final desc = TextEditingController(text: e["description"]?.toString() ?? "");
  final options = {...companyCategories(s.company), if (e["category"] != null) e["category"].toString()}.toList();
  String category = e["category"]?.toString() ?? "General";
  DateTime date = DateTime.tryParse((e["date"] ?? e["createdAt"])?.toString() ?? "")?.toLocal() ?? DateTime.now();
  String? payer = shownPayer;
  String fund = "cash";
  String receipt = "";

  return showLedgerSheet(context, "Edit expense", (ctx) => StatefulBuilder(builder: (ctx, set) {
        final payerChanged = canSwitchPayer && payer != shownPayer;
        final selected = s.funds.firstWhere((f) => f.id == fund, orElse: () => s.funds.first);
        final fundTooLow = payer == "company" && payerChanged && selected.balance < ((e["amount"] as num?) ?? 0);
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (detailsLocked)
            Text("Paid expenses keep their amount and details; you can change who paid and the receipt.",
                style: GoogleFonts.inter(fontSize: 12.5, color: kDark.withValues(alpha: 0.6))),
          if (!detailsLocked) ...[
            TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: fieldDecoration("Amount ₹", icon: Icons.currency_rupee_rounded)),
            const SizedBox(height: 10),
            DescriptionField(companyId: s.companyId, userId: s.userId, kind: "expense", controller: desc, hint: "Description"),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: category,
              isExpanded: true,
              decoration: fieldDecoration("Category", icon: Icons.category_rounded),
              items: options.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => set(() => category = v ?? category),
            ),
            const SizedBox(height: 10),
            InkWell(
              onTap: () async {
                final picked = await showDatePicker(context: ctx, initialDate: date, firstDate: DateTime(2020), lastDate: DateTime.now());
                if (picked != null) set(() => date = picked);
              },
              child: InputDecorator(decoration: fieldDecoration("Date", icon: Icons.calendar_today_rounded), child: Text(DateFormat("dd MMM yyyy").format(date))),
            ),
          ],
          if (canSwitchPayer) ...[
            const SizedBox(height: 12),
            Text("Who paid?", style: labelStyle),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: "manager", label: Text("Me (manager)")),
                ButtonSegment(value: "company", label: Text("Company")),
              ],
              selected: {payer ?? "manager"},
              onSelectionChanged: (v) => set(() => payer = v.first),
            ),
            if (payer == "company" && payerChanged) ...[
              const SizedBox(height: 10),
              fundDropdown(s, fund, (v) => set(() => fund = v ?? "cash"), hint: "Paid from"),
              if (fundTooLow)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text("Insufficient balance in ${selected.name} (${inr(selected.balance)} available). You can add money when you save.",
                      style: GoogleFonts.inter(color: kTerracotta, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
            ],
          ],
          if (lifecycle.isNotEmpty) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: kForest, side: const BorderSide(color: kForest)),
              onPressed: () async {
                final img = await pickReceiptImage(ctx);
                if (img != null) set(() => receipt = img);
              },
              icon: Icon(receipt.isEmpty ? Icons.photo_camera_rounded : Icons.check_circle_rounded),
              label: Text(receipt.isEmpty ? "Replace bill receipt (optional)" : "New receipt attached"),
            ),
          ],
          const SizedBox(height: 16),
          primaryButton("Save changes", () async {
                  if (fundTooLow && !await topUpFund(ctx, s, selected, (e["amount"] as num?) ?? 0)) return;
                  if (!ctx.mounted) return;
                  final id = e["_id"].toString();
                  if (!detailsLocked) {
                    final amt = double.tryParse(amount.text.trim()) ?? 0;
                    if (!(amt > 0) || desc.text.trim().isEmpty) return toast(ctx, "Enter a valid amount and description", error: true);
                    final res = await LedgerService.updateExpense(id, {
                      "userId": s.userId,
                      "amount": amt,
                      "description": desc.text.trim(),
                      "category": category,
                      "date": date.toIso8601String(),
                    });
                    if (!ctx.mounted) return;
                    if (res["success"] != true) return toast(ctx, res["message"]?.toString() ?? "Failed to update expense", error: true);
                  }
                  final problems = <String>[];
                  if (payerChanged) {
                    final res = await LedgerService.changePayerType(id, s.userId, payer!, fundId: payer == "company" ? fund : null);
                    if (res["success"] != true) problems.add("who paid: ${res["message"] ?? "failed"}");
                  }
                  if (receipt.isNotEmpty) {
                    final res = await LedgerService.updateReceipts(id, s.userId, attachment: receipt);
                    if (res["success"] != true) problems.add("receipt: ${res["message"] ?? "upload failed"}");
                  }
                  if (!ctx.mounted) return;
                  notifyLedgerChanged();
                  if (problems.isNotEmpty) return toast(ctx, "Saved, except ${problems.join("; ")}", error: true);
                  toast(ctx, payerChanged ? "Now posted as ${payer == "company" ? "the company" : "you (manager)"}" : "Expense updated successfully");
                  Navigator.pop(ctx);
                }),
        ]);
      }));
}

/// Which staff can see a manager's expense (web's visibility popup).
Future<void> showVisibilitySheet(BuildContext context, LedgerScope s, Map<String, dynamic> e) {
  final staff = s.members.where((m) => m["userId"].toString() != s.userId).toList();
  final selected = <String>{...List.from(e["visibleTo"] ?? const []).map((v) => idOf(v))};
  return showLedgerSheet(context, "Staff visibility", (ctx) => StatefulBuilder(builder: (ctx, set) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text("Choose who can see \"${e["description"]}\" in their list.", style: GoogleFonts.inter(fontSize: 12.5, color: kDark.withValues(alpha: 0.6))),
        const SizedBox(height: 8),
        if (staff.isEmpty) Text("No other members yet.", style: GoogleFonts.inter(color: kDark.withValues(alpha: 0.6))),
        ...staff.map((m) => CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text("${m["name"]} (${s.roleLabel(m["role"])})"),
              value: selected.contains(m["userId"].toString()),
              onChanged: (v) => set(() => v == true ? selected.add(m["userId"].toString()) : selected.remove(m["userId"].toString())),
            )),
        const SizedBox(height: 12),
        primaryButton("Save visibility", () async {
          final res = await LedgerService.setExpenseVisibility(e["_id"].toString(), s.userId, selected.toList());
          if (!ctx.mounted) return;
          if (handleResult(ctx, res, "Visibility updated")) {
            Navigator.pop(ctx);
            notifyLedgerChanged();
          }
        }),
      ])));
}
