import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'update_reminder_page.dart';
import 'package:card/config/app_config.dart';
import 'card_home.dart';
import 'view_card_screen.dart';
import 'home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── 20 unique card styles (same as view_card_screen) ─────────────────────────
enum _CardStyle {
  sbi, hdfc, kotak, axisRibbon, flipkart, yes, icici,
  amexGold, amexBlue, federal, indusind, rbl, hsbc, pnb,
  idfc, idbi, paytm, stanchart, canara, tmb,
}

_CardStyle _styleForBank(String bankName) {
  final b = bankName.toLowerCase().trim();
  if (b.contains('sbi') || b.contains('state bank'))        return _CardStyle.sbi;
  if (b.contains('hdfc'))                                    return _CardStyle.hdfc;
  if (b.contains('kotak'))                                   return _CardStyle.kotak;
  if (b.contains('axis'))                                    return _CardStyle.axisRibbon;
  if (b.contains('flipkart'))                                return _CardStyle.flipkart;
  if (b.contains('yes'))                                     return _CardStyle.yes;
  if (b.contains('icici') || b.contains('amazon'))          return _CardStyle.icici;
  if (b.contains('amex gold') || b.contains('american express gold')) return _CardStyle.amexGold;
  if (b.contains('amex') || b.contains('american'))         return _CardStyle.amexBlue;
  if (b.contains('federal'))                                 return _CardStyle.federal;
  if (b.contains('indus'))                                   return _CardStyle.indusind;
  if (b.contains('rbl'))                                     return _CardStyle.rbl;
  if (b.contains('hsbc'))                                    return _CardStyle.hsbc;
  if (b.contains('pnb') || b.contains('punjab'))            return _CardStyle.pnb;
  if (b.contains('idfc') || b.contains('onecard') || b.contains('slice')) return _CardStyle.idfc;
  if (b.contains('idbi') || b.contains('bandhan'))          return _CardStyle.idbi;
  if (b.contains('paytm') || b.contains('airtel') || b.contains('jupiter')) return _CardStyle.paytm;
  if (b.contains('standard') || b.contains('scbank'))       return _CardStyle.stanchart;
  if (b.contains('canara') || b.contains('union') || b.contains('boi') || b.contains('central')) return _CardStyle.canara;
  if (b.contains('tmb') || b.contains('tamilnadu'))         return _CardStyle.tmb;
  if (bankName.isEmpty) return _CardStyle.idfc;
  final index = bankName.codeUnits.reduce((a, b) => a + b) % _CardStyle.values.length;
  return _CardStyle.values[index];
}

// ── palette ───────────────────────────────────────────────────────────────────
const Color _bg   = Color(0xFF0A0A0F);
const Color _card = Color(0xFF13131A);
const Color _cyan = Color(0xFF00D9FF);
const Color _green= Color(0xFF00E5A0);
const Color _red  = Color(0xFFFF4D6D);

class ViewReminderPage extends StatefulWidget {
  final String userId;
  final String userName;
  const ViewReminderPage({super.key, required this.userId, required this.userName});
  @override State<ViewReminderPage> createState() => _ViewReminderPageState();
}

class _ViewReminderPageState extends State<ViewReminderPage> {
  List reminders = [];
  bool isLoading  = true;
  int  _selectedIndex = 0;
  double get totalDueAmount {
    double total = 0;

    for (var reminder in reminders) {
      if ((reminder["status"] ?? "unpaid") == "unpaid") {
        total +=
            double.tryParse(reminder["amount"]?.toString() ?? "0") ?? 0;
      }
    }

    return total;
  }


  @override void initState() { super.initState(); fetchReminders(); }

  // ── FETCH ─────────────────────────────────────────────────────────────────
  Future<void> fetchReminders() async {
    try {
      final res  = await http.get(Uri.parse("${AppConfig.reminders}?userId=${widget.userId}"));
      final data = jsonDecode(res.body);
      if (!mounted) return;
      setState(() { reminders = data["data"] ?? []; isLoading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);
      _snack("Error: $e", error: true);
    }

  }

  // ── DELETE ────────────────────────────────────────────────────────────────
  Future<void> deleteReminder(String id) async {
    try {
      final res  = await http.delete(Uri.parse("${AppConfig.reminders}?id=$id"));
      final data = jsonDecode(res.body);
      if (!mounted) return;
      if (res.statusCode == 200) { _snack(data["message"]); fetchReminders(); }
      else { _snack(data["message"] ?? "Delete failed", error: true); }
    } catch (e) { _snack("Error: $e", error: true); }
  }

  void _snack(String msg, {bool error = false}) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: error ? _red : _green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        content: Text(msg, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ));

