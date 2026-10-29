import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/expense_company_service.dart';
import '../../services/ledger_service.dart';
import 'ledger_common.dart';

/// Settings → Your companies (the Admin): add a company, remove one from MY list (nothing is deleted) and restore
/// removed ones. Same as the web.
class CompaniesManagerCard extends StatefulWidget {
  final LedgerScope scope;
  const CompaniesManagerCard({super.key, required this.scope});

  @override
  State<CompaniesManagerCard> createState() => _CompaniesManagerCardState();
}

class _CompaniesManagerCardState extends State<CompaniesManagerCard> {
  LedgerScope get s => widget.scope;
  List<Map<String, dynamic>>? _companies;
  List<Map<String, dynamic>> _removed = [];
  bool _showRemoved = false;
  bool _adding = false;
  bool _saving = false;
  final _name = TextEditingController();
  final _details = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _details.dispose();
    super.dispose();
  }

  bool _isAdminOf(Map<String, dynamic> c) => c["isCompanyAdmin"] == true || idOf(c["createdBy"]) == s.userId;

  Future<void> _load() async {
    final res = await LedgerService.userCompaniesWithHidden(s.userId);
    if (!mounted) return;
    final all = List<Map<String, dynamic>>.from(res["companies"] ?? const []).where((c) => c["external"] != true).toList();
    setState(() {
      _companies = all.where((c) => c["hiddenFromList"] != true).toList();
      _removed = all.where((c) => c["hiddenFromList"] == true).toList();
    });
  }

  Future<void> _add() async {
    if (_name.text.trim().isEmpty) return toast(context, "Enter the company name", error: true);
    setState(() => _saving = true);
    final res = await ExpenseCompanyService.createCompany(
      userId: s.userId,
      name: _name.text.trim(),
      details: _details.text.trim(),
      userName: s.userName,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (res["success"] != true) return toast(context, res["message"]?.toString() ?? "Could not create the company", error: true);
    toast(context, "${_name.text.trim()} created · join code ${res["joinCode"] ?? ""}");
    _name.clear();
    _details.clear();
    setState(() => _adding = false);
    _load();
  }

  Future<void> _remove(Map<String, dynamic> c) async {
    final ok = await confirmDialog(
      context,
      "Remove ${c["name"]} from your list?",
      "It only disappears from your own company list. The company, its members, expenses and money are not deleted, and everyone else still sees it. You can restore it from Removed companies.",
      confirmLabel: "Remove from list",
      danger: true,
    );
    if (!ok || !mounted) return;
    final res = await LedgerService.setCompanyHidden(c["_id"].toString(), s.userId, true);
    if (!mounted) return;
    if (!handleResult(context, res, "${c["name"]} removed from your list")) return;
    _load();
  }

  Future<void> _restore(Map<String, dynamic> c) async {
    final res = await LedgerService.setCompanyHidden(c["_id"].toString(), s.userId, false);
    if (!mounted) return;
    if (handleResult(context, res, "${c["name"]} is back in your list")) _load();
  }

  @override
  Widget build(BuildContext context) {
    TextStyle sub = GoogleFonts.inter(fontSize: 12, color: kDark.withValues(alpha: 0.55));
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text("Your companies", style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: kDark))),
          TextButton(onPressed: () => setState(() => _adding = !_adding), child: Text(_adding ? "Cancel" : "+ Add company")),
        ]),
        Text("Removing a company only hides it from your own list. Nothing is deleted and others still see it.", style: sub),
        if (_adding) ...[
          const SizedBox(height: 10),
          TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: fieldDecoration("Company name *", icon: Icons.business_rounded)),
          const SizedBox(height: 8),
          TextField(controller: _details, decoration: fieldDecoration("Details (optional)", icon: Icons.notes_rounded)),
          const SizedBox(height: 10),
          primaryButton(_saving ? "Creating…" : "Create company", _saving ? null : _add),
        ],
        const SizedBox(height: 6),
        if (_companies == null)
          const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
        else
          for (final c in _companies!)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: kDark.withValues(alpha: 0.06)))),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text("${c["name"]}${c["_id"].toString() == s.companyId ? " · this company" : ""}",
                        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: kDark)),
                    Text(_isAdminOf(c) ? roleNameOf(Map<String, dynamic>.from(c), "admin") : (c["customRoleName"]?.toString() ?? s.roleLabel(c["userRole"])), style: sub),
                  ]),
                ),
                if (_isAdminOf(c))
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: kTerracotta, side: const BorderSide(color: kTerracotta), visualDensity: VisualDensity.compact),
                    onPressed: () => _remove(c),
                    child: const Text("Remove"),
                  ),
              ]),
            ),
        TextButton(
          onPressed: () => setState(() => _showRemoved = !_showRemoved),
          child: Text(_showRemoved ? "Hide removed companies" : "Removed companies (${_removed.length})"),
        ),
        if (_showRemoved)
          if (_removed.isEmpty)
            Text("You haven't removed any companies.", style: sub)
          else
            for (final c in _removed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Expanded(child: Text(c["name"].toString(), style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: kDark))),
                  OutlinedButton(onPressed: () => _restore(c), child: const Text("Restore")),
                ]),
              ),
      ]),
    );
  }
}
