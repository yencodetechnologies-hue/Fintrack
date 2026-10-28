import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/ledger_service.dart';
import '../../services/expense_company_service.dart';
import '../ledger/ledger_common.dart';
import '../ledger/ledger_company_logo.dart';

/// Create (group == null) or edit a company group: a name plus the companies in it. Grouping only changes how the
/// companies list is shown; each company keeps its own members, money and books. Only companies I run can be picked.
/// Resolves to true when something was saved or removed.
Future<bool> showCompanyGroupSheet(BuildContext context, {required String userId, required List<Map<String, dynamic>> companies, Map<String, dynamic>? group}) async {
  final name = TextEditingController(text: group?["name"]?.toString() ?? "");
  final groupId = group?["_id"]?.toString();
  // companies I run, plus any made right here with "+ Add"
  final mine = companies.where((c) => c["userRole"] == "admin" && c["external"] != true).toList();
  final picked = companies.where((c) => groupId != null && c["companyGroup"]?["_id"]?.toString() == groupId).map((c) => c["_id"].toString()).toSet();
  var changed = false;
  final newName = TextEditingController();
  var creating = false;

  await showLedgerSheet(context, group == null ? "New company group" : "Edit company group", (ctx) => StatefulBuilder(builder: (ctx, set) {
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text("Keep related companies together. Each company stays separate, with its own members, money and books.",
              style: GoogleFonts.inter(fontSize: 13, color: kDark.withValues(alpha: 0.6))),
          const SizedBox(height: 12),
          TextField(controller: name, decoration: fieldDecoration("Group name *, e.g. YD Group", icon: Icons.folder_rounded)),
          const SizedBox(height: 12),
          Text("Companies${picked.isNotEmpty ? " (${picked.length} selected)" : ""}",
              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: kDark)),
          const SizedBox(height: 6),
          if (mine.length < 2)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text("A group needs at least two companies you run. Add a new one below.",
                  style: GoogleFonts.inter(fontSize: 13, color: kDark.withValues(alpha: 0.6))),
            ),
          for (final c in mine)
              Builder(builder: (_) {
                final id = c["_id"].toString();
                final on = picked.contains(id);
                final elsewhere = c["companyGroup"] != null && c["companyGroup"]["_id"]?.toString() != groupId ? c["companyGroup"]["name"]?.toString() : null;
                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  decoration: BoxDecoration(
                    color: on ? const Color(0xFFF0FDF4) : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: on ? kForest : kDark.withValues(alpha: 0.1), width: on ? 1.5 : 1),
                  ),
                  child: CheckboxListTile(
                    value: on,
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: (v) => set(() => v == true ? picked.add(id) : picked.remove(id)),
                    secondary: CompanyAvatar(company: c, size: 30, radius: 8),
                    title: Text(c["name"].toString(), style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14, color: kDark)),
                    subtitle: elsewhere == null ? null : Text("Now in “$elsewhere”; picking it moves it here", style: GoogleFonts.inter(fontSize: 12)),
                  ),
                );
              }),
          // make a brand-new company straight into this group (I become its Admin; its join code is in its Settings)
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: newName, decoration: fieldDecoration("New company name", icon: Icons.add_business_rounded))),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: creating
                  ? null
                  : () async {
                      final n = newName.text.trim();
                      if (n.isEmpty) return toast(ctx, "Enter the new company's name", error: true);
                      set(() => creating = true);
                      final res = await ExpenseCompanyService.createCompany(userId: userId, name: n);
                      if (!ctx.mounted) return;
                      set(() => creating = false);
                      if (res["success"] != true || res["company"] is! Map) {
                        return toast(ctx, res["message"]?.toString() ?? "Could not create the company", error: true);
                      }
                      final c = {...Map<String, dynamic>.from(res["company"]), "userRole": "admin", "isCompanyAdmin": true, "companyGroup": null};
                      set(() {
                        mine.add(c);
                        picked.add(c["_id"].toString());
                        newName.clear();
                      });
                      changed = true; // the companies list needs a reload even if the group isn't saved
                      toast(ctx, "${c["name"]} created · join code ${res["joinCode"] ?? c["joinCode"] ?? ""}");
                    },
              child: Text(creating ? "Adding…" : "+ Add"),
            ),
          ]),
          const SizedBox(height: 14),
          primaryButton(group == null ? "Create group" : "Save", mine.length < 2
              ? null
              : () async {
                  if (name.text.trim().isEmpty) return toast(ctx, "Enter a group name", error: true);
                  if (picked.length < 2) return toast(ctx, "Pick at least two companies", error: true);
                  final res = await LedgerService.saveCompanyGroup(groupId, {"userId": userId, "name": name.text.trim(), "companyIds": picked.toList()});
                  if (!ctx.mounted) return;
                  if (handleResult(ctx, res, group == null ? "Company group created" : "Company group updated")) {
                    changed = true;
                    Navigator.pop(ctx);
                  }
                }),
          if (group != null) ...[
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                style: TextButton.styleFrom(foregroundColor: kTerracotta),
                onPressed: () async {
                  final yes = await confirmDialog(ctx, "Remove this group?",
                      "“${group["name"]}” is removed and its companies show on their own again. Nothing inside the companies changes.",
                      confirmLabel: "Remove group", danger: true);
                  if (!yes || !ctx.mounted) return;
                  final res = await LedgerService.deleteCompanyGroup(groupId!, userId);
                  if (!ctx.mounted) return;
                  if (handleResult(ctx, res, "Company group removed")) {
                    changed = true;
                    Navigator.pop(ctx);
                  }
                },
                child: const Text("Remove group"),
              ),
            ),
          ],
        ]);
      }));
  name.dispose();
  newName.dispose();
  return changed;
}
