import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/ledger_service.dart';
import 'ledger_common.dart';

/// Company settings for both roles (web's SettingsPanel): join code, members, categories, configuration, danger zone.
class SettingsPage extends StatefulWidget {
  final LedgerScope scope;
  const SettingsPage({super.key, required this.scope});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> with LedgerAutoRefresh {
  LedgerScope get s => widget.scope;
  late List<Map<String, dynamic>> _members = s.members;
  late Map<String, dynamic> _company = s.company;
  late String _joinCode = s.company["joinCode"]?.toString() ?? "------";
  late DateTime? _codeCreated = DateTime.tryParse(s.company["joinCodeCreatedAt"]?.toString() ?? "")?.toLocal();
  late final _gstin = TextEditingController(text: s.company["gstin"]?.toString() ?? "");
  late final _currency = TextEditingController(text: s.company["currency"]?.toString() ?? "INR");
  late final _threshold = TextEditingController(text: s.company["verificationThreshold"]?.toString() ?? "");
  final _email = TextEditingController();
  String _role = "member";
  bool _adding = false;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _secondsLeft >= 0) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _gstin.dispose();
    _currency.dispose();
    _threshold.dispose();
    _email.dispose();
    super.dispose();
  }

  // Members, categories and the join code refresh live; the form fields keep whatever is being typed.
  @override
  Set<String> get ledgerTopics => const {"members", "company", "permissions"};

  @override
  void onLedgerChanged() async {
    final res = await LedgerService.companyDetails(s.companyId, s.userId);
    if (!mounted || res["success"] != true) return;
    final company = Map<String, dynamic>.from(res["company"]);
    setState(() {
      _company = company;
      _members = List<Map<String, dynamic>>.from(res["members"] ?? const []);
      if (company["joinCode"] != null) _joinCode = company["joinCode"].toString();
      _codeCreated = DateTime.tryParse(company["joinCodeCreatedAt"]?.toString() ?? "")?.toLocal() ?? _codeCreated;
    });
  }

  int get _secondsLeft => _codeCreated == null ? 0 : 300 - DateTime.now().difference(_codeCreated!).inSeconds;

  Future<void> _newCode() async {
    final res = await LedgerService.regenerateJoinCode(s.companyId, s.userId);
    if (!mounted) return;
    if (handleResult(context, res, "New code generated — valid for 5 minutes")) {
      setState(() {
        _joinCode = res["joinCode"].toString();
        _codeCreated = DateTime.now();
      });
    }
  }

  Future<void> _addMember() async {
    final email = _email.text.trim();
    if (email.isEmpty) return toast(context, "Enter the member's email address", error: true);
    setState(() => _adding = true);
    final res = await LedgerService.addMember(s.companyId, s.userId, email, _role);
    if (!mounted) return;
    setState(() => _adding = false);
    if (res["success"] == true) {
      toast(context, "${res["member"]?["name"] ?? email} added as ${_role == "admin" ? "manager" : "staff"}");
      _email.clear();
      notifyLedgerChanged();
      return;
    }
    if (res["code"] == "USER_NOT_FOUND") {
      final send = await confirmDialog(
        context,
        "Not a Q Fin user yet",
        "$email is not in the user list. Send an invite link to their email? Once they sign up with this email, they'll join ${s.companyName} as ${_role == "admin" ? "a manager" : "staff"}.",
        confirmLabel: "Send invite",
      );
      if (!send || !mounted) return;
      final inv = await LedgerService.inviteMember(s.companyId, s.userId, email, _role);
      if (!mounted) return;
      if (handleResult(context, inv, "Invite sent to $email")) _email.clear();
      return;
    }
    toast(context, res["message"]?.toString() ?? "Failed to add staff", error: true);
  }

  Future<void> _setRole(Map<String, dynamic> m, String role) async {
    final name = m["name"]?.toString() ?? "this member";
    final ok = await confirmDialog(
      context,
      role == "admin" ? "Make $name a manager?" : "Make $name staff?",
      role == "admin"
          ? "They will be able to approve, pay and reimburse expenses, and see all company data."
          : "They will see staff expenses and manager expenses shared with them.",
    );
    if (!ok || !mounted) return;
    final res = await LedgerService.setMemberRole(s.companyId, s.userId, m["userId"].toString(), role);
    if (!mounted) return;
    if (handleResult(context, res, role == "admin" ? "$name is now a manager" : "$name is now staff")) notifyLedgerChanged();
  }

  Future<void> _remove(Map<String, dynamic> m) async {
    final ok = await confirmDialog(context, "Remove staff?", "Remove ${m["name"]} from ${s.companyName}? They can rejoin later with the join code.",
        confirmLabel: "Remove", danger: true);
    if (!ok || !mounted) return;
    final res = await LedgerService.removeMember(s.companyId, m["userId"].toString(), s.userId);
    if (!mounted) return;
    if (handleResult(context, res, "${m["name"]} removed")) notifyLedgerChanged();
  }

  Future<void> _save() async {
    final res = await LedgerService.updateSettings(s.companyId, {
      "userId": s.userId,
      "gstin": _gstin.text.trim(),
      "currency": _currency.text.trim(),
      "verificationThreshold": _threshold.text.trim().isEmpty ? null : double.tryParse(_threshold.text.trim()),
    });
    if (!mounted) return;
    if (handleResult(context, res, "Settings saved")) notifyLedgerChanged();
  }

  Future<void> _deleteCompany() async {
    final ok = await confirmDialog(context, "Delete company?", "This permanently deletes ${s.companyName} and all its expenses for everyone. This cannot be undone.",
        confirmLabel: "Delete", danger: true);
    if (!ok || !mounted) return;
    final res = await LedgerService.deleteCompany(s.companyId, s.userId);
    if (!mounted) return;
    if (handleResult(context, res, "${s.companyName} deleted")) {
      // leave the settings page and the company workspace, back to the company list
      Navigator.of(context)
        ..pop()
        ..pop();
    }
  }

  void _manageCategories() {
    final add = TextEditingController();
    showLedgerSheet(context, "Expense categories", (ctx) => StatefulBuilder(builder: (ctx, set) {
          final list = companyCategories(_company);
          Future<void> addOne() async {
            final name = add.text.trim();
            if (name.isEmpty) return;
            final res = await LedgerService.addCategory(s.companyId, s.userId, name);
            if (!ctx.mounted) return;
            if (handleResult(ctx, res, "$name added")) {
              set(() {
                _company = {
                  ..._company,
                  if (res["customCategories"] != null) "customCategories": res["customCategories"],
                  if (res["hiddenCategories"] != null) "hiddenCategories": res["hiddenCategories"],
                };
                add.clear();
              });
              notifyLedgerChanged();
            }
          }

          Future<void> remove(String name) async {
            final ok = await confirmDialog(ctx, "Delete category?", "\"$name\" won't be offered when posting expenses. Existing expenses keep it.", confirmLabel: "Delete", danger: true);
            if (!ok || !ctx.mounted) return;
            final res = await LedgerService.deleteCategory(s.companyId, s.userId, name);
            if (!ctx.mounted) return;
            if (handleResult(ctx, res, "$name removed")) {
              set(() => _company = {
                    ..._company,
                    if (res["customCategories"] != null) "customCategories": res["customCategories"],
                    if (res["hiddenCategories"] != null) "hiddenCategories": res["hiddenCategories"],
                  });
              notifyLedgerChanged();
            }
          }

          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("${list.length} categories offered when posting expenses.", style: GoogleFonts.inter(fontSize: 12.5, color: kDark.withValues(alpha: 0.6))),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: TextField(controller: add, decoration: fieldDecoration("New category", icon: Icons.add_rounded))),
              const SizedBox(width: 8),
              ElevatedButton(onPressed: addOne, child: const Text("Add")),
            ]),
            const SizedBox(height: 8),
            ...list.map((c) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(c),
                  subtitle: kBaseCategories.contains(c) ? const Text("Built-in") : null,
                  trailing: c == "General" ? null : IconButton(icon: const Icon(Icons.delete_outline_rounded, color: kTerracotta), onPressed: () => remove(c)),
                )),
          ]);
        }));
  }

  @override
  Widget build(BuildContext context) {
    final expired = _secondsLeft <= 0;
    final timer = expired ? "Expired" : "Valid for ${(_secondsLeft ~/ 60)}:${(_secondsLeft % 60).toString().padLeft(2, "0")}";
    final creatorId = idOf(_company["createdBy"]);

    Widget card(String title, {String? sub, required List<Widget> children, Color? titleColor}) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: titleColor ?? kDark)),
            if (sub != null) Padding(padding: const EdgeInsets.only(top: 2, bottom: 10), child: Text(sub, style: GoogleFonts.inter(fontSize: 12.5, color: kDark.withValues(alpha: 0.6)))),
            if (sub == null) const SizedBox(height: 10),
            ...children,
          ]),
        );

    return Theme(
      data: sheetTheme,
      child: Scaffold(
        backgroundColor: kForest,
        appBar: AppBar(backgroundColor: kForest, foregroundColor: Colors.white, elevation: 0, title: Text("Settings", style: GoogleFonts.inter(fontWeight: FontWeight.bold))),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 30), children: [
          if (s.isAdmin && s.can("settings"))
            card("Join code", sub: "Share it with staff so they can join ${s.companyName}.", children: [
              Row(children: [
                Expanded(child: Text(_joinCode, style: GoogleFonts.ibmPlexMono(fontSize: 28, letterSpacing: 6, fontWeight: FontWeight.bold, color: expired ? kDark.withValues(alpha: 0.35) : kForest))),
                IconButton(
                  tooltip: "Copy",
                  icon: const Icon(Icons.copy_rounded, color: kForest),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _joinCode));
                    toast(context, "Code copied");
                  },
                ),
              ]),
              Text(timer, style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: expired ? kTerracotta : kForest)),
              const SizedBox(height: 10),
              primaryButton("Generate new code", _newCode, color: kForestDark),
            ]),
          if (s.isAdmin && s.can("members"))
            card("Direct member invite", sub: "Add a registered user directly by email, or invite someone new to sign up and join.", children: [
              TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: fieldDecoration("colleague@example.com", icon: Icons.email_rounded)),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [ButtonSegment(value: "member", label: Text("Staff")), ButtonSegment(value: "admin", label: Text("Manager"))],
                selected: {_role},
                onSelectionChanged: (v) => setState(() => _role = v.first),
              ),
              const SizedBox(height: 10),
              primaryButton(_adding ? "Adding…" : "Add member", _adding ? null : _addMember),
            ]),
          // the count is staff only; managers (incl. the creator) are listed but not counted
          card("Staff (${_members.where((m) => m["role"] != "admin").length}) · ${_members.where((m) => m["role"] == "admin").length} manager${_members.where((m) => m["role"] == "admin").length == 1 ? "" : "s"}", children: [
            for (final m in _members)
              Builder(builder: (_) {
                final id = m["userId"].toString();
                final isManager = m["role"] == "admin";
                final isCreator = id == creatorId;
                final isMe = id == s.userId;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: kForest,
                      child: Text((m["name"]?.toString() ?? "M").characters.first.toUpperCase(), style: const TextStyle(color: Colors.white)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text("${m["name"] ?? "Member"}${isMe ? " (You)" : ""}", style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: kDark)),
                        Text("${isCreator ? "Manager · Creator" : (isManager ? "Manager" : "Staff")}${(m["email"]?.toString() ?? "").isNotEmpty ? " · ${m["email"]}" : ""}",
                            style: GoogleFonts.inter(fontSize: 11.5, color: kDark.withValues(alpha: 0.55))),
                      ]),
                    ),
                    if (s.isAdmin && s.can("members") && !isCreator && !isMe)
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert_rounded, color: kDark),
                        onSelected: (v) => v == "remove" ? _remove(m) : _setRole(m, v),
                        itemBuilder: (_) => [
                          PopupMenuItem(value: isManager ? "member" : "admin", child: Text(isManager ? "Make staff" : "Make manager")),
                          const PopupMenuItem(value: "remove", child: Text("Remove from company", style: TextStyle(color: kTerracotta))),
                        ],
                      ),
                  ]),
                );
              }),
          ]),
          if (s.isAdmin && s.can("settings"))
            card("Expense categories", sub: "${companyCategories(_company).length} categories offered when posting expenses.", children: [
              OutlinedButton(onPressed: _manageCategories, child: const Text("Manage categories")),
            ]),
          card("Company configuration", sub: s.isAdmin ? "Configure financial identification, currency and transaction approval threshold." : null, children: [
            TextField(controller: _gstin, enabled: s.isAdmin && s.can("settings"), textCapitalization: TextCapitalization.characters, decoration: fieldDecoration("GSTIN / Tax ID", icon: Icons.badge_rounded)),
            const SizedBox(height: 10),
            TextField(controller: _currency, enabled: s.isAdmin && s.can("settings"), decoration: fieldDecoration("Currency", icon: Icons.currency_exchange_rounded)),
            const SizedBox(height: 10),
            TextField(controller: _threshold, enabled: s.isAdmin && s.can("settings"), keyboardType: TextInputType.number, decoration: fieldDecoration("Verification threshold ₹", icon: Icons.verified_user_rounded)),
            const SizedBox(height: 6),
            Text("Payments above this need a second manager to verify.", style: GoogleFonts.inter(fontSize: 11.5, color: kDark.withValues(alpha: 0.6))),
            if (s.isAdmin && s.can("settings")) ...[const SizedBox(height: 12), primaryButton("Save settings", _save)],
          ]),
          // only the primary admin (company creator) can delete the company
          if (creatorId == s.userId)
            card("Danger zone", titleColor: kTerracotta, sub: "Deleting the company removes it and all its expenses for everyone.", children: [
              OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: kTerracotta, side: const BorderSide(color: kTerracotta)),
                onPressed: _deleteCompany,
                child: const Text("Delete company"),
              ),
            ]),
        ]),
      ),
    );
  }
}
