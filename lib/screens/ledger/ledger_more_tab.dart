import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../services/ledger_service.dart';
import 'ledger_common.dart';
import 'ledger_groups_tab.dart';

class LedgerMoreTab extends StatelessWidget {
  final LedgerScope scope;
  const LedgerMoreTab({super.key, required this.scope});

  @override
  Widget build(BuildContext context) {
    Widget item(IconData icon, String title, String subtitle, Widget page) => ledgerCard(
          padding: EdgeInsets.zero,
          child: ListTile(
            leading: Icon(icon, color: kForest),
            title: Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: kDark)),
            subtitle: Text(subtitle, style: GoogleFonts.inter(fontSize: 12)),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => page)),
          ),
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 30),
      children: [
        if (scope.isAdmin) item(Icons.menu_book_rounded, "Ledger", "Every transaction and its entries", _LedgerPage(scope: scope)),
        if (scope.isAdmin) item(Icons.groups_rounded, "Expense groups", "Staff groups and their shared expenses", _page("Expense groups", LedgerGroupsTab(scope: scope))),
        if (scope.isAdmin) item(Icons.history_rounded, "Audit log", "Who did what, and when", _AuditPage(scope: scope)),
        item(Icons.settings_rounded, "Settings", "Company details and members", _SettingsPage(scope: scope)),
      ],
    );
  }
}

Widget _page(String title, Widget body) => Theme(data: sheetTheme, child: Scaffold(
      backgroundColor: kForest,
      appBar: AppBar(
        backgroundColor: kForest,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(title, style: GoogleFonts.fraunces(fontWeight: FontWeight.bold)),
      ),
      body: body,
    ));

const Map<String, String> _txLabels = {
  "admin_paid": "Paid by admin",
  "company_paid": "Paid by company",
  "borrowed": "Paid with borrowed money",
  "reimburse": "Admin reimbursed",
  "lend": "Admin loan to company",
  "intercompany": "Inter-company",
  "routed": "Routed payment",
  "reversal": "Reversal",
};

class _LedgerPage extends StatefulWidget {
  final LedgerScope scope;
  const _LedgerPage({required this.scope});

  @override
  State<_LedgerPage> createState() => _LedgerPageState();
}

class _LedgerPageState extends State<_LedgerPage> with LedgerAutoRefresh {
  @override
  void onLedgerChanged() => _load();

  List<Map<String, dynamic>> _txs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await LedgerService.transactions(widget.scope.companyId, widget.scope.userId);
    if (!mounted) return;
    setState(() {
      _txs = List<Map<String, dynamic>>.from(res["transactions"] ?? const []);
      _loading = false;
    });
  }

  Future<void> _reverse(Map<String, dynamic> t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Reverse transaction?"),
        content: const Text("A reversal entry is booked; nothing is deleted. Linked entries in other companies are reversed too."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Reverse", style: TextStyle(color: kTerracotta))),
        ],
      ),
    );
    if (ok != true) return;
    final res = await LedgerService.reverse(t["_id"].toString(), widget.scope.userId);
    if (!mounted) return;
    if (handleResult(context, res, "Transaction reversed")) {
      _load();
      widget.scope.reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return _page(
      "Ledger",
      _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_txs.isEmpty) emptyState("No transactions yet"),
                ..._txs.map((t) {
                  final reversed = t["reversedBy"] != null;
                  return ledgerCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(_txLabels[t["type"]] ?? t["type"].toString(), style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: kDark))),
                            if (reversed) statusPill("Reversed", kTerracotta),
                            if (t["verification"] == "pending") statusPill("Pending verification", kAmber),
                          ],
                        ),
                        Text("${t["memo"]} · ${dateLabel(t["createdAt"])} · ${nameOf(t["createdBy"])}",
                            style: GoogleFonts.inter(fontSize: 12, color: kDark.withValues(alpha: 0.6))),
                        const Divider(),
                        ...(t["entries"] as List? ?? const []).map((e) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                children: [
                                  Expanded(child: Text(nameOf(e["accountId"], "Account"), style: GoogleFonts.inter(fontSize: 12.5, color: kDark))),
                                  SizedBox(width: 80, child: Text((e["debit"] ?? 0) > 0 ? "Dr ${inr(e["debit"])}" : "", textAlign: TextAlign.right, style: GoogleFonts.inter(fontSize: 12))),
                                  SizedBox(width: 80, child: Text((e["credit"] ?? 0) > 0 ? "Cr ${inr(e["credit"])}" : "", textAlign: TextAlign.right, style: GoogleFonts.inter(fontSize: 12))),
                                ],
                              ),
                            )),
                        if (widget.scope.isSuperAdmin && !reversed && t["type"] != "reversal")
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(onPressed: () => _reverse(t), child: const Text("Reverse", style: TextStyle(color: kTerracotta))),
                          ),
                      ],
                    ),
                  );
                }),
              ],
            ),
    );
  }
}

