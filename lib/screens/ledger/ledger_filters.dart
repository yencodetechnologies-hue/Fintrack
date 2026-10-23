import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'ledger_common.dart';
import 'ledger_period_filter.dart';

// Shared search + filter pills (Expenses, Payments): a slim search field, then a row of rounded pills that open a
// menu; a pill turns green when it isn't on its default, and the period pill opens the Day/Month/Year/Custom picker.

/// White card with the search field on top and the pills underneath (scrolls sideways when they don't fit).
Widget filterCard({required Widget search, required List<Widget> pills, VoidCallback? onClear, EdgeInsets margin = EdgeInsets.zero}) => Container(
      margin: margin,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        search,
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (var i = 0; i < pills.length; i++) ...[if (i > 0) const SizedBox(width: 8), pills[i]],
            if (onClear != null) ...[
              const SizedBox(width: 4),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: kTerracotta, visualDensity: VisualDensity.compact),
                onPressed: onClear,
                child: Text("Clear", style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700)),
              ),
            ],
          ]),
        ),
      ]),
    );

/// 44px rounded search box with a clear (✕) button.
class FilterSearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final VoidCallback onChanged;
  const FilterSearchField({super.key, required this.controller, required this.hint, required this.onChanged});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 44,
        child: TextField(
          controller: controller,
          onChanged: (_) => onChanged(),
          style: GoogleFonts.inter(fontSize: 14, color: kDark),
          textAlignVertical: TextAlignVertical.center,
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: const Color(0xFFF1F5F9),
            hintText: hint,
            hintStyle: GoogleFonts.inter(fontSize: 14, color: kDark.withValues(alpha: 0.45)),
            prefixIcon: Icon(Icons.search_rounded, size: 20, color: kDark.withValues(alpha: 0.5)),
            suffixIcon: controller.text.isEmpty
                ? null
                : IconButton(
                    icon: Icon(Icons.close_rounded, size: 18, color: kDark.withValues(alpha: 0.5)),
                    onPressed: () {
                      controller.clear();
                      onChanged();
                    },
                  ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kForest, width: 1.2)),
          ),
        ),
      );
}

/// The pill itself: icon, current value, ▾; green when [active].
Widget filterChipFace(IconData icon, String label, bool active) => Container(
      height: 36,
      padding: const EdgeInsets.only(left: 10, right: 6),
      decoration: BoxDecoration(
        color: active ? kForest.withValues(alpha: 0.08) : Colors.white,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: active ? kForest.withValues(alpha: 0.45) : const Color(0xFFE2E8F0)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: active ? kForest : kDark.withValues(alpha: 0.55)),
        const SizedBox(width: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 170),
          child: Text(label, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: active ? kForest : kDark)),
        ),
        Icon(Icons.expand_more_rounded, size: 18, color: active ? kForest : kDark.withValues(alpha: 0.5)),
      ]),
    );

/// A pill that opens a menu of [options] (value → label) with a ✓ on the current one.
Widget filterPill({
  required IconData icon,
  required String value,
  required String defaultValue,
  required Map<String, String> options,
  required ValueChanged<String> onSelected,
  String? label,
}) =>
    PopupMenuButton<String>(
      tooltip: "",
      position: PopupMenuPosition.under,
      color: Colors.white,
      constraints: const BoxConstraints(maxHeight: 420, minWidth: 180),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: onSelected,
      itemBuilder: (_) => options.entries
          .map((e) => PopupMenuItem(
                value: e.key,
                height: 40,
                child: Row(children: [
                  Expanded(
                    child: Text(e.value,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(fontSize: 13.5, fontWeight: e.key == value ? FontWeight.w700 : FontWeight.w500, color: e.key == value ? kForest : kDark)),
                  ),
                  if (e.key == value) const Icon(Icons.check_rounded, size: 18, color: kForest),
                ]),
              ))
          .toList(),
      child: filterChipFace(icon, label ?? options[value] ?? options.values.first, value != defaultValue),
    );

/// "All time", "23 Oct 2026", "Oct 2026", "2026" or "01 Oct – 15 Oct 2026".
String periodLabel(String from, String to) {
  if (from.isEmpty && to.isEmpty) return "All time";
  final f = DateTime.tryParse(from), t = DateTime.tryParse(to);
  if (f != null && t != null) {
    if (from == to) return DateFormat("dd MMM yyyy").format(f);
    if (f.day == 1 && f.month == t.month && f.year == t.year && t.day == DateTime(t.year, t.month + 1, 0).day) return DateFormat("MMM yyyy").format(f);
    if (from.endsWith("-01-01") && to.endsWith("-12-31") && f.year == t.year) return "${f.year}";
    return "${DateFormat("dd MMM").format(f)} – ${DateFormat("dd MMM yyyy").format(t)}";
  }
  if (f != null) return "From ${DateFormat("dd MMM yyyy").format(f)}";
  return "Until ${DateFormat("dd MMM yyyy").format(t!)}";
}

/// Period pill: opens a small sheet with the Day / Month / Year / Custom picker; changes apply as you pick.
Widget periodPill(BuildContext context, {required String from, required String to, required Iterable<String> dates, required void Function(String from, String to) onChanged}) {
  final input = InputDecoration(
    isDense: true,
    filled: true,
    fillColor: const Color(0xFFF8FAFC),
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
  );
  return GestureDetector(
    onTap: () {
      var f = from, t = to;
      showLedgerSheet(context, "Period", (ctx) => StatefulBuilder(builder: (ctx, set) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            PeriodFilter(
              from: f,
              to: t,
              decoration: input,
              labelWidth: 60,
              dates: dates,
              onChanged: (nf, nt) {
                set(() {
                  f = nf;
                  t = nt;
                });
                onChanged(nf, nt);
              },
            ),
            const SizedBox(height: 16),
            primaryButton("Done", () => Navigator.pop(ctx)),
          ])));
    },
    child: filterChipFace(Icons.calendar_today_rounded, periodLabel(from, to), from.isNotEmpty || to.isNotEmpty),
  );
}
