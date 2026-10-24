import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/ledger_service.dart';
import 'ledger_common.dart';
import 'ledger_fund_topup.dart';

num _round(num n) => (n * 100).round() / 100;

/// Manager gives a staff member money up front, paid by the company (from a fund now) or by the manager.
Future<void> showCreateVoucherSheet(BuildContext context, LedgerScope s, {VoidCallback? onDone}) {
  final staff = s.staff.where((m) => m["userId"].toString() != s.userId).toList();
  String? recipientId = staff.length == 1 ? staff.first["userId"].toString() : null;
  String fundedBy = "company";
  String fundId = "cash";
  final amount = TextEditingController();
  final purpose = TextEditingController();

  return showLedgerSheet(context, "Create voucher", (ctx) => StatefulBuilder(builder: (ctx, set) {
        final value = double.tryParse(amount.text.trim()) ?? 0;
        final fund = s.funds.firstWhere((f) => f.id == fundId, orElse: () => s.funds.first);
        final short = fundedBy == "company" && value > 0 && fund.balance < value;
        if (staff.isEmpty) {
          return Text("This company has no staff members yet. Vouchers can be given to staff only.",
              style: GoogleFonts.inter(color: kDark.withValues(alpha: 0.7)));
        }
        Widget choice(String key, String title, String sub) => Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => set(() => fundedBy = key),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: fundedBy == key ? kForest.withValues(alpha: 0.06) : Colors.white,
                    border: Border.all(color: fundedBy == key ? kForest : const Color(0xFFE2E8F0), width: 1.5),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: kDark)),
                    const SizedBox(height: 2),
                    Text(sub, style: GoogleFonts.inter(fontSize: 11.5, color: kDark.withValues(alpha: 0.6))),
                  ]),
                ),
              ),
            );
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text("Give a staff member money up front. They claim what they actually spent.",
              style: GoogleFonts.inter(fontSize: 12.5, color: kDark.withValues(alpha: 0.6))),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: recipientId,
            isExpanded: true,
            decoration: fieldDecoration("For whom", icon: Icons.person_rounded),
            items: staff.map((m) => DropdownMenuItem(value: m["userId"].toString(), child: Text(m["name"].toString()))).toList(),
            onChanged: (v) => set(() => recipientId = v),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => set(() {}),
            decoration: fieldDecoration("Amount ₹", icon: Icons.currency_rupee_rounded),
          ),
          const SizedBox(height: 10),
          TextField(controller: purpose, maxLength: 140, decoration: fieldDecoration("Purpose, e.g. Site visit travel", icon: Icons.flag_rounded)),
          Text("Paid by", style: labelStyle),
          const SizedBox(height: 6),
          Row(children: [
            choice("company", "Company", "Taken from Cash or Bank now"),
            const SizedBox(width: 8),
            choice("manager", "Me (Self)", "The company will owe you this"),
          ]),
          if (fundedBy == "company") ...[
            const SizedBox(height: 10),
            fundDropdown(s, fundId, (v) => set(() => fundId = v ?? "cash"), hint: "From fund"),
            if (short)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text("Only ${inr(fund.balance)} available in ${fund.name}. You can add money when you give it.",
                    style: GoogleFonts.inter(color: kTerracotta, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
          ],
          const SizedBox(height: 16),
          primaryButton("Give voucher", () async {
                  if (recipientId == null) return toast(ctx, "Choose who gets the voucher", error: true);
                  if (!(value > 0)) return toast(ctx, "Enter a valid amount", error: true);
                  if (purpose.text.trim().isEmpty) return toast(ctx, "Enter what the voucher is for", error: true);
                  if (short && !await topUpFund(ctx, s, fund, value)) return;
                  if (!ctx.mounted) return;
                  final res = await LedgerService.createVoucher(s.companyId, {
                    "userId": s.userId,
                    "recipientId": recipientId,
                    "amount": value,
                    "purpose": purpose.text.trim(),
                    "fundedBy": fundedBy,
                    if (fundedBy == "company") "fundId": fundId,
                  });
                  if (!ctx.mounted) return;
                  final name = staff.firstWhere((m) => m["userId"].toString() == recipientId)["name"];
                  if (handleResult(ctx, res, "Voucher of ${inr(value)} given to $name")) {
                    Navigator.pop(ctx);
                    notifyLedgerChanged();
                    onDone?.call();
                  }
                }),
        ]);
      }));
}

