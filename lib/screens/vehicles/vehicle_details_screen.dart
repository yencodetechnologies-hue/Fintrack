import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../services/vehicle_service.dart';

class VehicleDetailsScreen extends StatefulWidget {
  final String vehicleId;
  final String userId;

  const VehicleDetailsScreen({
    super.key,
    required this.vehicleId,
    required this.userId,
  });

  @override
  State<VehicleDetailsScreen> createState() => _VehicleDetailsScreenState();
}

class _VehicleDetailsScreenState extends State<VehicleDetailsScreen> {
  static const Color creamSheet = Color(0xFF195754);
  static const Color darkSurface = Color(0xFF113F3D);
  static const Color forestDark = Color(0xFF113F3D);
  static const Color darkText = Color(0xFF1E293B);
  static const Color terracotta = Color(0xFFB8452D);
  static const Color emeraldGreen = Color(0xFF10B981);
  static const Color goldAccent = Color(0xFFD4AF37);

  Map<String, dynamic>? _vehicle;
  bool _isLoading = true;
  bool _loadFailed = false;

  // Live Ride Tracking State
  bool _isRideActive = false;
  DateTime? _rideStartTime;
  double _currentSpeedKmh = 0.0;
  double _liveDistanceKm = 0.0;
  double _liveFuelUsed = 0.0;
  Position? _lastPosition;
  StreamSubscription<Position>? _positionStreamSub;
  // true while Start ride is checking location/permission, so a double tap can't open two GPS streams
  bool _startingRide = false;
  // GPS only reports after moving ~2 m, so standing still sends nothing: this drops the speed to 0 after a quiet spell
  Timer? _speedWatchdog;
  DateTime? _lastFixAt;

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
    _speedWatchdog?.cancel();
    if (_isRideActive) WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _initNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const initSettings = InitializationSettings(android: androidSettings, iOS: iosSettings);
    await _notificationsPlugin.initialize(settings: initSettings);
  }

  /// Asks once for permission to show notifications, so the low-range alert can appear. A "no" doesn't block the ride.
  Future<void> _askNotificationPermission() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final android = _notificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        if (android != null && (await android.areNotificationsEnabled()) != true) {
          await android.requestNotificationsPermission();
        }
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        await _notificationsPlugin
            .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(alert: true, sound: true);
      }
    } catch (_) {
      // the alert is a nice-to-have; the ride still starts
    }
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
    // first load shows a spinner; later refreshes keep the current screen up
    if (_vehicle == null) setState(() => _isLoading = true);
    final vehicle = await VehicleService.getVehicleById(widget.vehicleId, widget.userId);
    if (mounted) {
      setState(() {
        if (vehicle != null) _vehicle = vehicle;
        _loadFailed = vehicle == null && _vehicle == null;
        _isLoading = false;
      });
      if (vehicle == null && _vehicle != null) _snack("Couldn't refresh. Check your connection.");
    }
  }

  void _snack(String text, {SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), action: action, duration: Duration(seconds: action == null ? 3 : 6)));
  }

  // Toggle "Start Ride"
  Future<void> _toggleRideState(bool start, {bool showSummary = true}) async {
    if (start) {
      if (_isRideActive || _startingRide) return;
      _startingRide = true;
      try {
        await _startRide();
      } finally {
        _startingRide = false;
      }
    } else {
      await _stopRide(showSummary: showSummary);
    }
  }

  Future<void> _startRide() async {
    {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _snack(
          "Location is turned off. Turn it on to track the ride.",
          action: SnackBarAction(label: "Turn on", onPressed: () => Geolocator.openLocationSettings()),
        );
        return;
      }
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

      // the low-range alert is a phone notification: ask for it now if it isn't allowed yet (#14)
      await _askNotificationPermission();
      // keep the screen awake during the ride (#13)
      WakelockPlus.enable();
      if (!mounted) return;

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
      // keeps tracking with the screen locked or the app in the background:
      // Android runs a location foreground service ("Ride in progress" notification), iOS keeps background location on
      final String rideName = _vehicle?["name"]?.toString() ?? "your vehicle";
      final LocationSettings locationSettings = defaultTargetPlatform == TargetPlatform.android
          ? AndroidSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 2, // Update every 2 meters
              intervalDuration: const Duration(seconds: 1),
              foregroundNotificationConfig: ForegroundNotificationConfig(
                notificationTitle: "Ride in progress",
                notificationText: "Tracking speed and distance for $rideName",
                notificationChannelName: "Ride tracking",
                enableWakeLock: true,
                setOngoing: true,
              ),
            )
          : defaultTargetPlatform == TargetPlatform.iOS
              ? AppleSettings(
                  accuracy: LocationAccuracy.bestForNavigation,
                  distanceFilter: 2,
                  activityType: ActivityType.automotiveNavigation,
                  pauseLocationUpdatesAutomatically: false,
                  allowBackgroundLocationUpdates: true,
                  showBackgroundLocationIndicator: true,
                )
              : const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 2);

      _positionStreamSub = Geolocator.getPositionStream(locationSettings: locationSettings).listen((Position pos) {
        if (!mounted) return;

        double addedDistanceKm = 0.0;
        double? computedKmh;

        // a rough fix (accuracy worse than 30 m) only moves the speed, never the trip distance
        final accurate = pos.accuracy > 0 && pos.accuracy <= 30;
        if (_lastPosition != null && accurate) {
          final double distMeters = Geolocator.distanceBetween(
            _lastPosition!.latitude,
            _lastPosition!.longitude,
            pos.latitude,
            pos.longitude,
          );
          if (distMeters > 1.5 && distMeters < 500) { // filter out GPS jitter & teleporting
            addedDistanceKm = distMeters / 1000.0;
          }
          final secs = pos.timestamp.difference(_lastPosition!.timestamp).inMilliseconds / 1000.0;
          if (secs > 0.5 && distMeters < 500) computedKmh = (distMeters / secs) * 3.6;
        }
        // the phone's own speed when it has one (some phones report 0 or -1), else the speed between the last two fixes
        double speedKmh = pos.speed > 0 ? pos.speed * 3.6 : (computedKmh ?? 0.0);
        if (!speedKmh.isFinite || speedKmh > 300) speedKmh = _currentSpeedKmh; // ignore an impossible spike
        _lastFixAt = DateTime.now();

        final double mileage = (_vehicle?["averageMileage"] as num?)?.toDouble() ?? 15.0;
        final double currentFuel = (_vehicle?["currentFuelLevel"] as num?)?.toDouble() ?? 20.0;
        final double lowThreshold = (_vehicle?["lowRangeThresholdKm"] as num?)?.toDouble() ?? 25.0;

        setState(() {
          _currentSpeedKmh = speedKmh;
          _liveDistanceKm += addedDistanceKm;
          _liveFuelUsed = mileage > 0 ? (_liveDistanceKm / mileage) : 0.0;
          if (accurate || _lastPosition == null) _lastPosition = pos;
        });

        // Check remaining safe range notification
        final double remFuel = _mathMax(0.0, currentFuel - _liveFuelUsed);
        final double remRangeKm = remFuel * mileage;

        if (remRangeKm <= lowThreshold) {
          _triggerLowRangeNotification(_vehicle?["name"] ?? "Vehicle", remRangeKm);
        }
      }, onError: (Object e) {
        // GPS stopped (location switched off mid-ride, permission removed…): end the ride and keep what was tracked
        if (!mounted || !_isRideActive) return;
        _snack("Location stopped working, so the ride was ended.");
        _toggleRideState(false);
      });

      // no GPS update for 4 s means we're standing still: show 0 instead of the last speed
      _lastFixAt = DateTime.now();
      _speedWatchdog?.cancel();
      _speedWatchdog = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || !_isRideActive) return;
        final last = _lastFixAt;
        if (_currentSpeedKmh > 0 && last != null && DateTime.now().difference(last).inSeconds >= 4) {
          setState(() => _currentSpeedKmh = 0.0);
        }
      });
    }
  }

  Future<void> _stopRide({bool showSummary = true}) async {
    {
      if (!_isRideActive) return;
      WakelockPlus.disable();
      _speedWatchdog?.cancel();
      _speedWatchdog = null;
      _positionStreamSub?.cancel();

      final DateTime endTime = DateTime.now();
      final double distance = _liveDistanceKm;
      final double fuelUsed = _liveFuelUsed;
      final DateTime startTime = _rideStartTime ?? endTime;
      // at least one second, so a very short ride can't divide by zero
      final int seconds = endTime.difference(startTime).inSeconds < 1 ? 1 : endTime.difference(startTime).inSeconds;
      final double avgSpeed = distance > 0 ? distance / (seconds / 3600.0) : 0.0;

      // the ride is over: clear its live numbers so the fuel isn't taken off twice once the server's figures load
      setState(() {
        _isRideActive = false;
        _positionStreamSub = null;
        _currentSpeedKmh = 0.0;
        _liveDistanceKm = 0.0;
        _liveFuelUsed = 0.0;
        _lastPosition = null;
      });

      if (distance > 0.01) {
        final saved = await _saveRide(startTime, endTime, distance, fuelUsed, avgSpeed);
        if (mounted && showSummary) _showRideSummaryDialog(distance, fuelUsed, avgSpeed, saved: saved);
      } else {
        _snack("Ride stopped. It was too short to save.");
      }
    }
  }

  /// Sends a finished ride to the server; on failure offers Retry with the same numbers.
  Future<bool> _saveRide(DateTime start, DateTime end, double distance, double fuelUsed, double avgSpeed) async {
    final res = await VehicleService.saveRide(
      vehicleId: widget.vehicleId,
      userId: widget.userId,
      startTime: start,
      endTime: end,
      distanceKm: distance,
      fuelUsed: fuelUsed,
      avgSpeedKmh: avgSpeed.isFinite ? avgSpeed : 0.0,
    );
    if (!mounted) return false;
    if (res["success"] == true) {
      _fetchVehicleDetails();
      return true;
    }
    _snack(
      "Couldn't save the ride: ${res["message"] ?? "check your connection"}",
      action: SnackBarAction(label: "Retry", onPressed: () => _saveRide(start, end, distance, fuelUsed, avgSpeed)),
    );
    return false;
  }

  /// Leaving while a ride is running: stop and save it, or discard it, or keep riding.
  Future<void> _confirmLeaveDuringRide() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("Ride in progress", style: GoogleFonts.inter(color: darkText, fontWeight: FontWeight.bold)),
        content: Text(
          "Tracking stops when you leave this screen. Stop and save the ride first?",
          style: GoogleFonts.inter(color: darkText.withValues(alpha: 0.7), fontSize: 14),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, "stay"), child: const Text("Keep riding")),
          TextButton(onPressed: () => Navigator.pop(ctx, "discard"), child: Text("Discard", style: TextStyle(color: terracotta))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: forestDark),
            onPressed: () => Navigator.pop(ctx, "save"),
            child: Text("Stop & save", style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (!mounted || choice == null || choice == "stay") return;
    if (choice == "save") {
      await _toggleRideState(false, showSummary: false);
    } else {
      _positionStreamSub?.cancel();
      _speedWatchdog?.cancel();
      WakelockPlus.disable();
      setState(() {
        _isRideActive = false;
        _positionStreamSub = null;
        _liveDistanceKm = 0.0;
        _liveFuelUsed = 0.0;
        _currentSpeedKmh = 0.0;
      });
    }
    if (mounted) Navigator.pop(context);
  }

  static double _mathMax(double a, double b) => a > b ? a : b;

  void _showRideSummaryDialog(double distKm, double fuelUsed, double avgSpeed, {bool saved = true}) {
    final String symbol = _vehicle?["fuelType"] == "electric" ? "kWh" : "L";
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            const Icon(Icons.flag_rounded, color: forestDark, size: 24),
            const SizedBox(width: 8),
            Text("Ride Summary", style: GoogleFonts.inter(color: darkText, fontWeight: FontWeight.bold)),
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
            if (!saved) ...[
              const SizedBox(height: 14),
              Text("Not saved yet: tap Retry on the message below to save it.",
                  style: GoogleFonts.inter(color: terracotta, fontSize: 13, fontWeight: FontWeight.w600)),
            ],
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

  // ---- Edit vehicle (#5) incl. setting fuel level and odometer by hand (#6) ----
  void _showEditSheet() {
    final v = _vehicle!;
    final isElectric = v["fuelType"] == "electric";
    String fmt(dynamic n) {
      final d = (n as num?)?.toDouble() ?? 0;
      return d == d.roundToDouble() ? d.toStringAsFixed(0) : d.toStringAsFixed(1);
    }

    final nameCtrl = TextEditingController(text: v["name"]?.toString() ?? "");
    final mileageCtrl = TextEditingController(text: fmt(v["averageMileage"]));
    final tankCtrl = TextEditingController(text: fmt(v["tankCapacity"]));
    final fuelCtrl = TextEditingController(text: (((v["currentFuelLevel"] as num?) ?? 0).toDouble()).toStringAsFixed(1));
    final alertCtrl = TextEditingController(text: fmt(v["lowRangeThresholdKm"]));
    final odoCtrl = TextEditingController(text: fmt(v["odometerKm"]));
    var saving = false;
    String? error;

    InputDecoration deco(String label, IconData icon, {String? suffix}) => InputDecoration(
          labelText: label,
          suffixText: suffix,
          prefixIcon: Icon(icon, color: forestDark),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          filled: true,
          fillColor: Colors.white,
          isDense: true,
        );
    const numKb = TextInputType.numberWithOptions(decimal: true);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
          child: Container(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(sheetCtx).size.height * 0.9),
            decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: darkText.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)))),
                const SizedBox(height: 16),
                Text("Edit vehicle", style: GoogleFonts.inter(color: darkText, fontSize: 20, fontWeight: FontWeight.bold)),
                Text("${v["brand"] ?? ""} ${v["model"] ?? ""} · ${(v["fuelType"] ?? "").toString().toUpperCase()}",
                    style: GoogleFonts.inter(color: darkText.withValues(alpha: 0.55), fontSize: 13)),
                const SizedBox(height: 16),
                TextField(controller: nameCtrl, textCapitalization: TextCapitalization.words, decoration: deco("Nickname", Icons.badge_outlined)),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: TextField(controller: mileageCtrl, keyboardType: numKb, decoration: deco("Mileage", Icons.speed_rounded, suffix: isElectric ? "km/kWh" : "km/L"))),
                  const SizedBox(width: 10),
                  Expanded(child: TextField(controller: tankCtrl, keyboardType: numKb, decoration: deco(isElectric ? "Battery" : "Tank", Icons.inventory_2_outlined, suffix: isElectric ? "kWh" : "L"))),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: TextField(controller: fuelCtrl, keyboardType: numKb, decoration: deco(isElectric ? "Charge now" : "Fuel now", isElectric ? Icons.bolt_rounded : Icons.local_gas_station_rounded, suffix: isElectric ? "kWh" : "L"))),
                  const SizedBox(width: 10),
                  Expanded(child: TextField(controller: alertCtrl, keyboardType: numKb, decoration: deco("Low-range alert", Icons.notifications_active_outlined, suffix: "km"))),
                ]),
                const SizedBox(height: 10),
                TextField(controller: odoCtrl, keyboardType: numKb, decoration: deco("Odometer", Icons.av_timer_rounded, suffix: "km")),
                const SizedBox(height: 6),
                Text("Set fuel and odometer to what your vehicle shows right now; rides and refuels continue from there.",
                    style: GoogleFonts.inter(color: darkText.withValues(alpha: 0.5), fontSize: 12)),
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(error!, style: GoogleFonts.inter(color: terracotta, fontSize: 13, fontWeight: FontWeight.w600)),
                ],
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: forestDark, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                    onPressed: saving
                        ? null
                        : () async {
                            final mileage = double.tryParse(mileageCtrl.text.trim());
                            final tank = double.tryParse(tankCtrl.text.trim());
                            final fuel = double.tryParse(fuelCtrl.text.trim());
                            final alert = double.tryParse(alertCtrl.text.trim());
                            final odo = double.tryParse(odoCtrl.text.trim());
                            String? problem;
                            if (nameCtrl.text.trim().isEmpty) {
                              problem = "Enter a nickname";
                            } else if (mileage == null || mileage <= 0) {
                              problem = "Mileage must be more than 0";
                            } else if (tank == null || tank <= 0) {
                              problem = isElectric ? "Battery size must be more than 0" : "Tank size must be more than 0";
                            } else if (fuel == null || fuel < 0 || fuel > tank) {
                              problem = isElectric ? "Charge must be between 0 and the battery size" : "Fuel must be between 0 and the tank size";
                            } else if (alert == null || alert < 0) {
                              problem = "Low-range alert can't be negative";
                            } else if (odo == null || odo < 0) {
                              problem = "Odometer can't be negative";
                            }
                            if (problem != null) {
                              setSheet(() => error = problem);
                              return;
                            }
                            setSheet(() {
                              saving = true;
                              error = null;
                            });
                            final res = await VehicleService.updateVehicle(widget.vehicleId, widget.userId, {
                              "name": nameCtrl.text.trim(),
                              "averageMileage": mileage,
                              "tankCapacity": tank,
                              "currentFuelLevel": fuel,
                              "lowRangeThresholdKm": alert,
                              "odometerKm": odo,
                            });
                            if (res["success"] == true) {
                              if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                              if (mounted) setState(() => _vehicle = Map<String, dynamic>.from(res["vehicle"]));
                              _snack("Vehicle updated");
                            } else if (sheetCtx.mounted) {
                              setSheet(() {
                                saving = false;
                                error = "Couldn't save: ${res["message"] ?? "check your connection"}";
                              });
                            }
                          },
                    child: Text(saving ? "Saving…" : "Save changes", style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  /// Mileage measured from refuels that have an odometer reading (#10): km between the first and last such refuel,
  /// divided by the fuel added after the first one (assumes each refuel fills the tank). null when there aren't two yet.
  ({double kmPerUnit, double km, double units, int fills})? _measuredMileage() {
    final logs = List<Map<String, dynamic>>.from(_vehicle?["refuelLogs"] ?? const [])
        .where((l) => ((l["odometer"] as num?) ?? 0) > 0)
        .toList()
      ..sort((a, b) => DateTime.parse(a["date"].toString()).compareTo(DateTime.parse(b["date"].toString())));
    if (logs.length < 2) return null;
    final km = ((logs.last["odometer"] as num) - (logs.first["odometer"] as num)).toDouble();
    final units = logs.skip(1).fold<double>(0, (sum, l) => sum + ((l["fuelAdded"] as num?) ?? 0).toDouble());
    if (km <= 0 || units <= 0) return null;
    return (kmPerUnit: km / units, km: km, units: units, fills: logs.length);
  }

  Future<void> _useMeasuredMileage(double value) async {
    final res = await VehicleService.updateVehicle(widget.vehicleId, widget.userId, {"averageMileage": double.parse(value.toStringAsFixed(1))});
    if (!mounted) return;
    if (res["success"] == true) {
      setState(() => _vehicle = Map<String, dynamic>.from(res["vehicle"]));
      _snack("Mileage set to ${value.toStringAsFixed(1)}");
    } else {
      _snack("Couldn't update mileage: ${res["message"] ?? "check your connection"}");
    }
  }

  Widget _sectionCard({required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.black.withValues(alpha: 0.06))),
        child: child,
      );

  /// Refuel history (#7): totals, then each refuel newest first.
  Widget _refuelHistory(String fuelUnit) {
    final logs = List<Map<String, dynamic>>.from(_vehicle?["refuelLogs"] ?? const [])
      ..sort((a, b) => DateTime.parse(b["date"].toString()).compareTo(DateTime.parse(a["date"].toString())));
    final isElectric = fuelUnit == "kWh";
    if (logs.isEmpty) {
      return _sectionCard(
        child: Center(
          child: Text(isElectric ? "No recharges logged yet." : "No refuels logged yet.", style: GoogleFonts.inter(color: darkText.withValues(alpha: 0.5), fontSize: 13)),
        ),
      );
    }
    final now = DateTime.now();
    double spentAll = 0, spentMonth = 0, unitsAll = 0;
    for (final l in logs) {
      final cost = ((l["cost"] as num?) ?? 0).toDouble();
      spentAll += cost;
      unitsAll += ((l["fuelAdded"] as num?) ?? 0).toDouble();
      final d = DateTime.parse(l["date"].toString()).toLocal();
      if (d.year == now.year && d.month == now.month) spentMonth += cost;
    }
    final money = NumberFormat.currency(locale: "en_IN", symbol: "₹", decimalDigits: 0);
    Widget total(String label, String value) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: GoogleFonts.inter(color: darkText.withValues(alpha: 0.5), fontSize: 11, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(value, style: GoogleFonts.inter(color: darkText, fontSize: 16, fontWeight: FontWeight.w800)),
          ]),
        );
    return _sectionCard(
      child: Column(children: [
        Row(children: [
          total("This month", money.format(spentMonth)),
          total("All time", money.format(spentAll)),
          total(isElectric ? "Charged" : "Filled", "${unitsAll.toStringAsFixed(1)} $fuelUnit"),
        ]),
        const SizedBox(height: 10),
        const Divider(height: 1),
        for (final l in logs.take(20)) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: forestDark.withValues(alpha: 0.08), shape: BoxShape.circle),
                child: Icon(isElectric ? Icons.bolt_rounded : Icons.local_gas_station_rounded, color: forestDark, size: 16),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text("${((l["fuelAdded"] as num?) ?? 0).toStringAsFixed(1)} $fuelUnit",
                      style: GoogleFonts.inter(color: darkText, fontWeight: FontWeight.bold, fontSize: 14)),
                  Text(
                    "${DateFormat("EEE, d MMM y · h:mm a").format(DateTime.parse(l["date"].toString()).toLocal())}"
                    "${((l["odometer"] as num?) ?? 0) > 0 ? " · ${((l["odometer"] as num)).toStringAsFixed(0)} km" : ""}",
                    style: GoogleFonts.inter(color: darkText.withValues(alpha: 0.55), fontSize: 12),
                  ),
                ]),
              ),
              Text(((l["cost"] as num?) ?? 0) > 0 ? money.format((l["cost"] as num)) : "—",
                  style: GoogleFonts.ibmPlexMono(color: darkText, fontWeight: FontWeight.bold, fontSize: 14)),
            ]),
          ),
        ],
      ]),
    );
  }

  // Refuel Log Bottom Sheet Modal
  void _showRefuelModal() {
    final fuelCtrl = TextEditingController();
    final costCtrl = TextEditingController();
    final odoCtrl = TextEditingController();

    final isElectric = _vehicle?["fuelType"] == "electric";
    final unit = isElectric ? "kWh" : "Liters";

    var saving = false;
    String? error;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(builder: (sheetCtx, setSheet) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
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
                style: GoogleFonts.inter(color: darkText, fontSize: 20, fontWeight: FontWeight.bold),
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
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(error!, style: GoogleFonts.inter(color: terracotta, fontSize: 13, fontWeight: FontWeight.w600)),
              ],
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: forestDark,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: saving
                      ? null
                      : () async {
                          final fuelVal = double.tryParse(fuelCtrl.text.trim()) ?? 0.0;
                          final costVal = double.tryParse(costCtrl.text.trim()) ?? 0.0;
                          final odoVal = double.tryParse(odoCtrl.text.trim());

                          if (fuelVal <= 0) {
                            setSheet(() => error = "Enter how much ${isElectric ? "charge" : "fuel"} you added (more than 0)");
                            return;
                          }
                          if (costVal < 0 || (odoVal != null && odoVal < 0)) {
                            setSheet(() => error = "Cost and odometer can't be negative");
                            return;
                          }
                          setSheet(() {
                            saving = true;
                            error = null;
                          });

                          final res = await VehicleService.addRefuelLog(
                            vehicleId: widget.vehicleId,
                            userId: widget.userId,
                            fuelAdded: fuelVal,
                            cost: costVal,
                            odometer: odoVal,
                          );

                          if (res["success"] == true) {
                            if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                            _snack(isElectric ? "Recharge saved" : "Refuel saved");
                            _fetchVehicleDetails();
                          } else if (sheetCtx.mounted) {
                            setSheet(() {
                              saving = false;
                              error = "Couldn't save: ${res["message"] ?? "check your connection"}";
                            });
                          }
                        },
                  child: Text(saving ? "Saving…" : "Save Entry", style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loadFailed && _vehicle == null) {
      return Scaffold(
        backgroundColor: creamSheet,
        appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, foregroundColor: Colors.white),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.cloud_off_rounded, color: Colors.white70, size: 44),
              const SizedBox(height: 12),
              Text("Couldn't load this vehicle", style: GoogleFonts.inter(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text("Check your connection. If it was deleted, go back to your vehicles.",
                  textAlign: TextAlign.center, style: GoogleFonts.inter(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: forestDark),
                onPressed: _fetchVehicleDetails,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text("Retry"),
              ),
            ]),
          ),
        ),
      );
    }
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


    return PopScope(
      canPop: !_isRideActive,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeaveDuringRide();
      },
      child: Scaffold(
      backgroundColor: creamSheet,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: darkSurface,
              shape: BoxShape.circle,
              border: Border.all(color: emeraldGreen.withValues(alpha: 0.3)),
            ),
            child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
          ),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Text(
          name,
          style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 20),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: _isRideActive ? "Stop the ride to edit" : "Edit vehicle",
            icon: Icon(Icons.edit_rounded, color: _isRideActive ? Colors.white38 : Colors.white),
            onPressed: _isRideActive ? null : _showEditSheet,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: _fetchVehicleDetails,
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: forestDark,
          onRefresh: _fetchVehicleDetails,
          child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
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
                              style: GoogleFonts.inter(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
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

              // 2. FUTURISTIC E-BIKE SPEEDOMETER & RIDE DASHBOARD
              FuturisticSpeedometerDashboard(
                isRideActive: _isRideActive,
                currentSpeed: _currentSpeedKmh,
                liveDistanceKm: _liveDistanceKm,
                liveFuelUsed: _liveFuelUsed,
                fuelUnit: fuelUnit,
                fuelPct: fuelPct,
                vehicleName: name,
                rideStartTime: _rideStartTime,
                maxSpeed: vehicleType == "bike" ? 120 : 180,
                onToggleRide: (val) => _toggleRideState(val),
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
                        style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                  ),
                ],
              ),
              // measured mileage from refuels (#10)
              Builder(builder: (_) {
                final m = _measuredMileage();
                if (m == null) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      "Tip: add the odometer reading when you ${isElectric ? "recharge" : "refuel"} to a full ${isElectric ? "battery" : "tank"}. After two, your real mileage shows here.",
                      style: GoogleFonts.inter(color: Colors.white60, fontSize: 12),
                    ),
                  );
                }
                final off = (m.kmPerUnit - mileage).abs() >= 0.5;
                return Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _sectionCard(
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text("MEASURED MILEAGE", style: GoogleFonts.ibmPlexMono(color: darkText.withValues(alpha: 0.5), fontSize: 10, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 2),
                          Text("${m.kmPerUnit.toStringAsFixed(1)} $mileageUnit", style: GoogleFonts.inter(color: forestDark, fontSize: 20, fontWeight: FontWeight.w800)),
                          Text("${m.km.toStringAsFixed(0)} km on ${m.units.toStringAsFixed(1)} $fuelUnit · ${m.fills} fills · you set ${mileage.toStringAsFixed(1)}",
                              style: GoogleFonts.inter(color: darkText.withValues(alpha: 0.55), fontSize: 12)),
                        ]),
                      ),
                      if (off && !_isRideActive)
                        TextButton(onPressed: () => _useMeasuredMileage(m.kmPerUnit), child: const Text("Use this")),
                    ]),
                  ),
                );
              }),
              const SizedBox(height: 24),

              // 4. Ride History Section
              Text("Recent Rides", style: GoogleFonts.inter(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
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
                    final started = DateTime.tryParse(r["startTime"]?.toString() ?? "")?.toLocal();
                    final ended = DateTime.tryParse(r["endTime"]?.toString() ?? "")?.toLocal();
                    final mins = started != null && ended != null ? ended.difference(started).inMinutes : null;
                    final duration = mins == null ? "" : mins >= 60 ? " · ${mins ~/ 60} h ${mins % 60} min" : " · ${mins < 1 ? "<1" : mins} min";
                    final when = started == null ? "" : DateFormat("EEE, d MMM · h:mm a").format(started);

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
                                  Text("Avg ${speed.toStringAsFixed(1)} km/h$duration", style: GoogleFonts.inter(color: darkText.withValues(alpha: 0.6), fontSize: 12)),
                                  if (when.isNotEmpty) Text(when, style: GoogleFonts.inter(color: darkText.withValues(alpha: 0.45), fontSize: 11)),
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

              // 5. Refuel / recharge history with cost (#7)
              const SizedBox(height: 24),
              Text(isElectric ? "Recharge history" : "Refuel history", style: GoogleFonts.inter(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              _refuelHistory(fuelUnit),
            ],
          ),
        ),
        ),
      ),
    ),
    );
  }
}

