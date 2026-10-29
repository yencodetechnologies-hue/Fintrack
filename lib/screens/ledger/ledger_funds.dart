import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../services/ledger_service.dart';
import 'ledger_common.dart';
import 'ledger_description_field.dart';

/// Managers: Cash and bank balances, add income, add/remove bank accounts, rename Cash (web's Company Funds).
class FundsPage extends StatefulWidget {
  final LedgerScope scope;
  const FundsPage({super.key, required this.scope});

  @override
  State<FundsPage> createState() => _FundsPageState();
}

class _FundsPageState extends State<FundsPage> {
  LedgerScope get s => widget.scope;
  late List<Map<String, dynamic>> _accounts = s.bankAccounts;
  late num _cash = s.cashBalance;
  late String _cashName = s.cashName == "Cash" ? (s.company["cashAccountName"]?.toString() ?? "InCash") : s.cashName;
  List<Map<String, dynamic>> _income = [];

  @override
  void initState() {
    super.initState();
    _loadIncome();
  }

  Future<void> _loadIncome() async {
    final res = await LedgerService.incomeHistory(s.companyId, s.userId);
    if (mounted && res["success"] == true) setState(() => _income = List<Map<String, dynamic>>.from(res["income"] ?? const []));
  }

  void _changed() {
    notifyLedgerChanged();
    s.reload();
  }

