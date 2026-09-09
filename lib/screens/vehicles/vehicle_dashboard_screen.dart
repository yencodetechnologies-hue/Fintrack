import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../services/vehicle_service.dart';
import 'add_vehicle_screen.dart';
import 'vehicle_details_screen.dart';

class VehicleDashboardScreen extends StatefulWidget {
  final String userId;
  final String userName;

  const VehicleDashboardScreen({
    Key? key,
    required this.userId,
    required this.userName,
  }) : super(key: key);

  @override
  State<VehicleDashboardScreen> createState() => _VehicleDashboardScreenState();
}

class _VehicleDashboardScreenState extends State<VehicleDashboardScreen> {
  static const Color creamSheet = Color(0xFFFBF9F1);
  static const Color forestDark = Color(0xFF0F261C);
  static const Color darkText = Color(0xFF1E293B);
  static const Color terracotta = Color(0xFFB8452D);
  static const Color emeraldGreen = Color(0xFF10B981);

  List<dynamic> _vehicles = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchVehicles();
  }

  Future<void> _fetchVehicles() async {
    setState(() => _isLoading = true);
    final list = await VehicleService.getUserVehicles(widget.userId);
    if (mounted) {
      setState(() {
        _vehicles = list;
        _isLoading = false;
      });
    }
  }

  void _navigateToAddVehicle() async {
    final res = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddVehicleScreen(userId: widget.userId, userName: widget.userName),
      ),
    );

    if (res == true) {
      _fetchVehicles();
    }
  }

  void _navigateToDetails(String vehicleId) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VehicleDetailsScreen(vehicleId: vehicleId, userId: widget.userId),
      ),
    );
    _fetchVehicles();
  }

  void _confirmDelete(String vehicleId, String vehicleName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: creamSheet,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("Delete Vehicle?", style: GoogleFonts.fraunces(color: darkText, fontWeight: FontWeight.bold)),
        content: Text("Are you sure you want to remove '$vehicleName'?", style: GoogleFonts.inter(color: darkText)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text("Cancel", style: GoogleFonts.inter(color: darkText.withValues(alpha: 0.6))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: terracotta, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: () async {
              Navigator.pop(ctx);
              final ok = await VehicleService.deleteVehicle(vehicleId);
              if (ok) _fetchVehicles();
            },
            child: Text("Delete", style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
          "Vehicle Dashboard",
          style: GoogleFonts.fraunces(
            color: darkText,
            fontWeight: FontWeight.w600,
            fontSize: 22,
            fontStyle: FontStyle.italic,
          ),
        ),
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: forestDark,
        elevation: 4,
        onPressed: _navigateToAddVehicle,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: Text("Add Vehicle", style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: forestDark,
          onRefresh: _fetchVehicles,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Summary Banner
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: forestDark,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(color: forestDark.withValues(alpha: 0.2), blurRadius: 12, offset: const Offset(0, 4)),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("MY GARAGE", style: GoogleFonts.ibmPlexMono(color: Colors.white60, fontSize: 10, letterSpacing: 1.5)),
                          const SizedBox(height: 4),
                          Text(
                            "${_vehicles.length} Vehicles Managed",
                            style: GoogleFonts.fraunces(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), shape: BoxShape.circle),
                        child: const FaIcon(FontAwesomeIcons.gaugeHigh, color: Colors.white, size: 22),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // My Vehicles Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("My Vehicles", style: GoogleFonts.fraunces(color: darkText, fontSize: 20, fontWeight: FontWeight.bold)),
                    TextButton.icon(
                      onPressed: _navigateToAddVehicle,
                      icon: const Icon(Icons.add_circle_outline_rounded, color: terracotta, size: 18),
                      label: Text("Add New", style: GoogleFonts.inter(color: terracotta, fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Vehicles List
                if (_isLoading)
                  const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: forestDark)))
                else if (_vehicles.isEmpty)
                  _buildEmptyState()
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _vehicles.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 14),
                    itemBuilder: (context, index) {
                      final v = _vehicles[index];
                      return _buildVehicleCard(v);
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: forestDark.withValues(alpha: 0.08), shape: BoxShape.circle),
            child: const FaIcon(FontAwesomeIcons.car, color: forestDark, size: 32),
          ),
          const SizedBox(height: 16),
          Text("No Vehicles Added Yet", style: GoogleFonts.fraunces(color: darkText, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(
            "Add your Bike, Car, or Auto to track mileage, live speed, fuel usage, and range alerts.",
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(color: darkText.withValues(alpha: 0.6), fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: forestDark,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            onPressed: _navigateToAddVehicle,
            icon: const Icon(Icons.add_rounded, color: Colors.white),
            label: Text("Add Your First Vehicle", style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleCard(Map<String, dynamic> v) {
    final String id = v["_id"]?.toString() ?? "";
    final String name = v["name"] ?? "Vehicle";
    final String brand = v["brand"] ?? "";
    final String model = v["model"] ?? "";
    final String vehicleType = v["vehicleType"] ?? "car";
    final String fuelType = v["fuelType"] ?? "petrol";
    final double mileage = (v["averageMileage"] as num?)?.toDouble() ?? 15.0;
    final double tankCap = (v["tankCapacity"] as num?)?.toDouble() ?? 40.0;
    final double currentFuel = (v["currentFuelLevel"] as num?)?.toDouble() ?? 20.0;

    final double estRangeKm = currentFuel * mileage;
    final double fuelPct = tankCap > 0 ? (currentFuel / tankCap).clamp(0.0, 1.0) : 0.5;

    final isElectric = fuelType == "electric";
    final mileageUnit = isElectric ? "km/kWh" : "km/L";

    dynamic icon = vehicleType == "bike" ? FontAwesomeIcons.motorcycle : FontAwesomeIcons.car;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => _navigateToDetails(id),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.black.withValues(alpha: 0.08), width: 1.2),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4)),
            ],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: forestDark.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: FaIcon(icon, color: forestDark, size: 20),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: GoogleFonts.inter(color: darkText, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        Text(
                          "$brand $model",
                          style: GoogleFonts.inter(color: darkText.withValues(alpha: 0.6), fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),

                  // Fuel Type Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: forestDark.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      fuelType.toUpperCase(),
                      style: GoogleFonts.ibmPlexMono(color: forestDark, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 4),

                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: terracotta, size: 20),
                    onPressed: () => _confirmDelete(id, name),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 14),

              // Metrics Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("ESTIMATED SAFE RANGE", style: GoogleFonts.ibmPlexMono(color: darkText.withValues(alpha: 0.5), fontSize: 10, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text("${estRangeKm.toStringAsFixed(0)} km", style: GoogleFonts.fraunces(color: forestDark, fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text("AVG MILEAGE", style: GoogleFonts.ibmPlexMono(color: darkText.withValues(alpha: 0.5), fontSize: 10, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text("$mileage $mileageUnit", style: GoogleFonts.ibmPlexMono(color: darkText, fontSize: 13, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Fuel Gauge Progress Bar
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: fuelPct,
                  minHeight: 6,
                  backgroundColor: Colors.black.withValues(alpha: 0.06),
                  valueColor: AlwaysStoppedAnimation<Color>(fuelPct < 0.25 ? terracotta : emeraldGreen),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
