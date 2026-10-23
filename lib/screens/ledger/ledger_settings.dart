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
    final target = _inviteTarget(_role);
    final res = await LedgerService.addMember(s.companyId, s.userId, email, target.role, customRoleId: target.customRoleId);
    if (!mounted) return;
    setState(() => _adding = false);
    if (res["success"] == true) {
      toast(context, "${res["member"]?["name"] ?? email} added as ${target.label}");
      _email.clear();
      notifyLedgerChanged();
      return;
    }
    if (res["code"] == "USER_NOT_FOUND") {
      final send = await confirmDialog(
        context,
        "Not a Q Fin user yet",
        "$email is not in the user list. Send an invite link to their email? Once they sign up with this email, they'll join ${s.companyName} as ${target.label}.",
        confirmLabel: "Send invite",
      );
      if (!send || !mounted) return;
      final inv = await LedgerService.inviteMember(s.companyId, s.userId, email, target.role, customRoleId: target.customRoleId);
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

  List<Map<String, dynamic>> get _customRoles => List<Map<String, dynamic>>.from(_company["customRoles"] ?? const []);

  // the role picker's value: "member" | "admin" | "role:" + a custom role id
  ({String role, String? customRoleId, String label}) _inviteTarget(String value) {
    if (value.startsWith("role:")) {
      final id = value.substring(5);
      final r = _customRoles.where((x) => x["_id"].toString() == id).firstOrNull;
      return (role: r?["base"] == "manager" ? "admin" : "member", customRoleId: id, label: "\"${r?["name"] ?? "custom role"}\"");
    }
    return (role: value, customRoleId: null, label: value == "admin" ? "a manager" : "staff");
  }

  // primary admin only: puts a member into one of the custom roles
  Future<void> _setCustomRole(Map<String, dynamic> m, String roleId) async {
    final res = await LedgerService.setMemberCustomRole(s.companyId, m["userId"].toString(), s.userId, roleId);
    if (!mounted) return;
    if (handleResult(context, res, "Role updated")) notifyLedgerChanged();
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
              // custom roles: only the primary admin can add people into them
              if (s.isPrimary && _customRoles.isNotEmpty)
                DropdownButtonFormField<String>(
                  initialValue: _role,
                  isExpanded: true,
                  decoration: fieldDecoration("Role", icon: Icons.badge_rounded),
                  items: [
                    const DropdownMenuItem(value: "member", child: Text("Staff")),
                    const DropdownMenuItem(value: "admin", child: Text("Manager")),
                    for (final r in _customRoles) DropdownMenuItem(value: "role:${r["_id"]}", child: Text(r["name"].toString(), overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setState(() => _role = v ?? "member"),
                )
              else
                SegmentedButton<String>(
                  segments: const [ButtonSegment(value: "member", label: Text("Staff")), ButtonSegment(value: "admin", label: Text("Manager"))],
                  selected: {_role.startsWith("role:") ? "member" : _role},
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
                final customRole = m["customRoleName"]?.toString() ?? "";
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
                        Text("${isCreator ? "Manager · Creator" : (customRole.isNotEmpty ? "$customRole · ${isManager ? "manager-like" : "staff-like"}" : (isManager ? "Manager" : "Staff"))}${(m["email"]?.toString() ?? "").isNotEmpty ? " · ${m["email"]}" : ""}",
                            style: GoogleFonts.inter(fontSize: 11.5, color: kDark.withValues(alpha: 0.55))),
                      ]),
                    ),
                    if (s.isAdmin && s.can("members") && !isCreator && !isMe)
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert_rounded, color: kDark),
                        onSelected: (v) => v == "remove"
                            ? _remove(m)
                            : v.startsWith("role:")
                                ? _setCustomRole(m, v.substring(5))
                                : _setRole(m, v),
                        itemBuilder: (_) => [
                          // someone in a custom role: only the primary admin can change them
                          if (customRole.isEmpty || s.isPrimary) ...[
                            if (customRole.isNotEmpty || !isManager) const PopupMenuItem(value: "admin", child: Text("Make manager")),
                            if (customRole.isNotEmpty || isManager) const PopupMenuItem(value: "member", child: Text("Make staff")),
                          ],
                          if (s.isPrimary)
                            for (final r in List<Map<String, dynamic>>.from(_company["customRoles"] ?? const []))
                              if (r["_id"].toString() != m["customRoleId"]?.toString())
                                PopupMenuItem(value: "role:${r["_id"]}", child: Text("Make ${r["name"]}")),
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
