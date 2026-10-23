import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../services/trip_service.dart';

class TripDetailsTheme {
  static const Color scaffoldBg = Color(0xFF195754);
  static const Color darkSurface = Color(0xFF113F3D);
  static const Color mintAccent = Color(0xFF10B981);
  static const Color forestDark = Color(0xFF113F3D);
  static const Color darkText = Color(0xFF1E293B);
  static const Color terracotta = Color(0xFFB8452D);
  static const Color goldAccent = Color(0xFFD4AF37);
  static const Color textMuted = Color(0xFF6B7280);
  static const Color cardBg = Colors.white;
}

class TripDetailsScreen extends StatefulWidget {
  final String tripId;
  final String userId;
  final String userName;

  const TripDetailsScreen({
    super.key,
    required this.tripId,
    required this.userId,
    required this.userName,
  });

  @override
  State<TripDetailsScreen> createState() => _TripDetailsScreenState();
}

class _TripDetailsScreenState extends State<TripDetailsScreen> {
  late Future<Map<String, dynamic>?> _tripFuture;

  @override
  void initState() {
    super.initState();
    _refreshTrip();
  }

  void _refreshTrip() {
    setState(() {
      _tripFuture = TripService.getTripDetails(widget.tripId);
    });
  }

  String _formatDateRange(String? startStr, String? endStr) {
    if (startStr == null && endStr == null) return "Flexible Dates";
    final fmt = DateFormat("MMM d, yyyy");
    final start = startStr != null ? DateTime.tryParse(startStr) : null;
    final end = endStr != null ? DateTime.tryParse(endStr) : null;

    if (start != null && end != null) {
      return "${fmt.format(start)} - ${fmt.format(end)}";
    } else if (start != null) {
      return "Starts ${fmt.format(start)}";
    }
    return "Flexible Dates";
  }

