import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/ledger_service.dart';
import 'ledger_common.dart';
import 'ledger_expenses_tab.dart' show showPostExpenseSheet;

class LedgerGroupsTab extends StatefulWidget {
  final LedgerScope scope;
  const LedgerGroupsTab({super.key, required this.scope});

  @override
  State<LedgerGroupsTab> createState() => _LedgerGroupsTabState();
}

class _LedgerGroupsTabState extends State<LedgerGroupsTab> with LedgerAutoRefresh {
  @override
  void onLedgerChanged() => _load();

  LedgerScope get s => widget.scope;
  List<Map<String, dynamic>> _groups = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await LedgerService.groups(s.companyId, s.userId);
    if (!mounted) return;
    setState(() {
      _groups = List<Map<String, dynamic>>.from(res["groups"] ?? const []);
      _loading = false;
    });
  }

  void _newGroup() {
    final name = TextEditingController();
    final project = TextEditingController();
    final picked = <String>{};
    final others = s.members.where((m) => m["userId"].toString() != s.userId).toList();
    showLedgerSheet(context, "New group", (ctx) => StatefulBuilder(
          builder: (ctx, set) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(controller: name, decoration: fieldDecoration("Group name", icon: Icons.groups_rounded)),
              const SizedBox(height: 10),
              TextField(controller: project, decoration: fieldDecoration("Project / business", icon: Icons.work_rounded)),
              const SizedBox(height: 12),
              Text("Members", style: labelStyle),
              ...others.map((m) => CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    activeColor: kForest,
                    value: picked.contains(m["userId"].toString()),
                    title: Text(m["name"].toString()),
                    onChanged: (v) => set(() => v == true ? picked.add(m["userId"].toString()) : picked.remove(m["userId"].toString())),
                  )),
              const SizedBox(height: 12),
              primaryButton("Create group", () async {
                final res = await LedgerService.createGroup({
                  "companyId": s.companyId,
                  "userId": s.userId,
                  "name": name.text.trim(),
                  "project": project.text.trim(),
                  "memberIds": picked.toList(),
                });
                if (!ctx.mounted) return;
                if (handleResult(ctx, res, "Group created")) {
                  Navigator.pop(ctx);
                  _load();
                }
              }),
            ],
          ),
        ));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: Colors.white));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 30),
        children: [
          Text(s.isAdmin ? "All groups in ${s.companyName}" : "Groups you post expenses in",
              style: GoogleFonts.inter(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 10),
          if (_groups.isEmpty) emptyState("No groups yet"),
          ..._groups.map((g) => ledgerCard(
                padding: EdgeInsets.zero,
                child: ListTile(
                  title: Text(g["name"].toString(), style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: kDark)),
                  subtitle: Text("${g["memberCount"]} members · ${s.companyName}${(g["project"] ?? "").toString().isNotEmpty ? " · ${g["project"]}" : ""}"),
                  trailing: Text(inr(g["total"]), style: GoogleFonts.fraunces(fontWeight: FontWeight.bold, color: kForest)),
                  onTap: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => _GroupDetail(scope: s, groupId: g["_id"].toString())));
                    _load();
                  },
                ),
              )),
          const SizedBox(height: 6),
          primaryButton("+ New group", _newGroup, color: kForestDark),
          const SizedBox(height: 10),
          Text("Only staff in a group see its activity. Admins see all company expenses.",
              textAlign: TextAlign.center, style: GoogleFonts.inter(color: Colors.white54, fontSize: 11.5)),
        ],
      ),
    );
  }
}

class _GroupDetail extends StatefulWidget {
  final LedgerScope scope;
  final String groupId;
  const _GroupDetail({required this.scope, required this.groupId});

  @override
  State<_GroupDetail> createState() => _GroupDetailState();
}

class _GroupDetailState extends State<_GroupDetail> with LedgerAutoRefresh {
  @override
  void onLedgerChanged() => _load();

