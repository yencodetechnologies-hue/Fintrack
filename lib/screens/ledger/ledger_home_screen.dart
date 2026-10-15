import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/ledger_service.dart';
import 'ledger_common.dart';
import 'ledger_dashboard_tab.dart';
import 'ledger_expenses_tab.dart';
import 'ledger_interco_tab.dart';
import 'ledger_reports_tab.dart';
import 'ledger_more_tab.dart';
import 'ledger_groups_tab.dart';

class LedgerHomeScreen extends StatefulWidget {
  final String userId;
  final String userName;
  final List<Map<String, dynamic>> companies;
  final String initialCompanyId;

  const LedgerHomeScreen({
    super.key,
    required this.userId,
    required this.userName,
    required this.companies,
    required this.initialCompanyId,
  });

  @override
  State<LedgerHomeScreen> createState() => _LedgerHomeScreenState();
}

class _LedgerHomeScreenState extends State<LedgerHomeScreen> with LedgerAutoRefresh {
  @override
  void onLedgerChanged() => _load();

  late String _companyId = widget.initialCompanyId;
  LedgerScope? _scope;
  String? _error;
  int _tab = 0;
  final _poller = LedgerPoller();

  @override
  void initState() {
    super.initState();
    _load();
    _poller.start();
  }

  @override
  void dispose() {
    _poller.stop();
    super.dispose();
  }

  Future<void> _reloadAll() async {
    await _load();
    notifyLedgerChanged();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      LedgerService.companyDetails(_companyId, widget.userId),
      LedgerService.balances(_companyId, widget.userId),
    ]);
    if (!mounted) return;
    final details = results[0];
    final balances = results[1];
    if (details["success"] != true) {
      setState(() => _error = details["message"]?.toString() ?? "Could not load company");
      return;
    }
    setState(() {
      _error = null;
      _scope = LedgerScope(
        userId: widget.userId,
        userName: widget.userName,
        company: Map<String, dynamic>.from(details["company"]),
        role: balances["role"]?.toString() ?? (details["currentUserRole"] == "admin" ? "admin" : "employee"),
        members: List<Map<String, dynamic>>.from(details["members"] ?? const []),
        reload: _reloadAll,
      );
    });
  }

  void _switchCompany(String id) {
    setState(() {
      _companyId = id;
      _scope = null;
      _tab = 0;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final scope = _scope;
    final adminTabs = scope?.isAdmin ?? false;
    final tabs = <({IconData icon, String label, Widget Function(LedgerScope) build})>[
      (icon: Icons.home_rounded, label: "Home", build: (s) => LedgerDashboardTab(scope: s, onOpenExpenses: () => setState(() => _tab = 1))),
      (icon: Icons.receipt_long_rounded, label: "Expenses", build: (s) => LedgerExpensesTab(scope: s)),
      if (adminTabs) (icon: Icons.swap_horiz_rounded, label: "Inter-co", build: (s) => LedgerIntercoTab(scope: s)),
      if (!adminTabs) (icon: Icons.groups_rounded, label: "Groups", build: (s) => LedgerGroupsTab(scope: s)),
      if (adminTabs) (icon: Icons.bar_chart_rounded, label: "Reports", build: (s) => LedgerReportsTab(scope: s)),
      (icon: Icons.more_horiz_rounded, label: "More", build: (s) => LedgerMoreTab(scope: s)),
    ];
    final tab = _tab < tabs.length ? _tab : 0;

    return Theme(data: sheetTheme, child: Scaffold(
      backgroundColor: kForest,
      appBar: AppBar(
        backgroundColor: kForest,
        elevation: 0,
        foregroundColor: Colors.white,
        titleSpacing: 0,
        title: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _companyId,
            dropdownColor: kForestDark,
            iconEnabledColor: kMint,
            style: GoogleFonts.fraunces(color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold),
            items: widget.companies
                .map((c) => DropdownMenuItem(value: c["_id"].toString(), child: Text(c["name"].toString(), overflow: TextOverflow.ellipsis)))
                .toList(),
            onChanged: (v) => v != null && v != _companyId ? _switchCompany(v) : null,
          ),
        ),
      ),
      body: _error != null
          ? Center(child: Text(_error!, style: GoogleFonts.inter(color: Colors.white)))
          : scope == null
              ? const Center(child: CircularProgressIndicator(color: Colors.white))
              : KeyedSubtree(key: ValueKey("$_companyId-$tab"), child: tabs[tab].build(scope)),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: tab,
        type: BottomNavigationBarType.fixed,
        backgroundColor: kForestDark,
        selectedItemColor: kMint,
        unselectedItemColor: Colors.white60,
        onTap: (i) => setState(() => _tab = i),
        items: tabs.map((t) => BottomNavigationBarItem(icon: Icon(t.icon), label: t.label)).toList(),
      ),
    ));
  }
}
