import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/ledger_service.dart';
import 'ledger_common.dart';

/// Feature switches per role (web's Permissions page). The primary admin edits Managers and Staff; other managers
/// (with "Change staff permissions") edit Staff, and can't switch on a staff feature that's off for managers.
/// Each switch saves on its own; whatever was saved last wins.
class PermissionsPage extends StatefulWidget {
  final LedgerScope scope;
  const PermissionsPage({super.key, required this.scope});

  @override
  State<PermissionsPage> createState() => _PermissionsPageState();
}

class _PermissionsPageState extends State<PermissionsPage> with LedgerAutoRefresh {
  // another editor changed the switches: show theirs (skipped while we are saving our own)
  @override
  void onLedgerChanged() {
    if (!_saving) _load();
  }

  @override
  Set<String> get ledgerTopics => const {"permissions"};

  LedgerScope get s => widget.scope;
  Map<String, dynamic>? _data;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await LedgerService.permissions(s.companyId, s.userId);
    if (!mounted) return;
    setState(() {
      if (res["success"] == true) {
        _data = res;
        _error = null;
      } else {
        _error = res["message"]?.toString() ?? "Could not load permissions";
      }
    });
  }

  Map<String, bool> _values(String role) => Map<String, bool>.from((_data?[role] as Map?)?.map((k, v) => MapEntry(k.toString(), v == true)) ?? const {});
  List<Map<String, dynamic>> _defs(String role) => List<Map<String, dynamic>>.from((_data?["definitions"]?[role] as List?) ?? const []);
  Map<String, dynamic> get _mine => Map<String, dynamic>.from(_data?["mine"] ?? const {});

  // a non-primary manager can't switch on what managers themselves don't have
  bool _lockedForStaff(Map<String, dynamic> def) => _data?["role"] != "primary" && def["needs"] != null && _mine[def["needs"]] == false;

  Future<void> _save(String role, Map<String, bool> changes) async {
    final before = _values(role);
    setState(() {
      _saving = true;
      _data = {..._data!, role: {...before, ...changes}};
    });
    final res = await LedgerService.updatePermissions(s.companyId, s.userId, role, changes);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _data = {..._data!, role: res["success"] == true ? res[role] : before};
    });
    if (res["success"] == true) {
      notifyLedgerChanged();
    } else {
      toast(context, res["message"]?.toString() ?? "Could not save", error: true);
    }
  }

  void _setAll(String role, bool on) {
    final values = _values(role);
    _save(role, {
      for (final def in _defs(role)) def["key"].toString(): role == "staff" && on && _lockedForStaff(def) ? (values[def["key"]] ?? false) : on,
    });
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    Widget body;
    if (_error != null) {
      body = Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, style: GoogleFonts.inter(color: Colors.white))));
    } else if (data == null) {
      body = const Center(child: CircularProgressIndicator(color: Colors.white));
    } else if (data["canEditStaff"] != true) {
      body = Center(child: Text("You can't change permissions in this company.", style: GoogleFonts.inter(color: Colors.white)));
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 30), children: [
          Text(
            "Turn features on or off for everyone in a role. Switched-off features are hidden for them and refused by the server."
            "${data["role"] == "primary" ? " As the primary admin, these never apply to you." : " You can change staff permissions, but only for features managers have."}",
            style: GoogleFonts.inter(color: Colors.white70, fontSize: 12.5),
          ),
          const SizedBox(height: 12),
          if (data["canEditManagers"] == true) _section("manager", "Managers", "Every manager except the primary admin"),
          _section("staff", "Staff", "Every staff member"),
        ]),
      );
    }
    return Theme(
      data: sheetTheme,
      child: Scaffold(
        backgroundColor: kForest,
        appBar: AppBar(
          backgroundColor: kForest,
          foregroundColor: Colors.white,
          elevation: 0,
          title: Text("Permissions", style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
        ),
        body: body,
      ),
    );
  }

  Widget _section(String role, String title, String subtitle) {
    final defs = _defs(role);
    final values = _values(role);
    final onCount = defs.where((d) => values[d["key"]] == true).length;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: kDark)),
              Text(subtitle, style: GoogleFonts.inter(fontSize: 12, color: kDark.withValues(alpha: 0.6))),
            ]),
          ),
          Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: const Color(0xFFE8F7EF), border: Border.all(color: const Color(0xFFCBEBD9)), borderRadius: BorderRadius.circular(99)),
            child: Text("$onCount/${defs.length} on", style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: kForest)),
          ),
        ]),
        Row(children: [
          TextButton(onPressed: _saving ? null : () => _setAll(role, true), child: const Text("Turn all on")),
          Text("·", style: GoogleFonts.inter(color: kDark.withValues(alpha: 0.4))),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: kTerracotta),
            onPressed: _saving ? null : () => _setAll(role, false),
            child: const Text("Turn all off"),
          ),
        ]),
        for (var i = 0; i < defs.length; i++) ...[
          if (i > 0) const Divider(height: 1, color: Color(0xFFF1F5F9)),
          Builder(builder: (_) {
            final def = defs[i];
            final key = def["key"].toString();
            final on = values[key] == true;
            final locked = role == "staff" && !on && _lockedForStaff(def);
            final hint = locked ? "Off for managers, so you can't turn it on" : def["hint"]?.toString();
            return SwitchListTile(
              contentPadding: const EdgeInsets.only(right: 4),
              value: on,
              activeThumbColor: Colors.white,
              activeTrackColor: kForest,
              onChanged: locked || _saving ? null : (v) => _save(role, {key: v}),
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
