import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/expense_company_service.dart';
import '../../services/ledger_service.dart';
import '../ledger/ledger_home_screen.dart';
import 'create_expense_group_screen.dart';
import 'group_expenses_screen.dart';
import 'create_company_screen.dart';
import 'join_company_screen.dart';

class ExpenseLandingScreen extends StatefulWidget {
  final String userId;
  final String userName;

  const ExpenseLandingScreen({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<ExpenseLandingScreen> createState() => _ExpenseLandingScreenState();
}

class _ExpenseLandingScreenState extends State<ExpenseLandingScreen> {
  static const Color bgGreen = Color(0xFF0C5F41);
  static const Color darkSurface = Color(0xFF0C3826);
  static const Color forestDark = Color(0xFF0C5F41);
  static const Color mintAccent = Color(0xFF10B981);
  static const Color darkText = Color(0xFF1E293B);
  static const Color terracotta = Color(0xFFB8452D);

  bool _isLoading = true;
  bool _showGroups = false;
  bool _refreshInProgress = false;
  List<Map<String, dynamic>> _userCompanies = [];
  List<Map<String, dynamic>> _userGroups = [];
  bool _loadingGroups = false;
  String? _companiesError;
  String? _groupsError;

  @override
  void initState() {
    super.initState();
    final cached = ExpenseCompanyService.getCachedCompanies(widget.userId);
    if (cached != null && cached.isNotEmpty) {
      _userCompanies = List.from(cached);
      _isLoading = false;
    }
    _loadUserCompanies(showLoading: _userCompanies.isEmpty);
  }

  Future<void> _loadUserCompanies({bool showLoading = false}) async {
    if (_refreshInProgress) return;
    _refreshInProgress = true;
    if (showLoading) {
      setState(() => _isLoading = true);
    }
    try {
      final res = await LedgerService.userCompanies(widget.userId);
      if (res["success"] != true || res["companies"] is! List) {
        if (mounted && _userCompanies.isEmpty) {
          setState(() => _companiesError = res["message"]?.toString() ?? "Could not load your companies. Check your connection.");
        }
        return;
      }
      final companies = List<Map<String, dynamic>>.from(res["companies"]).where((c) => c["external"] != true).toList();
      companies.sort((a, b) {
        final aDateRaw = a["createdAt"] ?? a["updatedAt"];
        final bDateRaw = b["createdAt"] ?? b["updatedAt"];
        final aDate = aDateRaw != null ? DateTime.tryParse(aDateRaw.toString()) ?? DateTime(1970) : DateTime(1970);
        final bDate = bDateRaw != null ? DateTime.tryParse(bDateRaw.toString()) ?? DateTime(1970) : DateTime(1970);
        return bDate.compareTo(aDate);
      });
      if (!mounted) return;
      setState(() {
        _userCompanies = companies;
        _companiesError = null;
      });
    } catch (_) {
    } finally {
      _refreshInProgress = false;
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _openCreateCompany() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreateCompanyScreen(
          userId: widget.userId,
          userName: widget.userName,
        ),
      ),
    ).then((_) => _loadUserCompanies());
  }

  void _openJoinCompany() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => JoinCompanyScreen(
          userId: widget.userId,
          userName: widget.userName,
        ),
      ),
    ).then((_) => _loadUserCompanies());
  }

  void _openCompanyDashboard(Map<String, dynamic> company) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LedgerHomeScreen(
          userId: widget.userId,
          userName: widget.userName,
          companies: _userCompanies,
          initialCompanyId: company["_id"].toString(),
        ),
      ),
    ).then((_) => _loadUserCompanies());
  }

  Future<void> _openCreateGroup() async {
    final group = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => CreateExpenseGroupScreen(
          userId: widget.userId,
        ),
      ),
    );
    if (!mounted || group == null) return;
    await _loadUserGroups();
    if (!mounted) return;
    final name = (group["name"] ?? "Group").toString();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("$name created")),
    );
  }

  Future<void> _openGroup(Map<String, dynamic> group) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => GroupExpensesScreen(
          group: group,
          userId: widget.userId,
          userName: widget.userName,
        ),
      ),
    );
    if (mounted) _loadUserGroups();
  }

  Future<void> _loadUserGroups() async {
    if (_loadingGroups) return;
    setState(() {
      _loadingGroups = true;
      _groupsError = null;
    });
    final response = await ExpenseCompanyService.getUserExpenseGroups(widget.userId);
    if (!mounted) return;
    setState(() {
      _loadingGroups = false;
      if (response["success"] == true && response["groups"] is List) {
        _userGroups = List<Map<String, dynamic>>.from(response["groups"]);
      } else {
        _groupsError = (response["message"] ?? "Could not load groups").toString();
      }
    });
  }

  void _selectPage(bool groups) {
    if (_showGroups == groups) return;
    setState(() => _showGroups = groups);
    if (groups) _loadUserGroups();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgGreen,
      appBar: AppBar(
        backgroundColor: bgGreen,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: darkSurface,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: const Icon(Icons.arrow_back_rounded, color: mintAccent, size: 20),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "Expense Tracker",
          style: GoogleFonts.inter(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
      ),
      body: RefreshIndicator(
        color: mintAccent,
        onRefresh: () => _showGroups ? _loadUserGroups() : _loadUserCompanies(),
        child: SafeArea(
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPageToggle(),
                const SizedBox(height: 20),
                if (_showGroups) ...[
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _userCompanies.isEmpty ? null : _openCreateGroup,
                      style: FilledButton.styleFrom(
                        backgroundColor: darkSurface,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: darkSurface.withValues(alpha: 0.55),
                      ),
                      icon: const Icon(Icons.group_add_rounded, color: mintAccent),
                      label: Text("Create Group", style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  if (_userCompanies.isEmpty && !_isLoading) ...[
                    const SizedBox(height: 12),
                    Text(
                      "Join or create a company before creating a group.",
                      style: GoogleFonts.inter(color: Colors.white.withValues(alpha: 0.75)),
                    ),
                  ],
                  const SizedBox(height: 18),
                  if (_loadingGroups)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator(color: mintAccent),
                      ),
                    )
                  else if (_groupsError != null)
                    Center(
                      child: TextButton.icon(
                        onPressed: _loadUserGroups,
                        icon: const Icon(Icons.refresh, color: mintAccent),
                        label: Text("Retry loading groups", style: GoogleFonts.inter(color: Colors.white70)),
                      ),
                    )
                  else if (_userGroups.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          "No groups yet",
                          style: GoogleFonts.inter(color: Colors.white.withValues(alpha: 0.72)),
                        ),
                      ),
                    )
                  else
                    ..._userGroups.map(_buildGroupCard),
                ],
                if (!_showGroups) ...[
                // Premium Action Buttons Row (Create & Join - Shown only when companies exist)
                if (_userCompanies.isNotEmpty) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: _openCreateCompany,
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              height: 46,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              decoration: BoxDecoration(
                                color: darkSurface,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 1.2),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.1),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.add_business_rounded, size: 18, color: Colors.white),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        "Create Company",
                                        style: GoogleFonts.inter(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: _openJoinCompany,
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              height: 46,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 1.2),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.1),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.group_add_rounded, size: 18, color: terracotta),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        "Join Company",
                                        style: GoogleFonts.inter(
                                          color: terracotta,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],

                      if (_isLoading) ...[
                        const _CompanyListShimmer(),
                      ] else if (_companiesError != null && _userCompanies.isEmpty) ...[
                        Center(
                          child: Column(children: [
                            Text(_companiesError!, textAlign: TextAlign.center, style: GoogleFonts.inter(color: Colors.white)),
                            TextButton.icon(
                              onPressed: () => _loadUserCompanies(showLoading: true),
                              icon: const Icon(Icons.refresh, color: mintAccent),
                              label: Text("Retry", style: GoogleFonts.inter(color: Colors.white70)),
                            ),
                          ]),
                        ),
                      ] else if (_userCompanies.isNotEmpty) ...[
                        // Section Header: My Companies List
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "My Companies",
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              "${_userCompanies.length} Organizations",
                              style: GoogleFonts.ibmPlexMono(
                                color: Colors.white.withValues(alpha: 0.7),
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Companies List
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _userCompanies.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 14),
                          itemBuilder: (context, index) {
                            final company = _userCompanies[index];
                            return _buildCompanyCard(company);
                          },
                        ),
                      ] else ...[
                        // Empty State if User Has No Companies Yet
                        Text(
                          "Get Started",
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          "Create a new company ledger or join an existing company using a 6-digit code.",
                          style: GoogleFonts.inter(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 13.5,
                          ),
                        ),
                        const SizedBox(height: 24),

                        _buildOptionCard(
                          title: "Create Company",
                          subtitle: "Set up a new organization ledger & invite team members via 6-digit join code.",
                          icon: Icons.add_business_rounded,
                          accentColor: forestDark,
                          onTap: _openCreateCompany,
                        ),
                        const SizedBox(height: 16),

                        _buildOptionCard(
                          title: "Join Company",
                          subtitle: "Enter a 6-digit company join code provided by your company admin.",
                          icon: Icons.group_add_rounded,
                          accentColor: terracotta,
                          onTap: _openJoinCompany,
                        ),
                      ],
                ],
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildPageToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          _buildToggleOption("Company", false),
          _buildToggleOption("Group", true),
        ],
      ),
    );
  }

  Widget _buildToggleOption(String label, bool groups) {
    final selected = _showGroups == groups;
    return Expanded(
      child: GestureDetector(
        onTap: () => _selectPage(groups),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: selected ? forestDark : Colors.white.withValues(alpha: 0.75),
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGroupCard(Map<String, dynamic> group) {
    final company = group["companyId"] is Map ? group["companyId"]["name"] : null;
    final creator = group["createdBy"] is Map ? group["createdBy"]["name"] : null;
    final memberCount = group["members"] is List ? (group["members"] as List).length : 0;
    final settled = group["settlementStatus"] == "settled";
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () => _openGroup(group),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(color: forestDark, borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.groups_rounded, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(child: Text((group["name"] ?? "Group").toString(), style: GoogleFonts.inter(color: darkText, fontWeight: FontWeight.bold))),
                        if (settled) const Icon(Icons.check_circle_rounded, color: mintAccent, size: 18),
                      ]),
                      const SizedBox(height: 4),
                      Text(
                        "${company ?? "Company"} · ${memberCount == 1 ? "1 member" : "$memberCount members"}${creator == null ? "" : " · Admin: $creator"}",
                        style: GoogleFonts.inter(color: const Color(0xFF64748B), fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompanyCard(Map<String, dynamic> company) {
    final name = company["name"] ?? "Company";
    final details = company["details"] ?? "";
    final isAdmin = (company["userRole"] ?? "member").toString() == "admin";
    final userRole = isAdmin ? "MANAGER" : "STAFF";

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _openCompanyDashboard(company),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black.withValues(alpha: 0.08), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: forestDark,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : "C",
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              color: darkText,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: isAdmin ? forestDark.withValues(alpha: 0.1) : terracotta.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            userRole,
                            style: GoogleFonts.inter(
                              color: isAdmin ? forestDark : terracotta,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (details.toString().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        details.toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          color: darkText.withValues(alpha: 0.5),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: darkText.withValues(alpha: 0.4), size: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOptionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: accentColor.withValues(alpha: 0.2), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: accentColor, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        color: darkText,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        color: darkText.withValues(alpha: 0.6),
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: darkText.withValues(alpha: 0.4), size: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompanyListShimmer extends StatefulWidget {
  const _CompanyListShimmer();

  @override
  State<_CompanyListShimmer> createState() => _CompanyListShimmerState();
}

class _CompanyListShimmerState extends State<_CompanyListShimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.3, end: 0.8).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Opacity(
          opacity: _animation.value,
          child: Column(
            children: List.generate(2, (index) {
              return Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 120,
                            height: 16,
                            decoration: BoxDecoration(
                              color: Colors.grey[300],
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            width: 80,
                            height: 12,
                            decoration: BoxDecoration(
                              color: Colors.grey[300],
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        );
      },
    );
  }
}