  void _renameCash() {
    final name = TextEditingController(text: _cashName);
    showLedgerSheet(context, "Rename cash account", (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(controller: name, autofocus: true, decoration: fieldDecoration("Name, e.g. InCash or Petty cash", icon: Icons.payments_rounded)),
          const SizedBox(height: 16),
          primaryButton("Save", () async {
            final value = name.text.trim();
            if (value.isEmpty) return toast(ctx, "Enter a name", error: true);
            final res = await LedgerService.updateCashAccountName(s.companyId, s.userId, value);
            if (!ctx.mounted) return;
            if (handleResult(ctx, res, "Cash account renamed")) {
              setState(() => _cashName = value);
              Navigator.pop(ctx);
              _changed();
            }
          }),
        ]));
  }

  void _addBank() {
    final bank = TextEditingController();
    final holder = TextEditingController();
    final number = TextEditingController();
    final ifsc = TextEditingController();
    showLedgerSheet(context, "New bank account", (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(controller: bank, decoration: fieldDecoration("Bank name *", icon: Icons.account_balance_rounded)),
          const SizedBox(height: 10),
          TextField(controller: holder, decoration: fieldDecoration("Account holder name", icon: Icons.person_rounded)),
          const SizedBox(height: 10),
          TextField(controller: number, keyboardType: TextInputType.number, decoration: fieldDecoration("Account number *", icon: Icons.numbers_rounded)),
          const SizedBox(height: 10),
          TextField(controller: ifsc, textCapitalization: TextCapitalization.characters, decoration: fieldDecoration("IFSC code", icon: Icons.tag_rounded)),
          const SizedBox(height: 16),
          primaryButton("Save account", () async {
            if (bank.text.trim().isEmpty || number.text.trim().isEmpty) return toast(ctx, "Bank name and account number are required", error: true);
            final res = await LedgerService.addBankAccount(s.companyId, {
              "userId": s.userId,
              "bankName": bank.text.trim(),
              "accountHolder": holder.text.trim(),
              "accountNumber": number.text.trim(),
              "ifsc": ifsc.text.trim().toUpperCase(),
            });
            if (!ctx.mounted) return;
            if (handleResult(ctx, res, "Bank account added")) {
              setState(() => _accounts = List<Map<String, dynamic>>.from(res["bankAccounts"] ?? _accounts));
              Navigator.pop(ctx);
              _changed();
            }
          }),
        ]));
  }

  Future<void> _deleteBank(Map<String, dynamic> b) async {
    final ok = await confirmDialog(context, "Remove bank account?", "${bankLabel(b)} will be removed from ${s.companyName}.", confirmLabel: "Remove", danger: true);
    if (!ok || !mounted) return;
    final res = await LedgerService.deleteBankAccount(s.companyId, b["_id"].toString(), s.userId);
    if (!mounted) return;
    if (handleResult(context, res, "Bank account removed")) {
      setState(() => _accounts = List<Map<String, dynamic>>.from(res["bankAccounts"] ?? const []));
      _changed();
    }
  }

  String _incomeRoute(Map i) {
    final to = i["destinationType"] == "cash" ? _cashName : (i["destinationName"]?.toString() ?? "");
    final from = i["sourceName"]?.toString() ?? "";
    return from.isNotEmpty ? "$to ← $from" : to;
  }

  void _addIncome() {
    final amount = TextEditingController();
    final desc = TextEditingController();
    String? destination;
    String? sourceBank;
    showLedgerSheet(context, "Add income", (ctx) => StatefulBuilder(builder: (ctx, set) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: fieldDecoration("Amount ₹ *", icon: Icons.currency_rupee_rounded)),
          const SizedBox(height: 10),
          DescriptionField(companyId: s.companyId, userId: s.userId, kind: "fund", controller: desc, hint: "Description (optional)"),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: destination,
            isExpanded: true,
            decoration: fieldDecoration("Add to *", icon: Icons.south_west_rounded),
            items: [
              DropdownMenuItem(value: "cash", child: Text("$_cashName (${inr(_cash)})")),
              ..._accounts.map((b) => DropdownMenuItem(value: b["_id"].toString(), child: Text("${bankLabel(b)} · ${inr(b["balance"] ?? 0)}", overflow: TextOverflow.ellipsis))),
            ],
            onChanged: (v) => set(() {
              destination = v;
              sourceBank = null;
            }),
          ),
          if (destination != null) ...[
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              key: ValueKey(destination),
              initialValue: sourceBank,
              isExpanded: true,
              decoration: fieldDecoration("Money coming from *", icon: Icons.account_balance_rounded),
              items: [
                DropdownMenuItem(value: "direct", child: Text(destination == "cash" ? "Direct cash (new money)" : "Direct income (new money)")),
                ..._accounts
                    .where((b) => b["_id"].toString() != destination)
                    .map((b) => DropdownMenuItem(value: b["_id"].toString(), child: Text("${bankLabel(b)} · ${inr(b["balance"] ?? 0)}", overflow: TextOverflow.ellipsis))),
              ],
              onChanged: (v) => set(() => sourceBank = v),
            ),
            if (sourceBank != null) ...[
              const SizedBox(height: 4),
              Text(
                  sourceBank == "direct"
                      ? "This amount is added as new money; no other balance changes."
                      : "This amount is taken out of the selected bank's balance and moved here.",
                  style: GoogleFonts.inter(fontSize: 12, fontStyle: FontStyle.italic, color: kDark.withValues(alpha: 0.55))),
            ],
          ],
          const SizedBox(height: 16),
          primaryButton("Save", () async {
            final amt = double.tryParse(amount.text.trim()) ?? 0;
            if (!(amt > 0)) return toast(ctx, "Enter a valid amount", error: true);
            if (destination == null) return toast(ctx, "Select a bank account or $_cashName", error: true);
            if (sourceBank == null) return toast(ctx, "Select where the money is coming from", error: true);
            final res = await LedgerService.addIncome(s.companyId, {
              "userId": s.userId,
              "amount": amt,
              "destination": destination,
              "sourceBankAccountId": sourceBank,
              "description": desc.text.trim(),
            });
            if (!ctx.mounted) return;
            if (handleResult(ctx, res, "Income added")) {
              setState(() {
                _accounts = List<Map<String, dynamic>>.from(res["bankAccounts"] ?? _accounts);
                _cash = (res["cashBalance"] as num?) ?? _cash;
              });
              Navigator.pop(ctx);
              _loadIncome();
              _changed();
            }
          }),
        ])));
  }

  @override
  Widget build(BuildContext context) {
    Widget fundCard({required String emoji, required String title, required String sub, required num balance, Widget? action}) => Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16, color: kDark)),
                Text(sub, style: GoogleFonts.inter(fontSize: 12, color: kDark.withValues(alpha: 0.55))),
                const SizedBox(height: 6),
                Text(inr(balance), style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.bold, color: kForest)),
              ]),
            ),
            if (action != null) action,
          ]),
        );

    return Theme(
      data: sheetTheme,
      child: Scaffold(
        backgroundColor: kForest,
        appBar: AppBar(backgroundColor: kForest, foregroundColor: Colors.white, elevation: 0, title: Text("Company funds", style: GoogleFonts.inter(fontWeight: FontWeight.bold))),
        body: RefreshIndicator(
          onRefresh: _loadIncome,
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 30), children: [
            Text("Track $_cashName and bank balances, and where company money moves.", style: GoogleFonts.inter(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 12),
            fundCard(
              emoji: "💵",
              title: _cashName,
              sub: "Cash in hand",
              balance: _cash,
              action: IconButton(tooltip: "Rename", onPressed: _renameCash, icon: const Icon(Icons.edit_rounded, color: kForest, size: 20)),
            ),
            ..._accounts.map((b) => fundCard(
                  emoji: "🏦",
                  title: b["bankName"]?.toString() ?? "Bank",
                  sub: [
                    if ((b["accountHolder"]?.toString() ?? "").isNotEmpty) b["accountHolder"],
                    "A/C ${b["accountNumber"] ?? ""}",
                    if ((b["ifsc"]?.toString() ?? "").isNotEmpty) "IFSC ${b["ifsc"]}",
                  ].join(" • "),
                  balance: (b["balance"] as num?) ?? 0,
                  action: IconButton(tooltip: "Remove", onPressed: () => _deleteBank(b), icon: const Icon(Icons.delete_outline_rounded, color: kTerracotta, size: 20)),
                )),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(child: primaryButton("↗ Add Income", _addIncome, color: kForestDark)),
              const SizedBox(width: 8),
              Expanded(child: primaryButton("+ Add Bank Account", _addBank, color: kForestDark)),
            ]),
            if (_income.isNotEmpty) ...[
              sectionTitle("Income"),
              Container(
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                child: Column(children: [
                  for (final i in _income)
                    ListTile(
                      dense: true,
                      leading: Text(i["destinationType"] == "cash" ? "💵" : "🏦", style: const TextStyle(fontSize: 20)),
                      title: Text(
                        (i["description"]?.toString() ?? "").isNotEmpty
                            ? i["description"].toString()
                            : _incomeRoute(i),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: kDark),
                      ),
                      subtitle: Text(
                        "${(i["description"]?.toString() ?? "").isNotEmpty ? "${_incomeRoute(i)} · " : ""}${dateLabel(i["createdAt"])}",
                        style: GoogleFonts.inter(fontSize: 12),
                      ),
                      trailing: Text(inr(i["amount"]), style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: kForest)),
                      // the Admin: tap to edit or delete
                      onTap: s.canEditEntries ? () => _incomeActions(i) : null,
                    ),
                ]),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  /// Edit (amount, description, date & time) or delete one income entry. A new amount moves that account's balance by
  /// the difference; deleting takes the money back out (a transfer goes back where it came from).
  Future<void> _incomeActions(Map<String, dynamic> i) async {
    final amount = TextEditingController(text: (i["amount"] ?? "").toString());
    final desc = TextEditingController(text: i["description"]?.toString() ?? "");
    DateTime when = DateTime.tryParse(i["createdAt"]?.toString() ?? "")?.toLocal() ?? DateTime.now();
    final done = await showLedgerSheet<bool>(context, "Income", (ctx) => StatefulBuilder(builder: (ctx, set) {
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_incomeRoute(i), style: GoogleFonts.inter(fontSize: 13, color: kDark.withValues(alpha: 0.6))),
            const SizedBox(height: 10),
            TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: fieldDecoration("Amount ₹", icon: Icons.currency_rupee_rounded)),
            const SizedBox(height: 10),
            TextField(controller: desc, decoration: fieldDecoration("Description", icon: Icons.notes_rounded)),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              icon: const Icon(Icons.event_rounded, size: 18),
              label: Text(DateFormat("dd MMM yyyy · h:mm a").format(when)),
              onPressed: () async {
                final d = await showDatePicker(context: ctx, initialDate: when, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 1)));
                if (d == null || !ctx.mounted) return;
                final t = await showTimePicker(context: ctx, initialTime: TimeOfDay.fromDateTime(when));
                set(() => when = DateTime(d.year, d.month, d.day, t?.hour ?? when.hour, t?.minute ?? when.minute));
              },
            ),
            const SizedBox(height: 12),
            primaryButton("Save", () async {
              final v = double.tryParse(amount.text.trim()) ?? 0;
              if (!(v > 0)) return toast(ctx, "Enter an amount greater than zero", error: true);
              final res = await LedgerService.editAccountsEntry(s.companyId, s.userId, "income:${i["_id"]}",
                  {"amount": v, "details": desc.text.trim(), "date": DateFormat("yyyy-MM-dd'T'HH:mm").format(when)});
              if (!ctx.mounted) return;
              if (handleResult(ctx, res, "Income updated · balances adjusted")) Navigator.pop(ctx, true);
            }),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: () async {
                  final ok = await confirmDialog(ctx, "Delete this income?", "${inr(i["amount"])} will be taken back out of the account it went into, and the entry removed.", confirmLabel: "Delete", danger: true);
                  if (!ok || !ctx.mounted) return;
                  final res = await LedgerService.deleteAccountsEntry(s.companyId, s.userId, "income:${i["_id"]}");
                  if (!ctx.mounted) return;
                  if (handleResult(ctx, res, "Deleted · balances adjusted")) Navigator.pop(ctx, true);
                },
                child: const Text("Delete this income", style: TextStyle(color: kTerracotta, fontWeight: FontWeight.w600)),
              ),
            ),
          ]);
        }));
    if (done == true && mounted) {
      notifyLedgerChanged();
      _loadIncome();
    }
  }
}