  String _date(String? d) {
    if (d == null) return "N/A";
    final dt = DateTime.parse(d);
    return "${dt.day.toString().padLeft(2,'0')}-${dt.month.toString().padLeft(2,'0')}-${dt.year}";
  }

  String _fKey(String k) {
    switch (k) {
      case "7_days_before": return "7 Days Before";
      case "3_days_before": return "3 Days Before";
      case "1_day_before":  return "1 Day Before";
      case "due_date":      return "Due Date";
      case "1_day_after":   return "1 Day After";
      default:              return k;
    }
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg, elevation: 0, centerTitle: true,
        leading: Padding(padding: const EdgeInsets.all(8),
            child: CircleAvatar(backgroundColor: Colors.transparent,
                child: Image.asset("assets/images/logo.png"))),
        title: ShaderMask(
          shaderCallback: (b) => const LinearGradient(
              colors: [Color(0xFF7DF9FF), Color(0xFF4DEEFF), Color(0xFF00D9FF)]).createShader(b),
          child: const Text("View Reminders",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: _cyan, size: 28),
            onPressed: () => showDialog(context: context,
                builder: (_) => _ConfirmDlg(
                  title: "Logout", message: "Are you sure you want to logout?",
                  confirmLabel: "Logout", confirmColor: _cyan,
                  onConfirm: () async {
                    final p = await SharedPreferences.getInstance();
                    await p.clear();
                    if (!context.mounted) return;
                    Navigator.pushAndRemoveUntil(context,
                        MaterialPageRoute(builder: (_) => const HomeScreen()), (r) => false);
                  },
                )),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: _cyan, backgroundColor: _card, onRefresh: fetchReminders,
        child: isLoading
            ? const Center(child: CircularProgressIndicator(color: _cyan))
            : reminders.isEmpty
            ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(width: 80, height: 80,
              decoration: BoxDecoration(color: _cyan.withValues(alpha: 0.08), shape: BoxShape.circle,
                  border: Border.all(color: _cyan.withValues(alpha: 0.2), width: 1.5)),
              child: const Icon(Icons.credit_card_off_rounded, color: _cyan, size: 36)),
          const SizedBox(height: 16),
          const Text("No reminders found",
              style: TextStyle(color: Colors.white54, fontSize: 15, fontWeight: FontWeight.w500)),
        ]))
            : ListView(
          children: [

            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: _cyan .withValues(alpha: 0.3)),
              ),
              child: Text(
                "Total Due Amount : ₹${totalDueAmount.toStringAsFixed(0)}",
                style: const TextStyle(
                  color: _cyan,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            ...reminders.map((r) => _buildItem(r)).toList(),

          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: _card, selectedItemColor: _cyan,
        unselectedItemColor: Colors.white38,
        type: BottomNavigationBarType.fixed, currentIndex: _selectedIndex,
        onTap: (i) {
          setState(() => _selectedIndex = i);
          if (i == 0) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => CardHome(userId: widget.userId, userName: widget.userName)));
          if (i == 1) Navigator.push(context, MaterialPageRoute(builder: (_) => ViewCardScreen(userId: widget.userId, userName: widget.userName)));
          if (i == 2) Navigator.push(context, MaterialPageRoute(builder: (_) => ViewReminderPage(userId: widget.userId, userName: widget.userName)));
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_rounded),          label: "Home"),
          BottomNavigationBarItem(icon: Icon(Icons.credit_card_rounded),   label: "Cards"),
          BottomNavigationBarItem(icon: Icon(Icons.notifications_rounded), label: "Reminder"),
        ],
      ),
    );
  }

  // ── REMINDER ITEM ─────────────────────────────────────────────────────────
  Widget _buildItem(Map r) {
    final bool isPaid = (r["status"] ?? "unpaid") == "paid";
    final String bank = (r["bankName"] ?? "").toString();
    final style = _styleForBank(bank);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(children: [

        // ── BANK STYLED CREDIT CARD ──────────────────────────────────────
        _ReminderCreditCard(
          bank: bank,
          amount: r["amount"]?.toString() ?? "0",
          paymentDate: _date(r["paymentDate"]),
          statementDate: _date(r["statementDate"]),
          isPaid: isPaid,
          style: style,
          onTogglePaid: () async {
            final newVal = !isPaid;
            setState(() => r["status"] = newVal ? "paid" : "unpaid");
            await http.put(
              Uri.parse(AppConfig.reminderStatus),
              headers: {"Content-Type": "application/json"},
              body: jsonEncode({
                "userId": r["userId"]["_id"],
                "cardId": r["cardId"]["_id"],
                "status": newVal ? "paid" : "unpaid",
              }),
            );
          },
        ),

        const SizedBox(height: 12),

        // ── NOTIFICATION SCHEDULE ────────────────────────────────────────
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _cyan.withValues(alpha: 0.2)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.notifications_active_rounded, color: _cyan, size: 15),
              const SizedBox(width: 7),
              const Text("Notification Schedule",
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: _cyan.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _cyan.withValues(alpha: 0.3))),
                child: Text("${(r["reminders"] as List?)?.length ?? 0} alerts",
                    style: const TextStyle(color: _cyan, fontSize: 10, fontWeight: FontWeight.w700)),
              ),
            ]),
            const SizedBox(height: 12),
            ..._scheduleItems(r["reminders"]),
          ]),
        ),

        const SizedBox(height: 10),

        // ── EDIT / DELETE ────────────────────────────────────────────────
        Row(children: [
          Expanded(child: _Btn(label: "Edit", icon: Icons.edit_rounded, color: _cyan,
              onTap: () => showDialog(context: context,
                  builder: (_) => _ConfirmDlg(
                    title: "Update Reminder", message: "Do you want to update this reminder?",
                    confirmLabel: "Update", confirmColor: _cyan,
                    onConfirm: () {
                      Navigator.pop(context);
                      Navigator.push(context,
                          MaterialPageRoute(builder: (_) => UpdateReminderPage(
                              userId: r["userId"]["_id"], userName: widget.userName, reminderData: r))).then((v) {
                        if (v == true) fetchReminders();
                      });
                    },
                  )))),
          const SizedBox(width: 10),
          Expanded(child: _Btn(label: "Delete", icon: Icons.delete_rounded, color: _red,
              onTap: () => showDialog(context: context,
                  builder: (_) => _ConfirmDlg(
                    title: "Delete Reminder",
                    message: "Are you sure you want to delete this reminder? This cannot be undone.",
                    confirmLabel: "Delete", confirmColor: _red,
                    onConfirm: () { Navigator.pop(context); deleteReminder(r["_id"]); },
                  )))),
        ]),
      ]),
    );
  }

  // ── SCHEDULE CHIPS ────────────────────────────────────────────────────────
  List<Widget> _scheduleItems(List? list) {
    if (list == null || list.isEmpty) return [
      const Text("No schedule set", style: TextStyle(color: Colors.white38, fontSize: 13))
    ];
    return list.map<Widget>((item) => Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _cyan.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _cyan.withValues(alpha: 0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: _cyan.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _cyan.withValues(alpha: 0.4))),
            child: Text(_fKey(item["key"]),
                style: const TextStyle(color: _cyan, fontWeight: FontWeight.w700, fontSize: 11.5)),
          ),
          const SizedBox(width: 8),
          Text("× ${item["count"]} times",
              style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 11.5)),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6,
            children: ((item["times"] ?? []) as List).map<Widget>((t) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.access_time_rounded, color: _cyan, size: 12),
                const SizedBox(width: 4),
                Text(t.toString(), style: const TextStyle(color: Colors.white, fontSize: 11.5)),
              ]),
            )).toList()),
      ]),
    )).toList();
  }
}

