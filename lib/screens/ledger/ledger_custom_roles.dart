import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/ledger_service.dart';
import 'ledger_common.dart';

/// Primary admin only (web's Custom roles): roles on top of Manager/Staff. Each has a base (manager-like members
/// see everything and are auto-approved, staff-like post for approval), its own switches (all start OFF) and its
/// members. Deleting a role removes its members from the company.
class CustomRolesSection extends StatefulWidget {
  final LedgerScope scope;
  final List<Map<String, dynamic>> definitions;
  final List<Map<String, dynamic>> roles;
  final VoidCallback onChanged;
  const CustomRolesSection({super.key, required this.scope, required this.definitions, required this.roles, required this.onChanged});

  @override
  State<CustomRolesSection> createState() => _CustomRolesSectionState();
}

class _CustomRolesSectionState extends State<CustomRolesSection> {
  LedgerScope get s => widget.scope;
  bool _busy = false;
  final Map<String, Map<String, bool>> _local = {}; // optimistic switch values per role

  Map<String, bool> _values(Map<String, dynamic> role) =>
      _local[role["_id"].toString()] ?? Map<String, bool>.from((role["permissions"] as Map? ?? const {}).map((k, v) => MapEntry(k.toString(), v == true)));

  bool _blocked(Map<String, dynamic> def, Map<String, dynamic> role) => def["only"] != null && def["only"] != role["base"];

  /// Runs a save; on success toasts [ok], refreshes everyone and returns the response, otherwise shows the error.
  Future<Map<String, dynamic>?> _run(Future<Map<String, dynamic>> Function() call, {String? ok}) async {
    setState(() => _busy = true);
    final res = await call();
    if (!mounted) return null;
    setState(() => _busy = false);
    if (res["success"] != true) {
      toast(context, res["message"]?.toString() ?? "Could not save", error: true);
      return null;
    }
    if (ok != null) toast(context, ok);
    notifyLedgerChanged();
    widget.onChanged();
    return res;
  }

  Future<void> _toggle(Map<String, dynamic> role, String key, bool on) async {
    final id = role["_id"].toString();
    final before = _values(role);
    setState(() => _local[id] = {...before, key: on});
    final res = await _run(() => LedgerService.updateCustomRole(s.companyId, id, s.userId, {"permissions": {key: on}}));
    if (!mounted) return;
    setState(() => _local[id] = res == null
        ? before
        : Map<String, bool>.from((res["role"]?["permissions"] as Map? ?? const {}).map((k, v) => MapEntry(k.toString(), v == true))));
  }

  void _setAll(Map<String, dynamic> role, bool on) {
    final id = role["_id"].toString();
    _local.remove(id);
    _run(() => LedgerService.updateCustomRole(s.companyId, id, s.userId, {
          "permissions": {for (final d in widget.definitions) d["key"].toString(): on && !_blocked(d, role)},
        }));
  }