/// The recipient records what they actually spent; the money was already given, so nobody pays it again.
/// closing=true: the manager who created it records what the staff member used (saved in the staff member's name).
Future<void> showClaimVoucherSheet(BuildContext context, LedgerScope s, Map<String, dynamic> v, num held, {VoidCallback? onDone, bool closing = false}) {
  final staffName = nameOf(v["recipientId"], "the staff member");
  final voucherAmount = (v["amount"] as num?) ?? 0;
  final amount = TextEditingController(text: voucherAmount.toString());
  String category = "General";
  String receipt = "";
  final funded = v["fundedBy"] == "company"
      ? "${s.companyName}${(v["fundName"]?.toString().isNotEmpty ?? false) ? " · ${v["fundName"]}" : ""}"
      : "${nameOf(v["createdBy"], "Manager")} (personally)";

  Widget row(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: GoogleFonts.inter(color: kDark.withValues(alpha: 0.6), fontSize: 13)),
          const SizedBox(width: 12),
          Expanded(child: Text(value, textAlign: TextAlign.right, style: GoogleFonts.inter(color: kDark, fontSize: 13, fontWeight: bold ? FontWeight.bold : FontWeight.w500))),
        ]),
      );

  return showLedgerSheet(context, closing ? "Close voucher" : "Claim voucher", (ctx) => StatefulBuilder(builder: (ctx, set) {
        final value = double.tryParse(amount.text.trim()) ?? 0;
        final extra = value > voucherAmount ? _round(value - voucherAmount) : 0;
        final fromHeld = extra < held ? extra : (held > 0 ? held : 0);
        final owed = _round(extra - fromHeld);
        final left = value > 0 && value < voucherAmount ? _round(voucherAmount - value) : 0;
        final lines = <String>[
          if (left > 0) closing ? "${inr(left)} stays with $staffName as their voucher balance." : "${inr(left)} stays with you as your voucher balance.",
          if (extra > 0 && fromHeld > 0) closing ? "${inr(fromHeld)} comes from $staffName's voucher balance." : "${inr(fromHeld)} comes from your voucher balance.",
          if (owed > 0) closing ? "The company will owe $staffName ${inr(owed)}." : "The company will owe you ${inr(owed)}.",
          if (value == voucherAmount) "Uses the full voucher.",
        ];
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(closing ? "Record what $staffName actually used. It is saved as $staffName's expense and the voucher is marked as used." : "Enter what you actually spent. The money was already given to you.",
              style: GoogleFonts.inter(fontSize: 12.5, color: kDark.withValues(alpha: 0.6))),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(12), border: Border.all(color: kMint.withValues(alpha: 0.5))),
            child: Column(children: [
              row("Purpose", v["purpose"]?.toString() ?? "", bold: true),
              row("Voucher amount", inr(voucherAmount), bold: true),
              row("Given by", nameOf(v["createdBy"], "Manager")),
              row("Paid by", funded),
              row("Given on", dateLabel(v["createdAt"])),
            ]),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => set(() {}),
            decoration: fieldDecoration(closing ? "Amount used ₹" : "Amount spent ₹", icon: Icons.currency_rupee_rounded),
          ),
          if (value > 0 && lines.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(lines.join(" "),
                  style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: owed > 0 ? kTerracotta : kForest)),
            ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: category,
            isExpanded: true,
            decoration: fieldDecoration("Category (optional)", icon: Icons.category_rounded),
            items: companyCategories(s.company).map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
            onChanged: (c) => set(() => category = c ?? "General"),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: kForest, side: const BorderSide(color: kForest)),
            onPressed: () async {
              final img = await pickReceiptImage(ctx);
              if (img != null) set(() => receipt = img);
            },
            icon: Icon(receipt.isEmpty ? Icons.photo_camera_rounded : Icons.check_circle_rounded),
            label: Text(receipt.isEmpty ? "Attach receipt (optional)" : "Receipt attached · tap to replace"),
          ),
          const SizedBox(height: 16),
          primaryButton(closing ? "Close voucher" : "Proceed to claim", () async {
            if (!(value > 0)) return toast(ctx, closing ? "Enter the amount used" : "Enter the amount you spent", error: true);
            final body = <String, dynamic>{
              "userId": s.userId,
              "amount": value,
              "category": category,
              if (receipt.isNotEmpty) "attachment": receipt,
            };
            final res = closing ? await LedgerService.closeVoucher(v["_id"].toString(), body) : await LedgerService.claimVoucher(v["_id"].toString(), body);
            if (!ctx.mounted) return;
            final msg = closing
                ? (left > 0 ? "Voucher closed · ${inr(left)} stays with $staffName" : "Voucher closed · ${inr(value)} used by $staffName")
                : (left > 0 ? "Claimed ${inr(value)} · ${inr(left)} stays with you" : "Claimed ${inr(value)}");
            if (handleResult(ctx, res, msg)) {
              Navigator.pop(ctx);
              notifyLedgerChanged();
              onDone?.call();
            }
          }),
        ]);
      }));
}

