import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/expense_company_service.dart';

class CompanySettingsScreen extends StatefulWidget {
  final String companyId;
  final String userId;
  final String userName;

  const CompanySettingsScreen({
    Key? key,
    required this.companyId,
    required this.userId,
    required this.userName,
  }) : super(key: key);

  @override
  State<CompanySettingsScreen> createState() => _CompanySettingsScreenState();
}

class _CompanySettingsScreenState extends State<CompanySettingsScreen> {
  static const Color creamSheet = Color(0xFFFBF9F1);
  static const Color forestDark = Color(0xFF0F261C);
  static const Color darkText = Color(0xFF1E293B);
  static const Color terracotta = Color(0xFFB8452D);

  bool _isLoading = true;
  Map<String, dynamic>? _company;
  List<Map<String, dynamic>> _members = [];
  String _currentUserRole = "member";
  bool _isRegenerating = false;

  Timer? _countdownTimer;
  int _remainingSeconds = 0;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startCountdownTimer([int seconds = 300]) {
    _countdownTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _remainingSeconds = seconds;
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_remainingSeconds > 0) {
        setState(() {
          _remainingSeconds--;
        });
      } else {
        timer.cancel();
      }
    });
  }

  String _formatTime(int totalSeconds) {
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    final res = await ExpenseCompanyService.getCompanyDetails(widget.companyId, widget.userId);
    if (!mounted) return;

    if (res["success"] == true) {
      final comp = res["company"];
      final loadedMembers = List<Map<String, dynamic>>.from(res["members"] ?? []);
      loadedMembers.sort((a, b) {
        final aIsAdmin = a["role"] == "admin";
        final bIsAdmin = b["role"] == "admin";
        if (aIsAdmin && !bIsAdmin) return -1;
        if (!aIsAdmin && bIsAdmin) return 1;
        final aName = (a["name"] ?? "").toString().trim().toLowerCase();
        final bName = (b["name"] ?? "").toString().trim().toLowerCase();
        return aName.compareTo(bName);
      });

      setState(() {
        _company = comp;
        _members = loadedMembers;
        _currentUserRole = res["currentUserRole"] ?? "member";
        _isLoading = false;
      });

      // Calculate exact remaining time using UTC timestamps
      if (comp != null) {
        final dateRaw = comp["joinCodeCreatedAt"] ?? comp["createdAt"];
        if (dateRaw != null) {
          final createdUtc = DateTime.tryParse(dateRaw.toString())?.toUtc();
          if (createdUtc != null) {
            final nowUtc = DateTime.now().toUtc();
            final elapsed = nowUtc.difference(createdUtc).inSeconds;
            final remaining = 300 - elapsed;
            if (remaining > 0) {
              _startCountdownTimer(remaining);
            } else {
              setState(() => _remainingSeconds = 0);
            }
          }
        }
      }
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _regenerateCode() async {
    if (_isRegenerating) return;
    setState(() => _isRegenerating = true);
    try {
      final res = await ExpenseCompanyService.regenerateJoinCode(
        companyId: widget.companyId,
        userId: widget.userId,
      );
      if (!mounted) return;

      if (res["success"] == true) {
        setState(() {
          if (_company != null) {
            _company!["joinCode"] = res["joinCode"];
            if (res["joinCodeCreatedAt"] != null) {
              _company!["joinCodeCreatedAt"] = res["joinCodeCreatedAt"];
            }
          }
        });
        _startCountdownTimer(300);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "New join code generated! 5-minute timer started.",
              style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            backgroundColor: forestDark,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              res["message"] ?? "Failed to regenerate code",
              style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            backgroundColor: terracotta,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error: $e", style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
            backgroundColor: terracotta,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isRegenerating = false);
      }
    }
  }

  Future<void> _removeMember(String memberUserId, String memberName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Remove Member", style: GoogleFonts.fraunces(fontWeight: FontWeight.bold)),
        content: Text("Are you sure you want to remove $memberName from the company?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Remove", style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm != true) return;

    final res = await ExpenseCompanyService.removeMember(
      companyId: widget.companyId,
      memberUserId: memberUserId,
      userId: widget.userId,
    );

    if (!mounted) return;

    if (res["success"] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("$memberName removed successfully", style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
          backgroundColor: forestDark,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      _loadSettings();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res["message"] ?? "Failed to remove member", style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
          backgroundColor: terracotta,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = _currentUserRole == "admin";

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
          "Company Settings",
          style: GoogleFonts.fraunces(
            color: forestDark,
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: forestDark))
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Company Info Card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: forestDark,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  _company?["name"] ?? "Company",
                                  style: GoogleFonts.fraunces(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  isAdmin ? "ADMIN" : "MEMBER",
                                  style: GoogleFonts.inter(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (_company?["details"] != null && _company!["details"].toString().isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              _company!["details"].toString(),
                              style: GoogleFonts.inter(
                                color: Colors.white.withValues(alpha: 0.8),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Join Code Section (Admin only)
                    if (isAdmin) ...[
                      Text(
                        "Company Join Code",
                        style: GoogleFonts.fraunces(color: darkText, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Share this 6-digit code with team members to join. (Valid for 5 minutes)",
                        style: GoogleFonts.inter(color: darkText.withValues(alpha: 0.6), fontSize: 12.5),
                      ),
                      const SizedBox(height: 12),

                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _remainingSeconds > 0 ? forestDark.withValues(alpha: 0.2) : terracotta.withValues(alpha: 0.4),
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                 Expanded(
                                   child: FittedBox(
                                     alignment: Alignment.centerLeft,
                                     fit: BoxFit.scaleDown,
                                     child: Text(
                                       _company?["joinCode"] ?? "------",
                                       style: GoogleFonts.ibmPlexMono(
                                         color: _remainingSeconds > 0 ? forestDark : terracotta,
                                         fontSize: 26,
                                         fontWeight: FontWeight.bold,
                                         letterSpacing: 4,
                                       ),
                                     ),
                                   ),
                                 ),
                                Row(
                                  children: [
                                    IconButton(
                                      tooltip: "Copy Code",
                                      icon: const Icon(Icons.copy_rounded, color: forestDark),
                                      onPressed: () {
                                        Clipboard.setData(ClipboardData(text: _company?["joinCode"] ?? ""));
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              "Join code copied to clipboard!",
                                              style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold),
                                            ),
                                            backgroundColor: forestDark,
                                            behavior: SnackBarBehavior.floating,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                          ),
                                        );
                                      },
                                    ),
                                    if (isAdmin)
                                      IconButton(
                                        tooltip: "Regenerate Code",
                                        icon: _isRegenerating
                                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: forestDark))
                                            : const Icon(Icons.refresh_rounded, color: terracotta),
                                        onPressed: _isRegenerating ? null : _regenerateCode,
                                      ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Divider(color: Colors.black.withValues(alpha: 0.08)),
                            const SizedBox(height: 6),
                            GestureDetector(
                              onTap: (_remainingSeconds == 0 && isAdmin && !_isRegenerating) ? _regenerateCode : null,
                              child: Row(
                                children: [
                                  Icon(
                                    _remainingSeconds > 0 ? Icons.timer_outlined : Icons.timer_off_rounded,
                                    size: 16,
                                    color: _remainingSeconds > 0 ? forestDark : terracotta,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      _remainingSeconds > 0
                                          ? "Timer: ${_formatTime(_remainingSeconds)} remaining"
                                          : "Code Expired (00:00) — Tap here to regenerate",
                                      style: GoogleFonts.ibmPlexMono(
                                        color: _remainingSeconds > 0 ? forestDark : terracotta,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.bold,
                                        decoration: (_remainingSeconds == 0 && isAdmin) ? TextDecoration.underline : TextDecoration.none,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                    ],

                    // Members List Section
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Members (${_members.length})",
                          style: GoogleFonts.fraunces(color: darkText, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _members.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final m = _members[index];
                        final memberId = m["userId"] != null ? m["userId"].toString() : "";
                        final isSelf = memberId == widget.userId;
                        final isMemberAdmin = m["role"] == "admin";

                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: isMemberAdmin ? forestDark : terracotta.withValues(alpha: 0.15),
                                child: Text(
                                  m["name"].toString().isNotEmpty ? m["name"][0].toUpperCase() : "M",
                                  style: TextStyle(
                                    color: isMemberAdmin ? Colors.white : terracotta,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      isSelf ? "${m['name']} (You)" : m["name"].toString(),
                                      style: GoogleFonts.inter(color: darkText, fontWeight: FontWeight.bold, fontSize: 14.5),
                                    ),
                                    if (m["email"] != null && m["email"].toString().isNotEmpty)
                                      Text(
                                        m["email"].toString(),
                                        style: GoogleFonts.inter(color: darkText.withValues(alpha: 0.5), fontSize: 12),
                                      ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: isMemberAdmin ? forestDark.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  m["role"].toString().toUpperCase(),
                                  style: GoogleFonts.inter(
                                    color: isMemberAdmin ? forestDark : darkText.withValues(alpha: 0.7),
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              if (isAdmin && !isMemberAdmin && memberId != widget.userId)
                                IconButton(
                                  icon: const Icon(Icons.person_remove_rounded, color: Colors.red, size: 20),
                                  onPressed: () => _removeMember(memberId, m["name"].toString()),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
