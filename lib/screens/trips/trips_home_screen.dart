import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../services/trip_service.dart';
import 'create_trip_screen.dart';
import 'join_trip_screen.dart';
import 'trip_details_screen.dart';
import 'trip_history_screen.dart';

class TripsTheme {
  static const Color scaffoldBg = Color(0xFF0C5F41);
  static const Color darkSurface = Color(0xFF0C3826);
  static const Color mintAccent = Color(0xFF10B981);
  static const Color forestDark = Color(0xFF0F261C);
  static const Color darkText = Color(0xFF132A20);
  static const Color terracotta = Color(0xFFB8452D);
  static const Color goldAccent = Color(0xFFD4AF37);
  static const Color textMuted = Color(0xFF68786E);
  static const Color cardBg = Colors.white;
}

class TripsHomeScreen extends StatefulWidget {
  final String userId;
  final String userName;

  const TripsHomeScreen({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<TripsHomeScreen> createState() => _TripsHomeScreenState();
}

class _TripsHomeScreenState extends State<TripsHomeScreen> {
  late Future<List<dynamic>> _tripsFuture;

  @override
  void initState() {
    super.initState();
    _refreshTrips();
  }

  void _refreshTrips() {
    setState(() {
      _tripsFuture = TripService.getUserTrips(widget.userId);
    });
  }

  bool _isTripEnded(Map<String, dynamic> trip) {
    if (trip["status"] == "completed") return true;
    if (trip["endDate"] != null) {
      final endDate = DateTime.tryParse(trip["endDate"]);
      if (endDate != null) {
        final yesterday = DateTime.now().subtract(const Duration(days: 1));
        if (endDate.isBefore(yesterday)) return true;
      }
    }
    return false;
  }

  String _formatDateRange(String? startStr, String? endStr) {
    if (startStr == null && endStr == null) return "Dates Flexible";
    final fmt = DateFormat("MMM d, yyyy");
    final start = startStr != null ? DateTime.tryParse(startStr) : null;
    final end = endStr != null ? DateTime.tryParse(endStr) : null;

    if (start != null && end != null) {
      return "${fmt.format(start)} - ${fmt.format(end)}";
    } else if (start != null) {
      return "Starts ${fmt.format(start)}";
    }
    return "Dates Flexible";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TripsTheme.scaffoldBg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: TripsTheme.darkSurface,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: const Icon(
              Icons.arrow_back_rounded,
              color: TripsTheme.mintAccent,
              size: 20,
            ),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "Trips & Group Expenses",
          style: GoogleFonts.fraunces(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 21,
            fontStyle: FontStyle.italic,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: "Trip History",
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: TripsTheme.darkSurface,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: const Icon(
                Icons.history_rounded,
                color: TripsTheme.mintAccent,
                size: 20,
              ),
            ),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TripHistoryScreen(
                    userId: widget.userId,
                    userName: widget.userName,
                  ),
                ),
              );
              _refreshTrips();
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: TripsTheme.mintAccent,
          backgroundColor: TripsTheme.darkSurface,
          onRefresh: () async => _refreshTrips(),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Top Action Buttons ("Add Trip" & "Join Trip")
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () async {
                          final res = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CreateTripScreen(
                                userId: widget.userId,
                                userName: widget.userName,
                              ),
                            ),
                          );
                          if (res == true) _refreshTrips();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 14),
                          decoration: BoxDecoration(
                            color: TripsTheme.darkSurface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.12),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const FaIcon(
                                FontAwesomeIcons.circlePlus,
                                color: TripsTheme.mintAccent,
                                size: 15,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                "Add Trip",
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GestureDetector(
                        onTap: () async {
                          final res = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => JoinTripScreen(
                                userId: widget.userId,
                                userName: widget.userName,
                              ),
                            ),
                          );
                          if (res == true) _refreshTrips();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.15),
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.12),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const FaIcon(
                                FontAwesomeIcons.qrcode,
                                color: TripsTheme.forestDark,
                                size: 15,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                "Join Trip",
                                style: GoogleFonts.inter(
                                  color: TripsTheme.forestDark,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),

                // 2. Section Header: "Saved Trips"
                Text(
                  "Saved Trips",
                  style: GoogleFonts.fraunces(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 14),

                // 3. Active Saved Trips List
                FutureBuilder<List<dynamic>>(
                  future: _tripsFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Center(
                          child: CircularProgressIndicator(
                            color: TripsTheme.mintAccent,
                          ),
                        ),
                      );
                    }

                    final allTrips = snapshot.data ?? [];
                    final activeTrips = allTrips.where((t) => !_isTripEnded(t)).toList();

                    if (activeTrips.isEmpty) {
                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
                        decoration: BoxDecoration(
                          color: TripsTheme.cardBg,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
                        ),
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: TripsTheme.scaffoldBg.withValues(alpha: 0.08),
                              ),
                              child: const FaIcon(
                                FontAwesomeIcons.planeDeparture,
                                color: TripsTheme.scaffoldBg,
                                size: 36,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              "No Active Trips",
                              style: GoogleFonts.fraunces(
                                color: TripsTheme.forestDark,
                                fontSize: 19,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              "Create a new trip or join an existing trip code to start tracking group expenses.",
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                color: TripsTheme.textMuted,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: activeTrips.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 16),
                      itemBuilder: (context, index) {
                        final trip = activeTrips[index] as Map<String, dynamic>;
                        final tripId = trip["_id"] as String;
                        final name = trip["name"] ?? "Unnamed Trip";
                        final fromLoc = trip["fromLocation"] ?? "From";
                        final toLoc = trip["toLocation"] ?? "To";
                        final budget = (trip["budget"] as num?)?.toDouble() ?? 0.0;
                        final organizerId = trip["organizer"] is Map ? trip["organizer"]["_id"] : trip["organizer"];
                        final isOrganizer = organizerId?.toString() == widget.userId;
                        final members = (trip["members"] as List<dynamic>?) ?? [];
                        final dateStr = _formatDateRange(trip["startDate"], trip["endDate"]);

                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(22),
                            onTap: () async {
                              final res = await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => TripDetailsScreen(
                                    tripId: tripId,
                                    userId: widget.userId,
                                    userName: widget.userName,
                                  ),
                                ),
                              );
                              if (res == true) _refreshTrips();
                            },
                            child: Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: TripsTheme.cardBg,
                                borderRadius: BorderRadius.circular(22),
                                border: Border.all(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  width: 1.2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.04),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Top Badge & Location
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: isOrganizer
                                              ? TripsTheme.scaffoldBg
                                              : TripsTheme.terracotta.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          isOrganizer ? "ORGANIZER" : "MEMBER",
                                          style: GoogleFonts.ibmPlexMono(
                                            color: isOrganizer ? Colors.white : TripsTheme.terracotta,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      Row(
                                        children: [
                                          const FaIcon(
                                            FontAwesomeIcons.userGroup,
                                            size: 13,
                                            color: TripsTheme.textMuted,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            "${members.length} ${members.length == 1 ? 'Member' : 'Members'}",
                                            style: GoogleFonts.inter(
                                              color: TripsTheme.textMuted,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),

                                  // Trip Name
                                  Text(
                                    name,
                                    style: GoogleFonts.fraunces(
                                      color: TripsTheme.darkText,
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 6),

                                  // Route: From -> To
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.location_on_outlined,
                                        color: TripsTheme.scaffoldBg,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          "$fromLoc ➔ $toLoc",
                                          style: GoogleFonts.inter(
                                            color: TripsTheme.darkText,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),

                                  const Divider(height: 1, color: Color(0xFFE8E5DA)),
                                  const SizedBox(height: 12),

                                  // Bottom Row: Date & Total Budget
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        dateStr,
                                        style: GoogleFonts.inter(
                                          color: TripsTheme.textMuted,
                                          fontSize: 12.5,
                                        ),
                                      ),
                                      Text(
                                        "${trip['currencySymbol'] ?? '₹'}${NumberFormat('#,##,###').format(budget)}",
                                        style: GoogleFonts.ibmPlexMono(
                                          color: TripsTheme.scaffoldBg,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