/// Staff hands unused voucher balance back; company Cash goes up once a manager confirms they got it.
Future<void> showHandBackSheet(BuildContext context, LedgerScope s, num held, {VoidCallback? onDone}) {
  final amount = TextEditingController(text: held.toString());
  final note = TextEditingController();
  return showLedgerSheet(context, "Hand back balance", (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text("You hold ${inr(held)} of voucher money. Give the cash to a manager; it goes back into company Cash when they confirm.",
            style: GoogleFonts.inter(fontSize: 12.5, color: kDark.withValues(alpha: 0.6))),
        const SizedBox(height: 12),
        TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: fieldDecoration("Amount ₹", icon: Icons.currency_rupee_rounded)),
        const SizedBox(height: 10),
        TextField(controller: note, maxLength: 140, decoration: fieldDecoration("Note (optional), e.g. Gave cash to Ravi", icon: Icons.notes_rounded)),
        const SizedBox(height: 8),
        primaryButton("Send hand-back", () async {
          final value = double.tryParse(amount.text.trim()) ?? 0;
          if (!(value > 0)) return toast(ctx, "Enter a valid amount", error: true);
          if (value > held) return toast(ctx, "You hold only ${inr(held)}", error: true);
          final res = await LedgerService.requestAdvanceReturn(s.companyId, s.userId, value, note.text.trim());
          if (!ctx.mounted) return;
          if (handleResult(ctx, res, "Hand-back of ${inr(value)} sent · a manager will confirm")) {
            Navigator.pop(ctx);
            notifyLedgerChanged();
            onDone?.call();
          }
        }),
      ]));
}

/// Staff Home: open vouchers (highlighted, each with Claim) and hand-backs waiting for a manager.
class StaffVoucherSection extends StatefulWidget {
  final LedgerScope scope;
  const StaffVoucherSection({super.key, required this.scope});

  @override
  State<StaffVoucherSection> createState() => _StaffVoucherSectionState();
}

class _StaffVoucherSectionState extends State<StaffVoucherSection> with LedgerAutoRefresh {
  @override
  void onLedgerChanged() => _load();

  @override
  Set<String> get ledgerTopics => const {"vouchers", "balances"};

  List<Map<String, dynamic>> _vouchers = [];
  List<Map<String, dynamic>> _returns = [];
  List<Map<String, dynamic>> _people = [];
  num _held = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await LedgerService.vouchers(widget.scope.companyId, widget.scope.userId);
    if (!mounted || res["success"] != true) return;
    setState(() {
      _vouchers = List<Map<String, dynamic>>.from(res["vouchers"] ?? const []);
      _returns = List<Map<String, dynamic>>.from(res["returns"] ?? const []);
      _people = List<Map<String, dynamic>>.from(res["people"] ?? const []);
      _held = (res["myAdvance"] as num?) ?? 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final admin = widget.scope.isAdmin;
    final open = _vouchers.where((v) => v["status"] == "open").toList();
    final pending = admin ? <Map<String, dynamic>>[] : _returns.where((r) => r["status"] == "pending" || r["status"] == "processing").toList();
    num heldOf(Map<String, dynamic> v) {
      final h = (_people.where((p) => idOf(p["userId"]) == idOf(v["recipientId"])).firstOrNull?["held"] as num?) ?? 0;
      return h > 0 ? h : 0;
    }
    if (open.isEmpty && pending.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(2, 12, 2, 6),
        child: Text(admin ? "Open vouchers" : "Vouchers", style: GoogleFonts.inter(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
      ),
      ...open.map((v) => VoucherTicket(
            scope: widget.scope,
            voucher: v,
            onClaim: () => showClaimVoucherSheet(context, widget.scope, v, _held, onDone: _load),
            onClose: () => showClaimVoucherSheet(context, widget.scope, v, heldOf(v), closing: true, onDone: _load),
          )),
      ...pending.map((r) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
            child: Text("Hand-back of ${inr(r["amount"])} waiting for a manager to confirm · ${dateLabel(r["createdAt"])}",
                style: GoogleFonts.inter(color: kForest.withValues(alpha: 0.7), fontSize: 12.5)),
          )),
    ]);
  }
}

/// An open voucher drawn as a ticket (web's voucher-ticket): details on the left, a perforated line, and a stub
/// with the amount and the action — Claim (staff), Close + Cancel · Delete (the manager who created it).
class VoucherTicket extends StatelessWidget {
  final LedgerScope scope;
  final Map<String, dynamic> voucher;
  final VoidCallback onClaim;
  final VoidCallback onClose;
  const VoucherTicket({super.key, required this.scope, required this.voucher, required this.onClaim, required this.onClose});

  static const double _stub = 128;
  static const Color _paper = Colors.white;
  static const Color _ink = kForest;

