import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../services/rate_history_service.dart';
import '../../utils/currency_converter.dart';

class RateHistoryCard extends StatefulWidget {
  final String from;
  final String to;

  const RateHistoryCard({
    super.key,
    required this.from,
    required this.to,
  });

  @override
  State<RateHistoryCard> createState() => _RateHistoryCardState();
}

class _RateHistoryCardState extends State<RateHistoryCard> {
  static const Color darkTeal = Color(0xFF195754);
  static const Color darkSurface = Color(0xFF113F3D);
  static const Color darkText = Color(0xFF1B2A2F);
  static const Color textMuted = Color(0xFF64748B);
  static const Color redAccent = Color(0xFFEF4444);

  int _selectedRange = 30; // 7, 30, 90
  bool _isLoading = true;
  String? _error;
  List<DayRate> _rates = [];
  RateHistoryStats? _stats;

  // Cached full data maps for instant swapping:
  String? _lastLoadedFrom;
  String? _lastLoadedTo;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void didUpdateWidget(covariant RateHistoryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.from != widget.from || oldWidget.to != widget.to) {
      // If the currencies were swapped (from->to becomes to->from) and we already have rates,
      // invert immediately with no new network call!
      if (_lastLoadedFrom == widget.to && _lastLoadedTo == widget.from && _rates.isNotEmpty) {
        _lastLoadedFrom = widget.from;
        _lastLoadedTo = widget.to;
        setState(() {
          _rates = _rates
              .map((r) => DayRate(date: r.date, rate: r.rate != 0 ? 1.0 / r.rate : 0.0))
              .toList();
          _stats = computeStats(_rates);
        });
      } else {
        _loadHistory();
      }
    }
  }

  Future<void> _loadHistory() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final data = await RateHistoryService.getRateHistory(
        from: widget.from,
        to: widget.to,
        days: _selectedRange,
      );

      if (!mounted) return;

      if (data.isEmpty) {
        setState(() {
          _isLoading = false;
          _error = "Rate history is currently unavailable for this pair.";
        });
        return;
      }

      _lastLoadedFrom = widget.from;
      _lastLoadedTo = widget.to;

      setState(() {
        _rates = data;
        _stats = computeStats(data);
        _isLoading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = "Could not load rate history. Please check connection.";
      });
    }
  }

  void _onRangeChanged(int days) {
    if (_selectedRange == days) return;
    HapticFeedback.selectionClick();
    setState(() => _selectedRange = days);
    _loadHistory();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Header with Range Chips
          _buildHeader(),
          const SizedBox(height: 18),

          // 2. Chart or State Body
          if (_isLoading)
            _buildLoadingSkeleton()
          else if (_error != null && _rates.isEmpty)
            _buildErrorState()
          else
            _buildChartSection(),

          // 3. Compare Summary Row
          if (!_isLoading && _stats != null) ...[
            const SizedBox(height: 20),
            Divider(color: Colors.black.withValues(alpha: 0.06), height: 1),
            const SizedBox(height: 16),
            _buildCompareSummary(),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Rate History",
                style: GoogleFonts.inter(
                  color: darkText,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                "${widget.from} to ${widget.to} · ${_selectedRange}D trends",
                style: GoogleFonts.inter(
                  color: textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        // Range Chips (7D, 30D, 90D)
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [7, 30, 90].map((days) {
              final isSelected = _selectedRange == days;
              return Material(
                color: isSelected ? darkTeal : Colors.transparent,
                borderRadius: BorderRadius.circular(11),
                child: InkWell(
                  borderRadius: BorderRadius.circular(11),
                  onTap: () => _onRangeChanged(days),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Text(
                      "${days}D",
                      style: GoogleFonts.inter(
                        color: isSelected ? Colors.white : textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingSkeleton() {
    return SizedBox(
      height: 190,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: darkTeal),
            ),
            const SizedBox(height: 12),
            Text(
              "Loading historical rates...",
              style: GoogleFonts.inter(color: textMuted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Container(
      height: 180,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wifi_off_rounded, color: textMuted.withValues(alpha: 0.6), size: 32),
          const SizedBox(height: 8),
          Text(
            _error ?? "Unable to load chart data",
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(color: textMuted, fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: _loadHistory,
            icon: const Icon(Icons.refresh_rounded, size: 16, color: darkTeal),
            label: Text("Retry", style: GoogleFonts.inter(color: darkTeal, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildChartSection() {
    if (_rates.isEmpty) return const SizedBox.shrink();

    final spots = <FlSpot>[];
    for (int i = 0; i < _rates.length; i++) {
      spots.add(FlSpot(i.toDouble(), _rates[i].rate));
    }

    final minY = _stats?.low ?? 0.0;
    final maxY = _stats?.high ?? 1.0;
    final rangeY = maxY - minY;
    // Add small breathing room at top and bottom (5%)
    final padY = rangeY > 0 ? rangeY * 0.08 : (minY > 0 ? minY * 0.05 : 0.05);
    final chartMinY = max(0.0, minY - padY);
    final chartMaxY = maxY + padY;

    // Determine interval for bottom titles (show 4-5 dates across the range)
    final xCount = _rates.length;
    final xInterval = max(1.0, (xCount / 4).floorToDouble());

    final isPositive = (_stats?.change ?? 0) >= 0;
    final lineColor = isPositive ? const Color(0xFF0D9488) : const Color(0xFFE11D48);

    return SizedBox(
      height: 200,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (xCount - 1).toDouble(),
          minY: chartMinY,
          maxY: chartMaxY,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: (chartMaxY - chartMinY) / 3,
            getDrawingHorizontalLine: (value) => FlLine(
              color: Colors.black.withValues(alpha: 0.05),
              strokeWidth: 1,
              dashArray: [4, 4],
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            show: true,
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 46,
                interval: (chartMaxY - chartMinY) / 3,
                getTitlesWidget: (value, meta) {
                  if (value == meta.min || value == meta.max) return const SizedBox.shrink();
                  return Text(
                    formatRate(value),
                    style: GoogleFonts.ibmPlexMono(
                      color: textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                interval: xInterval,
                getTitlesWidget: (value, meta) {
                  final idx = value.toInt();
                  if (idx < 0 || idx >= _rates.length) return const SizedBox.shrink();
                  final date = _rates[idx].date;
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      DateFormat("d MMM").format(date),
                      style: GoogleFonts.inter(
                        color: textMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            handleBuiltInTouches: true,
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => darkSurface,
              tooltipBorderRadius: BorderRadius.circular(10),
              tooltipPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              fitInsideHorizontally: true,
              fitInsideVertically: true,
              getTooltipItems: (touchedSpots) {
                return touchedSpots.map((spot) {
                  final idx = spot.x.toInt();
                  if (idx < 0 || idx >= _rates.length) return null;
                  final day = _rates[idx];
                  final dateStr = DateFormat("d MMM yyyy").format(day.date);
                  final rateStr = formatRate(day.rate);

                  return LineTooltipItem(
                    "$dateStr\n",
                    GoogleFonts.inter(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                    children: [
                      TextSpan(
                        text: "1 ${widget.from} = $rateStr ${widget.to}",
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  );
                }).toList();
              },
            ),
            getTouchedSpotIndicator: (barData, spotIndexes) {
              return spotIndexes.map((spotIndex) {
                return TouchedSpotIndicatorData(
                  FlLine(
                    color: darkTeal.withValues(alpha: 0.4),
                    strokeWidth: 1.5,
                    dashArray: [4, 4],
                  ),
                  FlDotData(
                    show: true,
                    getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                      radius: 5,
                      color: darkTeal,
                      strokeWidth: 2,
                      strokeColor: Colors.white,
                    ),
                  ),
                );
              }).toList();
            },
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.28,
              color: lineColor,
              barWidth: 2.4,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    lineColor.withValues(alpha: 0.22),
                    lineColor.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// "Compare" summary row: Change (+/- %), Highest, Lowest, Average
  Widget _buildCompareSummary() {
    final s = _stats;
    if (s == null) return const SizedBox.shrink();

    final isPositive = s.change > 0;
    final isZero = s.change == 0;
    final changeColor = isZero ? textMuted : (isPositive ? const Color(0xFF16A34A) : redAccent);
    final changeArrow = isZero ? "" : (isPositive ? "▲" : "▼");
    final sign = isPositive ? "+" : "";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "PERIOD SUMMARY",
              style: GoogleFonts.ibmPlexMono(
                color: textMuted,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
              ),
            ),
            Text(
              "vs ${_selectedRange}D ago",
              style: GoogleFonts.inter(
                color: textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 520;

            final changeTile = _buildMetricTile(
              label: "Change",
              valueText: "$changeArrow $sign${s.changePercent.abs().toStringAsFixed(2)}%",
              valueColor: changeColor,
              subtext: "$sign${formatRate(s.change)} abs",
            );

            final averageTile = _buildMetricTile(
              label: "Average",
              valueText: formatRate(s.average),
              subtext: "${_selectedRange}D mean",
            );

            final highTile = _buildMetricTile(
              label: "Highest",
              valueText: formatRate(s.high),
              subtext: DateFormat("d MMM yyyy").format(s.highDate),
            );

            final lowTile = _buildMetricTile(
              label: "Lowest",
              valueText: formatRate(s.low),
              subtext: DateFormat("d MMM yyyy").format(s.lowDate),
            );

            if (isWide) {
              return Row(
                children: [
                  Expanded(child: changeTile),
                  const SizedBox(width: 10),
                  Expanded(child: highTile),
                  const SizedBox(width: 10),
                  Expanded(child: lowTile),
                  const SizedBox(width: 10),
                  Expanded(child: averageTile),
                ],
              );
            }

            return Column(
              children: [
                Row(
                  children: [
                    Expanded(child: changeTile),
                    const SizedBox(width: 10),
                    Expanded(child: averageTile),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: highTile),
                    const SizedBox(width: 10),
                    Expanded(child: lowTile),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildMetricTile({
    required String label,
    required String valueText,
    Color? valueColor,
    required String subtext,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              color: textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              valueText,
              style: GoogleFonts.inter(
                color: valueColor ?? darkText,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtext,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              color: textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
