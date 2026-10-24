import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../services/ledger_service.dart';
import 'ledger_common.dart';
import 'ledger_funds.dart';
import 'ledger_settings.dart';
import 'ledger_vouchers.dart';
import 'ledger_payments.dart';
import 'ledger_permissions.dart';

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
        if (scope.isAdmin && scope.can("vouchers")) item(Icons.confirmation_number_rounded, "Vouchers", "Money given to staff up front, claims and hand-backs", VouchersPage(scope: scope)),
        if (scope.isAdmin && scope.can("reimburse")) item(Icons.payments_rounded, "Payments", "Pay staff and managers, by company or yourself", PaymentsPage(scope: scope)),
        if (scope.isAdmin && scope.can("funds")) item(Icons.account_balance_wallet_rounded, "Company funds", "${scope.cashName}, bank accounts and income", FundsPage(scope: scope)),
        if (scope.isAdmin && scope.can("ledger_audit")) item(Icons.menu_book_rounded, "Ledger", "Every transaction and its entries", _LedgerPage(scope: scope)),
        if (scope.isAdmin && scope.can("ledger_audit")) item(Icons.history_rounded, "Audit log", "Who did what, and when", _AuditPage(scope: scope)),
        if (scope.canOpenSettings) item(Icons.settings_rounded, "Settings", "Company details and members", SettingsPage(scope: scope)),
        if (scope.canEditPermissions) item(Icons.admin_panel_settings_rounded, "Permissions", "Turn features on or off for managers and staff", PermissionsPage(scope: scope)),
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
        title: Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
      ),
      body: body,
    ));

const Map<String, String> _txLabels = {
  "admin_paid": "Paid by manager",
  "company_paid": "Paid by company",
  "borrowed": "Paid with borrowed money",
  "reimburse": "Reimbursement",
  "lend": "Manager loan to company",
  "intercompany": "Inter-company",
  "routed": "Routed payment",
  "loan_repayment": "Loan repayment",
  "reversal": "Reversal",
  "voucher_issue": "Voucher given",
  "voucher_claim": "Voucher claimed",
  "advance_used": "Voucher balance used",
  "advance_offset": "Voucher balance set off",
  "advance_return": "Voucher balance handed back",
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

  @override
  Set<String> get ledgerTopics => const {"ledger"};

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
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              children: [
                if (_txs.isEmpty) emptyState("No transactions yet"),
                ..._txs.map((t) {
                  final reversed = t["reversedBy"] != null;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(_txLabels[t["type"]] ?? t["type"].toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: kDark))),
                            if (reversed) statusPill("Reversed", kTerracotta),
                            if (t["verification"] == "pending") statusPill("Pending verification", kAmber),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text("${t["memo"]} · ${dateLabel(t["createdAt"])} · ${nameOf(t["createdBy"])}",
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(fontSize: 11, height: 1.2, color: kDark.withValues(alpha: 0.6))),
                        const Divider(height: 8, thickness: 0.7),
                        ...(t["entries"] as List? ?? const []).map((e) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 1),
                              child: Row(
                                children: [
                                  Expanded(child: Text(nameOf(e["accountId"], "Account"), maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 11.5, color: kDark))),
                                  SizedBox(width: 80, child: Text((e["debit"] ?? 0) > 0 ? "Dr ${inr(e["debit"])}" : "", textAlign: TextAlign.right, style: GoogleFonts.inter(fontSize: 11.5))),
                                  SizedBox(width: 80, child: Text((e["credit"] ?? 0) > 0 ? "Cr ${inr(e["credit"])}" : "", textAlign: TextAlign.right, style: GoogleFonts.inter(fontSize: 11.5))),
                                ],
                              ),
                            )),
                        // the super admin, or a custom role with "Reverse ledger transactions"
                        if ((widget.scope.isSuperAdmin || (widget.scope.permissionRole == "custom" && widget.scope.permissions?["reverse_transactions"] == true)) &&
                            !reversed &&
                            t["type"] != "reversal")
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              style: TextButton.styleFrom(minimumSize: const Size(0, 30), padding: const EdgeInsets.symmetric(horizontal: 8), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                              onPressed: () => _reverse(t),
                              child: const Text("Reverse", style: TextStyle(color: kTerracotta)),
                            ),
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

  @override
  Set<String> get ledgerTopics => const {"ledger"};

  List<Map<String, dynamic>> _logs = [];
  bool _loading = true;
  String? _error;
  String _action = "All";

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await LedgerService.auditLog(widget.scope.companyId, widget.scope.userId);
    if (!mounted) return;
    setState(() {
      if (res["success"] == false && res["logs"] == null) {
        _error = res["message"]?.toString() ?? "Failed to load audit logs";
        _logs = [];
      } else {
        _error = null;
        _logs = List<Map<String, dynamic>>.from(res["logs"] ?? const []);
      }
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
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.cloud_off_rounded, size: 48, color: Colors.white70),
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: kForest,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text("Retry"),
                          onPressed: _load,
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  color: kForest,
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    physics: const AlwaysScrollableScrollPhysics(),
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
                                    Text("${nameOf(l["userId"], "Someone")} · ${l["action"].toString().replaceAll("_", " ")} ${l["object"].toString().replaceAll("advance_return", "hand-back").replaceAll("_", " ")}", style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: kDark)),
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
                ),
    );
  }
}