class _AuditPage extends StatefulWidget {
  final LedgerScope scope;
  const _AuditPage({required this.scope});

  @override
  State<_AuditPage> createState() => _AuditPageState();
}

class _AuditPageState extends State<_AuditPage> with LedgerAutoRefresh {
  @override
  void onLedgerChanged() => _load();

  List<Map<String, dynamic>> _logs = [];
  bool _loading = true;
  String _action = "All";

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await LedgerService.auditLog(widget.scope.companyId, widget.scope.userId);
    if (!mounted) return;
    setState(() {
      _logs = List<Map<String, dynamic>>.from(res["logs"] ?? const []);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final actions = {"All", ..._logs.map((l) => l["action"].toString())}.toList();
    final shown = _action == "All" ? _logs : _logs.where((l) => l["action"] == _action).toList();
    return _page(
      "Audit log",
      _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _action,
                  isExpanded: true,
                  decoration: fieldDecoration("Filter by action", icon: Icons.filter_list_rounded).copyWith(fillColor: Colors.white),
                  items: actions
                      .map((a) => DropdownMenuItem(
                            value: a,
                            child: Text(a == "All" ? "All actions" : a.replaceAll("_", " ")),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _action = v ?? "All"),
                ),
                const SizedBox(height: 10),
                if (shown.isEmpty) emptyState("No activity recorded"),
                ...shown.map((l) {
                  final at = DateTime.tryParse(l["at"]?.toString() ?? "")?.toLocal();
                  final flagged = l["action"] == "reverse" || l["action"] == "verify";
                  return ledgerCard(
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("${nameOf(l["userId"], "Someone")} · ${l["action"]} ${l["object"]}", style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: kDark)),
                              Text(at == null ? "" : DateFormat("dd MMM yyyy, hh:mm a").format(at), style: GoogleFonts.inter(fontSize: 12, color: kDark.withValues(alpha: 0.6))),
                            ],
                          ),
                        ),
                        if (flagged) statusPill(l["action"].toString(), l["action"] == "reverse" ? kTerracotta : kMint),
                      ],
                    ),
                  );
                }),
              ],
            ),
    );
  }
}

class _SettingsPage extends StatefulWidget {
  final LedgerScope scope;
  const _SettingsPage({required this.scope});