  void _showQrInviteSheet(String joinCode, String tripName) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) {
        return Container(
          decoration: const BoxDecoration(
            color: TripDetailsTheme.scaffoldBg,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(28),
              topRight: Radius.circular(28),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 20),

              Text(
                "Invite Members",
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "Let friends scan this QR code or enter the 6-digit code to join \"$tripName\".",
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 24),

              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
                ),
                child: Column(
                  children: [
                    QrImageView(
                      data: joinCode,
                      version: QrVersions.auto,
                      size: 150.0,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: TripDetailsTheme.scaffoldBg,
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: TripDetailsTheme.scaffoldBg,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      "TRIP CODE",
                      style: GoogleFonts.ibmPlexMono(
                        color: TripDetailsTheme.textMuted,
                        fontSize: 10,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    SelectableText(
                      joinCode,
                      style: GoogleFonts.ibmPlexMono(
                        color: TripDetailsTheme.scaffoldBg,
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: TripDetailsTheme.darkSurface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                    ),
                  ),
                  onPressed: () => Navigator.pop(sheetCtx),
                  child: Text(
                    "Done",
                    style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _confirmRemoveMember(String memberId, String memberName) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return Container(
          decoration: const BoxDecoration(
            color: TripDetailsTheme.scaffoldBg,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(28),
              topRight: Radius.circular(28),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 20),

              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: TripDetailsTheme.terracotta.withValues(alpha: 0.15),
                ),
                child: const Icon(Icons.person_remove_rounded, color: TripDetailsTheme.terracotta, size: 32),
              ),
              const SizedBox(height: 16),

              Text(
                "Remove Member",
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),

              Text(
                "Are you sure you want to remove \"$memberName\" from this trip?",
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 24),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () => Navigator.pop(sheetCtx),
                      child: Text(
                        "Cancel",
                        style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: TripDetailsTheme.terracotta,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () async {
                        Navigator.pop(sheetCtx);
                        final res = await TripService.deleteTrip(
                          tripId: widget.tripId,
                          userId: widget.userId,
                          removeMemberId: memberId,
                        );

                        if (!mounted) return;
                        if (res["success"] == true) {
                          _refreshTrip();
                        }
                      },
                      child: Text(
                        "Remove",
                        style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _showEditTripDetailsSheet(Map<String, dynamic> trip) {
    final nameCtrl = TextEditingController(text: trip["name"] ?? "");
    final fromCtrl = TextEditingController(text: trip["fromLocation"] ?? "");
    final toCtrl = TextEditingController(text: trip["toLocation"] ?? "");
    final budgetCtrl = TextEditingController(text: trip["budget"] != null ? (trip["budget"] as num).toStringAsFixed(0) : "");

    String selectedCurrency = trip["currency"] ?? "INR";
    final List<Map<String, String>> currencies = const [
      {"code": "INR", "symbol": "₹", "label": "INR (₹)"},
      {"code": "USD", "symbol": "\$", "label": "USD (\$)"},
      {"code": "EUR", "symbol": "€", "label": "EUR (€)"},
      {"code": "GBP", "symbol": "£", "label": "GBP (£)"},
      {"code": "JPY", "symbol": "¥", "label": "JPY (¥)"},
      {"code": "AED", "symbol": "AED", "label": "AED (Dirham)"},
      {"code": "SGD", "symbol": "S\$", "label": "SGD (S\$)"},
      {"code": "CAD", "symbol": "CA\$", "label": "CAD (CA\$)"},
      {"code": "AUD", "symbol": "A\$", "label": "AUD (A\$)"},
    ];

    DateTime? startDate = trip["startDate"] != null ? DateTime.tryParse(trip["startDate"]) : null;
    DateTime? endDate = trip["endDate"] != null ? DateTime.tryParse(trip["endDate"]) : null;
    final dateFmt = DateFormat("MMM d, yyyy");

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final activeSymbol = currencies.firstWhere(
              (c) => c["code"] == selectedCurrency,
              orElse: () => {"symbol": "₹"},
            )["symbol"]!;

            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
              child: Container(
                decoration: const BoxDecoration(
                  color: TripDetailsTheme.scaffoldBg,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(28),
                    topRight: Radius.circular(28),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),

                      Text(
                        "Edit Trip Details",
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Trip Name
                      Text("Trip Name", style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: nameCtrl,
                        style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: TripDetailsTheme.darkText),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.1))),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Route (From - To)
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("From Location", style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)),
                                const SizedBox(height: 6),
                                TextField(
                                  controller: fromCtrl,
                                  style: GoogleFonts.inter(color: TripDetailsTheme.darkText),
                                  decoration: InputDecoration(
                                    filled: true,
                                    fillColor: Colors.white,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.1))),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("To Location", style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)),
                                const SizedBox(height: 6),
                                TextField(
                                  controller: toCtrl,
                                  style: GoogleFonts.inter(color: TripDetailsTheme.darkText),
                                  decoration: InputDecoration(
                                    filled: true,
                                    fillColor: Colors.white,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.1))),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Currency & Budget Row
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          SizedBox(
                            width: 110,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("Currency", style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)),
                                const SizedBox(height: 6),
                                InkWell(
                                  onTap: () {
                                    _showCurrencyPickerSheet(
                                      context,
                                      selectedCurrency,
                                      (code, symbol) {
                                        setSheetState(() => selectedCurrency = code);
                                      },
                                    );
                                  },
                                  child: Container(
                                    height: 48,
                                    padding: const EdgeInsets.symmetric(horizontal: 10),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(color: Colors.black.withValues(alpha: 0.1)),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          selectedCurrency,
                                          style: GoogleFonts.ibmPlexMono(
                                            color: TripDetailsTheme.darkText,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                        const Icon(Icons.keyboard_arrow_down_rounded, color: TripDetailsTheme.darkText, size: 18),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("Total Budget", style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)),
                                const SizedBox(height: 6),
                                TextField(
                                  controller: budgetCtrl,
                                  keyboardType: TextInputType.number,
                                  style: GoogleFonts.ibmPlexMono(fontWeight: FontWeight.bold, fontSize: 16, color: TripDetailsTheme.darkText),
                                  decoration: InputDecoration(
                                    prefixText: "$activeSymbol ",
                                    filled: true,
                                    fillColor: Colors.white,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.1))),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Dates
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () async {
                                final now = DateTime.now();
                                final p = await showDatePicker(context: context, initialDate: startDate ?? now, firstDate: now.subtract(const Duration(days: 365)), lastDate: now.add(const Duration(days: 730)));
                                if (p != null) setSheetState(() => startDate = p);
                              },
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.black.withValues(alpha: 0.1))),
                                child: Text(startDate != null ? dateFmt.format(startDate!) : "Start Date", style: GoogleFonts.inter(fontSize: 12.5, color: TripDetailsTheme.darkText)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: InkWell(
                              onTap: () async {
                                final now = DateTime.now();
                                final p = await showDatePicker(context: context, initialDate: endDate ?? startDate ?? now, firstDate: now.subtract(const Duration(days: 365)), lastDate: now.add(const Duration(days: 730)));
                                if (p != null) setSheetState(() => endDate = p);
                              },
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.black.withValues(alpha: 0.1))),
                                child: Text(endDate != null ? dateFmt.format(endDate!) : "End Date", style: GoogleFonts.inter(fontSize: 12.5, color: TripDetailsTheme.darkText)),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: TripDetailsTheme.darkSurface,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                            ),
                          ),
                          onPressed: () async {
                            final b = double.tryParse(budgetCtrl.text.trim());
                            Navigator.pop(sheetCtx);

                            final res = await TripService.updateTrip(
                              tripId: widget.tripId,
                              userId: widget.userId,
                              name: nameCtrl.text.trim(),
                              fromLocation: fromCtrl.text.trim(),
                              toLocation: toCtrl.text.trim(),
                              startDate: startDate,
                              endDate: endDate,
                              budget: b,
                              currency: selectedCurrency,
                            );

                            if (res["success"] == true) {
                              _refreshTrip();
                            }
                          },
                          child: Text("Save Trip Details", style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _confirmDeleteOrLeave(bool isOrganizer, String tripName) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return Container(
          decoration: const BoxDecoration(
            color: TripDetailsTheme.scaffoldBg,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(28),
              topRight: Radius.circular(28),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 20),

              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                ),
                child: const Icon(Icons.delete_forever_rounded, color: Color(0xFFEF4444), size: 32),
              ),
              const SizedBox(height: 16),

              Text(
                isOrganizer ? "Delete Trip" : "Leave Trip",
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),

              Text(
                isOrganizer
                    ? "Are you sure you want to permanently delete \"$tripName\"? This action cannot be undone."
                    : "Are you sure you want to leave \"$tripName\"?",
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 24),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () => Navigator.pop(sheetCtx),
                      child: Text(
                        "Cancel",
                        style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEF4444),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () async {
                        Navigator.pop(sheetCtx);
                        final res = await TripService.deleteTrip(
                          tripId: widget.tripId,
                          userId: widget.userId,
                        );

                        if (!mounted) return;
                        if (res["success"] == true) {
                          Navigator.pop(context, true);
                        }
                      },
                      child: Text(
                        isOrganizer ? "Delete" : "Leave",
                        style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _showCustomTallySheet(Map<String, dynamic> trip) {
    final double totalBudget = (trip["budget"] as num?)?.toDouble() ?? 0.0;
    final List<dynamic> members = (trip["members"] as List<dynamic>?) ?? [];
    final String symbol = trip["currencySymbol"] ?? "₹";
    final currencyFormatter = NumberFormat.currency(symbol: "$symbol ", decimalDigits: 0);

    final organizerObj = trip["organizer"];
    final String organizerId = (organizerObj is Map ? organizerObj["_id"] : organizerObj)?.toString() ?? "";

    final Map<String, TextEditingController> controllers = {};
    for (final m in members) {
      final mId = m["userId"]?.toString() ?? "";
      final currentShare = (m["shareAmount"] as num?)?.toDouble() ?? 0.0;
      controllers[mId] = TextEditingController(
        text: currentShare > 0 ? currentShare.toStringAsFixed(0) : "0",
      );
    }

    String splitUnit = "amount"; // "amount" or "percentage"

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            double currentSum = 0;
            controllers.forEach((key, ctrl) {
              currentSum += double.tryParse(ctrl.text.trim()) ?? 0.0;
            });

            final bool isPercentageMode = splitUnit == "percentage";
            final double expectedTotal = isPercentageMode ? 100.0 : totalBudget;
            final diff = expectedTotal - currentSum;
            final bool isBalanced = diff.abs() < 1.0;

            void updateOrganizerShare(String editedMemberId) {
              if (organizerId.isEmpty || !controllers.containsKey(organizerId)) return;
              if (editedMemberId == organizerId) return;

              double otherSum = 0;
              controllers.forEach((mId, ctrl) {
                if (mId != organizerId) {
                  otherSum += double.tryParse(ctrl.text.trim()) ?? 0.0;
                }
              });

              final remainingForOrganizer = expectedTotal - otherSum;
              controllers[organizerId]!.text = remainingForOrganizer >= 0
                  ? remainingForOrganizer.toStringAsFixed(isPercentageMode ? 1 : 0)
                  : "0";
            }

            void switchUnit(String newUnit) {
              if (splitUnit == newUnit) return;
              setSheetState(() {
                if (newUnit == "percentage") {
                  // Convert amounts to percentages
                  controllers.forEach((mId, ctrl) {
                    final amt = double.tryParse(ctrl.text.trim()) ?? 0.0;
                    final pct = totalBudget > 0 ? (amt / totalBudget) * 100.0 : 0.0;
                    ctrl.text = pct.toStringAsFixed(1);
                  });
                } else {
                  // Convert percentages to amounts
                  controllers.forEach((mId, ctrl) {
                    final pct = double.tryParse(ctrl.text.trim()) ?? 0.0;
                    final amt = (pct / 100.0) * totalBudget;
                    ctrl.text = amt.toStringAsFixed(0);
                  });
                }
                splitUnit = newUnit;
              });
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                decoration: const BoxDecoration(
                  color: TripDetailsTheme.scaffoldBg,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(28),
                    topRight: Radius.circular(28),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Set Custom Tally Split",
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            setSheetState(() {
                              if (isPercentageMode) {
                                final equalPct = (100.0 / members.length).toStringAsFixed(1);
                                controllers.forEach((_, c) => c.text = equalPct);
                              } else {
                                final equalVal = (totalBudget / members.length).toStringAsFixed(0);
                                controllers.forEach((_, c) => c.text = equalVal);
                              }
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: TripDetailsTheme.darkSurface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.auto_awesome_rounded, color: TripDetailsTheme.mintAccent, size: 14),
                                const SizedBox(width: 4),
                                Text(
                                  "Equalize",
                                  style: GoogleFonts.inter(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Combined Budget & Tally Sum Summary Card
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: TripDetailsTheme.darkSurface,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: isBalanced ? Colors.white.withValues(alpha: 0.2) : const Color(0xFFEF4444),
                          width: 1.2,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "TOTAL BUDGET",
                                style: GoogleFonts.ibmPlexMono(
                                  color: Colors.white54,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                currencyFormatter.format(totalBudget),
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            height: 32,
                            width: 1,
                            color: Colors.white24,
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                isPercentageMode ? "TOTAL PERCENTAGE" : "TALLY SUM",
                                style: GoogleFonts.ibmPlexMono(
                                  color: isBalanced ? TripDetailsTheme.mintAccent : const Color(0xFFEF4444),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Text(
                                    isPercentageMode
                                        ? "${currentSum.toStringAsFixed(1)}%"
                                        : currencyFormatter.format(currentSum),
                                    style: GoogleFonts.inter(
                                      color: isBalanced ? Colors.white : const Color(0xFFEF4444),
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Icon(
                                    isBalanced ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                                    color: isBalanced ? TripDetailsTheme.mintAccent : const Color(0xFFEF4444),
                                    size: 18,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Amount vs Percentage Mode Selector
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: TripDetailsTheme.darkSurface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => switchUnit("amount"),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: !isPercentageMode ? TripDetailsTheme.scaffoldBg : Colors.transparent,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Center(
                                  child: Text(
                                    "Split by Amount ($symbol)",
                                    style: GoogleFonts.inter(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => switchUnit("percentage"),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: isPercentageMode ? TripDetailsTheme.scaffoldBg : Colors.transparent,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Center(
                                  child: Text(
                                    "Split by Percentage (%)",
                                    style: GoogleFonts.inter(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.4,
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          children: members.map((m) {
                            final mId = m["userId"]?.toString() ?? "";
                            final mName = m["name"] ?? "Member";
                            final ctrl = controllers[mId]!;
                            final isOrg = mId == organizerId;

                            final calculatedAmount = isPercentageMode
                                ? (double.tryParse(ctrl.text.trim()) ?? 0.0) / 100.0 * totalBudget
                                : double.tryParse(ctrl.text.trim()) ?? 0.0;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: isOrg
                                      ? TripDetailsTheme.mintAccent.withValues(alpha: 0.5)
                                      : Colors.black.withValues(alpha: 0.08),
                                  width: isOrg ? 1.4 : 1,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.02),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: TripDetailsTheme.darkSurface,
                                    ),
                                    child: Center(
                                      child: Text(
                                        mName.isNotEmpty ? mName[0].toUpperCase() : "M",
                                        style: GoogleFonts.inter(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
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
                                                mName,
                                                style: GoogleFonts.inter(
                                                  color: TripDetailsTheme.darkText,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14.5,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (isOrg) ...[
                                              const SizedBox(width: 4),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: TripDetailsTheme.scaffoldBg.withValues(alpha: 0.1),
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  "AUTO",
                                                  style: GoogleFonts.ibmPlexMono(
                                                    color: TripDetailsTheme.scaffoldBg,
                                                    fontSize: 9,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          isPercentageMode
                                              ? "= ${currencyFormatter.format(calculatedAmount)}"
                                              : isOrg
                                                  ? "Organizer (Auto-balanced)"
                                                  : "Member Share",
                                          style: GoogleFonts.inter(
                                            color: TripDetailsTheme.textMuted,
                                            fontSize: 11.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 110,
                                    child: TextField(
                                      controller: ctrl,
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      textAlign: TextAlign.end,
                                      onChanged: (val) {
                                        setSheetState(() {
                                          updateOrganizerShare(mId);
                                        });
                                      },
                                      style: GoogleFonts.ibmPlexMono(
                                        color: TripDetailsTheme.darkText,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                      decoration: InputDecoration(
                                        prefixText: !isPercentageMode ? "$symbol " : null,
                                        suffixText: isPercentageMode ? " %" : null,
                                        prefixStyle: GoogleFonts.ibmPlexMono(
                                          color: TripDetailsTheme.textMuted,
                                          fontSize: 13.5,
                                        ),
                                        suffixStyle: GoogleFonts.ibmPlexMono(
                                          color: TripDetailsTheme.textMuted,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13.5,
                                        ),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                        filled: true,
                                        fillColor: const Color(0xFFF8FAFC),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: const BorderSide(color: TripDetailsTheme.scaffoldBg, width: 1.5),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: TripDetailsTheme.darkSurface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                          ),
                        ),
                        onPressed: () async {
                          final List<Map<String, dynamic>> customSharesList = [];
                          controllers.forEach((mId, ctrl) {
                            final rawVal = double.tryParse(ctrl.text.trim()) ?? 0.0;
                            final double shareAmt = isPercentageMode
                                ? (rawVal / 100.0) * totalBudget
                                : rawVal;

                            customSharesList.add({
                              "userId": mId,
                              "shareAmount": shareAmt,
                            });
                          });

                          Navigator.pop(sheetCtx);

                          final res = await TripService.updateTrip(
                            tripId: widget.tripId,
                            userId: widget.userId,
                            splitType: "custom",
                            customShares: customSharesList,
                          );

                          if (res["success"] == true) {
                            _refreshTrip();
                          }
                        },
                        child: Text(
                          "Save Custom Tally Split",
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TripDetailsTheme.scaffoldBg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: TripDetailsTheme.darkSurface,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: const Icon(Icons.arrow_back_rounded, color: TripDetailsTheme.mintAccent, size: 20),
          ),
          onPressed: () => Navigator.pop(context, true),
        ),
        title: Text(
          "Trip Overview",
          style: GoogleFonts.inter(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 22,
            fontStyle: FontStyle.italic,
          ),
        ),
        centerTitle: true,
        actions: [
          FutureBuilder<Map<String, dynamic>?>(
            future: _tripFuture,
            builder: (context, snapshot) {
              if (!snapshot.hasData || snapshot.data == null) return const SizedBox.shrink();
              final trip = snapshot.data!;
              final organizerObj = trip["organizer"];
              final organizerId = organizerObj is Map ? organizerObj["_id"] : organizerObj;
              final isOrganizer = organizerId?.toString() == widget.userId;

              if (!isOrganizer) return const SizedBox.shrink();

              return PopupMenuButton<String>(
                color: TripDetailsTheme.darkSurface,
                elevation: 6,
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: TripDetailsTheme.darkSurface,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                  ),
                  child: const Icon(Icons.more_vert_rounded, color: TripDetailsTheme.mintAccent, size: 20),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                ),
                onSelected: (val) async {
                  if (val == "edit") {
                    _showEditTripDetailsSheet(trip);
                  } else if (val == "toggle_status") {
                    final newStatus = trip["status"] == "completed" ? "active" : "completed";
                    final res = await TripService.updateTrip(
                      tripId: widget.tripId,
                      userId: widget.userId,
                      status: newStatus,
                    );
                    if (res["success"] == true) _refreshTrip();
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: "edit",
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.edit_rounded, color: TripDetailsTheme.mintAccent, size: 16),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          "Edit Details",
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: "toggle_status",
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: (trip["status"] == "completed" ? Colors.amber : Colors.green).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            trip["status"] == "completed" ? Icons.replay_rounded : Icons.check_circle_outline_rounded,
                            color: trip["status"] == "completed" ? Colors.amber.shade400 : Colors.green.shade400,
                            size: 16,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          trip["status"] == "completed" ? "Reopen Trip" : "End Trip",
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<Map<String, dynamic>?>(
          future: _tripFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: TripDetailsTheme.mintAccent));
            }

            final trip = snapshot.data;
            if (trip == null) {
              return Center(
                child: Text(
                  "Trip details not found.",
                  style: GoogleFonts.inter(color: Colors.white70, fontSize: 15),
                ),
              );
            }

            final name = trip["name"] ?? "Trip";
            final fromLoc = trip["fromLocation"] ?? "From";
            final toLoc = trip["toLocation"] ?? "To";
            final budget = (trip["budget"] as num?)?.toDouble() ?? 0.0;
            final symbol = trip["currencySymbol"] ?? "₹";
            final currencyFormatter = NumberFormat.currency(symbol: "$symbol ", decimalDigits: 0);
            final joinCode = trip["joinCode"] ?? "CODE";
            final splitType = trip["splitType"] ?? "equal";
            final organizerObj = trip["organizer"];
            final organizerId = organizerObj is Map ? organizerObj["_id"] : organizerObj;
            final isOrganizer = organizerId?.toString() == widget.userId;
            final members = (trip["members"] as List<dynamic>?) ?? [];
            final dateStr = _formatDateRange(trip["startDate"], trip["endDate"]);

            return SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Top Card: Banner Details
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: isOrganizer ? TripDetailsTheme.darkSurface : Colors.black.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                isOrganizer ? "ORGANIZER" : "MEMBER",
                                style: GoogleFonts.ibmPlexMono(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            
                            // Share QR Button
                            GestureDetector(
                              onTap: () => _showQrInviteSheet(joinCode, name),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: TripDetailsTheme.darkSurface,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const FaIcon(FontAwesomeIcons.qrcode, color: TripDetailsTheme.mintAccent, size: 14),
                                    const SizedBox(width: 6),
                                    Text(
                                      joinCode,
                                      style: GoogleFonts.ibmPlexMono(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        Text(
                          name,
                          style: GoogleFonts.inter(
                            color: TripDetailsTheme.darkText,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),

                        Row(
                          children: [
                            const Icon(Icons.location_on, color: TripDetailsTheme.scaffoldBg, size: 18),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                "$fromLoc ➔ $toLoc",
                                style: GoogleFonts.inter(color: TripDetailsTheme.darkText.withValues(alpha: 0.8), fontSize: 14.5),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        Divider(color: Colors.black.withValues(alpha: 0.08), height: 1),
                        const SizedBox(height: 14),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "TOTAL BUDGET",
                                  style: GoogleFonts.ibmPlexMono(color: TripDetailsTheme.textMuted, fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  currencyFormatter.format(budget),
                                  style: GoogleFonts.ibmPlexMono(color: TripDetailsTheme.darkText, fontSize: 17, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    "DATES",
                                    style: GoogleFonts.ibmPlexMono(color: TripDetailsTheme.textMuted, fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    dateStr,
                                    textAlign: TextAlign.end,
                                    style: GoogleFonts.inter(color: TripDetailsTheme.darkText, fontSize: 11.5, fontWeight: FontWeight.w600),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 2,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),

                  // 2. Budget Split Breakdown Section
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          "Budget Split Breakdown",
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                            fontStyle: FontStyle.italic,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: isOrganizer ? () => _showCustomTallySheet(trip) : null,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: TripDetailsTheme.darkSurface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                splitType == "equal" ? "Equal (${members.length}-way)" : "Custom Split",
                                style: GoogleFonts.ibmPlexMono(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (isOrganizer) ...[
                                const SizedBox(width: 4),
                                const Icon(Icons.edit_rounded, color: TripDetailsTheme.mintAccent, size: 12),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Member Shares Cards
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: members.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final m = members[index] as Map<String, dynamic>;
                      final mName = m["name"] ?? "Member";
                      final mShare = (m["shareAmount"] as num?)?.toDouble() ?? 0.0;
                      final mPct = (m["sharePercentage"] as num?)?.toDouble() ?? 0.0;
                      final mId = m["userId"]?.toString() ?? "";
                      final isMe = mId == widget.userId;

                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: TripDetailsTheme.cardBg,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: TripDetailsTheme.scaffoldBg.withValues(alpha: 0.08),
                              child: Text(
                                mName.isNotEmpty ? mName[0].toUpperCase() : "M",
                                style: GoogleFonts.inter(
                                  color: TripDetailsTheme.scaffoldBg,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),

                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        mName,
                                        style: GoogleFonts.inter(
                                          color: TripDetailsTheme.darkText,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                        ),
                                      ),
                                      if (isMe) ...[
                                        const SizedBox(width: 6),
                                        Text(
                                          "(You)",
                                          style: GoogleFonts.inter(
                                            color: TripDetailsTheme.terracotta,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    "$mPct% share",
                                    style: GoogleFonts.inter(
                                      color: TripDetailsTheme.textMuted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            Text(
                              currencyFormatter.format(mShare),
                              style: GoogleFonts.ibmPlexMono(
                                color: TripDetailsTheme.scaffoldBg,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),

                            if (isOrganizer && !isMe && trip["status"] != "completed") ...[
                              const SizedBox(width: 10),
                              GestureDetector(
                                onTap: () => _confirmRemoveMember(mId, mName),
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: TripDetailsTheme.terracotta.withValues(alpha: 0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.person_remove_rounded,
                                    color: TripDetailsTheme.terracotta,
                                    size: 16,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),

                  // Delete Trip (Organizer) or Leave Trip (Member, only if trip is active)
                  if (isOrganizer || trip["status"] != "completed") ...[
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: () => _confirmDeleteOrLeave(isOrganizer, name),
                        icon: Icon(
                          isOrganizer ? Icons.delete_outline_rounded : Icons.exit_to_app_rounded,
                          color: const Color(0xFFEF4444),
                          size: 18,
                        ),
                        label: Text(
                          isOrganizer ? "Delete Trip" : "Leave Trip",
                          style: GoogleFonts.inter(
                            color: const Color(0xFFEF4444),
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _showCurrencyPickerSheet(
    BuildContext context,
    String currentCode,
    Function(String code, String symbol) onSelect,
  ) {
    final List<Map<String, String>> currencies = const [
      {"code": "INR", "symbol": "₹", "flag": "🇮🇳", "name": "Indian Rupee"},
      {"code": "USD", "symbol": "\$", "flag": "🇺🇸", "name": "US Dollar"},
      {"code": "EUR", "symbol": "€", "flag": "🇪🇺", "name": "Euro"},
      {"code": "GBP", "symbol": "£", "flag": "🇬🇧", "name": "British Pound"},
      {"code": "JPY", "symbol": "¥", "flag": "🇯🇵", "name": "Japanese Yen"},
      {"code": "AED", "symbol": "AED", "flag": "🇦🇪", "name": "UAE Dirham"},
      {"code": "SGD", "symbol": "S\$", "flag": "🇸🇬", "name": "Singapore Dollar"},
      {"code": "CAD", "symbol": "CA\$", "flag": "🇨🇦", "name": "Canadian Dollar"},
      {"code": "AUD", "symbol": "A\$", "flag": "🇦🇺", "name": "Australian Dollar"},
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) {
        return Container(
          decoration: const BoxDecoration(
            color: TripDetailsTheme.scaffoldBg,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(28),
              topRight: Radius.circular(28),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                "Select Trip Currency",
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 14),
              Flexible(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.5,
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: currencies.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final c = currencies[index];
                      final isSelected = c["code"] == currentCode;

                      return InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () {
                          Navigator.pop(sheetCtx);
                          onSelect(c["code"]!, c["symbol"]!);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: isSelected ? TripDetailsTheme.darkSurface : Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isSelected ? Colors.white.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Row(
                            children: [
                              Text(c["flag"]!, style: const TextStyle(fontSize: 20)),
                              const SizedBox(width: 12),
                              Text(
                                "${c["code"]} (${c["symbol"]})",
                                style: GoogleFonts.ibmPlexMono(
                                  color: isSelected ? Colors.white : TripDetailsTheme.darkText,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  c["name"]!,
                                  style: GoogleFonts.inter(
                                    color: isSelected ? Colors.white70 : TripDetailsTheme.textMuted,
                                    fontSize: 13,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isSelected)
                                const Icon(Icons.check_circle_rounded, color: TripDetailsTheme.mintAccent, size: 20),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
