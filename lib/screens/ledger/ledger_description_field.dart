import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/ledger_service.dart';
import 'ledger_common.dart';

/// Description text field that suggests descriptions used before in this company.
/// [kind] is "expense", "payment" or "fund" — it picks which past descriptions the backend returns.
class DescriptionField extends StatefulWidget {
  final String companyId;
  final String userId;
  final String kind;
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final int? maxLength;
  final ValueChanged<String>? onChanged;

  const DescriptionField({
    super.key,
    required this.companyId,
    required this.userId,
    required this.kind,
    required this.controller,
    required this.hint,
    this.icon = Icons.notes_rounded,
    this.maxLength,
    this.onChanged,
  });

  @override
  State<DescriptionField> createState() => _DescriptionFieldState();
}

class _DescriptionFieldState extends State<DescriptionField> {
  final _focus = FocusNode();
  List<String> _all = const [];

  @override
  void initState() {
    super.initState();
    LedgerService.descriptionSuggestions(widget.companyId, widget.userId, widget.kind).then((res) {
      if (!mounted || res["success"] != true) return;
      setState(() => _all = List<String>.from((res["descriptions"] as List? ?? const []).map((d) => d.toString())));
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<String>(
      textEditingController: widget.controller,
      focusNode: _focus,
      optionsBuilder: (value) {
        final q = value.text.trim().toLowerCase();
        return _all.where((d) => d.toLowerCase() != q && (q.isEmpty || d.toLowerCase().contains(q))).take(8);
      },
      onSelected: (d) => widget.onChanged?.call(d),
      fieldViewBuilder: (context, controller, focusNode, onSubmit) => TextField(
        controller: controller,
        focusNode: focusNode,
        maxLength: widget.maxLength,
        textCapitalization: TextCapitalization.sentences,
        onChanged: widget.onChanged,
        decoration: fieldDecoration(widget.hint, icon: widget.icon),
      ),
      optionsViewBuilder: (context, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 6,
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240, maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 4),
              shrinkWrap: true,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 2),
                  child: Text("Previously used", style: GoogleFonts.inter(fontSize: 11, color: kDark.withValues(alpha: 0.55))),
                ),
                for (final d in options)
                  InkWell(
                    onTap: () => onSelected(d),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Text(d, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 14, color: kDark)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