// ─── Reminder Credit Card ──────────────────────────────────────────────────────
class _ReminderCreditCard extends StatelessWidget {
  final String bank, amount, paymentDate, statementDate;
  final bool isPaid;
  final _CardStyle style;
  final VoidCallback onTogglePaid;

  const _ReminderCreditCard({
    required this.bank, required this.amount, required this.paymentDate,
    required this.statementDate, required this.isPaid,
    required this.style, required this.onTogglePaid,
  });

  @override
  Widget build(BuildContext context) {
    switch (style) {
      case _CardStyle.sbi:        return _mkCard(const [Color(0xFF002366), Color(0xFF0047AB)], const Color(0xFF002366), [Positioned.fill(child: CustomPaint(painter: _GridPainter(color: Color(0xFF4488CC))))]);
      case _CardStyle.hdfc:       return _mkCard(const [Color(0xFF8B0000), Color(0xFFCC0000)], const Color(0xFF8B0000), [Positioned.fill(child: CustomPaint(painter: _BrushPainter()))]);
      case _CardStyle.kotak:      return _mkCard(const [Color(0xFF1A0800), Color(0xFF2D1200)], const Color(0xFFB8600A), [Positioned.fill(child: CustomPaint(painter: _InfinityPainter())), Positioned(top:-20,right:20,child: Container(width:180,height:180, decoration: BoxDecoration(shape:BoxShape.circle,gradient:RadialGradient(colors:[Color(0xFFFF8C00).withValues(alpha:0.3),Colors.transparent]))))]);
      case _CardStyle.axisRibbon: return _mkCard(const [Color(0xFF050505), Color(0xFF0A0A0A)], const Color(0xFF2244AA), [Positioned.fill(child: CustomPaint(painter: _NeonRibbonPainter()))]);
      case _CardStyle.flipkart:   return _mkCard(const [Color(0xFF0B1C6B), Color(0xFF1A3399)], const Color(0xFF0B1C6B), [Positioned.fill(child: CustomPaint(painter: _RibbonPainter(c1: Color(0xFF4499FF), c2: Color(0xFFFF44AA))))]);
      case _CardStyle.yes:        return _mkCard(const [Color(0xFF003087), Color(0xFF0050C8)], const Color(0xFF003087), [Positioned.fill(child: CustomPaint(painter: _MandalaPainter()))]);
      case _CardStyle.icici:      return _mkCard(const [Color(0xFF1A1A1A), Color(0xFF0D0D0D)], Colors.black, [Positioned.fill(child: CustomPaint(painter: _BrushPainter()))]);
      case _CardStyle.amexGold:   return _mkCard(const [Color(0xFFB8970A), Color(0xFFDAA520), Color(0xFFEDD060)], const Color(0xFFB8860B), [Positioned.fill(child: CustomPaint(painter: _GoldWavePainter()))], textColor: const Color(0xFF1A1400));
      case _CardStyle.amexBlue:   return _mkCard(const [Color(0xFF003087), Color(0xFF0050C8)], const Color(0xFF001A66), [Positioned.fill(child: CustomPaint(painter: _DotGridPainter(color: Color(0xFF4488DD))))]);
      case _CardStyle.federal:    return _mkCard(const [Color(0xFF050505), Color(0xFF111111)], Colors.black, [Positioned.fill(child: CustomPaint(painter: _PolygonPainter(color: Color(0xFF333333))))], textColor: const Color(0xFFD4AF37));
      case _CardStyle.indusind:   return _mkCard(const [Color(0xFF111111), Color(0xFF1C1C1C)], Colors.black, [Positioned.fill(child: CustomPaint(painter: _GridTexturePainter()))]);
      case _CardStyle.rbl:        return _mkCard(const [Color(0xFF1A1A1A), Color(0xFF2A2A2A)], Colors.black, [Positioned.fill(child: CustomPaint(painter: _BrushPainter())), Positioned(bottom:-20,right:-10,child: Text('PLAY',style: TextStyle(fontSize:110,fontWeight:FontWeight.w900,color:Colors.white.withValues(alpha:0.07),letterSpacing:-4)))]);
      case _CardStyle.hsbc:       return _mkCard(const [Color(0xFF9B0000), Color(0xFFBB0000)], const Color(0xFF9B0000), [Positioned.fill(child: CustomPaint(painter: _HexPainter()))]);
      case _CardStyle.pnb:        return _mkCard(const [Color(0xFF5C0018), Color(0xFF8B0025)], const Color(0xFF5C0018), [Positioned.fill(child: CustomPaint(painter: _AuroraPainter()))]);
      case _CardStyle.idfc:       return _mkCard(const [Color(0xFF003344), Color(0xFF005566)], const Color(0xFF003344), [Positioned.fill(child: CustomPaint(painter: _CarbonPainter()))]);
      case _CardStyle.idbi:       return _mkCard(const [Color(0xFF1A0050), Color(0xFF2D0080)], const Color(0xFF1A0050), [Positioned.fill(child: CustomPaint(painter: _SunburstPainter()))]);
      case _CardStyle.paytm:      return _mkCard(const [Color(0xFF000814), Color(0xFF001A4D)], const Color(0xFF002D72), [Positioned.fill(child: CustomPaint(painter: _GalaxyPainter()))]);
      case _CardStyle.stanchart:  return _mkCard(const [Color(0xFF006B3C), Color(0xFF009B5B)], const Color(0xFF006B3C), [Positioned.fill(child: CustomPaint(painter: _ShimmerPainter()))]);
      case _CardStyle.canara:     return _mkCard(const [Color(0xFF004D00), Color(0xFF007700)], const Color(0xFF004D00), [Positioned.fill(child: CustomPaint(painter: _SparklePainter()))]);
      case _CardStyle.tmb:        return _mkCard(const [Color(0xFF00008B), Color(0xFF0000CD)], const Color(0xFF00008B), [Positioned.fill(child: CustomPaint(painter: _OceanPainter()))]);
    }
  }

