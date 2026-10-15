import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../services/ledger_events.dart';
export '../../services/ledger_events.dart';

const Color kForest = Color(0xFF0C5F41);
const Color kForestDark = Color(0xFF0C3826);
const Color kMint = Color(0xFF10B981);
const Color kDark = Color(0xFF1E293B);
const Color kTerracotta = Color(0xFFB8452D);
const Color kAmber = Color(0xFFB7791F);

/// Everything a tab needs to know about the selected company and the signed-in user.
class LedgerScope {
  final String userId;
  final String userName;
  final Map<String, dynamic> company;
  final String role; // employee | admin | super_admin
  final List<Map<String, dynamic>> members;
  final Future<void> Function() reload;

  LedgerScope({
    required this.userId,
    required this.userName,
    required this.company,
    required this.role,
    required this.members,
    required this.reload,
  });

  String get companyId => company["_id"].toString();
  String get companyName => company["name"]?.toString() ?? "Company";
  bool get isAdmin => role == "admin" || role == "super_admin";
  bool get isSuperAdmin => role == "super_admin";
  List<Map<String, dynamic>> get bankAccounts =>
      List<Map<String, dynamic>>.from(company["bankAccounts"] ?? const []);
  List<Map<String, dynamic>> get admins => members.where((m) => m["role"] == "admin").toList();
}

String inr(dynamic v) => "₹${NumberFormat("#,##0.00", "en_IN").format((v as num?) ?? 0)}";

String dateLabel(dynamic raw) {
  final d = raw == null ? null : DateTime.tryParse(raw.toString())?.toLocal();
  return d == null ? "" : DateFormat("dd MMM yyyy").format(d);
}

String idOf(dynamic ref) {
  if (ref == null) return "";
  if (ref is Map) return ref["_id"]?.toString() ?? "";
  return ref.toString();
}

String nameOf(dynamic ref, [String fallback = "Member"]) =>
    ref is Map ? (ref["name"]?.toString() ?? fallback) : fallback;

const Map<String, String> kLifecycleLabels = {
  "submitted": "Submitted",
  "approved": "Approved",
  "rejected": "Rejected",
  "paid_by_admin": "Paid by admin",
  "paid_by_company": "Paid by company",
  "reimbursed": "Reimbursed",
};

Color lifecycleColor(String? s) {
  switch (s) {
    case "submitted":
      return kAmber;
    case "approved":
      return kForest;
    case "rejected":
      return kTerracotta;
    case "reimbursed":
    case "paid_by_company":
      return kMint;
    default:
      return const Color(0xFF2563EB);
  }
}

Widget statusPill(String text, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: GoogleFonts.inter(color: color, fontSize: 10.5, fontWeight: FontWeight.bold)),
    );

Widget ledgerCard({required Widget child, EdgeInsets padding = const EdgeInsets.all(14)}) => Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: padding,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: child,
    );

Widget sectionTitle(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(2, 18, 2, 10),
      child: Text(text, style: GoogleFonts.fraunces(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
    );

TextStyle get labelStyle => GoogleFonts.inter(color: kDark, fontWeight: FontWeight.bold, fontSize: 13);

InputDecoration fieldDecoration(String hint, {IconData? icon}) => InputDecoration(
      hintText: hint,
      prefixIcon: icon == null ? null : Icon(icon, size: 18, color: kForest),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kForest, width: 1.5)),
    );

OverlayEntry? _activeToast;

/// Shows a message on the app's topmost overlay, above bottom sheets, dialogs and pushed screens.
void toast(BuildContext context, String message, {bool error = false}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  if (_activeToast?.mounted ?? false) _activeToast!.remove();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _ToastView(
      message: message,
      error: error,
      onDone: () {
        if (entry.mounted) entry.remove();
        if (identical(_activeToast, entry)) _activeToast = null;
      },
    ),
  );
  _activeToast = entry;
  overlay.insert(entry);
}

class _ToastView extends StatefulWidget {
  final String message;
  final bool error;
  final VoidCallback onDone;
  const _ToastView({required this.message, required this.error, required this.onDone});

  @override
  State<_ToastView> createState() => _ToastViewState();
}