  @override
  Widget build(BuildContext context) {
    final v = voucher;
    final admin = scope.isAdmin;
    final mine = idOf(v["createdBy"]) == scope.userId;
    final created = DateTime.tryParse(v["createdAt"]?.toString() ?? "")?.toLocal();
    final now = DateTime.now();
    final givenToday = created != null && created.year == now.year && created.month == now.month && created.day == now.day;
    final person = admin ? nameOf(v["recipientId"], "Staff") : nameOf(v["createdBy"], "Manager");
    final paidBy = v["fundedBy"] == "company" ? "Paid by company" : "Paid by ${mine ? "you" : nameOf(v["createdBy"], "manager")}";
    final meta = [paidBy, dateLabel(v["createdAt"]), if (admin) "by ${mine ? "you" : nameOf(v["createdBy"], "manager")}"].join(" · ");

    Widget link(String label, Color color, VoidCallback onTap) => InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            child: Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
          ),
        );

    final Widget action;
    if (!admin && scope.can("vouchers")) {
      action = _stubButton("Claim", onClaim);
    } else if (admin && mine && scope.can("vouchers")) {
      action = Column(children: [
        _stubButton("Close", onClose),
        const SizedBox(height: 6),
        // scales down on narrow phones instead of overflowing the stub
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            link("Cancel", kForest, () => cancelVoucherFlow(context, scope, v)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Text("·", style: GoogleFonts.inter(fontSize: 12, color: kForest.withValues(alpha: 0.35))),
            ),
            link("Delete", kForest, () => deleteVoucherFlow(context, scope, v)),
          ]),
        ),
      ]);
    } else if (admin) {
      action = Text("Only ${nameOf(v["createdBy"], "its creator")} can close it",
          textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 11, color: kForest.withValues(alpha: 0.55)));
    } else {
      action = const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PhysicalShape(
        clipper: const _TicketClipper(stubWidth: _stub, notch: 9),
        color: _paper,
        elevation: 3,
        shadowColor: Colors.black.withValues(alpha: 0.35),
        child: InkWell(
          onTap: () => showVoucherDetail(context, scope, v),
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // left: what it is and who it's for
              Expanded(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                    Row(children: [
                      Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: kForest.withValues(alpha: 0.12))),
                        child: const Icon(Icons.confirmation_number_outlined, size: 15, color: kForest),
                      ),
                      const SizedBox(width: 7),
                      Flexible(
                        child: Text(admin ? "OPEN VOUCHER" : "NEW VOUCHER",
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(color: _ink, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
                      ),
                      if (givenToday) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: kForest.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(99)),
                          child: Text("Today", style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w700, color: _ink)),
                        ),
                      ],
                    ]),
                    const SizedBox(height: 8),
                    Text(v["purpose"]?.toString() ?? "Voucher",
                        maxLines: 2, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(color: kForest, fontWeight: FontWeight.w700, fontSize: 15.5)),
                    const SizedBox(height: 6),
                    Row(children: [
                      CircleAvatar(
                        radius: 9,
                        backgroundColor: kForest,
                        child: Text(person.isEmpty ? "?" : person.characters.first.toUpperCase(),
                            style: GoogleFonts.inter(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(admin ? person : "From $person",
                            overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: kForest)),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    Text(meta, maxLines: 2, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 11, color: kForest.withValues(alpha: 0.55))),
                  ]),
                ),
              ),
              // perforation
              const SizedBox(width: 1, child: CustomPaint(painter: _DashPainter())),
              // stub: amount + action
              SizedBox(
                width: _stub,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text("AMOUNT", style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: kForest.withValues(alpha: 0.5))),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(inr(v["amount"]), style: GoogleFonts.inter(color: kForest, fontSize: 19, fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(height: 10),
                    action,
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _stubButton(String label, VoidCallback onTap) => SizedBox(
        width: double.infinity,
        height: 36,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: kForest,
            foregroundColor: Colors.white,
            padding: EdgeInsets.zero,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: onTap,
          child: Text(label, style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13.5)),
        ),
      );
}

/// Rounded card with two half-circle notches where the stub tears off.
class _TicketClipper extends CustomClipper<Path> {
  final double stubWidth;
  final double notch;
  const _TicketClipper({required this.stubWidth, required this.notch});

  @override
  Path getClip(Size size) {
    final x = size.width - stubWidth;
    final card = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(16)));
    final holes = Path()
      ..addOval(Rect.fromCircle(center: Offset(x, 0), radius: notch))
      ..addOval(Rect.fromCircle(center: Offset(x, size.height), radius: notch));
    return Path.combine(PathOperation.difference, card, holes);
  }

  @override
  bool shouldReclip(_TicketClipper old) => old.stubWidth != stubWidth || old.notch != notch;
}

