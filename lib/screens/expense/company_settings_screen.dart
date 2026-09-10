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
  static const Color creamSheet = Color(0xFF0C5F41);
  static const Color darkSurface = Color(0xFF0C3826);
  static const Color forestDark = Color(0xFF0C5F41);
  static const Color mintAccent = Color(0xFF10B981);
  static const Color darkText = Color(0xFF1E293B);

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

      // Calculate exact remaining time using local session memory or server timestamps
      if (comp != null) {
        DateTime? createdUtc = ExpenseCompanyService.getCodeTimestamp(widget.companyId);
        if (createdUtc == null) {
          final dateRaw = comp["joinCodeUpdatedAt"] ?? comp["joinCodeCreatedAt"] ?? comp["updatedAt"] ?? comp["createdAt"];
          if (dateRaw != null) {
            createdUtc = DateTime.tryParse(dateRaw.toString())?.toUtc();
          }
        }
        if (createdUtc != null) {
          final nowUtc = DateTime.now().toUtc();
          final elapsed = nowUtc.difference(createdUtc).inSeconds;
          final validElapsed = elapsed < 0 ? 0 : elapsed;
          final remaining = 300 - validElapsed;
          if (remaining > 0 && remaining <= 300) {
            _startCountdownTimer(remaining);
          } else {
            setState(() => _remainingSeconds = 0);
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
        ExpenseCompanyService.setCodeTimestamp(widget.companyId, DateTime.now().toUtc());
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
            backgroundColor: const Color(0xFFC53030),
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
            backgroundColor: const Color(0xFFC53030),
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
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("Remove Member", style: GoogleFonts.inter(color: darkText, fontWeight: FontWeight.bold, fontSize: 18)),
        content: Text("Are you sure you want to remove $memberName from the company?", style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF475569))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text("Cancel", style: GoogleFonts.inter(color: const Color(0xFF64748B), fontWeight: FontWeight.w600))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text("Remove", style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final res = await ExpenseCompanyService.removeMember(
      companyId: widget.companyId,
      memberUserId: memberUserId,
      adminUserId: widget.userId,
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
          backgroundColor: const Color(0xFFC53030),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  Future<void> _deleteCompany() async {
    final companyName = _company?["name"] ?? "this company";
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 26),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                "Delete Company Ledger",
                style: GoogleFonts.inter(color: darkText, fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ],
        ),
        content: Text(
          "Are you sure you want to permanently delete \"$companyName\"? This action will remove all expenses, settlements, and member records. THIS ACTION CANNOT BE UNDONE.",
          style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF475569)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text("Cancel", style: GoogleFonts.inter(color: const Color(0xFF64748B), fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text("Delete Ledger", style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Deleting company ledger...")),
      );
    }

    final res = await ExpenseCompanyService.deleteCompany(
      companyId: widget.companyId,
      userId: widget.userId,
    );

    if (!mounted) return;

    if (res["success"] == true) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Company ledger deleted successfully",
            style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          backgroundColor: forestDark,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      int count = 0;
      Navigator.of(context).popUntil((route) {
        return count++ == 2 || route.isFirst;
      });
    } else {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            res["message"] ?? "Failed to delete company",
            style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          backgroundColor: const Color(0xFFC53030),
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
              color: darkSurface,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: const Icon(Icons.arrow_back_rounded, color: mintAccent, size: 20),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "Company Settings",
          style: GoogleFonts.fraunces(
            color: Colors.white,
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
                        color: darkSurface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
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
                        style: GoogleFonts.fraunces(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),

                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                // Code Display Box
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: const Color(0xFFE2E8F0)),
                                    ),
                                    child: FittedBox(
                                      alignment: Alignment.centerLeft,
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        _company?["joinCode"] ?? "------",
                                        style: GoogleFonts.ibmPlexMono(
                                          color: const Color(0xFF0F261C),
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 4,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                
                                // Copy Button
                                Material(
                                  color: darkSurface,
                                  borderRadius: BorderRadius.circular(10),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(10),
                                    onTap: () {
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
                                    child: const Padding(
                                      padding: EdgeInsets.all(9),
                                      child: Icon(Icons.copy_rounded, color: mintAccent, size: 18),
                                    ),
                                  ),
                                ),

                                // Regenerate Button (Admin)
                                if (isAdmin) ...[
                                  const SizedBox(width: 6),
                                  Material(
                                    color: _remainingSeconds == 0 ? const Color(0xFFFEF2F2) : const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(10),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(10),
                                      onTap: _isRegenerating ? null : _regenerateCode,
                                      child: Padding(
                                        padding: const EdgeInsets.all(9),
                                        child: _isRegenerating
                                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: forestDark))
                                            : Icon(
                                                Icons.refresh_rounded,
                                                color: _remainingSeconds == 0 ? const Color(0xFFDC2626) : forestDark,
                                                size: 18,
                                              ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 10),

                            // Status Banner
                            GestureDetector(
                              onTap: (_remainingSeconds == 0 && isAdmin && !_isRegenerating) ? _regenerateCode : null,
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: _remainingSeconds > 0 ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: _remainingSeconds > 0
                                        ? const Color(0xFFA7F3D0).withValues(alpha: 0.6)
                                        : const Color(0xFFFCA5A5).withValues(alpha: 0.6),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _remainingSeconds > 0 ? Icons.timer_outlined : Icons.error_outline_rounded,
                                      size: 16,
                                      color: _remainingSeconds > 0 ? const Color(0xFF059669) : const Color(0xFFDC2626),
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        _remainingSeconds > 0
                                            ? "Valid for ${_formatTime(_remainingSeconds)}"
                                            : "Code Expired (00:00) • Tap to regenerate",
                                        style: GoogleFonts.inter(
                                          color: _remainingSeconds > 0 ? const Color(0xFF047857) : const Color(0xFFDC2626),
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    if (_remainingSeconds == 0 && isAdmin) ...[
                                      const SizedBox(width: 6),
                                      const Icon(Icons.arrow_forward_rounded, size: 14, color: Color(0xFFDC2626)),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Members List Section
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Members (${_members.length})",
                          style: GoogleFonts.fraunces(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
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
                                backgroundColor: isMemberAdmin ? forestDark : darkSurface.withValues(alpha: 0.1),
                                child: Text(
                                  m["name"].toString().isNotEmpty ? m["name"][0].toUpperCase() : "M",
                                  style: TextStyle(
                                    color: isMemberAdmin ? Colors.white : forestDark,
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
                                  icon: Icon(Icons.person_remove_rounded, color: Colors.red.shade400, size: 20),
                                  onPressed: () => _removeMember(memberId, m["name"].toString()),
                                ),
                            ],
                          ),
                        );
                      },
                    ),

                    if (isAdmin) ...[
                      const SizedBox(height: 32),
                      Text(
                        "Danger Zone",
                        style: GoogleFonts.fraunces(color: const Color(0xFFFCA5A5), fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFFCA5A5).withValues(alpha: 0.6)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Delete Company Ledger",
                              style: GoogleFonts.inter(color: const Color(0xFF991B1B), fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "Permanently remove this company, all recorded expenses, member records, and settlements.",
                              style: GoogleFonts.inter(color: const Color(0xFFB91C1C), fontSize: 12.5),
                            ),
                            const SizedBox(height: 14),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: _deleteCompany,
                                icon: const Icon(Icons.delete_forever_rounded, color: Colors.white, size: 18),
                                label: Text(
                                  "Delete Company Ledger",
                                  style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13.5),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFDC2626),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  elevation: 0,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}
