import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../config/app_config.dart';
import 'add_reminder_page.dart';
import 'card_create_screen.dart';
import 'home_screen.dart';
import 'view_card_screen.dart';
import 'view_reminder_page.dart';
import 'LendLiabilityPage.dart';
import 'profile_screen.dart';
import 'package:http/http.dart' as http;

class CardHome extends StatelessWidget {
  final String userId;
  final String userName;

  const CardHome({


    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  Widget build(BuildContext context) {
    return GridViewPage(
      userId: userId,
      userName: userName,
    );
  }
}

class GridViewPage extends StatefulWidget {
  final String userId;
  final String userName;

  const GridViewPage({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<GridViewPage> createState() => _GridViewPageState();
}

class _GridViewPageState extends State<GridViewPage> {
  int _selectedIndex = 0;
  OverlayEntry? _notifOverlay;
  final List<Map<String, dynamic>> _notifLogs = [];
  final Set<int> _selectedNotifs = {};
  bool _notifsLoading = false;

  // ── fetch ────────────────────────────────────────────────────────────────

  Future<void> _fetchNotifLogs() async {
    setState(() => _notifsLoading = true);
    try {
      final res = await http.get(
        Uri.parse(
          "${AppConfig.cron}?userId=${widget.userId}",
        ),
      );

      if (!mounted) return;

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final data = List<Map<String, dynamic>>.from(body['data'] as List);
      _notifLogs
        ..clear()
        ..addAll(data);
    } catch (e) {
      _notifLogs.clear();
    }
    if (!mounted) return;
    setState(() => _notifsLoading = false);
  }

  // ── toggle ───────────────────────────────────────────────────────────────

  void _toggleNotificationPopup(BuildContext ctx) {
    if (_notifOverlay != null) {
      _closeNotifPopup();
      return;
    }
    _fetchNotifLogs().then((_) {
      if (mounted) _openNotifPopup(ctx);
    });
  }

  // ── open ─────────────────────────────────────────────────────────────────

  void _openNotifPopup(BuildContext ctx) {
    final overlay = Overlay.of(ctx);
    final topPadding = MediaQuery.of(ctx).padding.top;
    final appBarBottom = topPadding + kToolbarHeight;
    final screenHeight = MediaQuery.of(ctx).size.height;

    _notifOverlay = OverlayEntry(
      builder: (overlayCtx) {
        return StatefulBuilder(
          builder: (overlayCtx, setPopState) {
            return Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    onTap: _closeNotifPopup,
                    child: Container(color: Colors.black54),
                  ),
                ),
                Positioned(
                  top: appBarBottom,
                  left: 0,
                  right: 0,
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      color: const Color(0xFF1A1A1A),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [

                          // header
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                            child: Row(
                              children: [
                                const Text(
                                  'Notifications',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const Spacer(),
                                if (_selectedNotifs.isNotEmpty) ...[
                                  Text(
                                    '${_selectedNotifs.length} selected',
                                    style: const TextStyle(
                                      color: Color(0xFF00D9FF),
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(
                                        color: Color(0xFF00D9FF),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      minimumSize: Size.zero,
                                      tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    onPressed: () {
                                      setPopState(() {
                                        final sorted =
                                        _selectedNotifs.toList()
                                          ..sort(
                                                (a, b) => b.compareTo(a),
                                          );
                                        for (final i in sorted) {
                                          _notifLogs.removeAt(i);
                                        }
                                        _selectedNotifs.clear();
                                      });
                                    },
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: Color(0xFF00D9FF),
                                      size: 13,
                                    ),
                                    label: const Text(
                                      'Delete',
                                      style: TextStyle(
                                        color: Color(0xFF00D9FF),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                ],
                                IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  icon: const Icon(
                                    Icons.close,
                                    color: Color(0xFF555555),
                                    size: 20,
                                  ),
                                  onPressed: _closeNotifPopup,
                                ),
                              ],
                            ),
                          ),

                          // chips
                          Padding(
                            padding:
                            const EdgeInsets.fromLTRB(16, 0, 16, 10),
                            child: Row(
                              children: [
                                _notifChip('Select all', () {
                                  setPopState(() {
                                    _selectedNotifs.addAll(
                                      List.generate(
                                        _notifLogs.length,
                                            (i) => i,
                                      ),
                                    );
                                  });
                                }),
                                const SizedBox(width: 8),
                                _notifChip('Clear', () {
                                  setPopState(
                                        () => _selectedNotifs.clear(),
                                  );
                                }),
                              ],
                            ),
                          ),

                          const Divider(
                            color: Color(0xFF2A2A2A),
                            height: 1,
                          ),

                          // list
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight: screenHeight * 0.55,
                            ),
                            child: _notifsLoading
                                ? const Padding(
                              padding: EdgeInsets.all(32),
                              child: Center(
                                child: CircularProgressIndicator(
                                  color: Color(0xFF00D9FF),
                                ),
                              ),
                            )
                                : _notifLogs.isEmpty
                                ? const Padding(
                              padding: EdgeInsets.all(32),
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons
                                          .notifications_off_outlined,
                                      size: 32,
                                      color: Color(0xFF333333),
                                    ),
                                    SizedBox(height: 8),
                                    Text(
                                      'No notifications',
                                      style: TextStyle(
                                        color: Color(0xFF555555),
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                                : ListView.separated(
                              shrinkWrap: true,
                              physics:
                              const ClampingScrollPhysics(),
                              itemCount: _notifLogs.length,
                              separatorBuilder: (_, x) =>
                              const Divider(
                                color: Color(0xFF222222),
                                height: 1,
                              ),
                              itemBuilder: (_, i) {
                                final log = _notifLogs[i];
                                final isSel =
                                _selectedNotifs.contains(i);
                                return InkWell(
                                  onTap: () =>
                                      setPopState(() {
                                        isSel
                                            ? _selectedNotifs
                                            .remove(i)
                                            : _selectedNotifs.add(i);
                                      }),
                                  child: Padding(
                                    padding:
                                    const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 11,
                                    ),
                                    child: Row(
                                      children: [
                                        AnimatedContainer(
                                          duration: const Duration(
                                            milliseconds: 150,
                                          ),
                                          width: 18,
                                          height: 18,
                                          decoration:
                                          BoxDecoration(
                                            color: isSel
                                                ? const Color(
                                              0xFF00D9FF,
                                            )
                                                : Colors
                                                .transparent,
                                            border: Border.all(
                                              color: isSel
                                                  ? const Color(
                                                0xFF00D9FF,
                                              )
                                                  : const Color(
                                                0xFF444444,
                                              ),
                                              width: 1.5,
                                            ),
                                            borderRadius:
                                            BorderRadius
                                                .circular(5),
                                          ),
                                          child: isSel
                                              ? const Icon(
                                            Icons.check,
                                            size: 12,
                                            color:
                                            Colors.black,
                                          )
                                              : null,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                            CrossAxisAlignment
                                                .start,
                                            children: [
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      '💳 Credit Card Reminder',
                                                      style:
                                                      TextStyle(
                                                        color: isSel
                                                            ? const Color(
                                                          0xFF00D9FF,
                                                        )
                                                            : Colors
                                                            .white,
                                                        fontSize:
                                                        13,
                                                        fontWeight:
                                                        FontWeight
                                                            .w500,
                                                      ),
                                                    ),
                                                  ),
                                                  Text(
                                                    _formatTime(
                                                      log['sentAt']
                                                      as String?,
                                                    ),
                                                    style:
                                                    const TextStyle(
                                                      color: Color(
                                                        0xFF555555,
                                                      ),
                                                      fontSize: 11,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(
                                                height: 3,
                                              ),
                                              Text(
                                                (log['message']
                                                as String?) ??
                                                    '',
                                                style:
                                                const TextStyle(
                                                  color: Color(
                                                    0xFF777777,
                                                  ),
                                                  fontSize: 12,
                                                ),
                                                overflow: TextOverflow
                                                    .ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    overlay.insert(_notifOverlay!);
  }

  // ── close ────────────────────────────────────────────────────────────────

  void _closeNotifPopup() {
    _notifOverlay?.remove();
    _notifOverlay = null;
    _selectedNotifs.clear();
  }

  // ── chip ─────────────────────────────────────────────────────────────────

  Widget _notifChip(String label, VoidCallback onTap) {
    return GestureDetector(
        onTap: onTap,
        child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF333333)),
              borderRadius: BorderRadius.circular(7),
            ),
          child: Text(
            label,
            style: const TextStyle(color: Color(0xFFAAAAAA), fontSize: 12),
          ),
        ),
    );
  }

  // ── format time ──────────────────────────────────────────────────────────

  String _formatTime(String? raw) {
    if (raw == null) return '';
    final dt = DateTime.tryParse(raw)?.toLocal();
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
  // ── dispose ──────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _closeNotifPopup();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> items = [
      {
        "name": "Add Card",
        "subtitle": "Add new card",
        "icon": Icons.add_card_rounded,
        "color": const Color(0xFF3B82F6), // Premium Blue
        "page": (BuildContext context) => CardCreateScreen(
              userId: widget.userId,
              userName: widget.userName,
            ),
      },
      {
        "name": "View Card",
        "subtitle": "View your cards",
        "icon": Icons.credit_card,
        "color": const Color(0xFF10B981), // Emerald Green
        "page": (BuildContext context) => ViewCardScreen(
              userId: widget.userId,
              userName: widget.userName,
            ),
      },
      {
        "name": "Add Reminder",
        "subtitle": "Add new reminder",
        "icon": Icons.add_alert_rounded,
        "color": const Color(0xFFF59E0B), // Amber Orange
        "page": (BuildContext context) => AddReminderPage(
              userId: widget.userId,
              userName: widget.userName,
            ),
      },
      {
        "name": "View Reminder",
        "subtitle": "View all reminders",
        "icon": Icons.notifications_active,
        "color": const Color(0xFF8B5CF6), // Violet Purple
        "page": (BuildContext context) => ViewReminderPage(
              userId: widget.userId,
              userName: widget.userName,
            ),
      },
      {
        "name": "Lend & Liability",
        "subtitle": "Track payments",
        "icon": Icons.account_balance_wallet,
        "color": const Color(0xFF06B6D4), // Teal Cyan
        "page": (BuildContext context) => LendLiabilityPage(
              userId: widget.userId,
              userName: widget.userName,
            ),
      },
    ];

    return Scaffold(
      backgroundColor: AppConfig.background,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.03),
              border: Border.all(
                color: AppConfig.primaryTeal.withOpacity(0.2),
                width: 1,
              ),
            ),
            padding: const EdgeInsets.all(4.0),
            child: Image.asset(
              "assets/images/logo.png",
              width: 24,
              height: 24,
            ),
          ),
        ),
        title: const Text(
          AppConfig.appName,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 22,
            letterSpacing: 0.5,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(
              Icons.notifications_rounded,
              color: AppConfig.primaryTeal,
              size: 26,
            ),
            onPressed: () => _toggleNotificationPopup(context),
          ),
          IconButton(
            icon: const Icon(
              Icons.logout_rounded,
              color: AppConfig.primaryTeal,
              size: 26,
            ),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  backgroundColor: AppConfig.darkSlate,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: Colors.white.withOpacity(0.08),
                      width: 1.5,
                    ),
                  ),
                  title: const Text(
                    "Logout",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  content: const Text(
                    "Are you sure you want to logout?",
                    style: TextStyle(color: Colors.white70),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      child: const Text(
                        "Cancel",
                        style: TextStyle(color: Colors.white60),
                      ),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppConfig.primaryTeal,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () async {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.clear();
                        if (!context.mounted) return;
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const HomeScreen(),
                          ),
                          (route) => false,
                        );
                      },
                      child: const Text(
                        "Logout",
                        style: TextStyle(
                          color: Color(0xFF0F172A),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // Background soft glowing teal orb 1
          Positioned(
            top: -80,
            left: -80,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppConfig.primaryTeal.withOpacity(0.1),
              ),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 90, sigmaY: 90),
                child: Container(color: Colors.transparent),
              ),
            ),
          ),
          // Background soft glowing blue orb 2
          Positioned(
            bottom: -100,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppConfig.gradientEnd.withOpacity(0.06),
              ),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 80, sigmaY: 80),
                child: Container(color: Colors.transparent),
              ),
            ),
          ),

          // Main content
          SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Greeting text
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          "Welcome back, ",
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 15,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        Text(
                          widget.userName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Premium Cardholder wallet container
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppConfig.darkSlate,
                            const Color(0xFF1E293B),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: AppConfig.primaryTeal.withOpacity(0.2),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.4),
                            blurRadius: 15,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Icon(
                                Icons.credit_card_rounded,
                                color: AppConfig.primaryTeal,
                                size: 36,
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppConfig.primaryTeal.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: AppConfig.primaryTeal.withOpacity(0.3),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.verified_user_rounded,
                                      color: AppConfig.primaryTeal,
                                      size: 14,
                                    ),
                                    const SizedBox(width: 4),
                                    const Text(
                                      "SECURE",
                                      style: TextStyle(
                                        color: AppConfig.primaryTeal,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 28),
                          const Text(
                            "Manage your cards\nand reminders easily",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              height: 1.3,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                widget.userName.toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.0,
                                ),
                              ),
                              const Text(
                                "•••• •••• •••• 2026",
                                style: TextStyle(
                                  color: Colors.white38,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.0,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 30),

                    // Quick Actions Title
                    const Text(
                      "Quick Actions",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Dynamic non-overflowing Action Grid
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: items.length,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 14,
                        childAspectRatio: 1.15, // Non-overflow ratio
                      ),
                      itemBuilder: (context, index) {
                        final item = items[index];

                        return InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => (item["page"]
                                    as Widget Function(BuildContext))(context),
                              ),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              color: Colors.white.withOpacity(0.02),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.06),
                                width: 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 6,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: (item["color"] as Color)
                                        .withOpacity(0.12),
                                  ),
                                  child: Icon(
                                    item["icon"],
                                    color: item["color"],
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  item["name"],
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  item["subtitle"],
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.4),
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 24),

                    // Secure status banner
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.01),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.04),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.blue.withOpacity(0.1),
                            ),
                            child: const Icon(
                              Icons.security_rounded,
                              color: Colors.blueAccent,
                              size: 26,
                            ),
                          ),
                          const SizedBox(width: 16),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Your data is secured",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  "100% encrypted and protected",
                                  style: TextStyle(
                                    color: Colors.white38,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: AppConfig.background,
        selectedItemColor: AppConfig.primaryTeal,
        unselectedItemColor: Colors.white54,
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        onTap: (index) {
          if (index == _selectedIndex) return;
          setState(() {
            _selectedIndex = index;
          });

          if (index == 0) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => CardHome(
                  userId: widget.userId,
                  userName: widget.userName,
                ),
              ),
            );
          }

          if (index == 1) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => ViewCardScreen(
                  userId: widget.userId,
                  userName: widget.userName,
                ),
              ),
            );
          }

          if (index == 2) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => ViewReminderPage(
                  userId: widget.userId,
                  userName: widget.userName,
                ),
              ),
            );
          }

          if (index == 3) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => ProfileScreen(
                  userId: widget.userId,
                  userName: widget.userName,
                ),
              ),
            );
          }
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_rounded),
            label: "Home",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.credit_card_rounded),
            label: "Cards",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.notifications_rounded),
            label: "Reminder",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_rounded),
            label: "Profile",
          ),
        ],
      ),
    );
  }
}