  Future<void> _addRole() async {
    final name = TextEditingController();
    var base = "staff";
    await showLedgerSheet(context, "Add role", (ctx) => StatefulBuilder(builder: (ctx, set) {
          Widget choice(String value, String title, String sub) => Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => set(() => base = value),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: base == value ? kForest.withValues(alpha: 0.08) : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: base == value ? kForest : const Color(0xFFE2E8F0), width: base == value ? 1.5 : 1),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: kDark)),
                      const SizedBox(height: 2),
                      Text(sub, style: GoogleFonts.inter(fontSize: 11.5, color: kDark.withValues(alpha: 0.6))),
                    ]),
                  ),
                ),
              );
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("Every switch starts off; you turn on what this role may do.", style: GoogleFonts.inter(fontSize: 12.5, color: kDark.withValues(alpha: 0.65))),
            const SizedBox(height: 12),
            TextField(controller: name, maxLength: 40, autofocus: true, decoration: fieldDecoration("Role name, e.g. Accountant", icon: Icons.badge_rounded)),
            Text("Works like", style: labelStyle),
            const SizedBox(height: 6),
            Row(children: [
              choice("manager", "Manager-like", "Sees all expenses; own posts approved straight away"),
              const SizedBox(width: 8),
              choice("staff", "Staff-like", "Sees own expenses; posts wait for approval"),
            ]),
            const SizedBox(height: 16),
            primaryButton("Create role", () async {
              final n = name.text.trim();
              if (n.isEmpty) return toast(ctx, "Give the role a name", error: true);
              final res = await LedgerService.createCustomRole(s.companyId, s.userId, n, base);
              if (!ctx.mounted) return;
              if (handleResult(ctx, res, "\"$n\" created · all switches are off")) {
                Navigator.pop(ctx);
                notifyLedgerChanged();
                widget.onChanged();
              }
            }),
          ]);
        }));
    name.dispose();
  }

  Future<void> _rename(Map<String, dynamic> role) async {
    final name = TextEditingController(text: role["name"]?.toString() ?? "");
    await showLedgerSheet(context, "Rename role", (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(controller: name, maxLength: 40, autofocus: true, decoration: fieldDecoration("Role name", icon: Icons.badge_rounded)),
          const SizedBox(height: 8),
          primaryButton("Save", () async {
            final n = name.text.trim();
            if (n.isEmpty) return toast(ctx, "Give the role a name", error: true);
            final res = await LedgerService.updateCustomRole(s.companyId, role["_id"].toString(), s.userId, {"name": n});
            if (!ctx.mounted) return;
            if (handleResult(ctx, res, "Renamed to $n")) {
              Navigator.pop(ctx);
              notifyLedgerChanged();
              widget.onChanged();
            }
          }),
        ]));
    name.dispose();
  }

  Future<void> _delete(Map<String, dynamic> role) async {
    final members = List<Map<String, dynamic>>.from(role["members"] ?? const []);
    final ok = await confirmDialog(
      context,
      "Delete \"${role["name"]}\"?",
      members.isEmpty
          ? "Nobody is in this role, so no one is removed. This can't be undone."
          : "These ${members.length} member${members.length == 1 ? "" : "s"} will also be removed from ${s.companyName}: ${members.map((m) => m["name"]).join(", ")}. This can't be undone.",
      confirmLabel: members.isEmpty ? "Delete role" : "Delete and remove",
      danger: true,
    );
    if (!ok || !mounted) return;
    await _run(() => LedgerService.deleteCustomRole(s.companyId, role["_id"].toString(), s.userId),
        ok: members.isEmpty ? "\"${role["name"]}\" deleted" : "\"${role["name"]}\" deleted · ${members.length} removed from ${s.companyName}");
  }

  void _assign(Map<String, dynamic> role, String memberUserId) =>
      _run(() => LedgerService.setMemberCustomRole(s.companyId, memberUserId, s.userId, role["_id"].toString()), ok: "Added to ${role["name"]}");

  void _unassign(Map<String, dynamic> member) =>
      _run(() => LedgerService.setMemberCustomRole(s.companyId, member["userId"].toString(), s.userId, null), ok: "${member["name"]} is now staff");

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 4),
        child: Row(children: [
          Expanded(child: Text("Custom roles", style: GoogleFonts.inter(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800))),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: kForest, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: _busy ? null : _addRole,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: Text("Add role", style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
          ),
        ]),
      ),
      Text("Make your own roles, like Accountant. Every switch starts off — turn on only what the role needs. Only you can change roles or put people in them.",
          style: GoogleFonts.inter(color: Colors.white70, fontSize: 12.5)),
      const SizedBox(height: 12),
      if (widget.roles.isEmpty)
        ledgerCard(child: Center(child: Text("No custom roles yet.", style: GoogleFonts.inter(color: kDark.withValues(alpha: 0.6)))))
      else
        ...widget.roles.map(_roleCard),
    ]);
  }

  Widget _roleCard(Map<String, dynamic> role) {
    final values = _values(role);
    final usable = widget.definitions.where((d) => !_blocked(d, role)).toList();
    final onCount = usable.where((d) => values[d["key"]] == true).length;
    final members = List<Map<String, dynamic>>.from(role["members"] ?? const []);
    final creatorId = idOf(s.company["createdBy"]);
    final inRole = members.map((m) => idOf(m["userId"])).toSet();
    final candidates = s.members.where((m) => m["userId"].toString() != creatorId && !inRole.contains(m["userId"].toString())).toList();
    final manager = role["base"] == "manager";

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(role["name"]?.toString() ?? "Role", style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w800, color: kDark)),
              const SizedBox(height: 4),
              Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: manager ? const Color(0xFFE0E7FF) : const Color(0xFFE8F7EF), borderRadius: BorderRadius.circular(99)),
                  child: Text(manager ? "Manager-like" : "Staff-like",
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: manager ? const Color(0xFF3730A3) : kForest)),
                ),
                Text("${members.length} member${members.length == 1 ? "" : "s"}", style: GoogleFonts.inter(fontSize: 12, color: kDark.withValues(alpha: 0.6))),
              ]),
            ]),
          ),
          Container(
            margin: const EdgeInsets.only(right: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: const Color(0xFFE8F7EF), border: Border.all(color: const Color(0xFFCBEBD9)), borderRadius: BorderRadius.circular(99)),
            child: Text("$onCount/${usable.length} on", style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: kForest)),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: kDark),
            onSelected: (v) => v == "rename" ? _rename(role) : _delete(role),
            itemBuilder: (_) => const [
              PopupMenuItem(value: "rename", child: Text("Rename")),
              PopupMenuItem(value: "delete", child: Text("Delete role", style: TextStyle(color: kTerracotta))),
            ],
          ),
        ]),
        Row(children: [
          TextButton(onPressed: _busy ? null : () => _setAll(role, true), child: const Text("Turn all on")),
          Text("·", style: GoogleFonts.inter(color: kDark.withValues(alpha: 0.4))),
          TextButton(style: TextButton.styleFrom(foregroundColor: kTerracotta), onPressed: _busy ? null : () => _setAll(role, false), child: const Text("Turn all off")),
        ]),
        // members
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(right: 8, bottom: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: const Color(0xFFF8FAFC), border: Border.all(color: const Color(0xFFF1F5F9)), borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("MEMBERS", style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: kDark.withValues(alpha: 0.55))),
            const SizedBox(height: 6),
            if (members.isEmpty) Text("Nobody in this role yet.", style: GoogleFonts.inter(fontSize: 12.5, color: kDark.withValues(alpha: 0.6))),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final m in members)
                InputChip(
                  label: Text(m["name"]?.toString() ?? "Member", style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600)),
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: Color(0xFFE2E8F0)),
                  deleteIcon: const Icon(Icons.close_rounded, size: 16),
                  onDeleted: _busy ? null : () => _unassign(m),
                  deleteButtonTooltipMessage: "Take out of this role (becomes staff)",
                ),
            ]),
            if (candidates.isNotEmpty)
              PopupMenuButton<String>(
                position: PopupMenuPosition.under,
                enabled: !_busy,
                onSelected: (id) => _assign(role, id),
                itemBuilder: (_) => candidates
                    .map((m) => PopupMenuItem(
                          value: m["userId"].toString(),
                          child: Text(
                              "${m["name"]} · ${(m["customRoleName"]?.toString().isNotEmpty ?? false) ? m["customRoleName"] : (m["role"] == "admin" ? "Manager" : "Staff")}",
                              overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.person_add_alt_1_rounded, size: 18, color: kForest),
                    const SizedBox(width: 6),
                    Text("Add a member", style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: kForest)),
                  ]),
                ),
              ),
          ]),
        ),
        for (var i = 0; i < widget.definitions.length; i++) ...[
          if (i > 0) const Divider(height: 1, color: Color(0xFFF1F5F9)),
          Builder(builder: (_) {
            final def = widget.definitions[i];
            final key = def["key"].toString();
            final blocked = _blocked(def, role);
            final on = !blocked && values[key] == true;
            final hint = blocked ? "Only for ${def["only"]}-like roles" : def["hint"]?.toString();
            return SwitchListTile(
              contentPadding: const EdgeInsets.only(right: 4),
              value: on,
              activeThumbColor: Colors.white,
              activeTrackColor: kForest,
              onChanged: blocked || _busy ? null : (v) => _toggle(role, key, v),
              title: Text(def["label"].toString(),
                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: on ? kDark : kDark.withValues(alpha: 0.5))),
              subtitle: hint == null || hint.isEmpty ? null : Text(hint, style: GoogleFonts.inter(fontSize: 12, color: kDark.withValues(alpha: 0.55))),
            );
          }),
        ],
      ]),
    );
  }
}