  Widget _mkCard(List<Color> colors, Color shadow, List<Widget> overlays, {Color textColor = Colors.white}) {
    final subtext = textColor == Colors.white ? Colors.white60 : const Color(0xFF4A3A00);
    return GestureDetector(
      onTap: onTogglePaid,
      child: Container(
        width: double.infinity, height: 210,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [BoxShadow(color: shadow.withValues(alpha: 0.5), blurRadius: 22, offset: const Offset(0, 9))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Stack(children: [
            ...overlays,
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // top row
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Flexible(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(bank.isEmpty ? 'BANK NAME' : bank.toUpperCase(),
                        style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1.1),
                        overflow: TextOverflow.ellipsis),
                    Text('CREDIT CARD', style: TextStyle(color: subtext, fontSize: 8, letterSpacing: 2)),
                  ])),
                  // paid/unpaid badge
                  GestureDetector(
                    onTap: onTogglePaid,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: isPaid ? const Color(0xFF00E5A0).withValues(alpha: 0.8) : Colors.white.withValues(alpha: 0.3)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(isPaid ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                            color: isPaid ? const Color(0xFF00E5A0) : Colors.white60, size: 13),
                        const SizedBox(width: 5),
                        Text(isPaid ? "PAID" : "UNPAID",
                            style: TextStyle(
                                color: isPaid ? const Color(0xFF00E5A0) : Colors.white60,
                                fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
                      ]),
                    ),
                  ),
                ]),
                const SizedBox(height: 14),
                // chip
                Container(width: 44, height: 34,
                    decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [Colors.white.withValues(alpha: 0.7), Colors.white.withValues(alpha: 0.4)],
                            begin: Alignment.topLeft, end: Alignment.bottomRight),
                        borderRadius: BorderRadius.circular(6)),
                    child: CustomPaint(painter: _CP())),
                const Spacer(),
                // amount
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text("AMOUNT DUE", style: TextStyle(color: subtext, fontSize: 8, fontWeight: FontWeight.w600, letterSpacing: 1.5)),
                    const SizedBox(height: 3),
                    Text("₹$amount", style: TextStyle(color: textColor, fontSize: 22, fontWeight: FontWeight.w800)),
                  ]),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text("STMT / DUE", style: TextStyle(color: subtext, fontSize: 8, fontWeight: FontWeight.w600, letterSpacing: 1.2)),
                    const SizedBox(height: 3),
                    Text("$statementDate  /  $paymentDate",
                        style: TextStyle(color: textColor, fontSize: 10, fontWeight: FontWeight.w600)),
                  ]),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────
