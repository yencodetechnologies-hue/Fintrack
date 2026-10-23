import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../services/trip_service.dart';

class CreateTripScreen extends StatefulWidget {
  final String userId;
  final String userName;

  const CreateTripScreen({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<CreateTripScreen> createState() => _CreateTripScreenState();
}

class _CreateTripScreenState extends State<CreateTripScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _fromController = TextEditingController();
  final _toController = TextEditingController();
  final _budgetController = TextEditingController();

  DateTime? _startDate;
  DateTime? _endDate;
  String _splitType = "equal";
  String _selectedCurrency = "INR";
  bool _isLoading = false;

  final List<Map<String, String>> _currencies = const [
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

  Map<String, dynamic>? _createdTrip;

  @override
  void dispose() {
    _nameController.dispose();
    _fromController.dispose();
    _toController.dispose();
    _budgetController.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool isStart) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? (_startDate ?? now) : (_endDate ?? _startDate ?? now),
      firstDate: now.subtract(const Duration(days: 30)),
      lastDate: now.add(const Duration(days: 730)),
    );

    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
          if (_endDate != null && _endDate!.isBefore(_startDate!)) {
            _endDate = _startDate;
          }
        } else {
          _endDate = picked;
        }
      });
    }
  }

  Future<void> _handleCreate() async {
    if (!_formKey.currentState!.validate()) return;

    final budget = double.tryParse(_budgetController.text.trim());
    if (budget == null || budget <= 0) {
      _showSnackBar("Please enter a valid budget amount");
      return;
    }

    setState(() => _isLoading = true);

    try {
      final res = await TripService.createTrip(
        userId: widget.userId,
        name: _nameController.text.trim(),
        fromLocation: _fromController.text.trim(),
        toLocation: _toController.text.trim(),
        startDate: _startDate,
        endDate: _endDate,
        budget: budget,
        currency: _selectedCurrency,
        splitType: _splitType,
      );

      if (!mounted) return;

      if (res["success"] == true && res["trip"] != null) {
        setState(() {
          _createdTrip = res["trip"] as Map<String, dynamic>;
        });
      } else {
        _showSnackBar(res["message"] ?? "Failed to create trip");
      }
    } catch (e) {
      if (mounted) _showSnackBar("Error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.inter(color: Colors.white)),
        backgroundColor: const Color(0xFF113F3D),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const Color scaffoldBg = Color(0xFF195754);
    const Color darkSurface = Color(0xFF113F3D);
    const Color mintAccent = Color(0xFF10B981);
    const Color darkText = Color(0xFF1E293B);
    const Color terracotta = Color(0xFFB8452D);
    const Color textMuted = Color(0xFF6B7280);

    final dateFmt = DateFormat("MMM d, yyyy");

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: darkSurface,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
          ),
          onPressed: () => Navigator.pop(context, _createdTrip != null),
        ),
        title: Text(
          "Create New Trip",
          style: GoogleFonts.inter(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 22,
            fontStyle: FontStyle.italic,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
          child: _createdTrip != null
              ? _buildSuccessView(darkSurface, darkText, terracotta, textMuted, mintAccent)
              : Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Form Container Card
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.03),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Trip Name
                            _buildLabel("Trip Name"),
                            const SizedBox(height: 5),
                            TextFormField(
                              controller: _nameController,
                              style: GoogleFonts.inter(color: darkText, fontWeight: FontWeight.bold, fontSize: 13.5),
                              decoration: _inputDeco("e.g. Goa Beach Trip, Manali Trek", prefixIcon: Icons.flight_takeoff_rounded),
                              validator: (v) => (v == null || v.trim().isEmpty) ? "Enter trip name" : null,
                            ),
                            const SizedBox(height: 12),

                            // Location: From -> To
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _buildLabel("From Location"),
                                      const SizedBox(height: 5),
                                      TextFormField(
                                        controller: _fromController,
                                        style: GoogleFonts.inter(color: darkText, fontSize: 13),
                                        decoration: _inputDeco("e.g. Mumbai", prefixIcon: Icons.near_me_rounded),
                                        validator: (v) => (v == null || v.trim().isEmpty) ? "Required" : null,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _buildLabel("To Location"),
                                      const SizedBox(height: 5),
                                      TextFormField(
                                        controller: _toController,
                                        style: GoogleFonts.inter(color: darkText, fontSize: 13),
                                        decoration: _inputDeco("e.g. Goa", prefixIcon: Icons.location_on_rounded),
                                        validator: (v) => (v == null || v.trim().isEmpty) ? "Required" : null,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // Dates Pickers
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _buildLabel("Start Date"),
                                      const SizedBox(height: 5),
                                      InkWell(
                                        onTap: () => _pickDate(true),
                                        borderRadius: BorderRadius.circular(12),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF8FAFC),
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
                                          ),
                                          child: Row(
                                            children: [
                                              const Icon(Icons.calendar_month_rounded, size: 16, color: scaffoldBg),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Text(
                                                  _startDate != null ? dateFmt.format(_startDate!) : "Select Date",
                                                  style: GoogleFonts.inter(
                                                    color: _startDate != null ? darkText : textMuted,
                                                    fontSize: 12,
                                                    fontWeight: _startDate != null ? FontWeight.bold : FontWeight.normal,
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
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
                                      _buildLabel("End Date"),
                                      const SizedBox(height: 5),
                                      InkWell(
                                        onTap: () => _pickDate(false),
                                        borderRadius: BorderRadius.circular(12),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF8FAFC),
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
                                          ),
                                          child: Row(
                                            children: [
                                              const Icon(Icons.calendar_month_rounded, size: 16, color: scaffoldBg),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Text(
                                                  _endDate != null ? dateFmt.format(_endDate!) : "Select Date",
                                                  style: GoogleFonts.inter(
                                                    color: _endDate != null ? darkText : textMuted,
                                                    fontSize: 12,
                                                    fontWeight: _endDate != null ? FontWeight.bold : FontWeight.normal,
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // Budget & Currency Input
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                SizedBox(
                                  width: 95,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _buildLabel("Currency"),
                                      const SizedBox(height: 5),
                                      InkWell(
                                        onTap: () {
                                          _showCurrencyPickerSheet(
                                            context,
                                            _selectedCurrency,
                                            (code, symbol) {
                                              setState(() => _selectedCurrency = code);
                                            },
                                          );
                                        },
                                        child: Container(
                                          height: 42,
                                          padding: const EdgeInsets.symmetric(horizontal: 10),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF8FAFC),
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
                                          ),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                _selectedCurrency,
                                                style: GoogleFonts.ibmPlexMono(
                                                  color: darkText,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13.5,
                                                ),
                                              ),
                                              const Icon(Icons.keyboard_arrow_down_rounded, color: darkText, size: 18),
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
                                      _buildLabel("Total Estimated Budget"),
                                      const SizedBox(height: 5),
                                      TextFormField(
                                        controller: _budgetController,
                                        keyboardType: TextInputType.number,
                                        style: GoogleFonts.ibmPlexMono(
                                          color: darkText,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                        ),
                                        decoration: _inputDeco(
                                          "e.g. 25000",
                                          prefix: "${_currencies.firstWhere((c) => c['code'] == _selectedCurrency)['symbol']} ",
                                        ),
                                        validator: (v) => (v == null || v.trim().isEmpty) ? "Enter budget" : null,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),

                            // Budget Split Type
                            _buildLabel("Budget Split Method"),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => setState(() => _splitType = "equal"),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                      decoration: BoxDecoration(
                                        color: _splitType == "equal" ? scaffoldBg : const Color(0xFFF8FAFC),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: _splitType == "equal" ? scaffoldBg : Colors.black.withValues(alpha: 0.08),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.pie_chart_rounded,
                                            size: 15,
                                            color: _splitType == "equal" ? mintAccent : textMuted,
                                          ),
                                          const SizedBox(width: 5),
                                          Text(
                                            "Equal Split",
                                            style: GoogleFonts.inter(
                                              color: _splitType == "equal" ? Colors.white : darkText,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12.5,
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
                                    onTap: () => setState(() => _splitType = "custom"),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                      decoration: BoxDecoration(
                                        color: _splitType == "custom" ? scaffoldBg : const Color(0xFFF8FAFC),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: _splitType == "custom" ? scaffoldBg : Colors.black.withValues(alpha: 0.08),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.tune_rounded,
                                            size: 15,
                                            color: _splitType == "custom" ? mintAccent : textMuted,
                                          ),
                                          const SizedBox(width: 5),
                                          Text(
                                            "Custom Split",
                                            style: GoogleFonts.inter(
                                              color: _splitType == "custom" ? Colors.white : darkText,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Submit Button
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: darkSurface,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                            ),
                            elevation: 3,
                            shadowColor: Colors.black.withValues(alpha: 0.2),
                          ),
                          onPressed: _isLoading ? null : _handleCreate,
                          child: _isLoading
                              ? const CircularProgressIndicator(color: mintAccent)
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.auto_awesome_rounded, color: mintAccent, size: 20),
                                    const SizedBox(width: 8),
                                    Text(
                                      "Create Trip & Generate Code",
                                      style: GoogleFonts.inter(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildSuccessView(Color darkSurface, Color darkText, Color terracotta, Color textMuted, Color mintAccent) {
    final joinCode = _createdTrip!["joinCode"] as String;
    final tripName = _createdTrip!["name"] as String;

    return Column(
      children: [
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: darkSurface,
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Icon(Icons.check_circle_rounded, color: mintAccent, size: 32),
        ),
        const SizedBox(height: 10),
        Text(
          "Trip Created Successfully!",
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          "Share the 6-digit Trip Code or QR code with your friends to let them join \"$tripName\".",
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(color: Colors.white70, fontSize: 12.5),
        ),
        const SizedBox(height: 18),

        // QR Code Container
        Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              QrImageView(
                data: joinCode,
                version: QrVersions.auto,
                size: 130.0,
                eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF195754)),
                dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Color(0xFF195754)),
              ),
              const SizedBox(height: 10),
              Text(
                "TRIP CODE",
                style: GoogleFonts.ibmPlexMono(color: textMuted, fontSize: 10, letterSpacing: 2),
              ),
              const SizedBox(height: 2),
              SelectableText(
                joinCode,
                style: GoogleFonts.ibmPlexMono(
                  color: const Color(0xFF195754),
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 3,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        SizedBox(
          width: double.infinity,
          height: 46,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: darkSurface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
              ),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              "Go to Saved Trips",
              style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.inter(
        color: const Color(0xFF1E293B),
        fontWeight: FontWeight.w700,
        fontSize: 13.5,
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
            color: Color(0xFF195754),
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
                            color: isSelected ? const Color(0xFF113F3D) : Colors.white,
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
                                  color: isSelected ? Colors.white : const Color(0xFF1E293B),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  c["name"]!,
                                  style: GoogleFonts.inter(
                                    color: isSelected ? Colors.white70 : const Color(0xFF6B7280),
                                    fontSize: 13,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isSelected)
                                const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 20),
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

  InputDecoration _inputDeco(String hint, {String? prefix, IconData? prefixIcon}) {
    return InputDecoration(
      prefixIcon: prefixIcon != null
          ? Icon(prefixIcon, color: const Color(0xFF6B7280), size: 18)
          : null,
      prefixText: prefix,
      prefixStyle: GoogleFonts.ibmPlexMono(color: const Color(0xFF1E293B), fontWeight: FontWeight.bold, fontSize: 15),
      hintText: hint,
      hintStyle: GoogleFonts.inter(color: const Color(0xFF6B7280).withValues(alpha: 0.5), fontSize: 12.5),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
        borderSide: const BorderSide(color: Color(0xFF195754), width: 1.5),
      ),
    );
  }
}
