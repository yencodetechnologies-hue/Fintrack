import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io' show Platform;
import '../config/app_config.dart';
import '../services/api_service.dart';
import '../services/card_service.dart';
import '../services/email_sync_service.dart';
import '../services/user_storage.dart';
import 'home_screen.dart';
import 'view_card_screen.dart';
import 'view_reminder_page.dart';
import 'delete_card_screen.dart';
import 'card_create_screen.dart';
import 'add_reminder_page.dart';
import 'LendLiabilityPage.dart';
import 'expense/expense_landing_screen.dart';
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

class _ProfileScreenState extends State<ProfileScreen> with WidgetsBindingObserver {
  String email = "";
  int cardCount = 0;
  int reminderCount = 0;
  bool isLoadingStats = true;
  bool isDeletingAccount = false;

  bool gmailConnected = false;
  String? gmailEmail;
  String? gmailLastSync;
  bool isGmailLoading = false;

  bool yahooConnected = false;
  String? yahooEmail;
  String? yahooLastSync;
  bool isYahooLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadProfileData();
    _loadGmailStatus();
    _loadYahooStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          _loadGmailStatus();
          _loadYahooStatus();
        }
      });
    }
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) {
      return "Good morning,";
    } else if (hour < 17) {
      return "Good afternoon,";
    } else {
      return "Good evening,";
    }
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
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => isGmailLoading = false);
    }
  }

  Future<void> _loadYahooStatus() async {
    try {
      final status = await EmailSyncService.getYahooStatus(widget.userId);
      if (mounted) {
        setState(() {
          yahooConnected = status['connected'] == true;
          yahooEmail = status['yahooEmail']?.toString();
          yahooLastSync = status['lastSyncAt']?.toString();
        });
      }
    } catch (_) {}
  }

  Future<void> _handleYahooConnect() async {
    setState(() => isYahooLoading = true);
    try {
      final authUrl = await EmailSyncService.getYahooConnectUrl(widget.userId);
      if (!mounted) return;
      if (authUrl != null && authUrl.isNotEmpty) {
        final uri = Uri.parse(authUrl);
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Yahoo service unavailable.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error connecting Yahoo: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => isYahooLoading = false);
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

  Future<void> _handleYahooSync() async {
    setState(() => isYahooLoading = true);
    try {
      final res = await EmailSyncService.syncBills(widget.userId);
      if (!mounted) return;
      if (res['success'] == true) {
        final parsed = res['parsedCount'] ?? 0;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Synced! Parsed $parsed statements.')),
        );
        await _loadYahooStatus();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res['message'] ?? 'Failed to sync Yahoo emails')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error syncing Yahoo: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => isYahooLoading = false);
    }
  }

  Future<void> _handleYahooDisconnect() async {
    setState(() => isYahooLoading = true);
    try {
      final res = await EmailSyncService.disconnectYahoo(widget.userId);
      if (!mounted) return;
      if (res['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Yahoo disconnected successfully')),
        );
        await _loadYahooStatus();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res['message'] ?? 'Failed to disconnect Yahoo')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error disconnecting Yahoo: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => isYahooLoading = false);
    }
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
    await _loadYahooStatus();
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
    const Color darkText = Color(0xFF1E293B);
    const Color forestDark = Color(0xFF195754);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        title: Text(
          'Gmail Bill Sync',
          style: GoogleFonts.inter(color: darkText, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              gmailConnected
                  ? 'Connected: ${gmailEmail ?? "Gmail"}'
                  : 'Connect Gmail to auto-fetch credit card bills (due date, amount).',
              style: GoogleFonts.inter(color: darkText),
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
                elevation: 0,
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
    const Color darkText = Color(0xFF1E293B);
    const Color forestDark = Color(0xFF195754);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
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
              style: GoogleFonts.inter(color: darkText, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              yahooConnected
                  ? 'Connected as: ${yahooEmail ?? "Yahoo User"}'
                  : 'Connect Yahoo Mail to auto-fetch credit card statements (due date, amount).',
              style: GoogleFonts.inter(color: darkText),
            ),
            if (yahooLastSync != null) ...[
              const SizedBox(height: 8),
              Text(
                'Last sync: $yahooLastSync',
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
          if (yahooConnected) ...[
            TextButton(
              onPressed: isYahooLoading
                  ? null
                  : () {
                      Navigator.pop(ctx);
                      _handleYahooSync();
                    },
              child: Text('Sync now', style: GoogleFonts.inter(color: forestDark, fontWeight: FontWeight.bold)),
            ),
            TextButton(
              onPressed: isYahooLoading
                  ? null
                  : () {
                      Navigator.pop(ctx);
                      _handleYahooDisconnect();
                    },
              child: Text('Disconnect', style: GoogleFonts.inter(color: const Color(0xFFB8452D), fontWeight: FontWeight.bold)),
            ),
          ] else
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: forestDark,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: isYahooLoading
                  ? null
                  : () {
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
    const Color darkText = Color(0xFF1E293B);
    const Color terracotta = Color(0xFFB8452D);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
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
              style: GoogleFonts.inter(
                color: darkText,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ],
        ),
        content: Text(
          "Are you sure you want to permanently delete your account? All credit cards, active reminders, lend/liability entries, and personal details will be completely purged from our servers. This action is irreversible.",
          style: GoogleFonts.inter(
            color: darkText,
            fontSize: 13.5,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              "Cancel",
              style: GoogleFonts.inter(
                color: darkText,
                fontWeight: FontWeight.bold,
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
    const Color darkText = Color(0xFF1E293B);
    const Color terracotta = Color(0xFFB8452D);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        title: Text(
          "Logout",
          style: GoogleFonts.inter(
            color: darkText,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          "Are you sure you want to logout from your account?",
          style: GoogleFonts.inter(color: darkText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              "Cancel",
              style: GoogleFonts.inter(color: darkText, fontWeight: FontWeight.bold),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: terracotta,
              elevation: 0,
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
    final String initial = widget.userName.isNotEmpty ? widget.userName[0].toUpperCase() : "U";

    return Scaffold(
      backgroundColor: const Color(0xFF195754),
      body: SafeArea(
        child: isDeletingAccount
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 20),
                    Text(
                      "Purging account data...",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              )
            : SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── 1. HEADER: EXECUTIVE PROFILE & LOGOUT ────────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "EXECUTIVE PROFILE",
                              style: GoogleFonts.ibmPlexMono(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.8,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "Account Passport",
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                        // Logout Top Right Circle Button
                        GestureDetector(
                          onTap: _showLogoutDialog,
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(alpha: 0.15),
                            ),
                            child: const Icon(
                              Icons.logout_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // ── 2. ACCOUNT PASSPORT CARD ────────────────────────────
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: Colors.black.withValues(alpha: 0.08),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Avatar Monogram Circle
                              Container(
                                width: 58,
                                height: 58,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: const Color(0xFF195754),
                                  border: Border.all(color: const Color(0xFFD4AF37), width: 2),
                                ),
                                child: Center(
                                  child: Text(
                                    initial,
                                    style: GoogleFonts.inter(
                                      color: const Color(0xFFD4AF37),
                                      fontSize: 26,
                                      fontWeight: FontWeight.bold,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),

                              // Name & Email
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 2),
                                    Text(
                                      widget.userName,
                                      style: GoogleFonts.inter(
                                        color: const Color(0xFF1E293B),
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      email,
                                      style: GoogleFonts.inter(
                                        color: const Color(0xFF6B7280),
                                        fontSize: 13,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),

                              // VERIFIED ACCOUNT Badge
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFD4AF37).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: const Color(0xFFD4AF37).withValues(alpha: 0.6),
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  "VERIFIED ACCOUNT",
                                  style: GoogleFonts.ibmPlexMono(
                                    color: const Color(0xFFB8860B),
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.1,
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 20),

                          // Counters Row
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF6F8F7),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: Colors.black.withValues(alpha: 0.08),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    children: [
                                      Text(
                                        isLoadingStats ? "..." : "$cardCount",
                                        style: GoogleFonts.inter(
                                          color: const Color(0xFF1E293B),
                                          fontSize: 20,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        "CREDIT CARDS",
                                        style: GoogleFonts.ibmPlexMono(
                                          color: const Color(0xFFB8860B),
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 1.2,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  height: 28,
                                  width: 1,
                                  color: Colors.black.withValues(alpha: 0.12),
                                ),
                                Expanded(
                                  child: Column(
                                    children: [
                                      Text(
                                        isLoadingStats ? "..." : "$reminderCount",
                                        style: GoogleFonts.inter(
                                          color: const Color(0xFF1E293B),
                                          fontSize: 20,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        "BILL ALERTS",
                                        style: GoogleFonts.ibmPlexMono(
                                          color: const Color(0xFF195754),
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 1.2,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 28),

                    // ── 3. SETTINGS & PREFERENCES SECTION ────────────────────
                    Text(
                      "Settings & Preferences",
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Settings White Card
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.black.withValues(alpha: 0.08),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          _buildMenuItem(
                            icon: Icons.credit_card_rounded,
                            title: "Manage Credit Cards",
                            color: const Color(0xFF195754),
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
                            icon: Icons.delete_outline_rounded,
                            title: "Delete Card Screen",
                            color: const Color(0xFFB8452D),
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
                          // Temporary: Gmail sign-in is disabled on iOS until an OAuth client exists.
                          if (!Platform.isIOS) ...[
                            _buildDivider(),
                            _buildMenuItem(
                              customLeading: Image.network(
                                "https://cdn-icons-png.flaticon.com/512/5968/5968534.png",
                                width: 20,
                                height: 20,
                                errorBuilder: (_, __, ___) => const Icon(Icons.mail_rounded, color: Color(0xFF195754), size: 20),
                              ),
                              title: gmailConnected ? "Gmail Connected (${gmailEmail ?? ''})" : "Connect Gmail",
                              color: const Color(0xFF195754),
                              onTap: _showGmailDialog,
                            ),
                          ],
                          _buildDivider(),
                          _buildMenuItem(
                            customLeading: Image.network(
                              "https://www.google.com/s2/favicons?domain=yahoo.com&sz=128",
                              width: 20,
                              height: 20,
                              errorBuilder: (_, __, ___) => const Icon(Icons.mail_rounded, color: Color(0xFF195754), size: 20),
                            ),
                            title: yahooConnected ? "Yahoo Connected (${yahooEmail ?? ''})" : "Connect Yahoo",
                            color: const Color(0xFF195754),
                            onTap: _showYahooDialog,
                          ),
                          _buildDivider(),
                          _buildMenuItem(
                            icon: Icons.balance_rounded,
                            title: "Lend & Borrow Tracker",
                            color: const Color(0xFF195754),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => LendLiabilityPage(
                                    userId: widget.userId,
                                    userName: widget.userName,
                                  ),
                                ),
                              ).then((_) => _loadProfileData());
                            },
                          ),
                          _buildDivider(),
                          _buildMenuItem(
                            icon: Icons.assignment_rounded,
                            title: "Expense Tracker",
                            color: const Color(0xFF195754),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ExpenseLandingScreen(
                                    userId: widget.userId,
                                    userName: widget.userName,
                                  ),
                                ),
                              ).then((_) => _loadProfileData());
                            },
                          ),
                          _buildDivider(),
                          _buildMenuItem(
                            icon: Icons.person_remove_rounded,
                            title: "Delete Account",
                            color: const Color(0xFFB8452D),
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
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
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
          color: isLast ? const Color(0xFFB8452D) : const Color(0xFF1E293B),
          fontSize: 14.5,
          fontWeight: FontWeight.w600,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: isLast ? const Color(0xFFB8452D) : const Color(0xFF9CA3AF),
        size: 20,
      ),
    );
  }

  Widget _buildDivider() {
    return Divider(
      height: 1,
      color: Colors.black.withValues(alpha: 0.06),
      indent: 56,
      endIndent: 16,
    );
  }
}