class _Btn extends StatelessWidget {
  final String label; final IconData icon; final Color color; final VoidCallback onTap;
  const _Btn({required this.label, required this.icon, required this.color, required this.onTap});
  @override Widget build(BuildContext context) => GestureDetector(onTap: onTap,
      child: Container(height: 46,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withValues(alpha: 0.45))),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: color, size: 18), const SizedBox(width: 7),
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13.5)),
          ])));
}

class _ConfirmDlg extends StatelessWidget {
  final String title, message, confirmLabel; final Color confirmColor; final VoidCallback onConfirm;
  const _ConfirmDlg({required this.title, required this.message, required this.confirmLabel, required this.confirmColor, required this.onConfirm});
  @override Widget build(BuildContext context) => AlertDialog(
      backgroundColor: const Color(0xFF13131A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: confirmColor.withValues(alpha: 0.3))),
      title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 17)),
      content: Text(message, style: const TextStyle(color: Colors.white60, fontSize: 14)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const TextStyle(color: Colors.white38).apply() != null ? const Text("Cancel", style: TextStyle(color: Colors.white38)) : const Text("Cancel")),
        GestureDetector(onTap: onConfirm,
            child: Container(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                decoration: BoxDecoration(color: confirmColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: confirmColor.withValues(alpha: 0.5))),
                child: Text(confirmLabel, style: TextStyle(color: confirmColor, fontWeight: FontWeight.w700, fontSize: 13.5)))),
        const SizedBox(width: 4),
      ]);
}

// ═══════════════════════ PAINTERS (copied from view_card_screen) ══════════════

class _CP extends CustomPainter {
  final Color color;
  const _CP({this.color = const Color(0xFFB8960C)});
  @override void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 0.8;
    canvas.drawLine(Offset(size.width/2, 0), Offset(size.width/2, size.height), p);
    canvas.drawLine(Offset(0, size.height/2), Offset(size.width, size.height/2), p);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0,0,size.width,size.height), const Radius.circular(6)), p);
  }
  @override bool shouldRepaint(_) => false;
}

