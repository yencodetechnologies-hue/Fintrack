import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data/indian_banks.dart';

class BankSelectorField extends StatelessWidget {
  final String? selectedBankId;
  final TextEditingController customBankController;
  final ValueChanged<String?> onBankIdChanged;
  final VoidCallback onCustomBankChanged;

  const BankSelectorField({
    super.key,
    required this.selectedBankId,
    required this.customBankController,
    required this.onBankIdChanged,
    required this.onCustomBankChanged,
  });

  String get _selectedBankTitle {
    if (selectedBankId == null) return "Select Bank";
    if (selectedBankId == kCustomBankId) {
      final custom = customBankController.text.trim();
      return custom.isNotEmpty ? custom : kCustomBankLabel;
    }
    return bankOptionById(selectedBankId!)?.displayName ?? "Select Bank";
  }

  void _openBankPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _BankPickerSheet(
        selectedBankId: selectedBankId,
        customBankController: customBankController,
        onBankSelected: (bankId) {
          onBankIdChanged(bankId);
          Navigator.pop(context);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool hasSelection = selectedBankId != null;
    const Color greenAccent = Color(0xFF0C5F41);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onTap: () => _openBankPicker(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFF6F8F7),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: hasSelection ? greenAccent.withValues(alpha: 0.6) : Colors.black.withValues(alpha: 0.12),
                width: 1.2,
              ),
              boxShadow: [
                if (hasSelection)
                  BoxShadow(
                    color: greenAccent.withValues(alpha: 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: greenAccent.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.account_balance_rounded,
                    color: greenAccent,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Bank Name",
                        style: GoogleFonts.inter(
                          color: const Color(0xFF6B7280),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _selectedBankTitle,
                        style: GoogleFonts.inter(
                          color: hasSelection ? const Color(0xFF0F261C) : const Color(0xFF9CA3AF),
                          fontSize: 15,
                          fontWeight: hasSelection ? FontWeight.bold : FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: greenAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.unfold_more_rounded,
                    color: greenAccent,
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (selectedBankId == kCustomBankId) ...[
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF6F8F7),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.black.withValues(alpha: 0.12),
                width: 1.2,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: TextField(
              controller: customBankController,
              onChanged: (_) => onCustomBankChanged(),
              style: GoogleFonts.inter(
                color: const Color(0xFF0F261C),
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                labelText: 'Enter Custom Bank Name',
                labelStyle: GoogleFonts.inter(
                  color: const Color(0xFF6B7280),
                  fontSize: 14,
                ),
                prefixIcon: const Icon(
                  Icons.edit_rounded,
                  color: greenAccent,
                  size: 20,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ],
        const SizedBox(height: 18),
      ],
    );
  }
}

// ─────────────────────────────────────────────
//  QFIN BANK PICKER SHEET
// ─────────────────────────────────────────────

class _BankPickerSheet extends StatefulWidget {
  final String? selectedBankId;
  final TextEditingController customBankController;
  final ValueChanged<String> onBankSelected;

  const _BankPickerSheet({
    required this.selectedBankId,
    required this.customBankController,
    required this.onBankSelected,
  });

  @override
  State<_BankPickerSheet> createState() => _BankPickerSheetState();
}

class _BankPickerSheetState extends State<_BankPickerSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<BankOption> _filteredBanks = indianBanks;

  static const Color _bg         = Colors.white;
  static const Color _greenAccent = Color(0xFF0C5F41);
  static const Color _darkText   = Color(0xFF0F261C);
  static const Color _goldAccent = Color(0xFFD4AF37);

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    final query = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredBanks = indianBanks;
      } else {
        _filteredBanks = indianBanks.where((b) {
          final title = b.displayName.toLowerCase();
          final matchesKey = b.matchKeywords.any((k) => k.toLowerCase().contains(query));
          return title.contains(query) || matchesKey;
        }).toList();
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          // Drag handle
          Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _greenAccent.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.account_balance_rounded, color: _greenAccent, size: 20),
                ),
                const SizedBox(width: 12),
                Text(
                  "Select Bank",
                  style: GoogleFonts.fraunces(
                    color: _darkText,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: Color(0xFF6B7280)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Search Field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF6F8F7),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
              ),
              child: TextField(
                controller: _searchCtrl,
                style: GoogleFonts.inter(color: _darkText, fontSize: 14.5),
                decoration: InputDecoration(
                  hintText: "Search bank by name...",
                  hintStyle: GoogleFonts.inter(color: const Color(0xFF9CA3AF), fontSize: 14),
                  prefixIcon: const Icon(Icons.search_rounded, color: _greenAccent, size: 20),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18, color: Color(0xFF6B7280)),
                          onPressed: () => _searchCtrl.clear(),
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Bank List
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              itemCount: _filteredBanks.length + 1, // +1 for Custom Bank
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                if (index == _filteredBanks.length) {
                  final bool isSelected = widget.selectedBankId == kCustomBankId;
                  return GestureDetector(
                    onTap: () => widget.onBankSelected(kCustomBankId),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: isSelected ? _greenAccent.withValues(alpha: 0.1) : const Color(0xFFF6F8F7),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected ? _greenAccent : Colors.black.withValues(alpha: 0.06),
                          width: isSelected ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: _goldAccent.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.add_rounded, color: _greenAccent, size: 20),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              kCustomBankLabel,
                              style: GoogleFonts.inter(
                                color: _darkText,
                                fontWeight: FontWeight.bold,
                                fontSize: 14.5,
                              ),
                            ),
                          ),
                          if (isSelected)
                            const Icon(Icons.check_circle_rounded, color: _greenAccent, size: 20),
                        ],
                      ),
                    ),
                  );
                }

                final bank = _filteredBanks[index];
                final bool isSelected = widget.selectedBankId == bank.id;

                return GestureDetector(
                  onTap: () => widget.onBankSelected(bank.id),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: isSelected ? _greenAccent.withValues(alpha: 0.1) : const Color(0xFFF6F8F7),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected ? _greenAccent : Colors.black.withValues(alpha: 0.06),
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: isSelected ? _greenAccent : _greenAccent.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              bank.displayName[0].toUpperCase(),
                              style: GoogleFonts.fraunces(
                                color: isSelected ? Colors.white : _greenAccent,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            bank.displayName,
                            style: GoogleFonts.inter(
                              color: _darkText,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                              fontSize: 14.5,
                            ),
                          ),
                        ),
                        if (isSelected)
                          const Icon(Icons.check_circle_rounded, color: _greenAccent, size: 20),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
