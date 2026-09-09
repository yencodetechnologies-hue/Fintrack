import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../../services/vehicle_service.dart';

class VehicleDetailsScreen extends StatefulWidget {
  final String vehicleId;
  final String userId;

  const VehicleDetailsScreen({
    Key? key,
    required this.vehicleId,
    required this.userId,
  }) : super(key: key);

  @override
  State<VehicleDetailsScreen> createState() => _VehicleDetailsScreenState();
}

class _VehicleDetailsScreenState extends State<VehicleDetailsScreen> {
  static const Color creamSheet = Color(0xFFFBF9F1);
  static const Color forestDark = Color(0xFF0F261C);
  static const Color darkText = Color(0xFF1E293B);
  static const Color terracotta = Color(0xFFB8452D);
  static const Color emeraldGreen = Color(0xFF10B981);
  static const Color goldAccent = Color(0xFFD4AF37);

  Map<String, dynamic>? _vehicle;
  bool _isLoading = true;

  // Live Ride Tracking State
  bool _isRideActive = false;
  DateTime? _rideStartTime;
  double _currentSpeedKmh = 0.0;
  double _liveDistanceKm = 0.0;
  double _liveFuelUsed = 0.0;
  Position? _lastPosition;
  StreamSubscription<Position>? _positionStreamSub;

  // Local Notifications Plugin
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  bool _hasNotifiedLowRange = false;

  @override
  void initState() {
    super.initState();
    _initNotifications();
    _fetchVehicleDetails();
  }

  @override
  void dispose() {
    _positionStreamSub?.cancel();
    super.dispose();
  }