class _GridPainter extends CustomPainter {
  final Color color;
  const _GridPainter({required this.color});
  @override void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color.withValues(alpha: 0.18)..style = PaintingStyle.stroke..strokeWidth = 0.5;
    for (double y = 0.2; y < 1.0; y += 0.2) { canvas.drawLine(Offset(0, size.height*y), Offset(size.width, size.height*y), p); }
    for (double x = 0.12; x < 1.0; x += 0.12) { canvas.drawLine(Offset(size.width*x, 0), Offset(size.width*x, size.height), p); }
    final fp = Paint()..color = color.withValues(alpha: 0.15)..style = PaintingStyle.fill;
    canvas.drawOval(Rect.fromCenter(center: Offset(size.width*0.22, size.height*0.42), width: size.width*0.22, height: size.height*0.42), fp);
    canvas.drawOval(Rect.fromCenter(center: Offset(size.width*0.52, size.height*0.38), width: size.width*0.28, height: size.height*0.45), fp);
  }
  @override bool shouldRepaint(_) => false;
}

class _BrushPainter extends CustomPainter {
  @override void paint(Canvas canvas, Size size) {
    for (int i = 0; i < 60; i++) {
      canvas.drawLine(Offset(0, (size.height/60)*i), Offset(size.width, (size.height/60)*i+2),
          Paint()..color = Colors.white.withValues(alpha: i%3==0 ? 0.04 : 0.02)..strokeWidth = 1.2);
    }
  }
  @override bool shouldRepaint(_) => false;
}

class _InfinityPainter extends CustomPainter {
  @override void paint(Canvas canvas, Size size) {
    final cx = size.width*0.65; final cy = size.height*0.48; final r = 40.0;
    canvas.drawCircle(Offset(cx, cy), 65, Paint()..color = const Color(0xFFFF8C00).withValues(alpha: 0.22)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22));
    final p = Paint()..style = PaintingStyle.stroke..strokeWidth = 6..strokeCap = StrokeCap.round;
    p.color = const Color(0xFFFFAA00).withValues(alpha: 0.6);
    canvas.drawOval(Rect.fromCenter(center: Offset(cx-r*0.7, cy), width: r*1.3, height: r*0.95), p);
    p.color = const Color(0xFFFF6600).withValues(alpha: 0.5);
    canvas.drawOval(Rect.fromCenter(center: Offset(cx+r*0.7, cy), width: r*1.3, height: r*0.95), p);
  }
  @override bool shouldRepaint(_) => false;
}

class _NeonRibbonPainter extends CustomPainter {
  @override void paint(Canvas canvas, Size size) {
    final bp = Path()..moveTo(size.width*0.05, size.height*0.85)..cubicTo(size.width*0.25, size.height*0.05, size.width*0.55, size.height, size.width*0.80, size.height*0.15);
    canvas.drawPath(bp, Paint()..color = const Color(0xFF4488FF).withValues(alpha: 0.28)..style = PaintingStyle.stroke..strokeWidth = 34..strokeCap = StrokeCap.round..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14));
    canvas.drawPath(bp, Paint()..color = const Color(0xFF2266FF).withValues(alpha: 0.9)..style = PaintingStyle.stroke..strokeWidth = 18..strokeCap = StrokeCap.round..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
    final pp = Path()..moveTo(size.width*0.18, size.height*0.95)..cubicTo(size.width*0.40, size.height*0.08, size.width*0.65, size.height*0.95, size.width*0.95, size.height*0.22);
    canvas.drawPath(pp, Paint()..color = const Color(0xFFFF44BB).withValues(alpha: 0.24)..style = PaintingStyle.stroke..strokeWidth = 28..strokeCap = StrokeCap.round..maskFilter = const MaskFilter.blur(BlurStyle.normal, 11));
    canvas.drawPath(pp, Paint()..color = const Color(0xFFDD1199).withValues(alpha: 0.85)..style = PaintingStyle.stroke..strokeWidth = 14..strokeCap = StrokeCap.round..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
  }
  @override bool shouldRepaint(_) => false;
}

class _RibbonPainter extends CustomPainter {
  final Color c1, c2;
  const _RibbonPainter({required this.c1, required this.c2});
  @override void paint(Canvas canvas, Size size) {
    canvas.drawPath(Path()..moveTo(size.width*0.1, size.height*0.9)..cubicTo(size.width*0.3, size.height*0.1, size.width*0.6, size.height*0.95, size.width*0.9, size.height*0.2),
        Paint()..color = c1.withValues(alpha: 0.6)..style = PaintingStyle.stroke..strokeWidth = 16..strokeCap = StrokeCap.round);
    canvas.drawPath(Path()..moveTo(size.width*0.2, size.height*0.95)..cubicTo(size.width*0.5, size.height*0.05, size.width*0.7, size.height*0.9, size.width*0.95, size.height*0.25),
        Paint()..color = c2.withValues(alpha: 0.6)..style = PaintingStyle.stroke..strokeWidth = 13..strokeCap = StrokeCap.round);
  }
  @override bool shouldRepaint(_) => false;
}

class _MandalaPainter extends CustomPainter {
  @override void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.white.withValues(alpha: 0.09)..style = PaintingStyle.stroke..strokeWidth = 0.8;
    final cx = size.width*0.5; final cy = size.height*0.5;
    for (double r = 18; r <= 120; r += 20) { canvas.drawCircle(Offset(cx, cy), r, p); }
    for (int i = 0; i < 12; i++) { final a = i*30*3.14159/180; canvas.drawLine(Offset(cx+18*_c(a), cy+18*_s(a)), Offset(cx+120*_c(a), cy+120*_s(a)), p); }
  }
  @override bool shouldRepaint(_) => false;
}