  @override
  State<_SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<_SettingsPage> with LedgerAutoRefresh {
  late List<Map<String, dynamic>> _members = widget.scope.members;

  // Only members and the join code refresh live; the form fields keep whatever is being typed.
  @override
  void onLedgerChanged() async {
    final res = await LedgerService.companyDetails(widget.scope.companyId, widget.scope.userId);
    if (!mounted || res["success"] != true) return;
    final company = Map<String, dynamic>.from(res["company"]);
    setState(() {
      _members = List<Map<String, dynamic>>.from(res["members"] ?? const []);
      if (company["joinCode"] != null) _joinCode = company["joinCode"].toString();
      _codeCreated = DateTime.tryParse(company["joinCodeCreatedAt"]?.toString() ?? "")?.toLocal() ?? _codeCreated;
    });
  }

  late final _gstin = TextEditingController(text: widget.scope.company["gstin"]?.toString() ?? "");
  late final _currency = TextEditingController(text: widget.scope.company["currency"]?.toString() ?? "INR");
  late final _threshold = TextEditingController(text: widget.scope.company["verificationThreshold"]?.toString() ?? "");
  bool _saving = false;
  late String _joinCode = widget.scope.company["joinCode"]?.toString() ?? "------";
  late DateTime? _codeCreated = DateTime.tryParse(widget.scope.company["joinCodeCreatedAt"]?.toString() ?? "")?.toLocal();

  bool get _codeExpired => _codeCreated == null || DateTime.now().difference(_codeCreated!).inMinutes >= 5;

  Future<void> _newCode() async {
    final res = await LedgerService.regenerateJoinCode(widget.scope.companyId, widget.scope.userId);
    if (!mounted) return;
    if (handleResult(context, res, "New code generated — valid for 5 minutes")) {
      setState(() {
        _joinCode = res["joinCode"].toString();
        _codeCreated = DateTime.now();
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final res = await LedgerService.updateSettings(widget.scope.companyId, {
      "userId": widget.scope.userId,
      "gstin": _gstin.text.trim(),
      "currency": _currency.text.trim(),
      "verificationThreshold": _threshold.text.trim().isEmpty ? null : double.tryParse(_threshold.text.trim()),
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (handleResult(context, res, "Settings saved")) widget.scope.reload();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scope;
    return _page(
      "Settings",
      ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (s.isAdmin)
            ledgerCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Join code", style: labelStyle),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _joinCode,
                          style: GoogleFonts.fraunces(
                            fontSize: 30,
                            letterSpacing: 6,
                            fontWeight: FontWeight.bold,
                            color: _codeExpired ? kDark.withValues(alpha: 0.35) : kForest,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: "Copy",
                        icon: const Icon(Icons.copy_rounded, color: kForest),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _joinCode));
                          toast(context, "Code copied");
                        },
                      ),
                    ],
                  ),
                  Text(
                    _codeExpired ? "Expired — generate a new code to invite someone." : "Valid for 5 minutes after it's generated.",
                    style: GoogleFonts.inter(fontSize: 11.5, color: _codeExpired ? kTerracotta : kDark.withValues(alpha: 0.6)),
                  ),
                  const SizedBox(height: 10),
                  primaryButton("Generate new code", _newCode, color: kForestDark),
                ],
              ),
            ),
          ledgerCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.companyName, style: GoogleFonts.fraunces(fontSize: 18, fontWeight: FontWeight.bold, color: kDark)),
                const SizedBox(height: 12),
                TextField(controller: _gstin, enabled: s.isAdmin, decoration: fieldDecoration("GSTIN", icon: Icons.badge_rounded)),
                const SizedBox(height: 10),
                TextField(controller: _currency, enabled: s.isAdmin, decoration: fieldDecoration("Currency", icon: Icons.currency_exchange_rounded)),
                const SizedBox(height: 10),
                TextField(
                  controller: _threshold,
                  enabled: s.isAdmin,
                  keyboardType: TextInputType.number,
                  decoration: fieldDecoration("Verification threshold ₹ (empty = off)", icon: Icons.verified_user_rounded),
                ),
                const SizedBox(height: 6),
                Text("Payments above this need a second admin to verify.", style: GoogleFonts.inter(fontSize: 11.5, color: kDark.withValues(alpha: 0.6))),
                if (s.isAdmin) ...[const SizedBox(height: 14), primaryButton(_saving ? "Saving..." : "Save", _saving ? null : _save)],
              ],
            ),
          ),
          sectionTitle("Members (${_members.length})"),
          ..._members.map((m) => ledgerCard(
                padding: EdgeInsets.zero,
                child: ListTile(
                  leading: CircleAvatar(backgroundColor: kForest, child: Text((m["name"]?.toString() ?? "M")[0].toUpperCase(), style: const TextStyle(color: Colors.white))),
                  title: Text(m["name"]?.toString() ?? "Member", style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: kDark)),
                  subtitle: Text(m["role"] == "admin" ? "Admin" : "Employee"),
                ),
              )),
        ],
      ),
    );
  }
}