  Future<void> _initNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const initSettings = InitializationSettings(android: androidSettings, iOS: iosSettings);
    await _notificationsPlugin.initialize(settings: initSettings);
  }

  Future<void> _triggerLowRangeNotification(String vehicleName, double remainingRangeKm) async {
    if (_hasNotifiedLowRange) return;
    _hasNotifiedLowRange = true;

    const androidDetails = AndroidNotificationDetails(
      'vehicle_low_range_channel',
      'Vehicle Range Alerts',
      channelDescription: 'Alerts when fuel or battery range is running low',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    const notificationDetails = NotificationDetails(android: androidDetails, iOS: DarwinNotificationDetails());

    await _notificationsPlugin.show(
      id: 888,
      title: "⚠️ Low Range Alert",
      body: "You're approaching your safe range limit for $vehicleName (${remainingRangeKm.toStringAsFixed(0)} km remaining). Refuel/recharge soon!",
      notificationDetails: notificationDetails,
    );
  }

  Future<void> _fetchVehicleDetails() async {
    setState(() => _isLoading = true);
    final vehicle = await VehicleService.getVehicleById(widget.vehicleId);
    if (mounted) {
      setState(() {
        _vehicle = vehicle;
        _isLoading = false;
      });
    }
  }

  // Toggle "Start Ride"
  Future<void> _toggleRideState(bool start) async {
    if (start) {
      // Request Location Permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Location permission required for live speedometer")),
            );
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Location permission denied permanently. Please enable in Settings.")),
          );
        }
        return;
      }

      setState(() {
        _isRideActive = true;
        _rideStartTime = DateTime.now();
        _currentSpeedKmh = 0.0;
        _liveDistanceKm = 0.0;
        _liveFuelUsed = 0.0;
        _lastPosition = null;
        _hasNotifiedLowRange = false;
      });

      // Start listening to GPS updates
      const locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 2, // Update every 2 meters
      );

      _positionStreamSub = Geolocator.getPositionStream(locationSettings: locationSettings).listen((Position pos) {
        if (!mounted) return;

        double speedKmh = pos.speed > 0 ? (pos.speed * 3.6) : 0.0;
        double addedDistanceKm = 0.0;

        if (_lastPosition != null) {
          double distMeters = Geolocator.distanceBetween(
            _lastPosition!.latitude,
            _lastPosition!.longitude,
            pos.latitude,
            pos.longitude,
          );
          if (distMeters > 1.5 && distMeters < 500) { // filter out GPS jitter & teleporting
            addedDistanceKm = distMeters / 1000.0;
          }
        }

        final double mileage = (_vehicle?["averageMileage"] as num?)?.toDouble() ?? 15.0;
        final double currentFuel = (_vehicle?["currentFuelLevel"] as num?)?.toDouble() ?? 20.0;
        final double lowThreshold = (_vehicle?["lowRangeThresholdKm"] as num?)?.toDouble() ?? 25.0;

        setState(() {
          _currentSpeedKmh = speedKmh;
          _liveDistanceKm += addedDistanceKm;
          _liveFuelUsed = mileage > 0 ? (_liveDistanceKm / mileage) : 0.0;
          _lastPosition = pos;
        });

        // Check remaining safe range notification
        final double remFuel = _mathMax(0.0, currentFuel - _liveFuelUsed);
        final double remRangeKm = remFuel * mileage;

        if (remRangeKm <= lowThreshold) {
          _triggerLowRangeNotification(_vehicle?["name"] ?? "Vehicle", remRangeKm);
        }
      });
    } else {
      // Stop Ride
      _positionStreamSub?.cancel();

      final DateTime endTime = DateTime.now();
      final double distance = _liveDistanceKm;
      final double fuelUsed = _liveFuelUsed;
      final double avgSpeed = distance > 0 && _rideStartTime != null
          ? (distance / (endTime.difference(_rideStartTime!).inSeconds / 3600.0))
          : 0.0;

      setState(() => _isRideActive = false);

      if (distance > 0.01) {
        // Save Ride to Backend
        final res = await VehicleService.saveRide(
          vehicleId: widget.vehicleId,
          startTime: _rideStartTime ?? DateTime.now(),
          endTime: endTime,
          distanceKm: distance,
          fuelUsed: fuelUsed,
          avgSpeedKmh: avgSpeed,
        );

        if (res["success"] == true) {
          _fetchVehicleDetails();
        }

        // Show Ride Summary Dialog
        if (mounted) {
          _showRideSummaryDialog(distance, fuelUsed, avgSpeed);
        }
      }
    }
  }

  static double _mathMax(double a, double b) => a > b ? a : b;

  void _showRideSummaryDialog(double distKm, double fuelUsed, double avgSpeed) {
    final String symbol = _vehicle?["fuelType"] == "electric" ? "kWh" : "L";
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: creamSheet,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            const Icon(Icons.flag_rounded, color: forestDark, size: 24),
            const SizedBox(width: 8),
            Text("Ride Summary", style: GoogleFonts.fraunces(color: darkText, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _summaryRow("Distance Covered", "${distKm.toStringAsFixed(2)} km"),
            const SizedBox(height: 10),
            _summaryRow("Estimated Fuel Used", "${fuelUsed.toStringAsFixed(2)} $symbol"),
            const SizedBox(height: 10),
            _summaryRow("Average Speed", "${avgSpeed.toStringAsFixed(1)} km/h"),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: forestDark,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: Text("Done", style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String val) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: GoogleFonts.inter(color: darkText.withValues(alpha: 0.7), fontSize: 13)),
        Text(val, style: GoogleFonts.ibmPlexMono(color: darkText, fontWeight: FontWeight.bold, fontSize: 14)),
      ],
    );
  }

  // Refuel Log Bottom Sheet Modal
  void _showRefuelModal() {
    final fuelCtrl = TextEditingController();
    final costCtrl = TextEditingController();
    final odoCtrl = TextEditingController();

    final isElectric = _vehicle?["fuelType"] == "electric";
    final unit = isElectric ? "kWh" : "Liters";

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: creamSheet,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
                    color: darkText.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                isElectric ? "Log Recharge ⚡" : "Log Refuel ⛽",
                style: GoogleFonts.fraunces(color: darkText, fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: fuelCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: GoogleFonts.ibmPlexMono(fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  labelText: "Amount Added ($unit)",
                  prefixIcon: Icon(isElectric ? Icons.bolt_rounded : Icons.local_gas_station_rounded, color: forestDark),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: costCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: GoogleFonts.ibmPlexMono(fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  labelText: "Cost (₹)",
                  prefixIcon: const Icon(Icons.currency_rupee_rounded, color: forestDark),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: odoCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: GoogleFonts.ibmPlexMono(fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  labelText: "Odometer Reading (km) - Optional",
                  prefixIcon: const Icon(Icons.speed_rounded, color: forestDark),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: forestDark,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () async {
                    final fuelVal = double.tryParse(fuelCtrl.text.trim()) ?? 0.0;
                    final costVal = double.tryParse(costCtrl.text.trim()) ?? 0.0;
                    final odoVal = double.tryParse(odoCtrl.text.trim());

                    if (fuelVal <= 0) return;

                    Navigator.pop(sheetCtx);

                    final res = await VehicleService.addRefuelLog(
                      vehicleId: widget.vehicleId,
                      fuelAdded: fuelVal,
                      cost: costVal,
                      odometer: odoVal,
                    );

                    if (res["success"] == true) {
                      _fetchVehicleDetails();
                    }
                  },
                  child: Text("Save Entry", style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _vehicle == null) {
      return Scaffold(
        backgroundColor: creamSheet,
        appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
        body: const Center(child: CircularProgressIndicator(color: forestDark)),
      );
    }

    final String name = _vehicle!["name"] ?? "Vehicle";
    final String brand = _vehicle!["brand"] ?? "";
    final String model = _vehicle!["model"] ?? "";
    final String vehicleType = _vehicle!["vehicleType"] ?? "car";
    final String fuelType = _vehicle!["fuelType"] ?? "petrol";
    final double mileage = (_vehicle!["averageMileage"] as num?)?.toDouble() ?? 15.0;
    final double tankCap = (_vehicle!["tankCapacity"] as num?)?.toDouble() ?? 40.0;
    final double currentFuelRaw = (_vehicle!["currentFuelLevel"] as num?)?.toDouble() ?? 20.0;
    final double lowThreshold = (_vehicle!["lowRangeThresholdKm"] as num?)?.toDouble() ?? 25.0;

    // Adjust fuel level during active ride
    final double effectiveFuel = _mathMax(0.0, currentFuelRaw - _liveFuelUsed);
    final double fuelPct = tankCap > 0 ? (effectiveFuel / tankCap).clamp(0.0, 1.0) : 0.5;
    final double remainingRangeKm = effectiveFuel * mileage;

    final isElectric = fuelType == "electric";
    final fuelUnit = isElectric ? "kWh" : "L";
    final mileageUnit = isElectric ? "km/kWh" : "km/L";

    dynamic typeIcon = vehicleType == "bike" ? FontAwesomeIcons.motorcycle : FontAwesomeIcons.car;


    return Scaffold(
      backgroundColor: creamSheet,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: forestDark.withValues(alpha: 0.06),
              shape: BoxShape.circle,
              border: Border.all(color: forestDark.withValues(alpha: 0.12)),
            ),
            child: const Icon(Icons.arrow_back_rounded, color: darkText, size: 20),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          name,
          style: GoogleFonts.fraunces(color: darkText, fontWeight: FontWeight.w600, fontSize: 20),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: darkText),
            onPressed: _fetchVehicleDetails,
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Vehicle Overview Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: forestDark,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(color: forestDark.withValues(alpha: 0.25), blurRadius: 16, offset: const Offset(0, 6)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: const BoxDecoration(color: Colors.white24, shape: BoxShape.circle),
                              child: FaIcon(typeIcon, color: Colors.white, size: 16),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: goldAccent, borderRadius: BorderRadius.circular(12)),
                              child: Text(
                                fuelType.toUpperCase(),
                                style: GoogleFonts.ibmPlexMono(color: darkText, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          "$brand $model",
                          style: GoogleFonts.ibmPlexMono(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("ESTIMATED SAFE RANGE", style: GoogleFonts.ibmPlexMono(color: Colors.white60, fontSize: 10, letterSpacing: 1)),
                            const SizedBox(height: 4),
                            Text(
                              "${remainingRangeKm.toStringAsFixed(0)} km",
                              style: GoogleFonts.fraunces(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text("AVG MILEAGE", style: GoogleFonts.ibmPlexMono(color: Colors.white60, fontSize: 10)),
                            const SizedBox(height: 2),
                            Text("$mileage $mileageUnit", style: GoogleFonts.ibmPlexMono(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Fuel Level Progress Gauge
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                        value: fuelPct,
                        minHeight: 8,
                        backgroundColor: Colors.white24,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          remainingRangeKm <= lowThreshold ? terracotta : emeraldGreen,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Fuel: ${effectiveFuel.toStringAsFixed(1)} / $tankCap $fuelUnit",
                          style: GoogleFonts.ibmPlexMono(color: Colors.white70, fontSize: 11),
                        ),
                        Text(
                          "${(fuelPct * 100).toStringAsFixed(0)}%",
                          style: GoogleFonts.ibmPlexMono(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // 2. LIVE SPEEDOMETER & RIDE DASHBOARD
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: _isRideActive ? emeraldGreen : Colors.black.withValues(alpha: 0.08), width: _isRideActive ? 2 : 1),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 12, offset: const Offset(0, 4))],
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: _isRideActive ? emeraldGreen : Colors.grey,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _isRideActive ? "LIVE RIDE ACTIVE" : "RIDE DASHBOARD",
                              style: GoogleFonts.ibmPlexMono(
                                color: _isRideActive ? emeraldGreen : darkText,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),

                        // START / STOP RIDE TOGGLE SWITCH
                        Switch(
                          value: _isRideActive,
                          activeThumbColor: emeraldGreen,
                          onChanged: (val) => _toggleRideState(val),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // LIVE SPEEDOMETER DISPLAY
                    Center(
                      child: Column(
                        children: [
                          Text(
                            _isRideActive ? _currentSpeedKmh.toStringAsFixed(0) : "0",
                            style: GoogleFonts.fraunces(
                              color: forestDark,
                              fontSize: 54,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            "KM / H",
                            style: GoogleFonts.ibmPlexMono(
                              color: darkText.withValues(alpha: 0.5),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 12),

                    // Running Ride Stats Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildLiveStatColumn("TRIP DISTANCE", "${_liveDistanceKm.toStringAsFixed(2)} km"),
                        Container(width: 1, height: 30, color: Colors.black12),
                        _buildLiveStatColumn("EST. FUEL USED", "${_liveFuelUsed.toStringAsFixed(2)} $fuelUnit"),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // 3. Quick Action Buttons (Refuel / Recharge & Specs)
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: forestDark,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: _showRefuelModal,
                      icon: Icon(isElectric ? Icons.bolt_rounded : Icons.local_gas_station_rounded, color: Colors.white, size: 18),
                      label: Text(
                        isElectric ? "Log Recharge" : "Log Refuel",
                        style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // 4. Ride History Section
              Text("Recent Rides", style: GoogleFonts.fraunces(color: darkText, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),

              if ((_vehicle!["rideHistory"] as List<dynamic>?) == null || (_vehicle!["rideHistory"] as List<dynamic>).isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
                  ),
                  child: Center(
                    child: Text(
                      "No rides logged yet. Turn ON 'Start Ride' to track live!",
                      style: GoogleFonts.inter(color: darkText.withValues(alpha: 0.5), fontSize: 13),
                    ),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: (_vehicle!["rideHistory"] as List<dynamic>).length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (ctx, idx) {
                    final rideList = (_vehicle!["rideHistory"] as List<dynamic>).reversed.toList();
                    final r = rideList[idx];
                    final dist = (r["distanceKm"] as num?)?.toDouble() ?? 0.0;
                    final used = (r["fuelUsed"] as num?)?.toDouble() ?? 0.0;
                    final speed = (r["avgSpeedKmh"] as num?)?.toDouble() ?? 0.0;

                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(color: forestDark.withValues(alpha: 0.08), shape: BoxShape.circle),
                                child: const Icon(Icons.directions_run_rounded, color: forestDark, size: 18),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("${dist.toStringAsFixed(2)} km Ride", style: GoogleFonts.inter(color: darkText, fontWeight: FontWeight.bold, fontSize: 14)),
                                  Text("Avg Speed: ${speed.toStringAsFixed(1)} km/h", style: GoogleFonts.inter(color: darkText.withValues(alpha: 0.6), fontSize: 12)),
                                ],
                              ),
                            ],
                          ),
                          Text("-${used.toStringAsFixed(2)} $fuelUnit", style: GoogleFonts.ibmPlexMono(color: terracotta, fontWeight: FontWeight.bold, fontSize: 13)),
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

  Widget _buildLiveStatColumn(String title, String val) {
    return Column(
      children: [
        Text(title, style: GoogleFonts.ibmPlexMono(color: darkText.withValues(alpha: 0.5), fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(val, style: GoogleFonts.inter(color: forestDark, fontSize: 15, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
