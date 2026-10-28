import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/ledger_service.dart';
import '../../services/expense_company_service.dart';
import '../../services/ledger_live.dart';
import 'ledger_common.dart';
import 'ledger_dashboard_tab.dart';
import 'ledger_expense_detail.dart';
import 'ledger_expenses_tab.dart';
import 'ledger_interco_tab.dart';
import 'ledger_reports_tab.dart';
import 'ledger_more_tab.dart';
import 'ledger_payments.dart';

/// A company's workspace: the web's Home / Expenses / Inter-co / Reports (+ Analysis) / More, as bottom tabs.
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

  // company details: name, funds, members, my role and permission switches
  @override
  Set<String> get ledgerTopics => const {"company", "members", "permissions", "funds"};

  late String _companyId = widget.initialCompanyId;
  late List<Map<String, dynamic>> _companies = List<Map<String, dynamic>>.from(widget.companies);
  LedgerScope? _scope;
  String? _error;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _hydrateScope();
    _load();
    _loadCompanies();
    LedgerLive.watch(_companyId, widget.userId);
  }

  @override
  void dispose() {
    LedgerLive.stop(_companyId);
    super.dispose();
  }

  // companies this company may borrow from (server list, same for every role); kept across scope rebuilds
  Set<String> _lenderIds = {};

  void _hydrateScope() {
    final initialCompany = _companies.firstWhere(
      (c) => c["_id"]?.toString() == _companyId,
      orElse: () => _companies.isNotEmpty ? _companies.first : <String, dynamic>{},
    );
    final cachedDetails = ExpenseCompanyService.getCachedDetails(_companyId, widget.userId);
    final companyMap = cachedDetails?["company"] is Map<String, dynamic>
        ? Map<String, dynamic>.from(cachedDetails!["company"])
        : (initialCompany.isNotEmpty ? Map<String, dynamic>.from(initialCompany) : null);
    if (companyMap == null) return;
    final role = cachedDetails?["currentUserRole"]?.toString() ?? initialCompany["userRole"]?.toString() ?? "member";
    _scope = _buildScope(
      companyMap,
      role == "admin" ? "admin" : "employee",
      cachedDetails?["members"] is List ? List<Map<String, dynamic>>.from(cachedDetails!["members"]) : const [],
      cachedDetails?["hiddenStaffIds"] is List ? List<String>.from(cachedDetails!["hiddenStaffIds"].map((e) => e.toString())) : const [],
      permissions: cachedDetails?["myPermissions"] is Map ? Map<String, dynamic>.from(cachedDetails!["myPermissions"]) : null,
      permissionRole: cachedDetails?["permissionRole"]?.toString(),
      roleName: cachedDetails?["myRoleName"]?.toString(),
    );
  }

  LedgerScope _buildScope(Map<String, dynamic> company, String role, List<Map<String, dynamic>> members, List<String> hidden,
          {Map<String, dynamic>? permissions, String? permissionRole, String? roleName}) =>
      LedgerScope(
        userId: widget.userId,
        userName: widget.userName,
        company: company,
        role: role,
        members: members,
        reload: _reloadAll,
        hiddenStaffIds: hidden,
        companies: _companies,
        permissions: permissions,
        permissionRole: permissionRole,
        roleName: roleName,
        lenderIds: _lenderIds,
      );

  // every open tab (and this screen) reloads through the shared ledger-changed signal
  Future<void> _reloadAll() async => notifyLedgerChanged();

  Future<void> _loadCompanies() async {
    final res = await LedgerService.userCompanies(widget.userId);
    if (!mounted || res["success"] != true || res["companies"] is! List) return;
    setState(() {
      _companies = List<Map<String, dynamic>>.from(res["companies"]);
      if (_scope != null) {
        _scope = _buildScope(_scope!.company, _scope!.role, _scope!.members, _scope!.hiddenStaffIds,
            permissions: _scope!.permissions, permissionRole: _scope!.permissionRole, roleName: _scope!.roleName);
      }
    });
  }

  Future<void> _load() async {
    final results = await Future.wait([
      LedgerService.companyDetails(_companyId, widget.userId),
      LedgerService.balances(_companyId, widget.userId),
      LedgerService.borrowSources(_companyId, widget.userId),
    ]);
    if (!mounted) return;
    final details = results[0];
    final balances = results[1];
    if (results[2]["success"] == true) {
      _lenderIds = {for (final c in List.from(results[2]["companies"] ?? const [])) c["_id"].toString()};
    }
    if (details["success"] != true) {
      if (_scope == null) setState(() => _error = details["message"]?.toString() ?? "Could not load company");
      return;
    }
    setState(() {
      _error = null;
      _scope = _buildScope(
        Map<String, dynamic>.from(details["company"]),
        balances["role"]?.toString() ?? (details["currentUserRole"] == "admin" ? "admin" : "employee"),
        List<Map<String, dynamic>>.from(details["members"] ?? const []),
        List<String>.from((details["hiddenStaffIds"] ?? const []).map((e) => e.toString())),
        permissions: details["myPermissions"] is Map ? Map<String, dynamic>.from(details["myPermissions"]) : null,
        permissionRole: details["permissionRole"]?.toString(),
        roleName: details["myRoleName"]?.toString(),
      );
    });
  }

  void _switchCompany(String id) {
    setState(() {
      _companyId = id;
      _tab = 0;
      _scope = null;
      _lenderIds = {};
      _hydrateScope();
    });
    LedgerLive.watch(id, widget.userId);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final scope = _scope;
    final admin = scope?.isAdmin ?? false;
    final tabs = <({IconData icon, String label, Widget Function(LedgerScope) build})>[
      (
        icon: Icons.home_rounded,
        label: "Home",
        build: (s) => LedgerDashboardTab(
              scope: s,
              onOpenExpenses: () => setState(() => _tab = 1),
              // Inter-co is the third tab only when Payments isn't there; otherwise it opens from More
              onOpenInterco: !s.can("intercompany")
                  ? null
                  : paymentsInNav(s)
                      ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => IntercoPage(scope: s)))
                      : () => setState(() => _tab = 2),
              onOpenExpense: (e) => showExpenseDetail(context, s, e),
            )
      ),
      (icon: Icons.receipt_long_rounded, label: "Expenses", build: (s) => LedgerExpensesTab(scope: s)),
      // managers who can pay people get Payments here (Inter-co then moves to More); everyone else keeps Inter-co
      if (scope != null && paymentsInNav(scope))
        (icon: Icons.payments_rounded, label: "Payments", build: (s) => PaymentsPage(scope: s, embedded: true, mineOnly: true))
      else if (scope?.can("intercompany") ?? true)
        (icon: Icons.swap_horiz_rounded, label: "Loans", build: (s) => LedgerIntercoTab(scope: s)),
      if (admin && (scope!.can("reports") || scope.can("analysis")))
        (icon: Icons.bar_chart_rounded, label: "Reports", build: (s) => LedgerReportsTab(scope: s)),
      (icon: Icons.more_horiz_rounded, label: "More", build: (s) => LedgerMoreTab(scope: s)),
    ];
    final tab = _tab < tabs.length ? _tab : 0;

    return Theme(
      data: sheetTheme,
      child: Scaffold(
        backgroundColor: kForest,
        appBar: AppBar(
          backgroundColor: kForest,
          elevation: 0,
          foregroundColor: Colors.white,
          titleSpacing: 0,
          // company switcher: as wide as the name, with the arrow right after it
          title: Align(
            alignment: Alignment.centerLeft,
            child: PopupMenuButton<String>(
              tooltip: "Switch company",
              position: PopupMenuPosition.under,
              color: kForestDark,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onSelected: (v) => v != _companyId ? _switchCompany(v) : null,
              itemBuilder: (_) => _companies
                  .where((c) => c["external"] != true)
                  .map((c) => PopupMenuItem(
                        value: c["_id"].toString(),
                        child: Row(children: [
                          Expanded(
                            child: Text(c["name"].toString(),
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                    color: Colors.white, fontWeight: c["_id"].toString() == _companyId ? FontWeight.w800 : FontWeight.w500)),
                          ),
                          if (c["_id"].toString() == _companyId) const Icon(Icons.check_rounded, size: 18, color: Colors.white),
                        ]),
                      ))
                  .toList(),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Flexible(
                  child: Text(
                    scope?.companyName ??
                        _companies.firstWhere((c) => c["_id"]?.toString() == _companyId, orElse: () => const {"name": "Company"})["name"].toString(),
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_drop_down_rounded, color: Colors.white, size: 26),
              ]),
            ),
          ),
          bottom: scope == null
              ? null
              : PreferredSize(
                  preferredSize: const Size.fromHeight(22),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16, bottom: 6),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      // the company creator (primary admin) is "Admin"; others show their role
                      child: Text(scope.isPrimary || idOf(scope.company["createdBy"]) == widget.userId
                          ? "You're Admin"
                          : (scope.roleName?.isNotEmpty ?? false) ? "You're ${scope.roleName}" : "You're ${scope.roleLabel(scope.isAdmin ? "admin" : "member")}",
                          style: GoogleFonts.inter(color: Colors.white70, fontSize: 12)),
                    ),
                  ),
                ),
        ),
        body: _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_error!, textAlign: TextAlign.center, style: GoogleFonts.inter(color: Colors.white)),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text("Try again"),
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white70)),
                    ),
                  ]),
                ),
              )
            : scope == null
                ? const Center(child: CircularProgressIndicator(color: Colors.white))
                : IndexedStack(
                    key: ValueKey(_companyId),
                    index: tab,
                    children: tabs.map((t) => t.build(scope)).toList(),
                  ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: tab,
          type: BottomNavigationBarType.fixed,
          backgroundColor: kForestDark,
          selectedItemColor: Colors.white,
          unselectedItemColor: Colors.white60,
          onTap: (i) => setState(() => _tab = i),
          items: tabs.map((t) => BottomNavigationBarItem(icon: Icon(t.icon), label: t.label)).toList(),
        ),
      ),
    );
  }
}
