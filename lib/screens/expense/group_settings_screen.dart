import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/expense_company_service.dart';

class GroupSettingsScreen extends StatefulWidget {
  final String groupId;
  final String groupName;
  final String userId;

  const GroupSettingsScreen({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.userId,
  });

  @override
  State<GroupSettingsScreen> createState() => _GroupSettingsScreenState();
}

class _GroupSettingsScreenState extends State<GroupSettingsScreen> {
  static const Color bgGreen = Color(0xFF0C5F41);
  static const Color darkSurface = Color(0xFF0C3826);
  static const Color mintAccent = Color(0xFF10B981);
  static const Color darkText = Color(0xFF1E293B);
  static const Color mutedText = Color(0xFF64748B);

  List<Map<String, dynamic>> _members = [];
  List<Map<String, dynamic>> _candidates = [];
  String? _groupAdminId;
  String _groupAdminName = "Group admin";
  bool _settled = false;
  bool _loading = true;
  String? _error;
  final Set<String> _busyMemberIds = {};

  String _id(dynamic value) {
    if (value is Map) return (value["_id"] ?? value["id"] ?? "").toString();
    return value?.toString() ?? "";
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message, style: const TextStyle(color: Colors.white)),
          behavior: SnackBarBehavior.floating,
          backgroundColor: darkSurface,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      );
  }

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
    final response = await ExpenseCompanyService.getGroupMembers(
      groupId: widget.groupId,
      userId: widget.userId,
    );
    if (!mounted) return;
    if (response["success"] == true) {
      setState(() {
        _members = List<Map<String, dynamic>>.from(
          (response["members"] as List? ?? const [])
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item)),
        );
        _candidates = List<Map<String, dynamic>>.from(
          (response["candidates"] as List? ?? const [])
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item)),
        );
        _groupAdminId = _id((response["group"] as Map?)?["createdBy"]);
        _groupAdminName =
            ((response["admin"] as Map?)?["name"] ?? "Group admin").toString();
        _settled =
            (response["group"] as Map?)?["settlementStatus"] == "settled";
        _loading = false;
      });
    } else {
      setState(() {
        _error =
            (response["message"] ?? "Could not load group members").toString();
        _loading = false;
      });
    }
  }

  bool get _isGroupAdmin => _groupAdminId == widget.userId;

  Future<void> _addMember(Map<String, dynamic> candidate) async {
    final memberId = _id(candidate["_id"]);
    if (memberId.isEmpty || _busyMemberIds.contains(memberId)) return;
    setState(() => _busyMemberIds.add(memberId));
    final response = await ExpenseCompanyService.addGroupMember(
      groupId: widget.groupId,
      userId: widget.userId,
      memberId: memberId,
    );
    if (!mounted) return;
    setState(() => _busyMemberIds.remove(memberId));
    Navigator.of(context).pop();
    if (response["success"] == true) {
      _showMessage("${candidate["name"] ?? "Member"} added to the group");
      await _load();
    } else {
      _showMessage((response["message"] ?? "Could not add member").toString());
    }
  }

  Future<void> _removeMember(Map<String, dynamic> member) async {
    final memberId = _id(member["_id"]);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Remove group member?"),
        content: Text(
            "${member["name"] ?? "This person"} will no longer see the group's expenses."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text("Cancel")),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text("Remove")),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busyMemberIds.add(memberId));
    final response = await ExpenseCompanyService.removeGroupMember(
      groupId: widget.groupId,
      userId: widget.userId,
      memberId: memberId,
    );
    if (!mounted) return;
    setState(() => _busyMemberIds.remove(memberId));
    if (response["success"] == true) {
      _showMessage("${member["name"] ?? "Member"} removed from the group");
      await _load();
    } else {
      _showMessage(
          (response["message"] ?? "Could not remove member").toString());
    }
  }

  void _showAddMembers() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        child: Container(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.72),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 10),
                child: Row(
                  children: [
                    Expanded(
                        child: Text("Add members",
                            style: GoogleFonts.inter(
                                fontSize: 21, fontWeight: FontWeight.bold))),
                    IconButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        icon: const Icon(Icons.close_rounded)),
                  ],
                ),
              ),
              Expanded(
                child: _candidates.isEmpty
                    ? const Center(
                        child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                                "Everyone in the company is already in this group.")))
                    : ListView.separated(
                        itemCount: _candidates.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, indent: 72),
                        itemBuilder: (context, index) {
                          final candidate = _candidates[index];
                          final id = _id(candidate["_id"]);
                          final busy = _busyMemberIds.contains(id);
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: const Color(0xFFE5F3ED),
                              child: Text(
                                  ((candidate["name"] ?? "?")
                                              .toString()
                                              .trim()
                                              .isNotEmpty
                                          ? candidate["name"]
                                              .toString()
                                              .trim()[0]
                                          : "?")
                                      .toUpperCase(),
                                  style: const TextStyle(color: darkSurface)),
                            ),
                            title: Text(
                                (candidate["name"] ?? "Member").toString()),
                            subtitle:
                                Text((candidate["email"] ?? "").toString()),
                            trailing: TextButton(
                              onPressed:
                                  busy ? null : () => _addMember(candidate),
                              child: busy
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : const Text("Add"),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgGreen,
      appBar: AppBar(
        backgroundColor: bgGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text("Group settings",
            style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: mintAccent))
            : _error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white)),
                        TextButton(
                            onPressed: _load, child: const Text("Retry")),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    color: mintAccent,
                    onRefresh: _load,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(
                          parent: BouncingScrollPhysics()),
                      padding: const EdgeInsets.all(20),
                      children: [
                        Text(widget.groupName,
                            style: GoogleFonts.inter(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        Text(
                            _isGroupAdmin
                                ? "Group admin: you"
                                : "Group admin: $_groupAdminName",
                            style: GoogleFonts.inter(color: Colors.white70)),
                        const SizedBox(height: 18),
                        if (_isGroupAdmin && _settled)
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(14)),
                            child: Text(
                                "This group is settled. Its membership is locked.",
                                style: GoogleFonts.inter(color: Colors.white)),
                          )
                        else if (_isGroupAdmin)
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _showAddMembers,
                              style: FilledButton.styleFrom(
                                  backgroundColor: darkSurface,
                                  foregroundColor: Colors.white,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 14)),
                              icon: const Icon(Icons.person_add_alt_1_rounded,
                                  color: mintAccent),
                              label: const Text("Add members"),
                            ),
                          ),
                        const SizedBox(height: 20),
                        Text("MEMBERS (${_members.length})",
                            style: GoogleFonts.ibmPlexMono(
                                color: Colors.white70,
                                fontSize: 11,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10),
                        if (_members.isEmpty)
                          const Text("No members found",
                              style: TextStyle(color: Colors.white70))
                        else
                          ..._members.map((member) {
                            final memberId = _id(member["_id"]);
                            final isAdmin = memberId == _groupAdminId;
                            final busy = _busyMemberIds.contains(memberId);
                            return Container(
                              margin: const EdgeInsets.only(bottom: 9),
                              decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(15)),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: const Color(0xFFE5F3ED),
                                  child: Text(
                                      ((member["name"] ?? "?")
                                                  .toString()
                                                  .trim()
                                                  .isNotEmpty
                                              ? member["name"]
                                                  .toString()
                                                  .trim()[0]
                                              : "?")
                                          .toUpperCase(),
                                      style:
                                          const TextStyle(color: darkSurface)),
                                ),
                                title: Text(
                                  (member["name"] ?? "Member").toString(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: darkText,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15),
                                ),
                                subtitle: Text(
                                  isAdmin
                                      ? "Group admin"
                                      : (member["email"] ?? "Member")
                                          .toString(),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: mutedText, fontSize: 12),
                                ),
                                trailing: isAdmin
                                    ? Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 9, vertical: 6),
                                        decoration: BoxDecoration(
                                            color: const Color(0xFFE5F3ED),
                                            borderRadius:
                                                BorderRadius.circular(20)),
                                        child: const Text("ADMIN",
                                            style: TextStyle(
                                                color: darkSurface,
                                                fontSize: 10,
                                                fontWeight: FontWeight.w800)),
                                      )
                                    : !_isGroupAdmin || _settled
                                        ? null
                                        : IconButton(
                                            constraints:
                                                const BoxConstraints.tightFor(
                                                    width: 40, height: 40),
                                            padding: EdgeInsets.zero,
                                            tooltip: "Remove member",
                                            onPressed: busy
                                                ? null
                                                : () => _removeMember(member),
                                            icon: busy
                                                ? const SizedBox(
                                                    width: 18,
                                                    height: 18,
                                                    child:
                                                        CircularProgressIndicator(
                                                            strokeWidth: 2))
                                                : const Icon(
                                                    Icons
                                                        .person_remove_alt_1_rounded,
                                                    color: Colors.redAccent,
                                                    size: 21),
                                          ),
                              ),
                            );
                          }),
                        if (_isGroupAdmin) ...[
                          const SizedBox(height: 20),
                          Text(
                              "Only the group admin can change membership. Members must belong to the associated company.",
                              style: GoogleFonts.inter(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  height: 1.4)),
                        ],
                      ],
                    ),
                  ),
      ),
    );
  }
}