  LedgerScope get s => widget.scope;
  Map<String, dynamic>? _data;
  final _note = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await LedgerService.groupDetail(widget.groupId, s.userId);
    if (!mounted) return;
    if (res["success"] != true) {
      toast(context, res["message"]?.toString() ?? "Could not open group", error: true);
      Navigator.pop(context);
      return;
    }
    setState(() => _data = res);
  }

  List<Map<String, dynamic>> get _members => List<Map<String, dynamic>>.from(_data?["group"]?["members"] ?? const []);
  bool get _isMember => _members.any((m) => m["_id"].toString() == s.userId);

  void _invite() {
    final inGroup = _members.map((m) => m["_id"].toString()).toSet();
    final candidates = s.members.where((m) => !inGroup.contains(m["userId"].toString())).toList();
    showLedgerSheet(context, "Invite staff", (ctx) => Column(
          children: [
            if (candidates.isEmpty) Text("Everyone in ${s.companyName} is already in this group.", style: GoogleFonts.inter(color: kDark)),
            ...candidates.map((m) => ListTile(
                  leading: const Icon(Icons.person_add_alt_1_rounded, color: kForest),
                  title: Text(m["name"].toString()),
                  onTap: () async {
                    final res = await LedgerService.addGroupMember(widget.groupId, s.userId, m["userId"].toString());
                    if (!ctx.mounted) return;
                    if (handleResult(ctx, res, "${m["name"]} added")) {
                      Navigator.pop(ctx);
                      _load();
                    }
                  },
                )),
          ],
        ));
  }

  Future<void> _sendNote() async {
    final text = _note.text.trim();
    if (text.isEmpty) return;
    final res = await LedgerService.addGroupNote(widget.groupId, s.userId, text);
    if (!mounted) return;
    if (handleResult(context, res, "Note sent")) {
      _note.clear();
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final group = _data?["group"];
    return Theme(data: sheetTheme, child: Scaffold(
      backgroundColor: kForest,
      appBar: AppBar(
        backgroundColor: kForest,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(group?["name"]?.toString() ?? "Group", style: GoogleFonts.fraunces(fontWeight: FontWeight.bold)),
      ),
      body: _data == null
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 30),
                children: [
                  Text("${s.companyName} · group total ${inr(_data!["total"])}", style: GoogleFonts.inter(color: Colors.white70)),
                  const SizedBox(height: 12),
                  ledgerCard(
                    child: Row(
                      children: [
                        Expanded(
                          child: Wrap(
                            spacing: -6,
                            children: _members
                                .map((m) => CircleAvatar(
                                      radius: 16,
                                      backgroundColor: kForest,
                                      child: Text(m["name"].toString()[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 13)),
                                    ))
                                .toList(),
                          ),
                        ),
                        if (_isMember || s.isAdmin) TextButton(onPressed: _invite, child: const Text("Invite staff", style: TextStyle(color: kForest))),
                      ],
                    ),
                  ),
                  sectionTitle("Shared expenses"),
                  if ((_data!["expenses"] as List).isEmpty) emptyState("No expenses in this group yet"),
                  ...(_data!["expenses"] as List).map((e) {
                    final mine = idOf(e["createdBy"]) == s.userId;
                    return ledgerCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(child: Text("${e["category"]} · ${inr(e["amount"])}", style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: kDark))),
                              statusPill(kLifecycleLabels[e["lifecycle"]] ?? "", lifecycleColor(e["lifecycle"])),
                            ],
                          ),
                          Text("By ${mine ? "you" : nameOf(e["createdBy"])} — \"${e["description"]}\"", style: GoogleFonts.inter(fontSize: 12, color: kDark.withValues(alpha: 0.6))),
                        ],
                      ),
                    );
                  }),
                  sectionTitle("Coordination"),
                  ...(_data!["notes"] as List).map((n) => ledgerCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(nameOf(n["userId"]), style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: kDark, fontSize: 12.5)),
                            Text(n["text"].toString(), style: GoogleFonts.inter(color: kDark)),
                          ],
                        ),
                      )),
                  if (_isMember) ...[
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _note,
                            decoration: fieldDecoration("Add a note for the group…").copyWith(fillColor: Colors.white),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          style: IconButton.styleFrom(backgroundColor: kForestDark),
                          onPressed: _sendNote,
                          icon: const Icon(Icons.send_rounded, color: kMint),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    primaryButton("+ Post expense to group", () => showPostExpenseSheet(context, s,
                        groupId: widget.groupId, groupName: group?["name"]?.toString(), onDone: _load), color: kForestDark),
                  ],
                ],
              ),
            ),
    ));
  }
}