/// Vertical dashed perforation between the ticket and its stub.
class _DashPainter extends CustomPainter {
  const _DashPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = kForest.withValues(alpha: 0.35)
      ..strokeWidth = 1.4;
    const dash = 5.0, gap = 4.0;
    for (var y = 12.0; y < size.height - 12; y += dash + gap) {
      canvas.drawLine(Offset(0.5, y), Offset(0.5, y + dash), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

const Map<String, (String, Color, Color)> _voucherStatus = {
  "open": ("Open", Color(0xFFECFDF5), Color(0xFF047857)),
  "claiming": ("Claiming…", Color(0xFFFFF7ED), Color(0xFFC2410C)),
  "claimed": ("Claimed", Color(0xFFEEF2FF), Color(0xFF4338CA)),
  "cancelled": ("Cancelled", Color(0xFFF1F5F9), Color(0xFF64748B)),
};

Widget _voucherPill(String? status) {
  final st = _voucherStatus[status] ?? _voucherStatus["open"]!;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: st.$2, borderRadius: BorderRadius.circular(20)),
    child: Text(st.$1, style: GoogleFonts.inter(color: st.$3, fontSize: 10.5, fontWeight: FontWeight.bold)),
  );
}

/// Managers: every voucher, what each staff member holds, and hand-backs to confirm (web's Vouchers page).
class VouchersPage extends StatefulWidget {
  final LedgerScope scope;
  const VouchersPage({super.key, required this.scope});

  @override
  State<VouchersPage> createState() => _VouchersPageState();
}

class _VouchersPageState extends State<VouchersPage> with LedgerAutoRefresh {
  @override
  void onLedgerChanged() => _load();

  @override
  Set<String> get ledgerTopics => const {"vouchers", "balances"};

  LedgerScope get s => widget.scope;
  Map<String, dynamic>? _data;
  String _filter = "all";
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await LedgerService.vouchers(s.companyId, s.userId);
    if (!mounted) return;
    if (res["success"] == true) {
      setState(() => _data = res);
    } else {
      toast(context, res["message"]?.toString() ?? "Could not load vouchers", error: true);
    }
  }

