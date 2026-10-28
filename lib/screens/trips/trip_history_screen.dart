import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../services/trip_service.dart';
import 'trip_details_screen.dart';

class TripHistoryTheme {
  static const Color scaffoldBg = Color(0xFF195754);
  static const Color darkSurface = Color(0xFF113F3D);
  static const Color mintAccent = Color(0xFF10B981);
  static const Color forestDark = Color(0xFF113F3D);
  static const Color darkText = Color(0xFF1E293B);
  static const Color terracotta = Color(0xFFB8452D);
  static const Color textMuted = Color(0xFF6B7280);
  static const Color cardBg = Colors.white;
}

class TripHistoryScreen extends StatefulWidget {
  final String userId;
  final String userName;

  const TripHistoryScreen({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<TripHistoryScreen> createState() => _TripHistoryScreenState();
}

class _TripHistoryScreenState extends State<TripHistoryScreen> {
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
      backgroundColor: TripHistoryTheme.scaffoldBg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: TripHistoryTheme.darkSurface,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: const Icon(
              Icons.arrow_back_rounded,
              color: TripHistoryTheme.mintAccent,
              size: 20,
            ),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "Trip History",
          style: GoogleFonts.inter(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 20,
            fontStyle: FontStyle.italic,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: TripHistoryTheme.mintAccent,
          backgroundColor: TripHistoryTheme.darkSurface,
          onRefresh: () async => _refreshTrips(),
          child: FutureBuilder<List<dynamic>>(
            future: _tripsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: TripHistoryTheme.mintAccent),
                );
              }

              final allTrips = snapshot.data ?? [];
              final endedTrips = allTrips.where((t) => _isTripEnded(t)).toList();

              if (endedTrips.isEmpty) {
                return SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Container(
                    width: double.infinity,
                    margin: const EdgeInsets.fromLTRB(20, 40, 20, 40),
                    padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
                    decoration: BoxDecoration(
                      color: TripHistoryTheme.cardBg,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: TripHistoryTheme.scaffoldBg.withValues(alpha: 0.08),
                          ),
                          child: const FaIcon(
                            FontAwesomeIcons.clockRotateLeft,
                            color: TripHistoryTheme.scaffoldBg,
                            size: 38,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          "No Past Trips in History",
                          style: GoogleFonts.inter(
                            color: TripHistoryTheme.forestDark,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "Completed or ended trips will appear here for your future expense reference.",
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            color: TripHistoryTheme.textMuted,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return ListView.separated(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                itemCount: endedTrips.length,
                separatorBuilder: (_, __) => const SizedBox(height: 16),
                itemBuilder: (context, index) {
                  final trip = endedTrips[index] as Map<String, dynamic>;
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
                          color: TripHistoryTheme.cardBg,
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
                            // Top Badges
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: isOrganizer
                                            ? TripHistoryTheme.scaffoldBg
                                            : TripHistoryTheme.terracotta.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        isOrganizer ? "ORGANIZER" : "MEMBER",
                                        style: GoogleFonts.ibmPlexMono(
                                          color: isOrganizer ? Colors.white : TripHistoryTheme.terracotta,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade200,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: Colors.black12),
                                      ),
                                      child: Text(
                                        "ENDED",
                                        style: GoogleFonts.ibmPlexMono(
                                          color: Colors.grey.shade700,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                Row(
                                  children: [
                                    const FaIcon(
                                      FontAwesomeIcons.userGroup,
                                      size: 13,
                                      color: TripHistoryTheme.textMuted,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      "${members.length} ${members.length == 1 ? 'Member' : 'Members'}",
                                      style: GoogleFonts.inter(
                                        color: TripHistoryTheme.textMuted,
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
                              style: GoogleFonts.inter(
                                color: TripHistoryTheme.darkText,
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
                                  color: TripHistoryTheme.scaffoldBg,
                                  size: 18,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    "$fromLoc ➔ $toLoc",
                                    style: GoogleFonts.inter(
                                      color: TripHistoryTheme.darkText,
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
                                    color: TripHistoryTheme.textMuted,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  "${trip['currencySymbol'] ?? '₹'}${NumberFormat('#,##,###').format(budget)}",
                                  style: GoogleFonts.ibmPlexMono(
                                    color: TripHistoryTheme.scaffoldBg,
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
        ),
      ),
    );
  }
}
