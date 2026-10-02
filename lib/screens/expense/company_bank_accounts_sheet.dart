import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../services/expense_company_service.dart';

class CompanyBankAccountsSheet extends StatefulWidget {
  final String companyId;
  final String userId;
  final List<Map<String, dynamic>> initialAccounts;
  final num initialCashBalance;

  const CompanyBankAccountsSheet({
    super.key,
    required this.companyId,
    required this.userId,
    required this.initialAccounts,
    this.initialCashBalance = 0,
  });

  @override
  State<CompanyBankAccountsSheet> createState() => _CompanyBankAccountsSheetState();
}

class _CompanyBankAccountsSheetState extends State<CompanyBankAccountsSheet> {
  static const Color forestDark = Color(0xFF0C5F41);
  static const Color darkText = Color(0xFF1E293B);
  static const Color terracotta = Color(0xFFB8452D);

  late List<Map<String, dynamic>> _accounts;
  late num _cashBalance;
  List<Map<String, dynamic>> _income = [];

  // "" = list, "bank" = add bank form, "income" = add income form
  String _mode = "";
  bool _saving = false;

  final _bankCtrl = TextEditingController();
  final _holderCtrl = TextEditingController();
  final _numberCtrl = TextEditingController();
  final _ifscCtrl = TextEditingController();

  final _incomeAmountCtrl = TextEditingController();
  String? _incomeDestination; // "cash" or bank id
  String? _incomeSourceBankId;

  @override
  void initState() {
    super.initState();
    _accounts = List.from(widget.initialAccounts);
    _cashBalance = widget.initialCashBalance;
    _loadIncome();
  }

  @override
  void dispose() {
    _bankCtrl.dispose();
    _holderCtrl.dispose();
    _numberCtrl.dispose();
    _ifscCtrl.dispose();
    _incomeAmountCtrl.dispose();
    super.dispose();
  }

