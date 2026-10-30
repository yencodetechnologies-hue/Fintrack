import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../utils/currency_converter.dart';

class CurrencyPickerSheet extends StatefulWidget {
  final String selectedCode;
  final List<String> availableCodes;
  final ValueChanged<String> onSelected;

  const CurrencyPickerSheet({
    super.key,
    required this.selectedCode,
    required this.availableCodes,
    required this.onSelected,
  });

  static Future<String?> show({
    required BuildContext context,
    required String selectedCode,
    required List<String> availableCodes,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => CurrencyPickerSheet(
        selectedCode: selectedCode,
        availableCodes: availableCodes,
        onSelected: (code) => Navigator.of(ctx).pop(code),
      ),
    );
  }

  @override
  State<CurrencyPickerSheet> createState() => _CurrencyPickerSheetState();
}

class _CurrencyPickerSheetState extends State<CurrencyPickerSheet> {
  static const Color darkTeal = Color(0xFF195754);
  static const Color darkSurface = Color(0xFF113F3D);
  static const Color mintAccent = Color(0xFF10B981);

  final TextEditingController _searchCtrl = TextEditingController();
  String _query = "";

  late final List<CurrencyInfo> _allCurrencies;

  @override
  void initState() {
    super.initState();
    // Build unique set of currency codes: all available codes from rates + popular ones
    final codeSet = <String>{};
    for (final c in widget.availableCodes) {
      codeSet.add(c.toUpperCase());
    }
    for (final c in kPopularCurrencies) {
      codeSet.add(c.toUpperCase());
    }

    _allCurrencies = codeSet.map(getCurrencyInfo).toList()
      ..sort((a, b) => a.code.compareTo(b.code));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final isSearching = query.isNotEmpty;

    final filtered = isSearching
        ? _allCurrencies.where((c) {
            final codeMatch = c.code.toLowerCase().contains(query);
            final nameMatch = c.name.toLowerCase().contains(query);
            return codeMatch || nameMatch;
          }).toList()
        : _allCurrencies;

    final popularList = isSearching
        ? <CurrencyInfo>[]
        : kPopularCurrencies.map(getCurrencyInfo).toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.82,
      decoration: const BoxDecoration(
        color: darkTeal,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            const SizedBox(height: 12),
            // Drag handle
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Header title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text(
                    "Select Currency",
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close_rounded, color: Colors.white70, size: 18),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Search bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: darkSurface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                ),
                child: TextField(
                  controller: _searchCtrl,
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded, color: Colors.white54, size: 20),
                    suffixIcon: _query.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, color: Colors.white54, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _query = "");
                            },
                          )
                        : null,
                    hintText: "Search by code or name (e.g. INR, Rupee)",
                    hintStyle: GoogleFonts.inter(color: Colors.white.withValues(alpha: 0.4), fontSize: 13),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // List of currencies
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.search_off_rounded, color: Colors.white.withValues(alpha: 0.4), size: 40),
                          const SizedBox(height: 8),
                          Text(
                            "No currencies match \"$_query\"",
                            style: GoogleFonts.inter(color: Colors.white.withValues(alpha: 0.6), fontSize: 14),
                          ),
                        ],
                      ),
                    )
                  : ListView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                      children: [
                        if (!isSearching && popularList.isNotEmpty) ...[
                          _sectionHeader("POPULAR"),
                          ...popularList.map(_buildCurrencyTile),
                          const SizedBox(height: 12),
                          _sectionHeader("ALL CURRENCIES"),
                        ],
                        ...filtered.map(_buildCurrencyTile),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
      child: Text(
        title,
        style: GoogleFonts.ibmPlexMono(
          color: Colors.white.withValues(alpha: 0.5),
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  Widget _buildCurrencyTile(CurrencyInfo c) {
    final isSelected = c.code.toUpperCase() == widget.selectedCode.toUpperCase();

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: isSelected ? Colors.white.withValues(alpha: 0.12) : darkSurface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => widget.onSelected(c.code),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                // Flag / Avatar
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    c.flag,
                    style: const TextStyle(fontSize: 22),
                  ),
                ),
                const SizedBox(width: 14),

                // Code and Name
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            c.code,
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              c.symbol,
                              style: GoogleFonts.inter(
                                color: Colors.white70,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        c.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          color: Colors.white.withValues(alpha: 0.65),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),

                // Selection checkmark
                if (isSelected)
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: mintAccent,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_rounded, color: Colors.white, size: 14),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