// ============================================================================
// RIDE PANEL: live speed gauge, trip / time / fuel used, fuel level, Start-Stop
// ============================================================================

class FuturisticSpeedometerDashboard extends StatefulWidget {
  final bool isRideActive;
  final double currentSpeed;
  final double liveDistanceKm;
  final double liveFuelUsed;
  final String fuelUnit;
  final double fuelPct;
  final String vehicleName;
  final DateTime? rideStartTime;
  /// top of the dial in km/h (bikes 120, cars 180)
  final double maxSpeed;
  final ValueChanged<bool> onToggleRide;

  const FuturisticSpeedometerDashboard({
    super.key,
    required this.isRideActive,
    required this.currentSpeed,
    required this.liveDistanceKm,
    required this.liveFuelUsed,
    required this.fuelUnit,
    required this.fuelPct,
    required this.vehicleName,
    required this.onToggleRide,
    this.rideStartTime,
    this.maxSpeed = 120,
  });

  @override
  State<FuturisticSpeedometerDashboard> createState() => _FuturisticSpeedometerDashboardState();
}

class _FuturisticSpeedometerDashboardState extends State<FuturisticSpeedometerDashboard> {
  static const Color panel = Color(0xFF0E2F2D);
  static const Color mint = Color(0xFF10B981);
  static const Color warn = Color(0xFFF87171);

