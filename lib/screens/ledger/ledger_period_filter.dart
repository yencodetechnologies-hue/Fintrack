import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'ledger_common.dart';

/// Every date-range filter in the app (same as the web's PeriodFilter):
/// All time / Day / This week / Month / Year / Custom. Works in yyyy-MM-dd strings; "" means open-ended.
class PeriodFilter extends StatefulWidget {
  final String from;
  final String to;
  final void Function(String from, String to) onChanged;

  /// yyyy-MM-dd (or longer) dates that exist in the data, used to offer months and years.
  final Iterable<String> dates;
  final InputDecoration decoration;
  final double labelWidth;

  /// The option shown first when the parent starts with a range already set (e.g. "month" on Accounts).
  final String? initialMode;

  const PeriodFilter({
    super.key,
    required this.from,
    required this.to,
    required this.onChanged,
    required this.decoration,
    this.dates = const [],
    this.labelWidth = 70,
    this.initialMode,
  });

  @override
  State<PeriodFilter> createState() => _PeriodFilterState();
}

class _PeriodFilterState extends State<PeriodFilter> {
  late String _mode = widget.initialMode ?? (widget.from.isEmpty && widget.to.isEmpty ? "all" : "custom");

  @override
  void didUpdateWidget(PeriodFilter old) {
    super.didUpdateWidget(old);
    // a parent "Reset" clears the range: show All time again
    if (widget.from.isEmpty && widget.to.isEmpty && _mode != "custom") _mode = "all";
  }

  void _set(String mode, String value) {
    if (value.isEmpty) return;
    if (mode == "day") {
      widget.onChanged(value, value);
    } else if (mode == "month") {
      final parts = value.split("-").map(int.parse).toList();
      widget.onChanged("$value-01", "$value-${DateTime(parts[0], parts[1] + 1, 0).day.toString().padLeft(2, "0")}");
    } else if (mode == "year") {
      widget.onChanged("$value-01-01", "$value-12-31");
    }
  }

  void _choose(String mode) {
    final today = DateFormat("yyyy-MM-dd").format(DateTime.now());
    setState(() => _mode = mode);
    if (mode == "all") {
      widget.onChanged("", "");
    } else if (mode == "day") {
      _set("day", today);
    } else if (mode == "week") {
      // this week: Monday to today
      final now = DateTime.now();
      widget.onChanged(DateFormat("yyyy-MM-dd").format(now.subtract(Duration(days: now.weekday - 1))), today);
    } else if (mode == "month") {
      _set("month", today.substring(0, 7));
    } else if (mode == "year") {
      _set("year", today.substring(0, 4));
    }
  }

  List<String> _keys(int len, String now) {
    final set = <String>{now};
    for (final d in widget.dates) {
      if (d.length >= len) set.add(d.substring(0, len));
    }
    return set.toList()..sort((a, b) => b.compareTo(a));
  }

  Future<void> _pick(void Function(String) onPicked, String current) async {
    final initial = DateTime.tryParse(current) ?? DateTime.now();
    final d = await showDatePicker(context: context, initialDate: initial, firstDate: DateTime(2020), lastDate: DateTime(2100));
    if (d != null) onPicked(DateFormat("yyyy-MM-dd").format(d));
  }

  Widget _labelled(String label, Widget child) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(children: [
          SizedBox(width: widget.labelWidth, child: Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: kDark.withValues(alpha: 0.6)))),
          Expanded(child: child),
        ]),
      );

  Widget _dateBox(String value, VoidCallback onTap) => InkWell(
        onTap: onTap,
        child: InputDecorator(
          decoration: widget.decoration,
          child: Text(value.isEmpty ? "Pick a date" : DateFormat("dd MMM yyyy").format(DateTime.parse(value)), style: GoogleFonts.inter(fontSize: 14, color: kDark)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final from = widget.from;
    final to = widget.to;
    final now = DateTime.now();
    return Column(children: [
      _labelled(
        "Period",
        DropdownButtonFormField<String>(
          key: ValueKey("period-$_mode"),
          initialValue: _mode,
          isExpanded: true,
          decoration: widget.decoration,
          items: const [
            DropdownMenuItem(value: "all", child: Text("All time")),
            DropdownMenuItem(value: "day", child: Text("Day")),
            DropdownMenuItem(value: "week", child: Text("This week")),
            DropdownMenuItem(value: "month", child: Text("Month")),
            DropdownMenuItem(value: "year", child: Text("Year")),
            DropdownMenuItem(value: "custom", child: Text("Custom")),
          ],
          onChanged: (v) => _choose(v ?? "all"),
        ),
      ),
      if (_mode == "day") _labelled("Day", _dateBox(from, () => _pick((v) => _set("day", v), from))),
      if (_mode == "month")
        _labelled(
          "Month",
          DropdownButtonFormField<String>(
            key: ValueKey("month-$from"),
            initialValue: from.length >= 7 ? from.substring(0, 7) : null,
            isExpanded: true,
            decoration: widget.decoration,
            items: _keys(7, DateFormat("yyyy-MM").format(now))
                .map((m) => DropdownMenuItem(value: m, child: Text(DateFormat("MMMM yyyy").format(DateTime.parse("$m-01")))))
                .toList(),
            onChanged: (v) => v == null ? null : _set("month", v),
          ),
        ),
      if (_mode == "year")
        _labelled(
          "Year",
          DropdownButtonFormField<String>(
            key: ValueKey("year-$from"),
            initialValue: from.length >= 4 ? from.substring(0, 4) : null,
            decoration: widget.decoration,
            items: _keys(4, now.year.toString()).map((y) => DropdownMenuItem(value: y, child: Text(y))).toList(),
            onChanged: (v) => v == null ? null : _set("year", v),
          ),
        ),
      if (_mode == "custom") ...[
        _labelled("From", _dateBox(from, () => _pick((v) => widget.onChanged(v, to), from))),
        _labelled("To", _dateBox(to, () => _pick((v) => widget.onChanged(from, v), to))),
      ],
    ]);
  }
}