  Future<void> _decide(Map<String, dynamic> r, bool accept) async {
    final id = r["_id"].toString();
    setState(() => _busy.add(id));
    final res = await LedgerService.decideAdvanceReturn(id, s.userId, accept);
    if (!mounted) return;
    setState(() => _busy.remove(id));
    if (handleResult(context, res, accept ? "${inr(r["amount"])} received into Cash" : "Hand-back declined")) notifyLedgerChanged();
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final vouchers = List<Map<String, dynamic>>.from(d?["vouchers"] ?? const []);
    final shown = _filter == "all" ? vouchers : vouchers.where((v) => v["status"] == _filter).toList();
    final pending = List<Map<String, dynamic>>.from(d?["returns"] ?? const []).where((r) => r["status"] == "pending").toList();
    final people = List<Map<String, dynamic>>.from(d?["people"] ?? const [])
        .where((p) => ((p["given"] as num?) ?? 0) != 0 || ((p["held"] as num?) ?? 0) != 0)
        .toList();
    num total(String f) => people.fold<num>(0, (sum, p) {
          final v = (p[f] as num?) ?? 0;
          return sum + (f == "held" && v < 0 ? 0 : v);
        });

    Widget card({required Widget child}) => Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
          clipBehavior: Clip.antiAlias,
          child: child,
        );
    Widget tile(String label, num value, {Color color = kForest}) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: kDark.withValues(alpha: 0.55))),
              const SizedBox(height: 4),
              FittedBox(fit: BoxFit.scaleDown, child: Text(inr(value), style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: color))),
            ]),
          ),
        );

    return Theme(
      data: sheetTheme,
      child: Scaffold(
        backgroundColor: kForest,
        appBar: AppBar(
          backgroundColor: kForest,
          foregroundColor: Colors.white,
          elevation: 0,
          title: Text("Vouchers", style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: kForestDark,
          onPressed: () => showCreateVoucherSheet(context, s, onDone: _load),
          icon: const Icon(Icons.add_rounded, color: Colors.white),
          label: Text("Create voucher", style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
        body: d == null
            ? const Center(child: CircularProgressIndicator(color: Colors.white))
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 96), children: [
                  Row(children: [
                    tile("GIVEN (NOT CANCELLED)", total("given")),
                    const SizedBox(width: 8),
                    tile("OPEN, NOT CLAIMED", total("open")),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [tile("HELD BY STAFF", total("held"), color: total("held") > 0 ? kTerracotta : kForest)]),
                  if (pending.isNotEmpty) ...[
                    sectionTitle("Hand-backs to confirm"),
                    card(
                      child: Column(children: [
                        for (final r in pending)
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Expanded(
                                    child: Text("${nameOf(r["userId"], "Staff")} is handing back cash",
                                        style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: kDark))),
                                Text(inr(r["amount"]), style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: kDark)),
                              ]),
                              Text("${dateLabel(r["createdAt"])}${(r["note"]?.toString() ?? "").isNotEmpty ? " · ${r["note"]}" : ""}",
                                  style: GoogleFonts.inter(fontSize: 12, color: kDark.withValues(alpha: 0.55))),
                              const SizedBox(height: 8),
                              if (idOf(r["userId"]) == s.userId)
                                Text("Another manager confirms", style: GoogleFonts.inter(fontSize: 12, color: kDark.withValues(alpha: 0.55)))
                              else
                                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                                  OutlinedButton(
                                      onPressed: _busy.contains(r["_id"].toString()) ? null : () => _decide(r, false), child: const Text("Decline")),
                                  const SizedBox(width: 8),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(backgroundColor: kForest, foregroundColor: Colors.white),
                                    onPressed: _busy.contains(r["_id"].toString()) ? null : () => _decide(r, true),
                                    child: const Text("Received"),
                                  ),
                                ]),
                            ]),
                          ),
                      ]),
                    ),
                  ],
                  sectionTitle("By staff member"),
                  card(
                    child: people.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(14),
                            child: Text("No vouchers given yet.", style: GoogleFonts.inter(color: kDark.withValues(alpha: 0.6))))
                        : Column(children: [
                            for (final p in people)
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                child: Row(children: [
                                  Expanded(
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text(p["name"]?.toString() ?? "", style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: kDark)),
                                      Text("Given ${inr(p["given"])} · Claimed ${inr(p["claimed"])} · Open ${inr(p["open"])}",
                                          style: GoogleFonts.inter(fontSize: 11.5, color: kDark.withValues(alpha: 0.55))),
                                    ]),
                                  ),
                                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                    Text("HOLDING", style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w700, color: kDark.withValues(alpha: 0.5))),
                                    Text(inr(((p["held"] as num?) ?? 0) > 0 ? p["held"] : 0),
                                        style: GoogleFonts.inter(
                                            fontWeight: FontWeight.w800, color: ((p["held"] as num?) ?? 0) > 0 ? kTerracotta : kDark)),
                                  ]),
                                ]),
                              ),
                          ]),
                  ),
                  Row(children: [
                    Expanded(child: sectionTitle("All vouchers")),
                    DropdownButton<String>(
                      value: _filter,
                      dropdownColor: kForestDark,
                      style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600),
                      iconEnabledColor: Colors.white,
                      underline: const SizedBox.shrink(),
                      items: const [
                        DropdownMenuItem(value: "all", child: Text("All")),
                        DropdownMenuItem(value: "open", child: Text("Open")),
                        DropdownMenuItem(value: "claimed", child: Text("Claimed")),
                        DropdownMenuItem(value: "cancelled", child: Text("Cancelled")),
                      ],
                      onChanged: (v) => setState(() => _filter = v ?? "all"),
                    ),
                  ]),
                  if (shown.isEmpty)
                    card(
                        child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Text("No vouchers here.", style: GoogleFonts.inter(color: kDark.withValues(alpha: 0.6)))))
                  else
                    card(
                      child: Column(children: [
                        for (var i = 0; i < shown.length; i++) ...[
                          if (i > 0) const Divider(height: 1, color: Color(0xFFF1F5F9)),
                          _voucherRow(shown[i]),
                        ],
                      ]),
                    ),
                ]),
              ),
      ),
    );
  }

  /// Voucher balance the recipient already holds (for the close sheet's over-spend line).
  num _heldOf(Map<String, dynamic> v) {
    final p = List<Map<String, dynamic>>.from(_data?["people"] ?? const []).where((p) => idOf(p["userId"]) == idOf(v["recipientId"])).firstOrNull;
    final h = (p?["held"] as num?) ?? 0;
    return h > 0 ? h : 0;
  }

  Widget _voucherRow(Map<String, dynamic> v) {
    final funded = v["fundedBy"] == "company"
        ? "Company${(v["fundName"]?.toString() ?? "").isNotEmpty ? " · ${v["fundName"]}" : ""}"
        : "${nameOf(v["createdBy"], "Manager")} (self)";
    final claimed = v["status"] == "claimed";
    final left = claimed ? _round(((v["amount"] as num?) ?? 0) - ((v["claimedAmount"] as num?) ?? 0)) : 0;
    final owed = (v["owedToRecipient"] as num?) ?? 0;
    return InkWell(
      onTap: () => showVoucherDetail(context, s, v),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(v["purpose"]?.toString() ?? "", style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: kDark))),
            Text(inr(v["amount"]), style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: kDark)),
          ]),
          Text("To ${nameOf(v["recipientId"], "Staff")} · by ${nameOf(v["createdBy"], "Manager")} · ${dateLabel(v["createdAt"])} · Paid by $funded",
              style: GoogleFonts.inter(fontSize: 12, color: kDark.withValues(alpha: 0.55))),
          if (claimed)
            Text(
              "Claimed ${inr(v["claimedAmount"])} on ${dateLabel(v["claimedAt"])}${left > 0 ? " · ${inr(left)} left with them" : ""}${owed > 0 ? " · company owes them ${inr(owed)}" : ""}",
              style: GoogleFonts.inter(fontSize: 12, color: kDark.withValues(alpha: 0.55)),
            ),
          if (v["closedBy"] != null)
            Text("Closed by ${nameOf(v["closedBy"], "Manager")} · ${dateLabel(v["closedAt"])}", style: GoogleFonts.inter(fontSize: 12, color: kDark.withValues(alpha: 0.55))),
          const SizedBox(height: 6),
          Row(children: [
            _voucherPill(v["status"]?.toString()),
            const Spacer(),
            if (v["status"] == "open" && idOf(v["createdBy"]) == s.userId && s.can("vouchers")) ...[
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: kForest, foregroundColor: Colors.white, visualDensity: VisualDensity.compact),
                onPressed: () => showClaimVoucherSheet(context, s, v, _heldOf(v), closing: true, onDone: _load),
                child: const Text("Close"),
              ),
              const SizedBox(width: 6),
            ],
            if (v["status"] == "open" && idOf(v["createdBy"]) == s.userId && s.can("vouchers")) voucherActionsMenu(context, s, v),
          ]),
        ]),
      ),
    );
  }
}

