import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
export '../../services/ledger_events.dart';

const Color kForest = Color(0xFF195754);
const Color kForestDark = Color(0xFF113F3D);
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
  /// Members this manager last unticked under "Visible to" (remembered on the server).
  final List<String> hiddenStaffIds;
  /// Every company the user belongs to (with userRole), for the company switcher and "Paying company".
  final List<Map<String, dynamic>> companies;
  /// My feature switches here (backend utils/permissions.js); null until loaded = everything allowed.
  final Map<String, dynamic>? permissions;
  /// "primary" (company creator / super admin) | "manager" | "staff".
  final String? permissionRole;
  /// My custom role's name (e.g. "Incharge"), when I'm in one.
  final String? roleName;

  LedgerScope({
    required this.userId,
    required this.userName,
    required this.company,
    required this.role,
    required this.members,
    required this.reload,
    this.hiddenStaffIds = const [],
    this.companies = const [],
    this.permissions,
    this.permissionRole,
    this.roleName,
  });

  /// False only when this feature is switched off for my role; switched-off features are hidden (the server refuses them too).
  bool can(String key) => permissions == null || permissions![key] != false;
  bool get isPrimary => permissionRole == "primary";
  /// My role as shown on "Post expense as": Admin (company Admin), my custom role (e.g. Partner), or the manager name.
  String get myRoleLabel => isPrimary ? "Admin" : (roleName?.isNotEmpty ?? false) ? roleName! : managerName;
  bool get canEditPermissions =>
      isPrimary ||
      (permissionRole == "custom" && permissions != null && (permissions!["manager_permissions"] == true || permissions!["manage_roles"] == true)) ||
      ((permissionRole == "manager" || (permissionRole == "custom" && isAdmin)) && can("staff_permissions"));
  /// The primary admin, or a custom role with "Manage custom roles".
  bool get canManageRoles => isPrimary || (permissionRole == "custom" && permissions?["manage_roles"] == true);
  // the company's names for its two built-in roles (renamable on the Permissions page)
  String get managerName => roleNameOf(company, "manager");
  String get staffName => roleNameOf(company, "staff");
  String get managersName => pluralRole(managerName);
  String get staffsName => pluralRole(staffName);
  /// "admin"/"manager" → the manager name, anything else → the staff name.
  String roleLabel(dynamic role) => role == "admin" || role == "manager" ? managerName : staffName;

  /// Managers' Settings page holds both members and company settings.
  bool get canOpenSettings => isAdmin ? (isPrimary || can("settings") || can("members")) : can("settings");

  /// Other registered companies this user manages; they can pay this company's bills (booked as a loan).
  List<Map<String, dynamic>> get managedOtherCompanies => companies
      .where((c) => c["_id"].toString() != companyId && c["userRole"] == "admin" && c["external"] != true)
      .toList();

  String get companyId => company["_id"].toString();
  String get companyName => company["name"]?.toString() ?? "Company";
  bool get isAdmin => role == "admin" || role == "super_admin";
  bool get isSuperAdmin => role == "super_admin";
  List<Map<String, dynamic>> get bankAccounts =>
      List<Map<String, dynamic>>.from(company["bankAccounts"] ?? const []);
  List<Map<String, dynamic>> get admins => members.where((m) => m["role"] == "admin").toList();
  List<Map<String, dynamic>> get staff => members.where((m) => m["role"] != "admin").toList();
  num get cashBalance => (company["cashBalance"] as num?) ?? 0;
  String get cashName => (company["cashAccountName"]?.toString().trim().isNotEmpty ?? false) ? company["cashAccountName"].toString() : "Cash";

  /// Cash first, then each bank account, with the balance shown on the web's fund pickers.
  List<({String id, String name, num balance})> get funds => [
        (id: "cash", name: cashName, balance: cashBalance),
        ...bankAccounts.map((b) => (id: b["_id"].toString(), name: bankLabel(b), balance: (b["balance"] as num?) ?? 0)),
      ];
}

/// A manager's own expense (posted as themselves): the company owes them, so they can mark it "Received" once
/// they get the money back (from the company or a person). Approved, or already marked paid by them.
bool canMarkReceived(LedgerScope s, Map<String, dynamic> e) {
  if (!s.isAdmin || !s.can("reimburse") || idOf(e["createdBy"]) != s.userId) return false;
  if (e["logAs"] == "company" || e["postedAs"] == "company" || e["groupId"] != null) return false;
  final lifecycle = e["lifecycle"]?.toString();
  final paidByMe = (lifecycle == "paid_by_admin" || lifecycle == "paid_by_person") &&
      (idOf(e["paidByUserId"]).isNotEmpty ? idOf(e["paidByUserId"]) : idOf(e["paidByAdminId"])) == s.userId;
  return (lifecycle == "approved" && e["status"] != "paid") || paidByMe;
}

