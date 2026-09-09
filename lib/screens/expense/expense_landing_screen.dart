import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/expense_company_service.dart';
import 'company_dashboard_screen.dart';
import 'create_company_screen.dart';
import 'join_company_screen.dart';

class ExpenseLandingScreen extends StatefulWidget {
  final String userId;
  final String userName;

  const ExpenseLandingScreen({
    Key? key,
    required this.userId,
    required this.userName,
  }) : super(key: key);

  @override
  State<ExpenseLandingScreen> createState() => _ExpenseLandingScreenState();
}

class _ExpenseLandingScreenState extends State<ExpenseLandingScreen> {
  static const Color creamSheet = Color(0xFFFBF9F1);
  static const Color forestDark = Color(0xFF0F261C);
  static const Color darkText = Color(0xFF1E293B);
  static const Color terracotta = Color(0xFFB8452D);

  bool _isLoading = true;
  List<Map<String, dynamic>> _userCompanies = [];

  @override
  void initState() {
    super.initState();
    _loadUserCompanies();
  }

  Future<void> _loadUserCompanies() async {
    setState(() => _isLoading = true);
    try {
      final companies = await ExpenseCompanyService.getUserCompanies(widget.userId);
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
        builder: (_) => CompanyDashboardScreen(
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
      backgroundColor: creamSheet,
      appBar: AppBar(
        backgroundColor: creamSheet,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: forestDark.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.arrow_back_rounded, color: forestDark, size: 20),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "Expense Tracker",
          style: GoogleFonts.fraunces(
            color: forestDark,
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
        actions: [
          // Top Right 3-Dot Popup Menu
          PopupMenuButton<String>(
            color: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: forestDark.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.more_vert_rounded, color: forestDark, size: 20),
            ),
            onSelected: (val) {
              if (val == "create") {
                _openCreateCompany();
              } else if (val == "join") {
                _openJoinCompany();
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: "create",
                child: Row(
                  children: [
                    const Icon(Icons.add_business_rounded, color: forestDark, size: 20),
                    const SizedBox(width: 12),
                    Text(
                      "Create Company",
                      style: GoogleFonts.inter(color: darkText, fontWeight: FontWeight.bold, fontSize: 13.5),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: "join",
                child: Row(
                  children: [
                    const Icon(Icons.group_add_rounded, color: terracotta, size: 20),
                    const SizedBox(width: 12),
                    Text(
                      "Join Company",
                      style: GoogleFonts.inter(color: darkText, fontWeight: FontWeight.bold, fontSize: 13.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: forestDark))
          : RefreshIndicator(
              color: forestDark,
              onRefresh: _loadUserCompanies,
              child: SafeArea(
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Banner Card
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: forestDark,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: forestDark.withValues(alpha: 0.25),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.business_center_rounded, color: Colors.white, size: 30),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Company Expense Ledger",
                                    style: GoogleFonts.fraunces(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    "Track company reimbursements, balances & settlements smoothly.",
                                    style: GoogleFonts.inter(
                                      color: Colors.white.withValues(alpha: 0.8),
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),

                      if (_userCompanies.isNotEmpty) ...[
                        // Section Header: My Companies List
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "My Companies",
                              style: GoogleFonts.fraunces(
                                color: darkText,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              "${_userCompanies.length} Organizations",
                              style: GoogleFonts.ibmPlexMono(
                                color: darkText.withValues(alpha: 0.5),
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          "Tap any company to view its expense ledger & balance summary.",
                          style: GoogleFonts.inter(
                            color: darkText.withValues(alpha: 0.6),
                            fontSize: 13,
                          ),
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
                            color: darkText,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          "Create a new company ledger or join an existing company using a 6-digit code.",
                          style: GoogleFonts.inter(
                            color: darkText.withValues(alpha: 0.6),
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
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.black.withValues(alpha: 0.08), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: forestDark,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : "C",
                    style: GoogleFonts.fraunces(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
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
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isAdmin ? forestDark.withValues(alpha: 0.1) : terracotta.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            userRole,
                            style: GoogleFonts.inter(
                              color: isAdmin ? forestDark : terracotta,
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (details.toString().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        details.toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          color: darkText.withValues(alpha: 0.6),
                          fontSize: 12.5,
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