/// ⋮ menu with Cancel and Delete for the manager who created an open voucher.
Widget voucherActionsMenu(BuildContext context, LedgerScope s, Map<String, dynamic> v) => PopupMenuButton<String>(
      tooltip: "More",
      icon: const Icon(Icons.more_vert_rounded, color: kDark),
      onSelected: (a) => a == "delete" ? deleteVoucherFlow(context, s, v) : cancelVoucherFlow(context, s, v),
      itemBuilder: (_) => const [
        PopupMenuItem(value: "cancel", child: Text("Cancel voucher")),
        PopupMenuItem(value: "delete", child: Text("Delete voucher", style: TextStyle(color: kTerracotta))),
      ],
    );

/// Asks first, then deletes an unclaimed voucher: money back, and it disappears from the lists.
Future<void> deleteVoucherFlow(BuildContext context, LedgerScope s, Map<String, dynamic> v) async {
  final back = v["fundedBy"] == "company"
      ? ((v["fundName"]?.toString() ?? "").isNotEmpty ? v["fundName"] : "the company fund")
      : "${nameOf(v["createdBy"], "the manager")} (removed from what the company owes them)";
  final ok = await confirmDialog(
    context,
    "Delete voucher?",
    "${inr(v["amount"])} for \"${v["purpose"]}\" goes back to $back, and the voucher is removed from the lists. Use Cancel instead to keep it listed as cancelled.",
    confirmLabel: "Delete voucher",
    danger: true,
  );
  if (!ok || !context.mounted) return;
  final res = await LedgerService.deleteVoucher(v["_id"].toString(), s.userId);
  if (!context.mounted) return;
  if (handleResult(context, res, "Voucher deleted · ${inr(v["amount"])} returned")) notifyLedgerChanged();
}

/// Asks first, then cancels an open voucher; the money goes back where it came from.
Future<void> cancelVoucherFlow(BuildContext context, LedgerScope s, Map<String, dynamic> v) async {
  final back = v["fundedBy"] == "company"
      ? ((v["fundName"]?.toString() ?? "").isNotEmpty ? v["fundName"] : "the company fund")
      : "${nameOf(v["createdBy"], "the manager")} (removed from what the company owes them)";
  final ok = await confirmDialog(context, "Cancel voucher?", "${inr(v["amount"])} for \"${v["purpose"]}\" goes back to $back.",
      confirmLabel: "Cancel voucher", danger: true);
  if (!ok || !context.mounted) return;
  final res = await LedgerService.cancelVoucher(v["_id"].toString(), s.userId);
  if (!context.mounted) return;
  if (handleResult(context, res, "Voucher cancelled · ${inr(v["amount"])} returned")) notifyLedgerChanged();
}

