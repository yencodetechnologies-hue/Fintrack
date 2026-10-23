import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/ledger_service.dart';
import 'ledger_common.dart';

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

  void _addIncome() {
    final amount = TextEditingController();
    final desc = TextEditingController();
    String? destination;
    String? sourceBank;
    showLedgerSheet(context, "Add income", (ctx) => StatefulBuilder(builder: (ctx, set) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: fieldDecoration("Amount ₹ *", icon: Icons.currency_rupee_rounded)),
          const SizedBox(height: 10),
          TextField(controller: desc, decoration: fieldDecoration("Description (optional)", icon: Icons.notes_rounded)),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: destination,
            isExpanded: true,
            decoration: fieldDecoration("Add to *", icon: Icons.south_west_rounded),
            items: [
              DropdownMenuItem(value: "cash", child: Text("$_cashName (${inr(_cash)})")),
              ..._accounts.map((b) => DropdownMenuItem(value: b["_id"].toString(), child: Text("${bankLabel(b)} · ${inr(b["balance"] ?? 0)}", overflow: TextOverflow.ellipsis))),
            ],
            onChanged: (v) => set(() => destination = v),
          ),
          if (destination == "cash") ...[
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: sourceBank,
              isExpanded: true,
              decoration: fieldDecoration("Cash coming from bank *", icon: Icons.account_balance_rounded),
              items: _accounts.map((b) => DropdownMenuItem(value: b["_id"].toString(), child: Text("${bankLabel(b)} · ${inr(b["balance"] ?? 0)}", overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (v) => set(() => sourceBank = v),
            ),
            const SizedBox(height: 4),
            Text("This amount is taken out of the selected bank's balance and added to $_cashName.",
                style: GoogleFonts.inter(fontSize: 11.5, fontStyle: FontStyle.italic, color: kDark.withValues(alpha: 0.55))),
          ],
          const SizedBox(height: 16),
          primaryButton("Save", () async {
            final amt = double.tryParse(amount.text.trim()) ?? 0;
            if (!(amt > 0)) return toast(ctx, "Enter a valid amount", error: true);
            if (destination == null) return toast(ctx, "Select a bank account or $_cashName", error: true);
            if (destination == "cash" && sourceBank == null) return toast(ctx, "Select the bank account the cash is coming from", error: true);
            final res = await LedgerService.addIncome(s.companyId, {
              "userId": s.userId,
              "amount": amt,
              "destination": destination,
              if (destination == "cash") "sourceBankAccountId": sourceBank,
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
            Text(emoji, style: const TextStyle(fontSize: 26)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 15, color: kDark)),
                Text(sub, style: GoogleFonts.inter(fontSize: 12, color: kDark.withValues(alpha: 0.55))),
                const SizedBox(height: 6),
                Text(inr(balance), style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.bold, color: kForest)),
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
            Text("Track $_cashName and bank balances, and where company money moves.", style: GoogleFonts.inter(color: Colors.white70, fontSize: 12.5)),
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
              sectionTitle("Recent income"),
              Container(
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                child: Column(children: [
                  for (final i in _income.take(10))
                    ListTile(
                      dense: true,
                      leading: Text(i["destinationType"] == "cash" ? "💵" : "🏦", style: const TextStyle(fontSize: 18)),
                      title: Text(
                        (i["description"]?.toString() ?? "").isNotEmpty
                            ? i["description"].toString()
                            : (i["destinationType"] == "cash" ? "$_cashName ← ${i["sourceName"]}" : i["destinationName"]?.toString() ?? ""),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: kDark),
                      ),
                      subtitle: Text(
                        "${(i["description"]?.toString() ?? "").isNotEmpty ? "${i["destinationType"] == "cash" ? "$_cashName ← ${i["sourceName"]}" : i["destinationName"]} · " : ""}${dateLabel(i["createdAt"])}",
                        style: GoogleFonts.inter(fontSize: 11.5),
                      ),
                      trailing: Text("+${inr(i["amount"])}", style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: kForest)),
                    ),
                ]),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}
