import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/app_config.dart';
import '../services/api_service.dart';
import '../services/card_service.dart';
import '../services/email_sync_service.dart';
import '../services/user_storage.dart';
import 'home_screen.dart';
import 'card_home.dart';
import 'view_card_screen.dart';
import 'view_reminder_page.dart';
import 'delete_card_screen.dart';
import '../widgets/qfin_nav_bar.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class ProfileScreen extends StatefulWidget {
  final String userId;
  final String userName;

  const ProfileScreen({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final int _selectedIndex = 3;
  String email = "";
  int cardCount = 0;
  int reminderCount = 0;
  bool isLoadingStats = true;
  bool isDeletingAccount = false;
  bool gmailConnected = false;
  String? gmailEmail;
  String? gmailLastSync;
  bool isGmailLoading = false;

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  Future<void> _loadGmailStatus() async {
    try {
      final status = await EmailSyncService.getStatus(widget.userId);
      if (mounted) {
        setState(() {
          gmailConnected = status['connected'] == true;
          gmailEmail = status['googleEmail']?.toString();
          gmailLastSync = status['lastSyncAt']?.toString();
        });
      }
    } catch (_) {}
  }

  Future<void> _handleGmailConnect() async {
    setState(() => isGmailLoading = true);
    try {
      final result = await EmailSyncService.connectGmail(widget.userId);
      if (!mounted) return;
      if (result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gmail connected: ${result['googleEmail'] ?? ''}'),
          ),
        );
        await _loadGmailStatus();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result['message'] ?? 'Failed to connect Gmail')),
        );
      }
    } finally {
      if (mounted) setState(() => isGmailLoading = false);
    }
  }

  Future<void> _handleGmailSync() async {
    setState(() => isGmailLoading = true);
    try {
      final result = await EmailSyncService.syncBills(widget.userId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['success'] == true
                ? 'Sync done — ${result['newBills'] ?? 0} new bill(s) found'
                : (result['message'] ?? 'Sync failed'),
          ),
        ),
      );
      await _loadGmailStatus();
    } finally {
      if (mounted) setState(() => isGmailLoading = false);
    }
  }

  Future<void> _handleGmailDisconnect() async {
    setState(() => isGmailLoading = true);
    try {
      final result = await EmailSyncService.disconnectGmail(widget.userId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['success'] == true
                ? 'Gmail disconnected'
                : (result['message'] ?? 'Disconnect failed'),
          ),
        ),
      );
      await _loadGmailStatus();
    } finally {
      if (mounted) setState(() => isGmailLoading = false);
    }
  }

  void _handleYahooConnect() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Yahoo Mail sync is coming soon.')),
    );
  }

  Future<void> _loadProfileData() async {
    final storedEmail = await UserStorage.getUserEmail();
    setState(() {
      email = storedEmail ?? "No email saved";
    });

    try {
      final cards = await CardService.getCards(widget.userId);
      final res = await http.get(Uri.parse("${AppConfig.reminders}?userId=${widget.userId}"));
      final remindersData = jsonDecode(res.body);
      final remindersList = remindersData["data"] ?? [];
      
      if (mounted) {
        setState(() {
          cardCount = cards.length;
          reminderCount = remindersList.length;
          isLoadingStats = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoadingStats = false;
        });
      }
    }
    await _loadGmailStatus();
  }

  Future<void> _handleDeleteAccount() async {
    setState(() => isDeletingAccount = true);
    try {
      final res = await ApiService.deleteAccount(widget.userId);
      if (!mounted) return;
      
      if (res["success"] == true) {
        await UserStorage.clearUserId();
        if (!mounted) return;
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppConfig.darkSlate,
            content: Text(
              "Your account and all associated data have been permanently deleted.",
              style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
            ),
          ),
        );
        
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (route) => false,
        );
      } else {
        setState(() => isDeletingAccount = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppConfig.darkSlate,
            content: Text(
              res["message"] ?? "Failed to delete account.",
              style: const TextStyle(color: Colors.white),
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => isDeletingAccount = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppConfig.darkSlate,
          content: Text("Error deleting account: $e", style: const TextStyle(color: Colors.white)),
        ),
      );
    }
  }

  void _showGmailDialog() {
    const Color creamSheet = Color(0xFFF6F4EB);
    const Color darkText = Color(0xFF132A20);
    const Color forestDark = Color(0xFF0F261C);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: creamSheet,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: darkText.withValues(alpha: 0.15)),
        ),
        title: Text(
          'Gmail Bill Sync',
          style: GoogleFonts.fraunces(color: darkText, fontWeight: FontWeight.w600),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              gmailConnected
                  ? 'Connected: ${gmailEmail ?? "Gmail"}'
                  : 'Connect Gmail to auto-fetch credit card bills (due date, amount).',
              style: GoogleFonts.inter(color: Colors.black87),
            ),
            if (gmailLastSync != null) ...[
              const SizedBox(height: 8),
              Text(
                'Last sync: $gmailLastSync',
                style: GoogleFonts.ibmPlexMono(color: Colors.black45, fontSize: 11),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Close', style: GoogleFonts.inter(color: darkText)),
          ),
          if (gmailConnected) ...[
            TextButton(
              onPressed: isGmailLoading
                  ? null
                  : () {
                      Navigator.pop(ctx);
                      _handleGmailSync();
                    },
              child: Text('Sync now', style: GoogleFonts.inter(color: forestDark, fontWeight: FontWeight.bold)),
            ),
            TextButton(
              onPressed: isGmailLoading
                  ? null
                  : () {
                      Navigator.pop(ctx);
                      _handleGmailDisconnect();
                    },
              child: Text('Disconnect', style: GoogleFonts.inter(color: const Color(0xFFB8452D), fontWeight: FontWeight.bold)),
            ),
          ] else
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: forestDark,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: isGmailLoading
                  ? null
                  : () {
                      Navigator.pop(ctx);
                      _handleGmailConnect();
                    },
              child: Text('Connect', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
    );
  }

  void _showYahooDialog() {
    const Color creamSheet = Color(0xFFF6F4EB);
    const Color darkText = Color(0xFF132A20);
    const Color forestDark = Color(0xFF0F261C);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: creamSheet,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: darkText.withValues(alpha: 0.15)),
        ),
        title: Row(
          children: [
            Image.network(
              "https://www.google.com/s2/favicons?domain=yahoo.com&sz=128",
              width: 22,
              height: 22,
              errorBuilder: (_, __, ___) => const Icon(Icons.mail_rounded, color: forestDark, size: 22),
            ),
            const SizedBox(width: 10),
            Text(
              'Yahoo Bill Sync',
              style: GoogleFonts.fraunces(color: darkText, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        content: Text(
          'Connect Yahoo Mail to auto-fetch credit card statements (due date, amount).',
          style: GoogleFonts.inter(color: Colors.black87),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Close', style: GoogleFonts.inter(color: darkText)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: forestDark,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _handleYahooConnect();
            },
            child: Text('Connect Yahoo', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showDeleteAccountDialog() {
    const Color creamSheet = Color(0xFFF6F4EB);
    const Color darkText = Color(0xFF132A20);
    const Color terracotta = Color(0xFFB8452D);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: creamSheet,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: terracotta.withValues(alpha: 0.2)),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: terracotta.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.warning_amber_rounded,
                color: terracotta,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              "Delete Account?",
              style: GoogleFonts.fraunces(
                color: darkText,
                fontWeight: FontWeight.w600,
                fontSize: 18,
              ),
            ),
          ],
        ),
        content: Text(
          "Are you sure you want to permanently delete your account? All credit cards, active reminders, lend/liability entries, and personal details will be completely purged from our servers. This action is irreversible.",
          style: GoogleFonts.inter(
            color: Colors.black87,
            fontSize: 14,
            height: 1.4,
          ),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              "Cancel",
              style: GoogleFonts.inter(
                color: darkText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: terracotta,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            onPressed: () {
              Navigator.pop(context);
              _handleDeleteAccount();
            },
            child: Text(
              "Delete Permanently",
              style: GoogleFonts.inter(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showLogoutDialog() {
    const Color creamSheet = Color(0xFFF6F4EB);
    const Color darkText = Color(0xFF132A20);
    const Color terracotta = Color(0xFFB8452D);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: creamSheet,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        title: Text(
          "Logout",
          style: GoogleFonts.fraunces(
            color: darkText,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          "Are you sure you want to logout?",
          style: GoogleFonts.inter(color: Colors.black87),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              "Cancel",
              style: GoogleFonts.inter(color: darkText),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: terracotta,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () async {
              Navigator.pop(context);
              await UserStorage.clearUserId();
              if (!context.mounted) return;
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const HomeScreen()),
                (route) => false,
              );
            },
            child: Text(
              "Logout",
              style: GoogleFonts.inter(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const Color forestDark = Color(0xFF0F261C);
    const Color creamBg    = Color(0xFFF6F4EB);
    const Color darkText   = Color(0xFF132A20);
    const Color goldAccent = Color(0xFFD4AF37);
    const Color terracotta = Color(0xFFB8452D);

    final String initial = widget.userName.isNotEmpty ? widget.userName[0].toUpperCase() : "U";

    return Scaffold(
      backgroundColor: creamBg,
      body: SafeArea(
        child: Column(
          children: [
            // Top Executive Header Bar (Clean Inline Row)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
              child: Row(
                children: [
                  if (Navigator.canPop(context)) ...[
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: forestDark.withValues(alpha: 0.08),
                          shape: BoxShape.circle,
                          border: Border.all(color: forestDark.withValues(alpha: 0.15)),
                        ),
                        child: const Icon(Icons.arrow_back_rounded, color: forestDark, size: 20),
                      ),
                      onPressed: () => Navigator.maybePop(context),
                    ),
                    const SizedBox(width: 10),
                  ],

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "EXECUTIVE PROFILE",
                          style: GoogleFonts.ibmPlexMono(
                            color: forestDark,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.8,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          "Account Passport",
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.fraunces(
                            color: darkText,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: terracotta.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                        border: Border.all(color: terracotta.withValues(alpha: 0.2)),
                      ),
                      child: const Icon(Icons.logout_rounded, color: terracotta, size: 18),
                    ),
                    onPressed: _showLogoutDialog,
                  ),
                ],
              ),
            ),
            const Divider(color: Color(0xFFE2DDD0), height: 1),

            // Scrollable Passport Content
            Expanded(
              child: isDeletingAccount
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(color: forestDark),
                          SizedBox(height: 20),
                          Text(
                            "Purging account data...",
                            style: TextStyle(
                              color: darkText,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    )
                  : SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          // ── EXECUTIVE PASSPORT IDENTITY CARD ────────────────
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(22),
                            decoration: BoxDecoration(
                              color: forestDark,
                              borderRadius: BorderRadius.circular(26),
                              boxShadow: [
                                BoxShadow(
                                  color: forestDark.withValues(alpha: 0.25),
                                  blurRadius: 18,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Stack(
                              children: [
                                Positioned(
                                  top: -30,
                                  right: -30,
                                  child: Container(
                                    width: 130,
                                    height: 130,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: goldAccent.withValues(alpha: 0.06),
                                    ),
                                  ),
                                ),
                                Column(
                                  children: [
                                    Row(
                                      children: [
                                        // Monogram Ring
                                        Container(
                                          width: 60,
                                          height: 60,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: darkText,
                                            border: Border.all(color: goldAccent, width: 2),
                                          ),
                                          child: Center(
                                            child: Text(
                                              initial,
                                              style: GoogleFonts.fraunces(
                                                color: goldAccent,
                                                fontSize: 26,
                                                fontWeight: FontWeight.bold,
                                                fontStyle: FontStyle.italic,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: goldAccent.withValues(alpha: 0.15),
                                                  borderRadius: BorderRadius.circular(20),
                                                  border: Border.all(color: goldAccent.withValues(alpha: 0.4)),
                                                ),
                                                child: Text(
                                                  "VERIFIED ACCOUNT",
                                                  style: GoogleFonts.ibmPlexMono(
                                                    color: goldAccent,
                                                    fontSize: 9,
                                                    fontWeight: FontWeight.bold,
                                                    letterSpacing: 1.2,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                widget.userName,
                                                style: GoogleFonts.fraunces(
                                                  color: Colors.white,
                                                  fontSize: 22,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                email,
                                                style: GoogleFonts.inter(
                                                  color: Colors.white.withValues(alpha: 0.65),
                                                  fontSize: 12,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 20),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.06),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                                        children: [
                                          _buildPassportMetric("CREDIT CARDS", isLoadingStats ? "..." : "$cardCount", goldAccent),
                                          Container(width: 1, height: 28, color: Colors.white.withValues(alpha: 0.15)),
                                          _buildPassportMetric("BILL ALERTS", isLoadingStats ? "..." : "$reminderCount", const Color(0xFF00E5A0)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 24),

                          // ── SETTINGS & CONTROLS GRID ───────────────────────
                          Row(
                            children: [
                              Text(
                                "Settings & Preferences",
                                style: GoogleFonts.fraunces(
                                  color: darkText,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(color: Colors.black.withValues(alpha: 0.08), width: 1.2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.02),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                _buildMenuItem(
                                  icon: Icons.credit_card_rounded,
                                  title: "Manage Credit Cards",
                                  color: forestDark,
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ViewCardScreen(
                                          userId: widget.userId,
                                          userName: widget.userName,
                                        ),
                                      ),
                                    ).then((_) => _loadProfileData());
                                  },
                                ),
                                _buildDivider(),
                                _buildMenuItem(
                                  icon: Icons.delete_sweep_rounded,
                                  title: "Delete Card Screen",
                                  color: terracotta,
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => DeleteCardScreen(
                                          userId: widget.userId,
                                        ),
                                      ),
                                    ).then((_) => _loadProfileData());
                                  },
                                ),
                                _buildDivider(),
                                _buildMenuItem(
                                  customLeading: Image.network(
                                    "https://cdn-icons-png.flaticon.com/512/5968/5968534.png",
                                    width: 20,
                                    height: 20,
                                    errorBuilder: (_, __, ___) => const Icon(Icons.mail_rounded, color: forestDark, size: 20),
                                  ),
                                  title: gmailConnected ? "Gmail Connected" : "Connect Gmail",
                                  color: forestDark,
                                  onTap: _showGmailDialog,
                                ),

                                _buildDivider(),
                                _buildMenuItem(
                                  icon: Icons.notifications_active_rounded,
                                  title: "Payment Reminders",
                                  color: forestDark,
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ViewReminderPage(
                                          userId: widget.userId,
                                          userName: widget.userName,
                                        ),
                                      ),
                                    ).then((_) => _loadProfileData());
                                  },
                                ),
                                _buildDivider(),
                                _buildMenuItem(
                                  icon: Icons.logout_rounded,
                                  title: "Logout Session",
                                  color: forestDark,
                                  onTap: _showLogoutDialog,
                                ),
                                _buildDivider(),
                                _buildMenuItem(
                                  icon: Icons.person_remove_rounded,
                                  title: "Delete Account",
                                  color: terracotta,
                                  onTap: _showDeleteAccountDialog,
                                  isLast: true,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPassportMetric(String label, String val, Color highlightColor) {
    return Column(
      children: [
        Text(
          val,
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.ibmPlexMono(
            color: highlightColor,
            fontSize: 9,
            fontWeight: FontWeight.w600,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }



  Widget _buildMenuItem({
    IconData? icon,
    Widget? customLeading,
    required String title,
    required Color color,
    required VoidCallback onTap,
    bool isLast = false,
  }) {
    const Color darkText = Color(0xFF132A20);
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: customLeading ?? Icon(
          icon ?? Icons.circle,
          color: color,
          size: 20,
        ),
      ),
      title: Text(
        title,
        style: GoogleFonts.inter(
          color: isLast ? const Color(0xFFB8452D) : darkText,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: isLast ? const Color(0xFFB8452D) : Colors.black38,
        size: 20,
      ),
    );
  }

  Widget _buildDivider() {
    return Divider(
      height: 1,
      color: Colors.black.withValues(alpha: 0.06),
      indent: 60,
      endIndent: 20,
    );
  }
}
