import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/currency_service.dart';
import '../../utils/currency_converter.dart';
import 'currency_picker_sheet.dart';
import 'rate_history_card.dart';

class CurrencyExchangeScreen extends StatefulWidget {
  const CurrencyExchangeScreen({super.key});

  @override
  State<CurrencyExchangeScreen> createState() => _CurrencyExchangeScreenState();
}

class _CurrencyExchangeScreenState extends State<CurrencyExchangeScreen>
    with SingleTickerProviderStateMixin {
  // FinTrack Vintage Deep Forest Theme
  static const Color darkTeal = Color(0xFF195754);
  static const Color darkSurface = Color(0xFF113F3D);
  static const Color deeperSurface = Color(0xFF0C2E2C);
  static const Color darkText = Color(0xFF1B2A2F);
  static const Color textMuted = Color(0xFF64748B);
  static const Color mintAccent = Color(0xFF10B981);
  static const Color goldAccent = Color(0xFFD4AF37);
  static const Color warmAmber = Color(0xFFD97706);

  final TextEditingController _amountCtrl = TextEditingController(text: "1");
  final FocusNode _amountFocusNode = FocusNode();

  String _fromCode = "USD";
  String _toCode = "INR";

  bool _isLoading = true;
  String? _errorMessage;
  CurrencyRatesResult? _ratesResult;

  late final AnimationController _swapAnimController;

  // Comparison currencies to show in the live grid
  static const List<String> _comparisonCurrencies = [
    "INR",
    "EUR",
    "GBP",
    "AED",
    "USD",
    "JPY",
    "CAD",
    "AUD",
    "SGD",
  ];

  @override
  void initState() {
    super.initState();
    _swapAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _amountCtrl.addListener(_onAmountChanged);
    _initAndLoadRates();
  }

  @override
  void dispose() {
    _swapAnimController.dispose();
    _amountCtrl.removeListener(_onAmountChanged);
    _amountCtrl.dispose();
    _amountFocusNode.dispose();
    super.dispose();
  }

  void _onAmountChanged() {
    setState(() {});
  }

  Future<void> _initAndLoadRates() async {
    final savedPair = await CurrencyService.getSelectedPair();
    if (mounted) {
      setState(() {
        _fromCode = savedPair["from"] ?? "USD";
        _toCode = savedPair["to"] ?? "INR";
      });
    }
    await _loadRates(force: false);
  }

  Future<void> _loadRates({bool force = false}) async {
    if (!mounted) return;
    setState(() {
      _isLoading = _ratesResult == null;
      _errorMessage = null;
    });

    try {
      final res = await CurrencyService.getRates(force: force);
      if (!mounted) return;

      setState(() {
        _ratesResult = res;
        _isLoading = false;
        _errorMessage = null;
      });

      if (res.rateLimited && force && mounted) {
        _showToast("Rates are already up to date (refreshed within the hour).");
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        if (_ratesResult == null) {
          _errorMessage = "Unable to load exchange rates. Check your internet connection.";
        }
      });
    }
  }

  void _swapCurrencies() {
    HapticFeedback.mediumImpact();
    _swapAnimController.forward(from: 0.0);
    setState(() {
      final temp = _fromCode;
      _fromCode = _toCode;
      _toCode = temp;
    });
    CurrencyService.saveSelectedPair(_fromCode, _toCode);
  }

  Future<void> _pickCurrency(bool isFrom) async {
    final current = isFrom ? _fromCode : _toCode;
    final available = _ratesResult?.rates.keys.toList() ?? kCurrenciesMap.keys.toList();

    final selected = await CurrencyPickerSheet.show(
      context: context,
      selectedCode: current,
      availableCodes: available,
    );

    if (selected != null && selected != current && mounted) {
      setState(() {
        if (isFrom) {
          _fromCode = selected;
        } else {
          _toCode = selected;
        }
      });
      CurrencyService.saveSelectedPair(_fromCode, _toCode);
    }
  }

  void _setPresetAmount(String val) {
    HapticFeedback.selectionClick();
    _amountCtrl.text = val;
    _amountCtrl.selection = TextSelection.fromPosition(
      TextPosition(offset: _amountCtrl.text.length),
    );
  }

  double _getParsedAmount() {
    final text = _amountCtrl.text.replaceAll(',', '').trim();
    if (text.isEmpty) return 0.0;
    return double.tryParse(text) ?? 0.0;
  }

  void _showToast(String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.inter(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
        ),
        backgroundColor: darkSurface,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: darkTeal,
      body: SafeArea(
        child: Column(
          children: [
            // 1. Executive Top Header
            _buildExecutiveHeader(),

            // 2. Main Scrollable Content
            Expanded(
              child: _buildBody(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExecutiveHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: darkSurface,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
              ),
              child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
            ),
            onPressed: () => Navigator.maybePop(context),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: goldAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      "GLOBAL REFERENCE RATES",
                      style: GoogleFonts.ibmPlexMono(
                        color: goldAccent,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  "Currency Exchange",
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: "Refresh rates",
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: darkSurface,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
              ),
              child: const Icon(Icons.refresh_rounded, color: Colors.white, size: 19),
            ),
            onPressed: () => _loadRates(force: true),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: goldAccent),
      );
    }

    if (_errorMessage != null && _ratesResult == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: darkSurface,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                ),
                child: const Icon(Icons.cloud_off_rounded, color: Colors.white70, size: 36),
              ),
              const SizedBox(height: 18),
              Text(
                "Exchange Rates Unavailable",
                style: GoogleFonts.inter(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(color: Colors.white.withValues(alpha: 0.7), fontSize: 14),
              ),
              const SizedBox(height: 22),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: goldAccent,
                  foregroundColor: deeperSurface,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () => _loadRates(force: true),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text("Retry", style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      );
    }

    final rates = _ratesResult?.rates ?? const <String, double>{};
    final amount = _getParsedAmount();
    final converted = convert(amount: amount, from: _fromCode, to: _toCode, rates: rates);
    final unit = unitRate(from: _fromCode, to: _toCode, rates: rates);
    final inverseUnit = unitRate(from: _toCode, to: _fromCode, rates: rates);

    final fromInfo = getCurrencyInfo(_fromCode);
    final toInfo = getCurrencyInfo(_toCode);

    return RefreshIndicator(
      color: mintAccent,
      backgroundColor: Colors.white,
      onRefresh: () => _loadRates(force: true),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 36),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Offline Warning Notice
            if (_ratesResult?.isOffline == true) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: warmAmber.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: warmAmber.withValues(alpha: 0.45)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.cloud_off_rounded, color: Color(0xFFFBBF24), size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "Offline · showing rates from ${_ratesResult?.lastUpdateDate}",
                        style: GoogleFonts.inter(
                          color: const Color(0xFFFDE68A),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Seamless Interconnected Converter Card
            _buildUnifiedConverterCard(fromInfo, toInfo, converted),
            const SizedBox(height: 14),

            // Quick Amount Presets
            _buildQuickAmountPresets(),
            const SizedBox(height: 20),

            // Live Rate Summary & Timestamp Card
            _buildRateSummaryCard(unit, inverseUnit),
            const SizedBox(height: 24),

            // Historical Rate Chart
            RateHistoryCard(
              from: _fromCode,
              to: _toCode,
            ),
            const SizedBox(height: 24),

            // Popular Multi-Currency Comparison Grid
            _buildComparisonSection(amount, rates),
            const SizedBox(height: 28),

            // Attribution Footer
            Text(
              "Rates: ExchangeRate-API · History: fawazahmed0 currency-api",
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: Colors.white.withValues(alpha: 0.65),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "Daily reference rates · Not for trading or commercial settlement",
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 10,
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  /// The unified, interconnected converter card
  Widget _buildUnifiedConverterCard(
    CurrencyInfo fromInfo,
    CurrencyInfo toInfo,
    double? converted,
  ) {
    final convertedStr = converted != null ? formatAmount(converted) : "---";

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Column(
            children: [
              // ── TOP SECTION: FROM ──
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "YOU SEND",
                          style: GoogleFonts.ibmPlexMono(
                            color: textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.1,
                          ),
                        ),
                        _buildSelectorPill(fromInfo, () => _pickCurrency(true)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          fromInfo.symbol,
                          style: GoogleFonts.inter(
                            color: textMuted,
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _amountCtrl,
                            focusNode: _amountFocusNode,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                            ],
                            style: GoogleFonts.inter(
                              color: darkText,
                              fontSize: 34,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                            ),
                            decoration: InputDecoration(
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                              hintText: "0.00",
                              hintStyle: GoogleFonts.inter(
                                color: textMuted.withValues(alpha: 0.35),
                                fontSize: 34,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                        if (_amountCtrl.text.isNotEmpty && _amountCtrl.text != "1")
                          IconButton(
                            icon: const Icon(Icons.cancel_rounded, color: textMuted, size: 20),
                            onPressed: () {
                              _amountCtrl.text = "1";
                              _amountCtrl.selection = TextSelection.fromPosition(
                                TextPosition(offset: _amountCtrl.text.length),
                              );
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      fromInfo.name,
                      style: GoogleFonts.inter(
                        color: textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              // Divider between the two halves
              Divider(
                height: 1,
                thickness: 1,
                color: Colors.black.withValues(alpha: 0.08),
              ),

              // ── BOTTOM SECTION: TO ──
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(26)),
                ),
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "YOU RECEIVE",
                          style: GoogleFonts.ibmPlexMono(
                            color: textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.1,
                          ),
                        ),
                        _buildSelectorPill(toInfo, () => _pickCurrency(false)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          toInfo.symbol,
                          style: GoogleFonts.inter(
                            color: mintAccent,
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: convertedStr));
                              _showToast("Copied $convertedStr to clipboard");
                            },
                            child: Text(
                              convertedStr,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                color: darkText,
                                fontSize: 34,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: "Copy result",
                          icon: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.copy_rounded, color: darkText, size: 16),
                          ),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: convertedStr));
                            _showToast("Copied $convertedStr to clipboard");
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      toInfo.name,
                      style: GoogleFonts.inter(
                        color: textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // ── Centered Floating Interconnected Swap Button ──
          Positioned(
            child: RotationTransition(
              turns: Tween(begin: 0.0, end: 0.5).animate(
                CurvedAnimation(parent: _swapAnimController, curve: Curves.easeInOutBack),
              ),
              child: Material(
                color: deeperSurface,
                shape: const CircleBorder(),
                elevation: 4,
                shadowColor: Colors.black.withValues(alpha: 0.3),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _swapCurrencies,
                  child: Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2.5),
                    ),
                    child: const Center(
                      child: FaIcon(
                        FontAwesomeIcons.arrowRightArrowLeft,
                        color: Colors.white,
                        size: 15,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectorPill(CurrencyInfo info, VoidCallback onTap) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black.withValues(alpha: 0.09)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(info.flag, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 7),
              Text(
                info.code,
                style: GoogleFonts.inter(
                  color: darkText,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.keyboard_arrow_down_rounded, color: textMuted, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  /// Row of quick amount preset buttons: 10, 50, 100, 500, 1000
  Widget _buildQuickAmountPresets() {
    final presets = ["10", "50", "100", "500", "1,000", "5,000"];

    return Row(
      children: presets.map((p) {
        final clean = p.replaceAll(',', '');
        final isSelected = _amountCtrl.text == clean;

        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2.5),
            child: Material(
              color: isSelected ? goldAccent : darkSurface,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => _setPresetAmount(clean),
                child: Container(
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected ? goldAccent : Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Text(
                    p,
                    style: GoogleFonts.inter(
                      color: isSelected ? deeperSurface : Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  /// Live Rate Summary Card
  Widget _buildRateSummaryCard(double? unit, double? inverseUnit) {
    final dateStr = _ratesResult?.lastUpdateDate ?? "Today";
    final unitStr = unit != null ? formatRate(unit) : "---";
    final invStr = inverseUnit != null ? formatRate(inverseUnit) : "---";

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: darkSurface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "EXCHANGE RATE",
                style: GoogleFonts.ibmPlexMono(
                  color: goldAccent,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: mintAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      "Daily reference rates",
                      style: GoogleFonts.inter(
                        color: Colors.white70,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                "1 $_fromCode = ",
                style: GoogleFonts.inter(
                  color: Colors.white70,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                "$unitStr $_toCode",
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            "1 $_toCode = $invStr $_fromCode",
            style: GoogleFonts.inter(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          Divider(color: Colors.white.withValues(alpha: 0.1), height: 1),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.schedule_rounded, color: Colors.white54, size: 13),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  "Last updated: $dateStr",
                  style: GoogleFonts.inter(
                    color: Colors.white60,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Popular Multi-Currency Live Comparison List
  Widget _buildComparisonSection(double amount, Map<String, double> rates) {
    final targets = _comparisonCurrencies.where((c) => c != _fromCode).take(6).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "QUICK COMPARISON",
              style: GoogleFonts.ibmPlexMono(
                color: goldAccent,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
              ),
            ),
            Text(
              "${_amountCtrl.text.isEmpty ? '1' : _amountCtrl.text} $_fromCode",
              style: GoogleFonts.inter(
                color: Colors.white60,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: darkSurface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Column(
            children: targets.asMap().entries.map((entry) {
              final i = entry.key;
              final code = entry.value;
              final info = getCurrencyInfo(code);
              final val = convert(amount: amount, from: _fromCode, to: code, rates: rates);
              final isSelected = _toCode == code;

              return Column(
                children: [
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _toCode = code);
                        CurrencyService.saveSelectedPair(_fromCode, _toCode);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            Text(info.flag, style: const TextStyle(fontSize: 20)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    code,
                                    style: GoogleFonts.inter(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    info.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.inter(
                                      color: Colors.white54,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(
                                  "${info.symbol} ",
                                  style: GoogleFonts.inter(
                                    color: isSelected
                                        ? mintAccent.withValues(alpha: 0.85)
                                        : Colors.white60,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  val != null ? formatAmount(val) : "---",
                                  style: GoogleFonts.inter(
                                    color: isSelected ? mintAccent : Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            if (isSelected) ...[
                              const SizedBox(width: 10),
                              const Icon(Icons.check_circle_rounded, color: mintAccent, size: 16),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (i < targets.length - 1)
                    Divider(height: 1, color: Colors.white.withValues(alpha: 0.08)),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

}