/// "Who paid?" choices this person may record on an approved bill (switches decide which), same as the web.
List<({String value, String label})> payerOptions(LedgerScope s, Map<String, dynamic> e) {
  final own = idOf(e["createdBy"]) == s.userId;
  if (s.isAdmin) {
    return [
      if (s.can("record_payments")) ...[(value: "admin", label: "Paid by me"), (value: "company", label: "Paid by company")],
      if (s.can("intercompany")) (value: "borrow", label: "Borrowed from a company"),
    ];
  }
  return [
    (value: "person", label: "Paid by me"),
    if (own) (value: "company", label: "Paid by company"),
    if (s.can("borrow")) (value: "borrow", label: "Borrowed from a company"),
  ];
}

/// A company's name for one of its built-in roles; blank = "Manager" / "Staff".
String roleNameOf(Map<String, dynamic>? company, String key) {
  final names = company?["roleNames"];
  final v = names is Map ? (names[key]?.toString().trim() ?? "") : "";
  return v.isNotEmpty ? v : (key == "manager" ? "Manager" : "Staff");
}

String pluralRole(String w) => RegExp(r"^staff$", caseSensitive: false).hasMatch(w) || w.toLowerCase().endsWith("s") ? w : "${w}s";

/// Categories offered on the web: the base list, then the company's own, minus any a manager removed.
const List<String> kBaseCategories = ["General", "Food & Dining", "Travel & Transport", "Office Supplies", "Utilities", "Software & Tech", "Other"];

List<String> companyCategories(Map<String, dynamic> company) {
  final hidden = List<String>.from(company["hiddenCategories"] ?? const []).map((c) => c.toLowerCase()).toSet();
  final seen = <String>{};
  return [...kBaseCategories, ...List<String>.from(company["customCategories"] ?? const [])].where((c) {
    final key = c.trim().toLowerCase();
    if (key.isEmpty || hidden.contains(key) || seen.contains(key)) return false;
    seen.add(key);
    return true;
  }).toList();
}

/// "HDFC Bank – Acme Pvt Ltd (…1234)", same as the web's bankAccountLabel.
String bankLabel(Map<String, dynamic> b) {
  final holder = (b["accountHolder"]?.toString().isNotEmpty ?? false) ? " – ${b["accountHolder"]}" : "";
  final n = (b["accountNumber"] ?? "").toString();
  final last4 = n.isEmpty ? "" : " (…${n.length > 4 ? n.substring(n.length - 4) : n})";
  return "${b["bankName"] ?? "Bank"}$holder$last4";
}

/// Status text naming who actually paid, same wording as the web's expenseStatusLabel.
String expenseStatusLabel(Map<String, dynamic> e, String companyName) {
  final lifecycle = e["lifecycle"]?.toString() ?? "submitted";
  String n(dynamic ref) => ref is Map ? (ref["name"]?.toString() ?? "") : "";
  switch (lifecycle) {
    case "paid_by_company":
      if (e["payerType"] == "other_company") return "Paid by ${n(e["payerCompanyId"]).isEmpty ? "another company" : n(e["payerCompanyId"])}";
      return "Paid by ${n(e["companyId"]).isEmpty ? companyName : n(e["companyId"])}";
    case "paid_by_admin":
    case "paid_by_person":
      final who = n(e["paidByUserId"]).isNotEmpty ? n(e["paidByUserId"]) : n(e["paidByAdminId"]);
      return who.isNotEmpty ? "Paid by $who" : (lifecycle == "paid_by_admin" ? "Paid by manager" : "Paid by staff");
    case "paid_by_voucher":
      return "Paid by voucher";
    case "awaiting_confirmation":
      return "Awaiting ${n(e["payerCompanyId"]).isEmpty ? "payer" : n(e["payerCompanyId"])} confirmation";
    default:
      return kLifecycleLabels[lifecycle] ?? lifecycle.replaceAll("_", " ");
  }
}

/// Who posted it: the company for company-posted expenses, otherwise the person (web's postedByName).
String postedByName(Map<String, dynamic> e, String companyName) {
  final companyPost = e["logAs"] == "company" || e["postedAs"] == "company";
  if (companyPost) return e["companyId"] is Map ? (e["companyId"]["name"]?.toString() ?? companyName) : companyName;
  return nameOf(e["createdBy"], "Staff");
}

