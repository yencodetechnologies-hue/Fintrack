import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/ledger_service.dart';
import 'ledger_common.dart';
import 'ledger_description_field.dart';

typedef LedgerFund = ({String id, String name, num balance});

num _round(num n) => (n * 100).round() / 100;

/// A payment needs more than [fund] holds: asks, then shows an "Add money" sheet on top of the current one.
/// Returns true once the money is added, so the caller can carry on with the payment:
///   if (short && !await topUpFund(ctx, s, fund, amount)) return;
Future<bool> topUpFund(BuildContext context, LedgerScope s, LedgerFund fund, num need) async {
  final shortBy = _round(need - fund.balance);
  final yes = await confirmDialog(
    context,
    "Not enough balance",
    "${fund.name} has ${inr(fund.balance)}, but this payment needs ${inr(need)} (${inr(shortBy)} short). Do you want to add money to ${fund.name} and pay now?",
    confirmLabel: "Add money",
  );
  if (!yes || !context.mounted) return false;
  final added = await showLedgerSheet<bool>(context, "Add money to ${fund.name}", (ctx) => _TopUpForm(s: s, fund: fund, need: need));
  if (added != true) return false;
  s.reload(); // refresh balances behind the sheets; the payment itself doesn't wait for it
  return true;
}

class _TopUpForm extends StatefulWidget {
  final LedgerScope s;
  final LedgerFund fund;
  final num need;
  const _TopUpForm({required this.s, required this.fund, required this.need});

  @override
  State<_TopUpForm> createState() => _TopUpFormState();
}

class _TopUpFormState extends State<_TopUpForm> {
  late final num _shortBy = _round(widget.need - widget.fund.balance);
  late final _amount = TextEditingController(text: _shortBy.toStringAsFixed(2));
  final _desc = TextEditingController();
  String _source = "direct";

  bool get _isCash => widget.fund.id == "cash";
  // money comes in new, or moves from another bank account (cash can't be moved into a bank here)
  List<LedgerFund> get _sources => widget.s.funds.where((f) => f.id != "cash" && f.id != widget.fund.id).toList();

  @override
  void dispose() {
    _amount.dispose();
    _desc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final amount = _round(double.tryParse(_amount.text.trim()) ?? 0);
    final from = _sources.where((f) => f.id == _source).firstOrNull;
    final sourceShort = from != null && from.balance < amount;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text("Balance ${inr(widget.fund.balance)} · payment needs ${inr(widget.need)}. The payment goes through right after the money is added.",
          style: GoogleFonts.inter(fontSize: 13, color: kDark.withValues(alpha: 0.7))),
      const SizedBox(height: 12),
      TextField(
        controller: _amount,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (_) => setState(() {}),
        decoration: fieldDecoration("Amount ₹ * (at least ${inr(_shortBy)})", icon: Icons.currency_rupee_rounded),
      ),
      const SizedBox(height: 10),
      DropdownButtonFormField<String>(
        initialValue: _source,
        isExpanded: true,
        decoration: fieldDecoration("Money coming from *", icon: Icons.account_balance_rounded),
        items: [
          DropdownMenuItem(value: "direct", child: Text(_isCash ? "Direct cash (new money)" : "Direct income (new money)")),
          ..._sources.map((f) => DropdownMenuItem(value: f.id, child: Text("${f.name} · ${inr(f.balance)}", overflow: TextOverflow.ellipsis))),
        ],
        onChanged: (v) => setState(() => _source = v ?? "direct"),
      ),
      if (sourceShort)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text("Only ${inr(from.balance)} available in ${from.name}.",
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: kTerracotta)),
        ),
      const SizedBox(height: 10),
      DescriptionField(companyId: widget.s.companyId, userId: widget.s.userId, kind: "fund", controller: _desc, hint: "Description (optional)"),
      const SizedBox(height: 16),
      primaryButton(
        "Add ${inr(amount)} & pay",
        sourceShort || !(amount > 0)
            ? null
            : () async {
                if (amount < _shortBy) return toast(context, "Add at least ${inr(_shortBy)} to cover this payment", error: true);
                final res = await LedgerService.addIncome(widget.s.companyId, {
                  "userId": widget.s.userId,
                  "amount": amount,
                  "destination": widget.fund.id,
                  "sourceBankAccountId": _source,
                  "description": _desc.text.trim(),
                });
                if (!context.mounted) return;
                if (handleResult(context, res, "${inr(amount)} added to ${widget.fund.name}")) Navigator.pop(context, true);
              },
      ),
    ]);
  }
}
