import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/ledger_service.dart';
import 'ledger_common.dart';
import 'ledger_company_logo.dart';

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
    _loadInvites();
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
    _loadInvites(); // someone may have signed up and joined
  }

  // emailed invites and whether each person has signed up yet
  List<Map<String, dynamic>> _invites = [];
  String? _inviteBusy;

  Future<void> _loadInvites() async {
    if (!(s.isAdmin && s.can("members"))) return;
    final res = await LedgerService.invites(s.companyId, s.userId);
    if (mounted && res["success"] == true) setState(() => _invites = List<Map<String, dynamic>>.from(res["invites"] ?? const []));
  }

  Future<void> _resendInvite(Map<String, dynamic> inv) async {
    setState(() => _inviteBusy = inv["_id"].toString());
    final res = await LedgerService.inviteMember(s.companyId, s.userId, inv["email"].toString(), inv["role"].toString(), customRoleId: inv["customRoleId"]?.toString());
    if (!mounted) return;
    setState(() => _inviteBusy = null);
    handleResult(context, res, "Invite sent again to ${inv["email"]}");
    _loadInvites();
  }

  Future<void> _cancelInvite(Map<String, dynamic> inv) async {
    final yes = await confirmDialog(context, "Cancel this invite?", "${inv["email"]} won't be added to ${s.companyName} when they sign up. You can invite them again later.",
        confirmLabel: "Cancel invite", danger: true);
    if (!yes || !mounted) return;
    setState(() => _inviteBusy = inv["_id"].toString());
    final res = await LedgerService.cancelInvite(s.companyId, inv["_id"].toString(), s.userId);
    if (!mounted) return;
    setState(() => _inviteBusy = null);
    handleResult(context, res, "Invite to ${inv["email"]} cancelled");
    _loadInvites();
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
      _loadInvites(); // saved even when the email fails
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
  // Admins only: someone an Admin makes Admin gets full access, like the creator
  Future<void> _setAdmin(Map<String, dynamic> m, bool admin) async {
    final name = m["name"]?.toString() ?? "this member";
    if (admin) {
      final ok = await confirmDialog(context, "Make $name an Admin?",
          "They get full access, exactly like you: every feature, permissions, roles, and deleting the company.");
      if (!ok || !mounted) return;
    }
    final res = await LedgerService.setMemberAdmin(s.companyId, m["userId"].toString(), s.userId, admin);
    if (!mounted) return;
    if (handleResult(context, res, admin ? "$name is now an Admin" : "$name is no longer an Admin")) notifyLedgerChanged();
  }

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

  bool _savingLogo = false;

  Future<void> _pickLogo() async {
    final logo = await pickCompanyLogo();
    if (logo != null) await _saveLogo(logo);
  }

  Future<void> _saveLogo(String logo) async {
    setState(() => _savingLogo = true);
    final res = await LedgerService.setCompanyLogo(s.companyId, s.userId, logo);
    if (!mounted) return;
    setState(() => _savingLogo = false);
    if (handleResult(context, res, logo.isEmpty ? "Logo removed" : "Logo updated")) {
      setState(() => _company = {..._company, "logo": logo});
      s.reload();
    }
  }

  Widget _inviteRow(Map<String, dynamic> inv) {
    final joined = inv["status"] == "accepted";
    final sent = inv["emailSent"] == true;
    final (String text, Color color, Color bg, IconData icon) = joined
        ? ("Joined${inv["acceptedAt"] != null ? " · ${dateLabel(inv["acceptedAt"])}" : ""}", kForest, const Color(0xFFE8F7EF), Icons.check_circle_rounded)
        : sent
            ? ("Invite sent${inv["sentAt"] != null ? " · ${dateLabel(inv["sentAt"])}" : ""} · waiting to sign up", const Color(0xFFB45309), const Color(0xFFFFF7ED), Icons.mark_email_unread_rounded)
            : ("Email not sent · resend it", kTerracotta, const Color(0xFFFEF2F2), Icons.error_rounded);
    final busy = _inviteBusy == inv["_id"].toString();
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: kDark.withValues(alpha: 0.06)))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(inv["email"].toString(), style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13.5, color: kDark)),
        Text("as ${inv["roleName"] ?? s.roleLabel(inv["role"])}${inv["invitedBy"] != null ? " · by ${inv["invitedBy"]}" : ""}",
            style: GoogleFonts.inter(fontSize: 11.5, color: kDark.withValues(alpha: 0.55))),
        const SizedBox(height: 6),
        Row(children: [
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 4),
                Flexible(child: Text(text, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700, color: color))),
              ]),
            ),
          ),
          if (!joined) ...[
            const Spacer(),
            TextButton(onPressed: busy ? null : () => _resendInvite(inv), child: const Text("Resend")),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: kTerracotta),
              onPressed: busy ? null : () => _cancelInvite(inv),
              child: const Text("Cancel"),
            ),
          ],
        ]),
      ]),
    );
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
          // logo first, on the company tiles: the primary Admin only (the server checks too)
          if (s.isPrimary)
            card("Company logo", sub: "Shown on the company tile for everyone in ${s.companyName}.", children: [
              Row(children: [
                CompanyAvatar(company: _company, size: 56, radius: 14),
                const SizedBox(width: 14),
                Expanded(
                  child: Wrap(spacing: 8, runSpacing: 6, children: [
                    ElevatedButton(
                      onPressed: _savingLogo ? null : _pickLogo,
                      child: Text(_savingLogo ? "Saving…" : (_company["logo"]?.toString().isNotEmpty ?? false) ? "Change" : "Upload logo"),
                    ),
                    if (_company["logo"]?.toString().isNotEmpty ?? false)
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(foregroundColor: kTerracotta, side: const BorderSide(color: kTerracotta)),
                        onPressed: _savingLogo ? null : () => _saveLogo(""),
                        child: const Text("Remove"),
                      ),
                  ]),
                ),
              ]),
            ]),
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
              if (s.canManageRoles && _customRoles.isNotEmpty)
                DropdownButtonFormField<String>(
                  initialValue: _role,
                  isExpanded: true,
                  decoration: fieldDecoration("Role", icon: Icons.badge_rounded),
                  items: [
                    DropdownMenuItem(value: "member", child: Text(s.staffName)),
                    DropdownMenuItem(value: "admin", child: Text(s.managerName)),
                    for (final r in _customRoles) DropdownMenuItem(value: "role:${r["_id"]}", child: Text(r["name"].toString(), overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setState(() => _role = v ?? "member"),
                )
              else
                SegmentedButton<String>(
                  segments: [ButtonSegment(value: "member", label: Text(s.staffName)), ButtonSegment(value: "admin", label: Text(s.managerName))],
                  selected: {_role.startsWith("role:") ? "member" : _role},
                  onSelectionChanged: (v) => setState(() => _role = v.first),
                ),
              const SizedBox(height: 10),
              primaryButton(_adding ? "Adding…" : "Add member", _adding ? null : _addMember),
            ]),
          // emailed invites: sent and waiting / email not sent / joined
          if (s.isAdmin && s.can("members") && _invites.isNotEmpty)
            card("Invites",
                sub: "${_invites.where((i) => i["status"] != "accepted").length} waiting to sign up · ${_invites.where((i) => i["status"] == "accepted").length} joined",
                children: [
                  for (final inv in _invites) _inviteRow(inv),
                ]),
          // the count is staff only; managers (incl. the creator) are listed but not counted
          card("${s.staffsName} (${_members.where((m) => m["role"] != "admin").length}) · ${_members.where((m) => m["role"] == "admin").length} ${(_members.where((m) => m["role"] == "admin").length == 1 ? s.managerName : s.managersName).toLowerCase()}", children: [
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
                        Text("${isCreator ? "Admin · Creator" : m["isAdmin"] == true ? "Admin" : (customRole.isNotEmpty ? customRole : (isManager ? s.managerName : s.staffName))}${(m["email"]?.toString() ?? "").isNotEmpty ? " · ${m["email"]}" : ""}",
                            style: GoogleFonts.inter(fontSize: 11.5, color: kDark.withValues(alpha: 0.55))),
                      ]),
                    ),
                    // an Admin can only be changed by an Admin
                    if (s.isAdmin && (s.can("members") || s.isPrimary) && !isCreator && !isMe && (m["isAdmin"] != true || s.isPrimary))
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert_rounded, color: kDark),
                        onSelected: (v) => v == "remove"
                            ? _remove(m)
                            : v == "coadmin" || v == "uncoadmin"
                                ? _setAdmin(m, v == "coadmin")
                            : v.startsWith("role:")
                                ? _setCustomRole(m, v.substring(5))
                                : _setRole(m, v),
                        itemBuilder: (_) => [
                          // someone in a custom role: only the primary admin can change them
                          if (s.isPrimary)
                            m["isAdmin"] == true
                                ? const PopupMenuItem(value: "uncoadmin", child: Text("Remove Admin access"))
                                : const PopupMenuItem(value: "coadmin", child: Text("Make Admin")),
                          if (customRole.isEmpty || s.canManageRoles) ...[
                            if (customRole.isNotEmpty || !isManager) PopupMenuItem(value: "admin", child: Text("Make ${s.managerName.toLowerCase()}")),
                            if (customRole.isNotEmpty || isManager) PopupMenuItem(value: "member", child: Text("Make ${s.staffName.toLowerCase()}")),
                          ],
                          if (s.canManageRoles)
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
          // the primary admin (company creator), or a custom role with "Delete the company"
          if (creatorId == s.userId || s.isPrimary || s.permissions?["delete_company"] == true)
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