  void _toast(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  String _money(num v) => "₹${v.toStringAsFixed(2)}";

  Future<void> _loadIncome() async {
    final res = await ExpenseCompanyService.getIncomeHistory(companyId: widget.companyId, userId: widget.userId);
    if (!mounted) return;
    if (res["success"] == true) {
      setState(() => _income = List<Map<String, dynamic>>.from(res["income"] ?? []));
    }
  }

  Future<void> _saveBank() async {
    if (_bankCtrl.text.trim().isEmpty || _numberCtrl.text.trim().isEmpty) {
      _toast("Bank name and account number are required");
      return;
    }
    setState(() => _saving = true);
    final res = await ExpenseCompanyService.addBankAccount(
      companyId: widget.companyId,
      userId: widget.userId,
      bankName: _bankCtrl.text.trim(),
      accountHolder: _holderCtrl.text.trim(),
      accountNumber: _numberCtrl.text.trim(),
      ifsc: _ifscCtrl.text.trim(),
    );
    if (!mounted) return;
    if (res["success"] == true) {
      setState(() {
        _accounts = List<Map<String, dynamic>>.from(res["bankAccounts"] ?? []);
        _mode = "";
        _saving = false;
        _bankCtrl.clear();
        _holderCtrl.clear();
        _numberCtrl.clear();
        _ifscCtrl.clear();
      });
    } else {
      setState(() => _saving = false);
      _toast(res["message"]?.toString() ?? "Failed to save bank account");
    }
  }

  Future<void> _saveIncome() async {
    final amount = double.tryParse(_incomeAmountCtrl.text.trim());
    if (amount == null || amount <= 0) {
      _toast("Enter a valid amount");
      return;
    }
    if (_incomeDestination == null) {
      _toast("Select a bank account or InCash");
      return;
    }
    if (_incomeDestination == "cash" && _incomeSourceBankId == null) {
      _toast("Select the bank account the cash is coming from");
      return;
    }
    setState(() => _saving = true);
    final res = await ExpenseCompanyService.addIncome(
      companyId: widget.companyId,
      userId: widget.userId,
      amount: amount,
      destination: _incomeDestination!,
      sourceBankAccountId: _incomeDestination == "cash" ? _incomeSourceBankId : null,
    );
    if (!mounted) return;
    if (res["success"] == true) {
      setState(() {
        _accounts = List<Map<String, dynamic>>.from(res["bankAccounts"] ?? []);
        _cashBalance = (res["cashBalance"] as num?) ?? 0;
        _mode = "";
        _saving = false;
        _incomeAmountCtrl.clear();
        _incomeDestination = null;
        _incomeSourceBankId = null;
      });
      _loadIncome();
    } else {
      setState(() => _saving = false);
      _toast(res["message"]?.toString() ?? "Failed to add income");
    }
  }

  Future<void> _delete(Map<String, dynamic> account) async {
    final res = await ExpenseCompanyService.deleteBankAccount(
      companyId: widget.companyId,
      userId: widget.userId,
      accountId: account["_id"].toString(),
    );
    if (!mounted) return;
    if (res["success"] == true) {
      setState(() => _accounts = List<Map<String, dynamic>>.from(res["bankAccounts"] ?? []));
    } else {
      _toast(res["message"]?.toString() ?? "Failed to remove bank account");
    }
  }

  InputDecoration _dec(String label, IconData icon) => InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 18, color: forestDark),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: forestDark, width: 1.5)),
      );

  TextStyle get _fieldStyle => GoogleFonts.inter(color: darkText, fontWeight: FontWeight.w600);

  Widget _fundTile({required IconData icon, required String title, String? subtitle, required num balance, Widget? trailing}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: ListTile(
        leading: Icon(icon, color: forestDark),
        title: Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: darkText, fontSize: 14.5)),
        subtitle: subtitle == null || subtitle.isEmpty
            ? null
            : Text(subtitle, style: GoogleFonts.inter(color: darkText.withValues(alpha: 0.6), fontSize: 12)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text("Balance", style: GoogleFonts.inter(fontSize: 10, color: darkText.withValues(alpha: 0.5))),
                Text(_money(balance), style: GoogleFonts.fraunces(fontWeight: FontWeight.bold, color: forestDark, fontSize: 15)),
              ],
            ),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }

  Widget _primaryButton(String label, IconData icon, VoidCallback onTap) => SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: onTap,
          icon: Icon(icon),
          label: Text(label),
          style: ElevatedButton.styleFrom(
            backgroundColor: forestDark,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      );

  Widget _formButtons(VoidCallback onSave) => Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _saving ? null : () => setState(() => _mode = ""),
              style: OutlinedButton.styleFrom(
                foregroundColor: darkText,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text("Cancel"),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton(
              onPressed: _saving ? null : onSave,
              style: ElevatedButton.styleFrom(
                backgroundColor: forestDark,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(_saving ? "Saving..." : "Save"),
            ),
          ),
        ],
      );

  DropdownButtonFormField<String> _bankDropdown({
    required String label,
    required String? value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      dropdownColor: Colors.white,
      style: _fieldStyle.copyWith(fontSize: 14),
      decoration: _dec(label, Icons.account_balance_rounded),
      items: items,
      onChanged: onChanged,
    );
  }

  Widget _incomeForm() {
    final bankItems = _accounts
        .map((b) => DropdownMenuItem<String>(
              value: b["_id"].toString(),
              child: Text("${b["bankName"]} (${_money((b["balance"] as num?) ?? 0)})", overflow: TextOverflow.ellipsis),
            ))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Add Income", style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: darkText, fontSize: 15)),
        const SizedBox(height: 10),
        TextField(
          controller: _incomeAmountCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: _fieldStyle,
          decoration: _dec("Amount (₹) *", Icons.currency_rupee_rounded),
        ),
        const SizedBox(height: 10),
        _bankDropdown(
          label: "Add to *",
          value: _incomeDestination,
          items: [
            DropdownMenuItem<String>(value: "cash", child: Text("InCash (${_money(_cashBalance)})")),
            ...bankItems,
          ],
          onChanged: (v) => setState(() => _incomeDestination = v),
        ),
        if (_incomeDestination == "cash") ...[
          const SizedBox(height: 10),
          _bankDropdown(
            label: "Cash coming from bank *",
            value: _incomeSourceBankId,
            items: bankItems,
            onChanged: (v) => setState(() => _incomeSourceBankId = v),
          ),
          const SizedBox(height: 6),
          Text(
            "This amount is taken out of the selected bank's balance and added to InCash.",
            style: GoogleFonts.inter(color: darkText.withValues(alpha: 0.55), fontSize: 11, fontStyle: FontStyle.italic),
          ),
        ],
        const SizedBox(height: 14),
        _formButtons(_saveIncome),
      ],
    );
  }

  Widget _bankForm() {
    return Column(
      children: [
        TextField(controller: _bankCtrl, style: _fieldStyle, decoration: _dec("Bank name *", Icons.account_balance_rounded)),
        const SizedBox(height: 10),
        TextField(controller: _holderCtrl, style: _fieldStyle, decoration: _dec("Account holder name", Icons.person_rounded)),
        const SizedBox(height: 10),
        TextField(
          controller: _numberCtrl,
          keyboardType: TextInputType.number,
          style: _fieldStyle,
          decoration: _dec("Account number *", Icons.numbers_rounded),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _ifscCtrl,
          textCapitalization: TextCapitalization.characters,
          style: _fieldStyle,
          decoration: _dec("IFSC code", Icons.pin_rounded),
        ),
        const SizedBox(height: 14),
        _formButtons(_saveBank),
      ],
    );
  }

  Widget _incomeHistory() {
    if (_income.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text("Recent Income", style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: darkText, fontSize: 14)),
        const SizedBox(height: 6),
        for (final i in _income.take(8))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(i["destinationType"] == "cash" ? Icons.payments_rounded : Icons.account_balance_rounded, size: 16, color: forestDark),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    i["destinationType"] == "cash"
                        ? "InCash ← ${i["sourceName"]}"
                        : "${i["destinationName"]}",
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(color: darkText, fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  i["createdAt"] != null ? DateFormat("dd MMM").format(DateTime.parse(i["createdAt"]).toLocal()) : "",
                  style: GoogleFonts.inter(color: darkText.withValues(alpha: 0.5), fontSize: 11),
                ),
                const SizedBox(width: 10),
                Text("+${_money(i["amount"] as num)}", style: GoogleFonts.inter(color: forestDark, fontWeight: FontWeight.bold, fontSize: 12.5)),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
      padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(color: darkText.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 14),
            Text("Company Funds", style: GoogleFonts.fraunces(color: darkText, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 14),
            _fundTile(icon: Icons.payments_rounded, title: "InCash", subtitle: "Cash in hand", balance: _cashBalance),
            for (final a in _accounts)
              _fundTile(
                icon: Icons.account_balance_rounded,
                title: "${a["bankName"]}",
                subtitle: [
                  if ((a["accountHolder"] ?? "").toString().isNotEmpty) a["accountHolder"],
                  "A/C ${a["accountNumber"]}",
                  if ((a["ifsc"] ?? "").toString().isNotEmpty) "IFSC ${a["ifsc"]}",
                ].join("\n"),
                balance: (a["balance"] as num?) ?? 0,
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: terracotta),
                  onPressed: () => _delete(a),
                ),
              ),
            const SizedBox(height: 6),
            if (_mode == "bank")
              _bankForm()
            else if (_mode == "income")
              _incomeForm()
            else ...[
              _primaryButton("Add Income", Icons.trending_up_rounded, () => setState(() => _mode = "income")),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _mode = "bank"),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text("Add Bank Account"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: forestDark,
                    side: const BorderSide(color: forestDark),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              _incomeHistory(),
            ],
          ],
        ),
      ),
    );
  }
}