class _GoldWavePainter extends CustomPainter {
  @override void paint(Canvas canvas, Size size) {
    for (double i = -size.height; i < size.width+size.height; i += 18) {
      canvas.drawLine(Offset(i, 0), Offset(i+size.height, size.height), Paint()..color = const Color(0xFF1A1400).withValues(alpha: 0.06)..strokeWidth = 6);
    }
  }
  @override bool shouldRepaint(_) => false;
}

class _DotGridPainter extends CustomPainter {
  final Color color;
  const _DotGridPainter({required this.color});
  @override void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color.withValues(alpha: 0.2);
    for (double x = 12; x < size.width; x += 14) { for (double y = 12; y < size.height; y += 14) { canvas.drawCircle(Offset(x, y), 0.8, p); } }
  }
  @override bool shouldRepaint(_) => false;
}

class _PolygonPainter extends CustomPainter {
  final Color color;
  const _PolygonPainter({required this.color});
  @override void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color.withValues(alpha: 0.5)..style = PaintingStyle.stroke..strokeWidth = 0.8;
    canvas.drawPath(Path()..moveTo(size.width*0.1,size.height*0.8)..lineTo(size.width*0.3,size.height*0.3)..lineTo(size.width*0.55,size.height*0.7)..lineTo(size.width*0.35,size.height*0.95)..close(), p);
    canvas.drawPath(Path()..moveTo(size.width*0.3,size.height*0.3)..lineTo(size.width*0.55,size.height*0.05)..lineTo(size.width*0.75,size.height*0.45)..lineTo(size.width*0.55,size.height*0.7)..close(), p);
  }
  @override bool shouldRepaint(_) => false;
}

class _GridTexturePainter extends CustomPainter {
  @override void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.white.withValues(alpha: 0.06)..style = PaintingStyle.stroke..strokeWidth = 0.5;
    for (double x = 0; x < size.width; x += 8) { canvas.drawLine(Offset(x, 0), Offset(x, size.height), p); }
    for (double y = 0; y < size.height; y += 8) { canvas.drawLine(Offset(0, y), Offset(size.width, y), p); }
  }
  @override bool shouldRepaint(_) => false;
}

class _HexPainter extends CustomPainter {
  @override void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.white.withValues(alpha: 0.08)..style = PaintingStyle.stroke..strokeWidth = 0.8;
    for (double cx = 0; cx < size.width+30; cx += 30) {
      for (double cy = 0; cy < size.height+20; cy += 26) {
        final offset = (cy ~/ 26 % 2 == 0) ? 0.0 : 15.0;
        final path = Path();
        for (int i = 0; i < 6; i++) { final a = i*60*3.14159/180; if (i == 0) { path.moveTo(cx+offset+12*_c(a), cy+12*_s(a)); } else { path.lineTo(cx+offset+12*_c(a), cy+12*_s(a)); } }
        path.close(); canvas.drawPath(path, p);
      }
    }
  }
  @override bool shouldRepaint(_) => false;
}

class _AuroraPainter extends CustomPainter {
  @override void paint(Canvas canvas, Size size) {
    final colors = [const Color(0xFFFF6666).withValues(alpha: 0.18), const Color(0xFFFF9999).withValues(alpha: 0.13), const Color(0xFFFFBBBB).withValues(alpha: 0.09)];
    for (int i = 0; i < 3; i++) {
      canvas.drawPath(Path()..moveTo(0, size.height*(0.3+i*0.1))..cubicTo(size.width*0.3, size.height*(0.6-i*0.15), size.width*0.65, size.height*(0.2+i*0.1), size.width, size.height*(0.5-i*0.1)),
          Paint()..color = colors[i]..style = PaintingStyle.stroke..strokeWidth = 40-i*10.0..strokeCap = StrokeCap.round..maskFilter = MaskFilter.blur(BlurStyle.normal, 20-i*4.0));
    }
  }
  @override bool shouldRepaint(_) => false;
}