/// Status dot colour, same groups as the web list: rejected / approved+paid / reimbursed / waiting.
Color statusTone(String? lifecycle) {
  if (lifecycle == "rejected") return kTerracotta;
  if (lifecycle == "reimbursed") return kForest;
  if (lifecycle == "approved" || (lifecycle?.startsWith("paid") ?? false)) return kMint;
  return kAmber;
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
  "submitted": "Awaiting approval",
  "approved": "Approved · unpaid",
  "rejected": "Rejected",
  "paid_by_admin": "Paid by manager",
  "paid_by_person": "Paid by staff",
  "paid_by_company": "Paid by company",
  "paid_by_voucher": "Paid by voucher",
  "awaiting_confirmation": "Awaiting confirmation",
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
    case "paid_by_person":
    case "paid_by_voucher":
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
      child: Text(text, style: GoogleFonts.inter(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
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
              Text(title, style: GoogleFonts.inter(color: kDark, fontSize: 20, fontWeight: FontWeight.bold)),
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

/// Dropdown of Cash plus the company's bank accounts, each with its balance (like the web).
/// Callers start `value` at "cash" so a fund is always chosen.
Widget fundDropdown(LedgerScope scope, String? value, ValueChanged<String?> onChanged, {String hint = "Bank or cash"}) {
  return DropdownButtonFormField<String>(
    initialValue: value ?? "cash",
    isExpanded: true,
    decoration: fieldDecoration(hint, icon: Icons.account_balance_rounded),
    items: scope.funds
        .map((f) => DropdownMenuItem(value: f.id, child: Text("${f.name} · ${inr(f.balance)}", overflow: TextOverflow.ellipsis)))
        .toList(),
    onChanged: onChanged,
  );
}

/// Yes/no question in the app's sheet style; resolves to true only on confirm.
Future<bool> confirmDialog(BuildContext context, String title, String message, {String confirmLabel = "Confirm", bool danger = false}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => Theme(
      data: sheetTheme,
      child: AlertDialog(
        title: Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: kDark)),
        content: Text(message, style: GoogleFonts.inter(color: kDark.withValues(alpha: 0.75), height: 1.4)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel, style: TextStyle(color: danger ? kTerracotta : kForest, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    ),
  );
  return ok == true;
}

/// Picks an image (camera or gallery) and returns it as a data URL, the format the server stores.
Future<String?> pickReceiptImage(BuildContext context) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (ctx) => Theme(
      data: sheetTheme,
      child: SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_camera_rounded), title: const Text("Take a photo"), onTap: () => Navigator.pop(ctx, ImageSource.camera)),
          ListTile(leading: const Icon(Icons.photo_library_rounded), title: const Text("Choose from gallery"), onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
        ]),
      ),
    ),
  );
  if (source == null) return null;
  final img = await ImagePicker().pickImage(source: source, maxWidth: 1400, imageQuality: 72);
  if (img == null) return null;
  final bytes = await File(img.path).readAsBytes();
  return "data:image/jpeg;base64,${base64Encode(bytes)}";
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

/// Managers who can pay people get Payments in the bottom bar (in Inter-co's place); Inter-co then opens from More.
bool paymentsInNav(LedgerScope s) => s.isAdmin && s.can("reimburse");

/// Category picker sheet: search box + categories as chips (the selected one filled). Typing a name that isn't in the
/// list offers "+ Add …". Resolves to the picked name and whether it's a new category, or null when dismissed.
Future<({String name, bool isNew})?> pickCategory(BuildContext context, List<String> options, String current, {bool allowNew = true}) async {
  final search = TextEditingController();
  // drop focus first: otherwise closing this sheet hands focus back to the form's last field (e.g. Amount) and jumps there
  FocusManager.instance.primaryFocus?.unfocus();
  // pick: unfocus the search box before closing, for the same reason
  void done(BuildContext ctx, ({String name, bool isNew}) value) {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.pop(ctx, value);
  }

  final picked = await showLedgerSheet<({String name, bool isNew})>(context, "Category", (ctx) => StatefulBuilder(builder: (ctx, set) {
        final q = search.text.trim();
        final shown = options.where((c) => c.toLowerCase().contains(q.toLowerCase())).toList();
        final exact = options.any((c) => c.toLowerCase() == q.toLowerCase());
        Widget chip(String label, {bool selected = false, IconData? icon, required VoidCallback onTap}) => Material(
              color: selected ? kForest : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(99),
              child: InkWell(
                borderRadius: BorderRadius.circular(99),
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (icon != null) ...[Icon(icon, size: 16, color: selected ? Colors.white : kForest), const SizedBox(width: 5)],
                    Text(label, style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w600, color: selected ? Colors.white : kDark)),
                  ]),
                ),
              ),
            );
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            controller: search,
            autofocus: false,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => set(() {}),
            decoration: fieldDecoration(allowNew ? "Search or type a new category" : "Search categories", icon: Icons.search_rounded),
          ),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in shown) chip(c, selected: c == current, onTap: () => done(ctx, (name: c, isNew: false))),
            if (allowNew && q.isNotEmpty && !exact) chip("Add “$q”", icon: Icons.add_rounded, onTap: () => done(ctx, (name: q, isNew: true))),
          ]),
          if (shown.isEmpty && (!allowNew || q.isEmpty))
            Text("No categories match.", style: GoogleFonts.inter(fontSize: 13, color: kDark.withValues(alpha: 0.6))),
          const SizedBox(height: 6),
        ]);
      }));
  search.dispose();
  // the sheet is closed: make sure nothing on the form grabs focus back
  FocusManager.instance.primaryFocus?.unfocus();
  return picked;
}

/// The field that opens [pickCategory]: looks like the other form fields, shows the current category.
Widget categoryField(String category, VoidCallback onTap, {bool enabled = true}) => InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: fieldDecoration("Category", icon: Icons.category_rounded).copyWith(
          suffixIcon: const Icon(Icons.expand_more_rounded),
          enabled: enabled,
        ),
        child: Text(category, style: GoogleFonts.inter(fontSize: 14.5, color: kDark), overflow: TextOverflow.ellipsis),
      ),
    );
