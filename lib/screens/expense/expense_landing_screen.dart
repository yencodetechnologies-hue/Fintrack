import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/expense_company_service.dart';
import '../ledger/ledger_home_screen.dart';
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
  List<Map<String, dynamic>> _userCompanies = [];

  @override
  void initState() {
    super.initState();
    final cached = ExpenseCompanyService.getCachedCompanies(widget.userId);
    if (cached != null && cached.isNotEmpty) {
      _userCompanies = List.from(cached);
      _isLoading = false;
    }
    _loadUserCompanies(showLoading: _userCompanies.isEmpty);
    _poll = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) _loadUserCompanies();
    });
  }

  Timer? _poll;

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _loadUserCompanies({bool showLoading = false}) async {
    if (showLoading) {
      setState(() => _isLoading = true);
    }
    try {
      final companies = await ExpenseCompanyService.getUserCompanies(widget.userId);
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
      });
    } catch (_) {
    } finally {
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
          style: GoogleFonts.fraunces(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
      ),
      body: RefreshIndicator(
        color: mintAccent,
        onRefresh: _loadUserCompanies,
        child: SafeArea(
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                              height: 42,
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
                      ] else if (_userCompanies.isNotEmpty) ...[
                        // Section Header: My Companies List
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "My Companies",
                              style: GoogleFonts.fraunces(
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
                          style: GoogleFonts.fraunces(
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
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildCompanyCard(Map<String, dynamic> company) {
    final name = company["name"] ?? "Company";
    final details = company["details"] ?? "";
    final userRole = (company["userRole"] ?? "member").toString().toUpperCase();
    final isAdmin = userRole == "ADMIN";

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
                    style: GoogleFonts.fraunces(
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