/// Everything about one voucher, with the claim receipt (web's VoucherDetailModal).
Future<void> showVoucherDetail(BuildContext context, LedgerScope s, Map<String, dynamic> v) {
  final claimed = v["status"] == "claimed";
  final amount = (v["amount"] as num?) ?? 0;
  final claimedAmount = (v["claimedAmount"] as num?) ?? 0;
  final left = claimed ? _round(amount - claimedAmount) : 0;
  final usedFromVoucher = claimedAmount < amount ? claimedAmount : amount;
  final fromHeldRaw = ((v["fromAdvance"] as num?) ?? 0) - usedFromVoucher;
  final fromHeld = claimed && fromHeldRaw > 0 ? _round(fromHeldRaw) : 0;
  final owed = (v["owedToRecipient"] as num?) ?? 0;
  String? receipt;
  bool loading = v["expenseId"] != null;
  bool started = false;

  Widget row(String label, String value, {String? sub, Color? color, IconData? icon}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (icon != null) ...[Icon(icon, size: 15, color: kForest.withValues(alpha: 0.7)), const SizedBox(width: 8)],
          Text(label.toUpperCase(),
              style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: kDark.withValues(alpha: 0.5))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(value, textAlign: TextAlign.right, style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: color ?? kDark)),
              if (sub != null) Text(sub, textAlign: TextAlign.right, style: GoogleFonts.inter(fontSize: 11.5, color: kDark.withValues(alpha: 0.55))),
            ]),
          ),
        ]),
      );

  return showLedgerSheet(context, v["purpose"]?.toString() ?? "Voucher", (ctx) => StatefulBuilder(builder: (ctx, set) {
        if (!started && v["expenseId"] != null) {
          started = true;
          LedgerService.expenseReceipts(idOf(v["expenseId"]), s.userId).then((res) {
            if (!ctx.mounted) return;
            final a = res["success"] == true ? (res["attachment"]?.toString() ?? "") : "";
            set(() {
              loading = false;
              receipt = a.isEmpty ? null : (a.startsWith("data:") ? a : "data:image/jpeg;base64,$a");
            });
          });
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _voucherPill(v["status"]?.toString()),
            const Spacer(),
            Text(inr(amount), style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold, color: kForest)),
          ]),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(12)),
            child: Column(children: [
              row("Given to", nameOf(v["recipientId"], "Staff"), icon: Icons.person_outline_rounded),
              row("Given by", nameOf(v["createdBy"], "Manager"), icon: Icons.badge_outlined),
              row("Given on", dateLabel(v["createdAt"]), icon: Icons.calendar_today_rounded),
              v["fundedBy"] == "company"
                  ? row("Paid by", "Company",
                      sub: "From ${(v["fundName"]?.toString() ?? "").isNotEmpty ? v["fundName"] : "company fund"}", icon: Icons.account_balance_outlined)
                  : row("Paid by", "${nameOf(v["createdBy"], "Manager")} (self)",
                      sub: "The company owes them this amount", icon: Icons.account_balance_wallet_outlined),
              if (claimed) ...[
                row("Amount spent", inr(claimedAmount)),
                row("Claimed on", dateLabel(v["claimedAt"])),
                if (left > 0) row("Left with staff", inr(left), sub: "Kept as their voucher balance", color: kTerracotta),
                if (fromHeld > 0) row("From earlier balance", inr(fromHeld)),
                if (owed > 0) row("Company owes staff", inr(owed), sub: "Spent more than they held", color: kTerracotta),
              ],
              if (v["closedBy"] != null) row("Closed by", nameOf(v["closedBy"], "Manager"), sub: "Recorded as used by ${nameOf(v["recipientId"], "staff")} · ${dateLabel(v["closedAt"])}"),
              if (v["status"] == "cancelled") ...[
                row("Cancelled by", nameOf(v["cancelledBy"], "Manager")),
                if (v["cancelledAt"] != null) row("Cancelled on", dateLabel(v["cancelledAt"])),
              ],
            ]),
          ),
          if (v["expenseId"] != null) ...[
            const SizedBox(height: 12),
            Text("CLAIM RECEIPT", style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w700, color: kDark.withValues(alpha: 0.5))),
            const SizedBox(height: 6),
            if (loading)
              const LinearProgressIndicator(color: kForest)
            else if (receipt == null)
              Text("No receipt was attached.", style: GoogleFonts.inter(fontSize: 13, color: kDark.withValues(alpha: 0.6)))
            else
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.memory(base64Decode(receipt!.substring(receipt!.indexOf(",") + 1)), height: 220, fit: BoxFit.contain),
              ),
          ],
          const SizedBox(height: 18),
          // the creating manager: close it as used (amount editable), or give the money back (Cancel keeps it listed)
          if (v["status"] == "open" && idOf(v["createdBy"]) == s.userId && s.can("vouchers")) ...[
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: kForest,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  showClaimVoucherSheet(context, s, v, 0, closing: true);
                },
                icon: const Icon(Icons.check_circle_outline_rounded, size: 20),
                label: Text("Close voucher", style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 12),
              child: Center(
                child: Text("Records it as used by ${nameOf(v["recipientId"], "staff")} · you can edit the amount",
                    textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 11.5, color: kDark.withValues(alpha: 0.55))),
              ),
            ),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kDark,
                    side: const BorderSide(color: Color(0xFFE2E8F0)),
                    minimumSize: const Size.fromHeight(44),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await cancelVoucherFlow(context, s, v);
                  },
                  icon: const Icon(Icons.undo_rounded, size: 18),
                  label: Text("Cancel", style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kTerracotta,
                    backgroundColor: kTerracotta.withValues(alpha: 0.05),
                    side: BorderSide(color: kTerracotta.withValues(alpha: 0.35)),
                    minimumSize: const Size.fromHeight(44),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await deleteVoucherFlow(context, s, v);
                  },
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: Text("Delete", style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                ),
              ),
            ]),
          ] else
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Done"),
              ),
            ),
        ]);
      }));
}