class _ToastViewState extends State<_ToastView> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 220))..forward();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 3200), _dismiss);
  }

  Future<void> _dismiss() async {
    _timer?.cancel();
    if (!mounted) return;
    await _anim.reverse();
    widget.onDone();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 10,
      left: 16,
      right: 16,
      child: FadeTransition(
        opacity: _anim,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, -0.4), end: Offset.zero).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOut)),
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: _dismiss,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                decoration: BoxDecoration(
                  color: widget.error ? const Color(0xFFC53030) : kForestDark,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 16, offset: Offset(0, 6))],
                ),
                child: Row(
                  children: [
                    Icon(widget.error ? Icons.error_outline_rounded : Icons.check_circle_rounded, color: widget.error ? Colors.white : kMint, size: 20),
                    const SizedBox(width: 10),
                    Expanded(child: Text(widget.message, style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13.5))),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows the result of an API call as a toast; returns true on success.
bool handleResult(BuildContext context, Map<String, dynamic> res, String okMessage) {
  final ok = res["success"] == true;
  toast(context, ok ? okMessage : (res["message"]?.toString() ?? "Something went wrong"), error: !ok);
  if (ok) notifyLedgerChanged();
  return ok;
}

/// White bottom sheet with a title; used for every form in the ledger screens.
Future<T?> showLedgerSheet<T>(BuildContext context, String title, Widget Function(BuildContext) builder) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Theme(
      data: sheetTheme,
      child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.9),
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(width: 38, height: 4, decoration: BoxDecoration(color: kDark.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10))),
              ),
              const SizedBox(height: 14),
              Text(title, style: GoogleFonts.fraunces(color: kDark, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 14),
              Builder(builder: builder),
            ],
          ),
        ),
      ),
    ),
    ),
  );
}

/// Light theme for white sheets: the app's global theme uses light text meant for the green screens.
final ThemeData sheetTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(seedColor: kForest, primary: kForest, brightness: Brightness.light, surface: Colors.white),
  scaffoldBackgroundColor: Colors.white,
  canvasColor: Colors.white,
  textTheme: GoogleFonts.interTextTheme().apply(bodyColor: kDark, displayColor: kDark),
  hintColor: const Color(0xFF94A3B8),
  dropdownMenuTheme: DropdownMenuThemeData(textStyle: GoogleFonts.inter(color: kDark)),
  checkboxTheme: CheckboxThemeData(
    fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? kForest : Colors.transparent),
    side: const BorderSide(color: Color(0xFF94A3B8), width: 1.5),
  ),
  listTileTheme: const ListTileThemeData(textColor: kDark, iconColor: kForest),
  chipTheme: ChipThemeData(
    backgroundColor: const Color(0xFFF1F5F9),
    labelStyle: GoogleFonts.inter(color: kDark, fontWeight: FontWeight.w600),
    side: BorderSide.none,
  ),
  segmentedButtonTheme: SegmentedButtonThemeData(
    style: ButtonStyle(
      foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : kDark),
      backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? kForest : Colors.white),
    ),
  ),
  textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: kForest)),
);

Widget primaryButton(String label, FutureOr<void> Function()? onPressed, {Color color = kForest}) =>
    _BusyButton(label: label, onPressed: onPressed, color: color);

/// Disables itself while its callback is running, so a double tap can't submit twice.
class _BusyButton extends StatefulWidget {
  final String label;
  final FutureOr<void> Function()? onPressed;
  final Color color;
  const _BusyButton({required this.label, required this.onPressed, required this.color});

  @override
  State<_BusyButton> createState() => _BusyButtonState();
}

class _BusyButtonState extends State<_BusyButton> {
  bool _busy = false;

  Future<void> _run() async {
    setState(() => _busy = true);
    try {
      await widget.onPressed!();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: widget.onPressed == null || _busy ? null : _run,
          style: ElevatedButton.styleFrom(
            backgroundColor: widget.color,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(widget.label, style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
        ),
      );
}

/// Dropdown of "cash" plus the company's bank accounts.
Widget fundDropdown(LedgerScope scope, String? value, ValueChanged<String?> onChanged, {String hint = "Bank or cash"}) {
  return DropdownButtonFormField<String>(
    initialValue: value,
    isExpanded: true,
    decoration: fieldDecoration(hint, icon: Icons.account_balance_rounded),
    items: [
      const DropdownMenuItem(value: "cash", child: Text("Cash / InCash")),
      ...scope.bankAccounts.map((b) {
        final n = (b["accountNumber"] ?? "").toString();
        final last4 = n.length > 4 ? n.substring(n.length - 4) : n;
        return DropdownMenuItem(value: b["_id"].toString(), child: Text("${b["bankName"]} •••• $last4", overflow: TextOverflow.ellipsis));
      }),
    ],
    onChanged: onChanged,
  );
}

const List<String> kMethods = ["UPI", "Bank", "Cash", "Card"];

Widget methodChips(String value, ValueChanged<String> onChanged) => Wrap(
      spacing: 8,
      children: kMethods
          .map((m) => ChoiceChip(
                label: Text(m),
                selected: value == m,
                selectedColor: kForest,
                labelStyle: GoogleFonts.inter(color: value == m ? Colors.white : kDark, fontWeight: FontWeight.w600),
                onSelected: (_) => onChanged(m),
              ))
          .toList(),
    );

Widget emptyState(String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 30),
      child: Center(child: Text(text, style: GoogleFonts.inter(color: Colors.white70))),
    );
