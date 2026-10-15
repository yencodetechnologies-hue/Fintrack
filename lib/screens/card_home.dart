// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:convert';
import '../config/app_config.dart';
import 'add_reminder_page.dart';
import 'card_create_screen.dart';
import 'view_card_screen.dart';
import 'view_reminder_page.dart';
import 'LendLiabilityPage.dart';
import 'trips/trips_home_screen.dart';
// import 'vehicles/vehicle_dashboard_screen.dart';
import 'expense/expense_landing_screen.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:http/http.dart' as http;
import '../services/email_sync_service.dart';
import '../services/fcm_service.dart';

class CardHomeTheme {
  static const Color background = Color(0xFF0F261C); // QFin Deep Forest Green Header / Background
  static const Color cardBg = Color(0xFFF6F4EB); // Vintage Cream Card Surface
  static const Color cardBorder = Color(0xFFE2DDD0); // Soft Vintage Cream Border
  static const Color borderDark = Color(0xFFE2DDD0);
  static const Color emeraldGlow = Color(0xFFD4AF37); // Vintage Gold Accent
  static const Color primaryBlue = Color(0xFFB8452D); // Terracotta Accent
  static const Color cyanGlow = Color(0xFFD4AF37); // Vintage Gold Accent
  static const Color cyanAccent = Color(0xFFD4AF37);
  static const Color textWhite = Color(0xFF132A20); // Dark Forest Slate Text inside Cream Cards
  static const Color textMuted = Color(0xFF6B7280); // Muted Text
}

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
  OverlayEntry? _notifOverlay;
  final List<Map<String, dynamic>> _notifLogs = [];
  final Set<int> _selectedNotifs = {};
  bool _notifsLoading = false;
  List<Map<String, dynamic>> _billSuggestions = [];
  bool _billsLoading = false;

  @override
  void initState() {
    super.initState();
    FCMService.syncTokenWithServer(widget.userId);
    _loadBillSuggestions();
  }

  Future<void> _loadBillSuggestions() async {
    setState(() => _billsLoading = true);
    try {
      final suggestions =
          await EmailSyncService.getSuggestions(widget.userId);
      if (mounted) {
        setState(() {
          _billSuggestions = suggestions;
          _billsLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _billSuggestions = [];
          _billsLoading = false;
        });
      }
    }
  }

  Widget _buildBillSuggestionBanner() {
    if (_billsLoading || _billSuggestions.isEmpty) {
      return const SizedBox.shrink();
    }

    const Color darkText = Color(0xFF132A20);
    const Color terracotta = Color(0xFFB8452D);
    const Color goldAccent = Color(0xFFD4AF37);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: terracotta,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  "Action Required",
                  style: GoogleFonts.fraunces(
                    color: darkText,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: terracotta.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: terracotta.withValues(alpha: 0.25)),
              ),
              child: Text(
                "${_billSuggestions.length} ${_billSuggestions.length == 1 ? 'Bill Found' : 'Bills Found'}",
                style: GoogleFonts.ibmPlexMono(
                  color: terracotta,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ..._billSuggestions.map((bill) {
          final bank = bill['bankName'] ?? 'Card';
          final last4 = bill['last4Digits'] ?? '****';
          final amount = bill['amount']?.toString() ?? '?';
          final dueRaw = bill['paymentDueDate'] as String?;
          final dueStr = dueRaw != null
              ? DateTime.tryParse(dueRaw)?.toLocal().toString().split(' ').first ?? dueRaw
              : 'soon';

          return Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white,
                  terracotta.withValues(alpha: 0.04),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: terracotta.withValues(alpha: 0.3),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: terracotta.withValues(alpha: 0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: terracotta.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.mark_email_unread_rounded,
                        color: terracotta,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "$bank •••• $last4",
                            style: GoogleFonts.inter(
                              color: darkText,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            "Statement Due: $dueStr",
                            style: GoogleFonts.inter(
                              color: Colors.black54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          "₹$amount",
                          style: GoogleFonts.inter(
                            color: darkText,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: goldAccent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            "DUE SOON",
                            style: GoogleFonts.ibmPlexMono(
                              color: const Color(0xFF8A6D00),
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 42,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: terracotta,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () async {
                      if (!mounted) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AddReminderPage(
                            userId: widget.userId,
                            userName: widget.userName,
                            initialBill: bill,
                          ),
                        ),
                      ).then((_) => _loadBillSuggestions());
                    },
                    icon: const Icon(Icons.add_alarm_rounded, size: 18),
                    label: Text(
                      'Set Bill Reminder',
                      style: GoogleFonts.inter(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

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

  void _toggleNotificationPopup(BuildContext ctx) {
    if (_notifOverlay != null) {
      _closeNotifPopup();
      return;
    }
    _fetchNotifLogs().then((_) {
      if (mounted) _openNotifPopup(ctx);
    });
  }

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
                  left: 16,
                  right: 16,
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF042217),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.35), width: 1.2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.6),
                            blurRadius: 25,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 16, 16, 10),
                            child: Row(
                              children: [
                                Text(
                                  'Notifications',
                                  style: GoogleFonts.fraunces(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const Spacer(),
                                if (_selectedNotifs.isNotEmpty) ...[
                                  Text(
                                    '${_selectedNotifs.length} selected',
                                    style: GoogleFonts.inter(
                                      color: const Color(0xFF10B981),
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(
                                        color: Color(0xFFB8452D),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    onPressed: () {
                                      setPopState(() {
                                        final sorted = _selectedNotifs.toList()..sort((a, b) => b.compareTo(a));
                                        for (final i in sorted) {
                                          _notifLogs.removeAt(i);
                                        }
                                        _selectedNotifs.clear();
                                      });
                                    },
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: Color(0xFFB8452D),
                                      size: 14,
                                    ),
                                    label: Text(
                                      'Delete',
                                      style: GoogleFonts.inter(
                                        color: const Color(0xFFB8452D),
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                ],
                                IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    color: Colors.white70,
                                    size: 22,
                                  ),
                                  onPressed: _closeNotifPopup,
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
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
                          Divider(
                            color: Colors.white.withValues(alpha: 0.12),
                            height: 1,
                          ),
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight: screenHeight * 0.5,
                            ),
                            child: _notifsLoading
                                ? const Padding(
                                    padding: EdgeInsets.all(32),
                                    child: Center(
                                      child: CircularProgressIndicator(
                                        color: Color(0xFF10B981),
                                      ),
                                    ),
                                  )
                                : _notifLogs.isEmpty
                                    ? Padding(
                                        padding: const EdgeInsets.all(32),
                                        child: Center(
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(
                                                Icons.notifications_off_outlined,
                                                size: 36,
                                                color: Color(0xFF10B981),
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                'No notifications',
                                                style: GoogleFonts.inter(
                                                  color: Colors.white70,
                                                  fontSize: 13.5,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      )
                                    : ListView.separated(
                                        shrinkWrap: true,
                                        physics: const ClampingScrollPhysics(),
                                        itemCount: _notifLogs.length,
                                        separatorBuilder: (_, x) => Divider(
                                          color: Colors.white.withValues(alpha: 0.12),
                                          height: 1,
                                        ),
                                        itemBuilder: (_, i) {
                                          final log = _notifLogs[i];
                                          final isSel = _selectedNotifs.contains(i);
                                          return InkWell(
                                            onTap: () => setPopState(() {
                                              isSel ? _selectedNotifs.remove(i) : _selectedNotifs.add(i);
                                            }),
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 20,
                                                vertical: 12,
                                              ),
                                              child: Row(
                                                children: [
                                                  AnimatedContainer(
                                                    duration: const Duration(
                                                      milliseconds: 150,
                                                    ),
                                                    width: 20,
                                                    height: 20,
                                                    margin: const EdgeInsets.only(
                                                      right: 12,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: isSel ? const Color(0xFF10B981) : Colors.transparent,
                                                      borderRadius: BorderRadius.circular(6),
                                                      border: Border.all(
                                                        color: isSel ? const Color(0xFF10B981) : Colors.white54,
                                                      ),
                                                    ),
                                                    child: isSel
                                                        ? const Icon(
                                                            Icons.check,
                                                            size: 14,
                                                            color: Color(0xFF042217),
                                                          )
                                                        : null,
                                                  ),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Row(
                                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                          children: [
                                                            Text(
                                                              (log['title'] as String?) ?? 'Notification',
                                                              style: GoogleFonts.inter(
                                                                color: Colors.white,
                                                                fontSize: 14,
                                                                fontWeight: FontWeight.bold,
                                                              ),
                                                            ),
                                                            Text(
                                                              _formatTime(
                                                                log['sentAt'] as String?,
                                                              ),
                                                              style: GoogleFonts.ibmPlexMono(
                                                                color: const Color(0xFF10B981),
                                                                fontSize: 11,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                        const SizedBox(height: 3),
                                                        Text(
                                                          (log['message'] as String?) ?? '',
                                                          style: GoogleFonts.inter(
                                                            color: Colors.white70,
                                                            fontSize: 12.5,
                                                          ),
                                                          overflow: TextOverflow.ellipsis,
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

  void _closeNotifPopup() {
    _notifOverlay?.remove();
    _notifOverlay = null;
    _selectedNotifs.clear();
  }

  Widget _notifChip(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF0C5F41),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  String _formatTime(String? raw) {
    if (raw == null) return '';
    final dt = DateTime.tryParse(raw)?.toLocal();
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return "Good morning";
    if (hour < 17) return "Good afternoon";
    return "Good evening";
  }

  @override
  Widget build(BuildContext context) {
    const Color darkText = Color(0xFF132A20);
    const Color goldText = Color(0xFFD4AF37);
    const Color terracotta = Color(0xFFB8452D);

    final List<Map<String, dynamic>> horizontalChips = [
      {
        "title": "Add Card",
        "icon": FontAwesomeIcons.creditCard,
        "color": terracotta,
        "bg": terracotta.withValues(alpha: 0.08),
        "page": (context) => CardCreateScreen(userId: widget.userId, userName: widget.userName),
      },
      {
        "title": "Add Reminder",
        "icon": FontAwesomeIcons.solidBell,
        "color": darkText,
        "bg": darkText.withValues(alpha: 0.08),
        "page": (context) => AddReminderPage(userId: widget.userId, userName: widget.userName),
      },
      {
        "title": "Lend & Borrow",
        "icon": FontAwesomeIcons.handshake,
        "color": const Color(0xFF8A6D00),
        "bg": goldText.withValues(alpha: 0.15),
        "page": (context) => LendLiabilityPage(userId: widget.userId, userName: widget.userName),
      },
    ];

    final List<Map<String, dynamic>> mainFeatures = [
      {
        "title": "My Credit Cards",
        "subtitle": "Manage active limits & billing cycles",
        "icon": FontAwesomeIcons.wallet,
        "badge": "Active Cards",
        "color": darkText,
        "page": (context) => ViewCardScreen(userId: widget.userId, userName: widget.userName),
      },
      {
        "title": "Upcoming Reminders",
        "subtitle": "Track bill due dates & scheduled payments",
        "icon": FontAwesomeIcons.calendarCheck,
        "badge": "Scheduled Bills",
        "color": terracotta,
        "page": (context) => ViewReminderPage(userId: widget.userId, userName: widget.userName),
      },
      {
        "title": "Lend & Borrow Tracker",
        "subtitle": "Monitor personal payables and receivables",
        "icon": FontAwesomeIcons.scaleUnbalanced,
        "badge": "Track Balances",
        "color": darkText,
        "page": (context) => LendLiabilityPage(userId: widget.userId, userName: widget.userName),
      },
      {
        "title": "Expense Tracker",
        "subtitle": "Monitor daily expenses, categories & spending analytics",
        "icon": FontAwesomeIcons.receipt,
        "badge": "Daily Expenses",
        "color": terracotta,
        "page": (context) => ExpenseLandingScreen(userId: widget.userId, userName: widget.userName),
      },


      {
        "title": "Trips & Group Planner",
        "subtitle": "Group trips, budget splits & QR code invites",
        "icon": FontAwesomeIcons.plane,
        "badge": "Group Expenses",
        "color": terracotta,
        "page": (context) => TripsHomeScreen(userId: widget.userId, userName: widget.userName),
      },
      // {
      //   "title": "Vehicle Dashboard",
      //   "subtitle": "Track mileage, live speed, fuel usage & safe range",
      //   "icon": FontAwesomeIcons.gaugeHigh,
      //   "badge": "Live Tracking",
      //   "color": const Color(0xFF10B981),
      //   "page": (context) => VehicleDashboardScreen(userId: widget.userId, userName: widget.userName),
      // },
    ];

    final initial = widget.userName.isNotEmpty ? widget.userName[0].toUpperCase() : 'U';

    return Scaffold(
      backgroundColor: const Color(0xFF0C5F41),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Unified Executive Top Navigation Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      if (Navigator.canPop(context)) ...[
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: Container(
                            padding: const EdgeInsets.all(9),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0C3826),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                            ),
                            child: const Icon(Icons.arrow_back_rounded, color: Color(0xFF10B981), size: 20),
                          ),
                          onPressed: () => Navigator.maybePop(context),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF0F3827),
                          border: Border.all(color: const Color(0xFF10B981), width: 2.2),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF10B981).withValues(alpha: 0.25),
                              blurRadius: 10,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            initial,
                            style: GoogleFonts.fraunces(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Notification Icon
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0C3826),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                      ),
                      child: Stack(
                        children: [
                          const Icon(Icons.notifications_outlined, color: Color(0xFF10B981), size: 20),
                          if (_notifLogs.isNotEmpty)
                            Positioned(
                              right: 0,
                              top: 0,
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: terracotta,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    onPressed: () => _toggleNotificationPopup(context),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // 2. Greeting & Title Banner
              Text(
                "FINANCIAL DASHBOARD",
                style: GoogleFonts.ibmPlexMono(
                  color: const Color(0xFF10B981),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2.2,
                ),
              ),
              const SizedBox(height: 2),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    "${_getGreeting()}, ",
                    style: GoogleFonts.fraunces(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 24,
                      fontWeight: FontWeight.w400,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  Text(
                    widget.userName,
                    style: GoogleFonts.fraunces(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // 3. Bill Suggestion / Action Required Banner
              _buildBillSuggestionBanner(),

              // 4. Quick Actions Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Quick Actions",
                    style: GoogleFonts.fraunces(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    "Shortcuts",
                    style: GoogleFonts.ibmPlexMono(
                      color: const Color(0xFF10B981),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: horizontalChips.map((chip) {
                  final Color color = chip["color"] as Color;
                  final Color bg = chip["bg"] as Color;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => (chip["page"] as Widget Function(BuildContext))(context),
                          ),
                        );
                      },
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.2),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: bg,
                                shape: BoxShape.circle,
                              ),
                              child: FaIcon(chip["icon"] as dynamic, color: color, size: 20),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              chip["title"] as String,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                color: darkText,
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 26),

              // 5. Management Hub Sections
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Management Hub",
                    style: GoogleFonts.fraunces(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    "Overview",
                    style: GoogleFonts.ibmPlexMono(
                      color: const Color(0xFF10B981),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: mainFeatures.length,
                separatorBuilder: (_, __) => const SizedBox(height: 14),
                itemBuilder: (context, index) {
                  final feat = mainFeatures[index];
                  final Color color = feat["color"] as Color;

                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(22),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => (feat["page"] as Widget Function(BuildContext))(context),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: Colors.black.withValues(alpha: 0.08),
                            width: 1.2,
                          ),
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
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: FaIcon(feat["icon"] as dynamic, color: color, size: 22),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    feat["title"] as String,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.inter(
                                      color: darkText,
                                      fontSize: 15.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    feat["subtitle"] as String,
                                    style: GoogleFonts.inter(
                                      color: CardHomeTheme.textMuted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.04),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.chevron_right_rounded,
                                color: CardHomeTheme.textMuted,
                                size: 18,
                              ),
                            ),
                          ],
                        ),
                      ),
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