class _CarbonPainter extends CustomPainter {
  @override void paint(Canvas canvas, Size size) {
    for (int i = 0; i < 60; i++) { canvas.drawRect(Rect.fromLTWH((size.width/60)*i*1.5, 0, 4, size.height), Paint()..color = Colors.white.withValues(alpha: 0.025)); }
  }
  @override bool shouldRepaint(_) => false;
}

class _SunburstPainter extends CustomPainter {
  @override void paint(Canvas canvas, Size size) {
    canvas.drawCircle(Offset(size.width*0.72, size.height*0.38), 72, Paint()..color = const Color(0xFF8800FF).withValues(alpha: 0.22)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 25));
    canvas.drawCircle(Offset(size.width*0.72, size.height*0.38), 32, Paint()..color = const Color(0xFFBB44FF).withValues(alpha: 0.3)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
  }
  @override bool shouldRepaint(_) => false;
}

class _GalaxyPainter extends CustomPainter {
  @override void paint(Canvas canvas, Size size) {
    canvas.drawCircle(Offset(size.width*0.6, size.height*0.4), 80, Paint()..color = const Color(0xFF0044FF).withValues(alpha: 0.14)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30));
    final sp = Paint()..color = Colors.white.withValues(alpha: 0.75);
    for (final s in [[0.08,0.12,1.0],[0.22,0.08,1.5],[0.38,0.22,1.0],[0.52,0.06,1.2],[0.65,0.18,1.8],[0.80,0.10,1.0],[0.92,0.28,1.3],[0.15,0.38,1.0],[0.45,0.42,0.8],[0.70,0.48,1.5],[0.88,0.80,0.8],[0.60,0.88,1.0]]) {
      canvas.drawCircle(Offset(size.width*s[0], size.height*s[1]), s[2], sp);
    }
  }
  @override bool shouldRepaint(_) => false;
}

class _ShimmerPainter extends CustomPainter {
  @override void paint(Canvas canvas, Size size) {
    for (double i = -size.height; i < size.width+size.height; i += 24) {
      canvas.drawPath(Path()..moveTo(i, 0)..lineTo(i+size.height, size.height)..lineTo(i+size.height+10, size.height)..lineTo(i+10, 0)..close(),
          Paint()..color = Colors.white.withValues(alpha: 0.055));
    }
  }
  @override bool shouldRepaint(_) => false;
}

class _SparklePainter extends CustomPainter {
  @override void paint(Canvas canvas, Size size) {
    for (final d in [[0.15,0.25,3.0],[0.28,0.45,2.0],[0.42,0.18,4.0],[0.55,0.55,2.5],[0.68,0.30,3.5],[0.80,0.60,2.0],[0.90,0.20,3.0]]) {
      canvas.drawCircle(Offset(size.width*d[0], size.height*d[1]), d[2]*3, Paint()..color = const Color(0xFF88FF88).withValues(alpha: 0.14)..maskFilter = MaskFilter.blur(BlurStyle.normal, d[2]*2.5));
      canvas.drawCircle(Offset(size.width*d[0], size.height*d[1]), d[2]*0.6, Paint()..color = const Color(0xFFAAFFAA).withValues(alpha: 0.9));
    }
  }
  @override bool shouldRepaint(_) => false;
}

class _OceanPainter extends CustomPainter {
  @override void paint(Canvas canvas, Size size) {
    for (int w = 0; w < 4; w++) {
      final p = Paint()..color = const Color(0xFF0088CC).withValues(alpha: 0.12)..style = PaintingStyle.stroke..strokeWidth = 1.5;
      final path = Path(); path.moveTo(0, size.height*(0.45+w*0.12));
      for (double x = 0; x <= size.width; x += 20) { path.quadraticBezierTo(x+10, size.height*(0.45+w*0.12)+(w%2==0 ? -12.0 : 12.0), x+20, size.height*(0.45+w*0.12)); }
      canvas.drawPath(path, p);
    }
  }
  @override bool shouldRepaint(_) => false;
}

double _c(double r) { final n=r%(2*3.14159265); return 1-n*n/2+n*n*n*n/24-n*n*n*n*n*n/720; }
double _s(double r) => _c(r-3.14159265/2);