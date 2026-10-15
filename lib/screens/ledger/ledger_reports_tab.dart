import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/ledger_service.dart';
import 'ledger_common.dart';
import 'ledger_expenses_tab.dart' show kCategories;

class LedgerReportsTab extends StatefulWidget {
  final LedgerScope scope;
  const LedgerReportsTab({super.key, required this.scope});

  @override
  State<LedgerReportsTab> createState() => _LedgerReportsTabState();
}

class _LedgerReportsTabState extends State<LedgerReportsTab> with LedgerAutoRefresh {
  @override
  void onLedgerChanged() => _load(quiet: true);

  LedgerScope get s => widget.scope;
  bool _full = false;
  DateTimeRange? _range;
  String _category = "All";
  Map<String, dynamic>? _report;
  bool _loading = true;

  final _fmt = DateFormat("yyyy-MM-dd");

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) setState(() => _loading = true);
    final res = await LedgerService.report(
      s.companyId,
      s.userId,
      from: _range == null ? null : _fmt.format(_range!.start),
      to: _range == null ? null : _fmt.format(_range!.end),
      category: _category,
    );
    if (!mounted) return;
    setState(() {
      _report = res["report"];
      _loading = false;
    });
  }

  Future<void> _export() async {
    final url = LedgerService.exportUrl(
      s.companyId,
      s.userId,
      full: _full,
      from: _range == null ? null : _fmt.format(_range!.start),
      to: _range == null ? null : _fmt.format(_range!.end),
    );
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && mounted) toast(context, "Could not open the download", error: true);
  }

  @override
  Widget build(BuildContext context) {
    final rangeLabel = _range == null ? "All dates" : "${DateFormat("dd MMM").format(_range!.start)} – ${DateFormat("dd MMM yyyy").format(_range!.end)}";
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 30),
      children: [
        if (s.isSuperAdmin) ...[
          SegmentedButton<bool>(
            style: SegmentedButton.styleFrom(backgroundColor: kForestDark, foregroundColor: Colors.white, selectedBackgroundColor: Colors.white, selectedForegroundColor: kForest),
            segments: const [
              ButtonSegment(value: false, label: Text("Company report")),
              ButtonSegment(value: true, label: Text("Full audit")),
            ],
            selected: {_full},
            onSelectionChanged: (v) => setState(() => _full = v.first),
          ),
          const SizedBox(height: 12),
        ],
        ledgerCard(
          child: Column(
            children: [
              InkWell(
                onTap: () async {
                  final picked = await showDateRangePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime.now(), initialDateRange: _range);
                  if (picked != null) {
                    setState(() => _range = picked);
                    _load();
                  }
                },
                child: InputDecorator(decoration: fieldDecoration("From – To", icon: Icons.date_range_rounded), child: Text(rangeLabel)),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: fieldDecoration("Category", icon: Icons.category_rounded),
                items: ["All", ...kCategories].map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (v) {
                  setState(() => _category = v ?? "All");
                  _load();
                },
              ),
            ],
          ),
        ),
        if (!_full) ...[
          sectionTitle("This period"),
          if (_loading)
            const Center(child: CircularProgressIndicator(color: Colors.white))
          else
            ledgerCard(
              child: Column(
                children: [
                  _row("Expenses", _report?["expenses"]),
                  _row("Paid by admins", _report?["paidByAdmins"]),
                  _row("Owed to admins", _report?["owedToAdmins"]),
                  _row("Inter-company net", _report?["intercompanyNet"]),
                ],
              ),
            ),
        ] else ...[
          sectionTitle("Full audit includes"),
          ledgerCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final line in ["All companies, every ledger entry", "Inter-company trail and reversals", "Audit log: who did what, when"])
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text("• $line", style: GoogleFonts.inter(color: kDark)),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 8),
        primaryButton("Export CSV (opens in Excel)", _export, color: kForestDark),
      ],
    );
  }

  Widget _row(String label, dynamic value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Expanded(child: Text(label, style: GoogleFonts.inter(color: kDark, fontWeight: FontWeight.w600))),
            Text(inr(value), style: GoogleFonts.fraunces(color: kForest, fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
      );
}