  // ticks once a second while riding, so the ride time counts up
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _syncClock();
  }

  @override
  void didUpdateWidget(FuturisticSpeedometerDashboard old) {
    super.didUpdateWidget(old);
    if (old.isRideActive != widget.isRideActive) _syncClock();
  }

  void _syncClock() {
    _clock?.cancel();
    _clock = widget.isRideActive ? Timer.periodic(const Duration(seconds: 1), (_) => mounted ? setState(() {}) : null) : null;
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  String get _elapsed {
    final start = widget.rideStartTime;
    if (!widget.isRideActive || start == null) return "00:00";
    final d = DateTime.now().difference(start);
    final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
    String two(int n) => n.toString().padLeft(2, "0");
    return h > 0 ? "$h:${two(m)}:${two(s)}" : "${two(m)}:${two(s)}";
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.isRideActive;
    final speed = active ? widget.currentSpeed : 0.0;
    final lowFuel = widget.fuelPct < 0.25;

    Widget stat(String label, String value, IconData icon) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(14)),
            child: Column(children: [
              Icon(icon, size: 16, color: Colors.white54),
              const SizedBox(height: 4),
              Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.ibmPlexMono(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              Text(label, style: GoogleFonts.inter(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w600)),
            ]),
          ),
        );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: (active ? mint : Colors.white).withValues(alpha: active ? 0.45 : 0.10)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Column(children: [
        // header: status + Start/Stop
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: (active ? mint : Colors.white).withValues(alpha: active ? 0.16 : 0.08),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 7, height: 7, decoration: BoxDecoration(color: active ? mint : Colors.white38, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(active ? "RIDE LIVE" : "READY",
                  style: GoogleFonts.inter(color: active ? mint : Colors.white60, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
            ]),
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: () => widget.onToggleRide(!active),
            style: FilledButton.styleFrom(
              backgroundColor: active ? warn : mint,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: const StadiumBorder(),
            ),
            icon: Icon(active ? Icons.stop_rounded : Icons.play_arrow_rounded, size: 18),
            label: Text(active ? "Stop ride" : "Start ride", style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13)),
          ),
        ]),
        const SizedBox(height: 8),

        // speed gauge
        // the dial must get the full width (a bare Stack would shrink to the number and squash the arc)
        SizedBox(
          width: double.infinity,
          height: 200,
          child: Stack(alignment: Alignment.center, children: [
            Positioned.fill(
              child: CustomPaint(painter: _GaugePainter(value: (speed / widget.maxSpeed).clamp(0.0, 1.0), active: active, ticks: (widget.maxSpeed / 20).round())),
            ),
            Column(mainAxisSize: MainAxisSize.min, children: [
              Text(speed.toStringAsFixed(0),
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 56, fontWeight: FontWeight.w800, height: 1)),
              const SizedBox(height: 4),
              Text("km/h", style: GoogleFonts.inter(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
            ]),
            // scale ends, under the open bottom of the dial
            Positioned(
              bottom: 6,
              left: 0,
              right: 0,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text("0", style: GoogleFonts.ibmPlexMono(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold)),
                const SizedBox(width: 104),
                Text(widget.maxSpeed.toStringAsFixed(0), style: GoogleFonts.ibmPlexMono(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold)),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 12),

        // trip / time / fuel used
        Row(children: [
          stat("Trip", "${widget.liveDistanceKm.toStringAsFixed(2)} km", Icons.route_rounded),
          const SizedBox(width: 8),
          stat("Ride time", _elapsed, Icons.timer_outlined),
          const SizedBox(width: 8),
          stat("Used", "${widget.liveFuelUsed.toStringAsFixed(2)} ${widget.fuelUnit}", Icons.local_gas_station_rounded),
        ]),
        const SizedBox(height: 14),

        // fuel level
        Row(children: [
          Text(widget.fuelUnit == "kWh" ? "Charge" : "Fuel", style: GoogleFonts.inter(color: Colors.white60, fontSize: 12, fontWeight: FontWeight.w600)),
          const Spacer(),
          Text("${(widget.fuelPct * 100).toStringAsFixed(0)}%",
              style: GoogleFonts.ibmPlexMono(color: lowFuel ? warn : Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: widget.fuelPct.clamp(0.0, 1.0),
            minHeight: 8,
            backgroundColor: Colors.white.withValues(alpha: 0.10),
            valueColor: AlwaysStoppedAnimation<Color>(lowFuel ? warn : mint),
          ),
        ),
        if (!active) ...[
          const SizedBox(height: 10),
          Text("Tap Start ride to track speed and distance with GPS.",
              textAlign: TextAlign.center, style: GoogleFonts.inter(color: Colors.white38, fontSize: 12)),
        ],
      ]),
    );
  }
}

/// Speedometer dial: a 270° arc open at the bottom, tick marks every 20 km/h, and a coloured fill up to the speed.
class _GaugePainter extends CustomPainter {
  final double value; // 0..1
  final bool active;
  final int ticks; // one mark every 20 km/h
  _GaugePainter({required this.value, required this.active, this.ticks = 6});

  static const double _start = math.pi * 0.75; // bottom-left
  static const double _sweep = math.pi * 1.5; // round to bottom-right

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 12.0;
    final radius = math.min(size.width, size.height) / 2 - stroke;
    final center = Offset(size.width / 2, size.height / 2 + 6);
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawArc(
      rect,
      _start,
      _sweep,
      false,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.08)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );

    // ticks every 20 km/h, inside the arc
    final tick = Paint()
      ..color = Colors.white.withValues(alpha: active ? 0.35 : 0.2)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i <= ticks; i++) {
      final a = _start + _sweep * i / ticks;
      final outer = radius - stroke / 2 - 6;
      final inner = outer - 8;
      canvas.drawLine(
        center + Offset(inner * math.cos(a), inner * math.sin(a)),
        center + Offset(outer * math.cos(a), outer * math.sin(a)),
        tick,
      );
    }

    if (value > 0) {
      canvas.drawArc(
        rect,
        _start,
        _sweep * value,
        false,
        Paint()
          ..shader = SweepGradient(
            startAngle: _start,
            endAngle: _start + _sweep,
            colors: const [Color(0xFF10B981), Color(0xFF2DD4BF), Color(0xFFF59E0B)],
            tileMode: TileMode.clamp,
          ).createShader(rect)
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.value != value || old.active != active || old.ticks != ticks;
}
