import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'home_screen.dart';
import 'card_home.dart';
import 'view_reminder_page.dart';
import 'view_card_screen.dart';
// ─────────────────────────────────────────────
//  LEND SERVICE
// ─────────────────────────────────────────────

class LendService {
  static final String baseUrl = AppConfig.lend;

  static Future<Map<String, dynamic>> addLend({
    required String userId,
    required String userName,
    required String name,
    required String reason,
    required String amount,
    required String date,
  }) async {
    try {
      final response = await http.post(
        Uri.parse("$baseUrl/create"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "userId":   userId,
          "userName": userName,
          "name":     name,
          "reason":   reason,
          "amount":   double.tryParse(amount) ?? 0,
          "date":     date,
        }),
      );
      return jsonDecode(response.body);
    } catch (e) {
      return {"success": false, "message": e.toString()};
    }
  }

  static Future<List<dynamic>> getLends(String userId) async {
    try {
      final response = await http.get(Uri.parse("$baseUrl/user/$userId"));
      final data = jsonDecode(response.body);
      if (data['success'] == true) return data['data'] ?? [];
      return [];
    } catch (e) {
      throw Exception("Error: $e");
    }
  }

  static Future<Map<String, dynamic>> deleteLend(String lendId) async {
    try {
      final response = await http.delete(Uri.parse("$baseUrl/delete/$lendId"));
      return jsonDecode(response.body);
    } catch (e) {
      return {"success": false, "message": e.toString()};
    }
  }

  static Future<Map<String, dynamic>> markReceived(
      String lendId,
      bool value,
      ) async {
    try {
      final response = await http.put(
        Uri.parse("$baseUrl/received/$lendId"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"isReceived": value}),
      );
      return jsonDecode(response.body);
    } catch (e) {
      return {"success": false, "message": e.toString()};
    }
  }
}

// ─────────────────────────────────────────────
//  LIABILITY SERVICE
// ─────────────────────────────────────────────

class LiabilityService {
  static final String baseUrl = AppConfig.liability;

  static Future<Map<String, dynamic>> addLiability({
    required String userId,
    required String userName,
    required String name,
    required String reason,
    required String amount,
    required String date,
  }) async {
    try {
      final response = await http.post(
        Uri.parse("$baseUrl/create"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "userId":   userId,
          "userName": userName,
          "name":     name,
          "reason":   reason,
          "amount":   double.tryParse(amount) ?? 0,
          "date":     date,
        }),
      );
      return jsonDecode(response.body);
    } catch (e) {
      return {"success": false, "message": e.toString()};
    }
  }

  static Future<List<dynamic>> getLiabilities(String userId) async {
    try {
      final response = await http.get(Uri.parse("$baseUrl/$userId"));
      final data = jsonDecode(response.body);
      if (data['success'] == true) return data['data'] ?? [];
      return [];
    } catch (e) {
      throw Exception("Error: $e");
    }
  }

  static Future<Map<String, dynamic>> deleteLiability(String liabilityId) async {
    try {
      final response = await http.delete(Uri.parse("$baseUrl/$liabilityId"));
      return jsonDecode(response.body);
    } catch (e) {
      return {"success": false, "message": e.toString()};
    }
  }

  static Future<Map<String, dynamic>> markPaid(
      String liabilityId,
      bool value,
      ) async {
    try {
      final response = await http.put(
        Uri.parse("$baseUrl/paid/$liabilityId"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"isPaid": value}),
      );
      return jsonDecode(response.body);
    } catch (e) {
      return {"success": false, "message": e.toString()};
    }
  }
}

// ─────────────────────────────────────────────
//  MODELS
// ─────────────────────────────────────────────

class LendEntry {
  final String id;
  final String name;
  final String reason;
  final String amount;
  final String date;
  bool isReceived;

  LendEntry({
    required this.id,
    required this.name,
    required this.reason,
    required this.amount,
    required this.date,
    this.isReceived = false,
  });

  factory LendEntry.fromJson(Map<String, dynamic> json) {
    return LendEntry(
      id:         json['_id']        ?? json['id'] ?? '',
      name:       json['name']       ?? '',
      reason:     json['reason']     ?? '',
      amount:     json['amount'].toString(),
      date:       json['date']       ?? '',
      isReceived: json['isReceived'] ?? false,
    );
  }
}

class LiabilityEntry {
  final String id;
  final String name;
  final String reason;
  final String amount;
  final String date;
  bool isPaid;

  LiabilityEntry({
    required this.id,
    required this.name,
    required this.reason,
    required this.amount,
    required this.date,
    this.isPaid = false,
  });

  factory LiabilityEntry.fromJson(Map<String, dynamic> json) {
    return LiabilityEntry(
      id:     json['_id']    ?? json['id'] ?? '',
      name:   json['name']   ?? '',
      reason: json['reason'] ?? '',
      amount: json['amount'].toString(),
      date:   json['date']   ?? '',
      isPaid: json['isPaid'] ?? false,
    );
  }
}

// ─────────────────────────────────────────────
//  PAGE
// ─────────────────────────────────────────────

class LendLiabilityPage extends StatefulWidget {
  final String userId;
  final String userName;

  const LendLiabilityPage({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<LendLiabilityPage> createState() => _LendLiabilityPageState();
}

class _LendLiabilityPageState extends State<LendLiabilityPage>
    with SingleTickerProviderStateMixin {

  static const Color _bg      = Color(0xFF0A0A0F);
  static const Color _card    = Color(0xFF13131A);
  static const Color _border  = Color(0xFF1E1E2E);
  static const Color _cyan    = Color(0xFF00D9FF);
  static const Color _green   = Color(0xFF00E5A0);
  static const Color _red     = Color(0xFFFF4D6D);
  static const Color _textPri = Colors.white;
  static const Color _textSec = Color(0xFF8A8AA0);

  late TabController _tabController;

  final List<LendEntry>      _lendList      = [];
  final List<LiabilityEntry> _liabilityList = [];

  bool _lendLoading      = false;
  bool _liabilityLoading = false;
  int _selectedIndex = 0;
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchLends();
    _fetchLiabilities();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ── FETCH ──

  Future<void> _fetchLends() async {
    setState(() => _lendLoading = true);
    try {
      final data = await LendService.getLends(widget.userId);
      setState(() {
        _lendList
          ..clear()
          ..addAll(data.map((e) => LendEntry.fromJson(e)));
      });
    } catch (_) {
      _showSnack("Failed to load lend records");
    } finally {
      setState(() => _lendLoading = false);
    }
  }

  Future<void> _fetchLiabilities() async {
    setState(() => _liabilityLoading = true);
    try {
      final data = await LiabilityService.getLiabilities(widget.userId);
      setState(() {
        _liabilityList
          ..clear()
          ..addAll(data.map((e) => LiabilityEntry.fromJson(e)));
      });
    } catch (_) {
      _showSnack("Failed to load liability records");
    } finally {
      setState(() => _liabilityLoading = false);
    }
  }

  // ── SNACK ──

  void _showSnack(String msg, {bool success = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white)),
        backgroundColor: success ? _green : _red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ── DELETE CONFIRM DIALOG ──

  Future<void> _confirmDelete({
    required BuildContext context,
    required String name,
    required Future<void> Function() onConfirmed,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF13131A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: _red.withValues(alpha: 0.4)),
        ),
        title: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: _red.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _red.withValues(alpha: 0.4)),
              ),
              child: const Icon(Icons.delete_rounded, color: _red, size: 18),
            ),
            const SizedBox(width: 12),
            const Text(
              "Delete",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 17,
              ),
            ),
          ],
        ),
        content: RichText(
          text: TextSpan(
            style: const TextStyle(color: Colors.white60, fontSize: 14, height: 1.5),
            children: [
              const TextSpan(text: "Are you sure you want to delete "),
              TextSpan(
                text: name,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const TextSpan(text: "'s record? This action cannot be undone."),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              "Cancel",
              style: TextStyle(color: Colors.white38, fontWeight: FontWeight.w600),
            ),
          ),
          GestureDetector(
            onTap: () => Navigator.pop(context, true),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: _red.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _red.withValues(alpha: 0.5)),
              ),
              child: const Text(
                "Delete",
                style: TextStyle(
                  color: _red,
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );

    if (confirmed == true) {
      await onConfirmed();
    }
  }

  // ── LEND FORM ──

  void _showLendForm() {
    final formKey    = GlobalKey<FormState>();
    final nameCtrl   = TextEditingController();
    final reasonCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final dateCtrl   = TextEditingController();

    Future<void> pickDate() async {
      final picked = await showDatePicker(
        context: context,
        initialDate: DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime(2100),
        builder: (ctx, child) => Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: _cyan,
              surface: Color(0xFF1A1A2E),
            ),
          ),
          child: child!,
        ),
      );
      if (picked != null) {
        dateCtrl.text =
        "${picked.day.toString().padLeft(2, '0')}/"
            "${picked.month.toString().padLeft(2, '0')}/"
            "${picked.year}";
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BottomSheetForm(
        title: "Add Lend Entry",
        accentColor: _cyan,
        formKey: formKey,
        nameCtrl: nameCtrl,
        reasonCtrl: reasonCtrl,
        amountCtrl: amountCtrl,
        dateCtrl: dateCtrl,
        onPickDate: pickDate,
        buttonLabel: "Add to Lend",
        buttonIcon: Icons.arrow_upward_rounded,
        onSubmit: () async {
          if (formKey.currentState!.validate()) {
            Navigator.pop(context);
            final res = await LendService.addLend(
              userId:   widget.userId,
              userName: widget.userName,
              name:     nameCtrl.text.trim(),
              reason:   reasonCtrl.text.trim(),
              amount:   amountCtrl.text.trim(),
              date:     dateCtrl.text.trim(),
            );
            if (res['success'] == true) {
              _showSnack("Lend entry added!", success: true);
              await _fetchLends();
            } else {
              _showSnack(res['message'] ?? "Failed to add lend");
            }
          }
        },
      ),
    );
  }

  // ── LIABILITY FORM ──

  void _showLiabilityForm() {
    final formKey    = GlobalKey<FormState>();
    final nameCtrl   = TextEditingController();
    final reasonCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final dateCtrl   = TextEditingController();

    Future<void> pickDate() async {
      final picked = await showDatePicker(
        context: context,
        initialDate: DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime(2100),
        builder: (ctx, child) => Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: _cyan,
              surface: Color(0xFF1A1A2E),
            ),
          ),
          child: child!,
        ),
      );
      if (picked != null) {
        dateCtrl.text =
        "${picked.day.toString().padLeft(2, '0')}/"
            "${picked.month.toString().padLeft(2, '0')}/"
            "${picked.year}";
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BottomSheetForm(
        title: "Add Liability Entry",
        accentColor: _cyan,
        formKey: formKey,
        nameCtrl: nameCtrl,
        reasonCtrl: reasonCtrl,
        amountCtrl: amountCtrl,
        dateCtrl: dateCtrl,
        onPickDate: pickDate,
        buttonLabel: "Add to Liability",
        buttonIcon: Icons.arrow_downward_rounded,
        onSubmit: () async {
          if (formKey.currentState!.validate()) {
            Navigator.pop(context);
            final res = await LiabilityService.addLiability(
              userId:   widget.userId,
              userName: widget.userName,
              name:     nameCtrl.text.trim(),
              reason:   reasonCtrl.text.trim(),
              amount:   amountCtrl.text.trim(),
              date:     dateCtrl.text.trim(),
            );
            if (res['success'] == true) {
              _showSnack("Liability entry added!", success: true);
              await _fetchLiabilities();
            } else {
              _showSnack(res['message'] ?? "Failed to add liability");
            }
          }
        },
      ),
    );
  }

  // ── TOTALS ──

  double get _totalLent => _lendList
      .where((e) => !e.isReceived)
      .fold(0.0, (s, e) => s + (double.tryParse(e.amount) ?? 0));

  double get _totalLiability => _liabilityList
      .where((e) => !e.isPaid)
      .fold(0.0, (s, e) => s + (double.tryParse(e.amount) ?? 0));

  // ── TOGGLE LEND RECEIVED ──

  Future<void> _toggleLendReceived(int index) async {
    final entry    = _lendList[index];
    final newValue = !entry.isReceived;
    final res      = await LendService.markReceived(entry.id, newValue);
    if (res['success'] == true) {
      setState(() => _lendList[index].isReceived = newValue);
      _showSnack(
        newValue ? "Marked as received!" : "Moved back to pending!",
        success: true,
      );
    } else {
      _showSnack(res['message'] ?? "Failed to update");
    }
  }

  // ── DELETE LEND (with confirm) ──

  Future<void> _deleteLend(int index) async {
    await _confirmDelete(
      context: context,
      name: _lendList[index].name,
      onConfirmed: () async {
        final res = await LendService.deleteLend(_lendList[index].id);
        if (res['success'] == true) {
          setState(() => _lendList.removeAt(index));
          _showSnack("Lend entry deleted", success: true);
        } else {
          _showSnack(res['message'] ?? "Failed to delete");
        }
      },
    );
  }

  // ── TOGGLE LIABILITY PAID ──

  Future<void> _toggleLiabilityPaid(int index) async {
    final entry    = _liabilityList[index];
    final newValue = !entry.isPaid;
    final res      = await LiabilityService.markPaid(entry.id, newValue);
    if (res['success'] == true) {
      setState(() => _liabilityList[index].isPaid = newValue);
      _showSnack(
        newValue ? "Marked as paid!" : "Moved back to unpaid!",
        success: true,
      );
    } else {
      _showSnack(res['message'] ?? "Failed to update");
    }
  }

  // ── DELETE LIABILITY (with confirm) ──

  Future<void> _deleteLiability(int index) async {
    await _confirmDelete(
      context: context,
      name: _liabilityList[index].name,
      onConfirmed: () async {
        final res = await LiabilityService.deleteLiability(_liabilityList[index].id);
        if (res['success'] == true) {
          setState(() => _liabilityList.removeAt(index));
          _showSnack("Liability deleted", success: true);
        } else {
          _showSnack(res['message'] ?? "Failed to delete");
        }
      },
    );
  }

  // ── BUILD ──

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,

      appBar: AppBar(
        elevation: 0, backgroundColor: Colors.black,
        leading: Padding(
          padding: const EdgeInsets.all(8.0),

          child: CircleAvatar(
            backgroundColor: Colors.transparent,

            child: Image.asset(
              "assets/images/logo.png",
            ),
          ),
        ),
        title: const Text(
          "Lend & Liability",
          style: TextStyle(
            color: const Color(0xFF00D9FF),
            fontWeight: FontWeight.bold,
            fontSize: 24,
          ),
        ),

        centerTitle: true,

        actions: [
          IconButton(
            icon: const Icon(
              Icons.logout_rounded,
              color: const Color(0xFF00D9FF),
              size: 30,
            ),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  backgroundColor: const Color(0xff1A1A1A),

                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),

                  title: const Text(
                    "Logout",
                    style: TextStyle(color: Colors.white),
                  ),

                  content: const Text(
                    "Are you sure want to logout?",
                    style: TextStyle(color: Colors.white70),
                  ),

                  actions: [
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      child: const Text(
                        "Cancel",
                        style: TextStyle(color: Colors.white),
                      ),
                    ),

                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                      ),

                      onPressed: () async {
                        final prefs =
                        await SharedPreferences.getInstance();

                        await prefs.clear();

                        if (!context.mounted) return;

                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                            const HomeScreen(),
                          ),
                              (route) => false,
                        );
                      },

                      child: const Text(
                        "Logout",
                        style: TextStyle(color: Colors.black),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],


        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: AnimatedBuilder(
            animation: _tabController,
            builder: (context, _) {
              final idx = _tabController.index;
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _border),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicator: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00D9FF), Color(0xFF006FFF)],
                    ),
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  labelColor: Colors.black,
                  unselectedLabelColor: _cyan,
                  labelStyle: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 11.5,
                  ),
                  tabs: [
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text("💸 Lend"),
                          const SizedBox(width: 6),
                          _TabIconBtn(
                            icon: Icons.add_rounded,
                            active: idx == 0,
                            activeAccent: _cyan,
                            onTap: () {
                              if (_tabController.index != 0) _tabController.animateTo(0);
                              Future.microtask(_showLendForm);
                            },
                          ),
                        ],
                      ),
                    ),
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text("🏦 Liability"),
                          const SizedBox(width: 6),
                          _TabIconBtn(
                            icon: Icons.add_rounded,
                            active: idx == 1,
                            activeAccent: _cyan,
                            onTap: () {
                              if (_tabController.index != 1) _tabController.animateTo(1);
                              Future.microtask(_showLiabilityForm);
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),

      body: TabBarView(
        controller: _tabController,
        children: [
          _lendLoading
              ? const Center(child: CircularProgressIndicator(color: _cyan))
              : RefreshIndicator(
            color: _cyan,
            backgroundColor: _card,
            onRefresh: _fetchLends,
            child: _LendTab(
              lendList: _lendList,
              totalLent: _totalLent,
              onToggleReceived: _toggleLendReceived,
              onDelete: _deleteLend,
            ),
          ),

          _liabilityLoading
              ? const Center(child: CircularProgressIndicator(color: _cyan))
              : RefreshIndicator(
            color: _cyan,
            backgroundColor: _card,
            onRefresh: _fetchLiabilities,
            child: _LiabilityTab(
              liabilityList: _liabilityList,
              totalLiability: _totalLiability,
              onTogglePaid: _toggleLiabilityPaid,
              onDelete: _deleteLiability,
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: Colors.black,

        selectedItemColor: Colors.blue,
        unselectedItemColor: Colors.white60,

        type: BottomNavigationBarType.fixed,

        currentIndex: _selectedIndex,

        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });

          if (index == 0) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => CardHome(
                  userId: widget.userId,
                  userName: widget.userName,
                ),
              ),
            );
          }

          if (index == 1) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ViewCardScreen(
                  userId: widget.userId,userName: widget.userName,
                ),
              ),
            );
          }

          if (index == 2) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ViewReminderPage(
                  userId: widget.userId,userName: widget.userName,
                ),
              ),
            );
          }
        },

        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: "Home",
          ),

          BottomNavigationBarItem(
            icon: Icon(Icons.credit_card),
            label: "Cards",
          ),

          BottomNavigationBarItem(
            icon: Icon(Icons.notifications),
            label: "Reminder",
          ),
        ],
      ),
    );

  }
}





// ─────────────────────────────────────────────
//  LEND TAB
// ─────────────────────────────────────────────

class _LendTab extends StatelessWidget {
  final List<LendEntry> lendList;
  final double totalLent;
  final Future<void> Function(int) onToggleReceived;
  final Future<void> Function(int) onDelete;

  const _LendTab({
    required this.lendList,
    required this.totalLent,
    required this.onToggleReceived,
    required this.onDelete,
  });

  static const Color _cyan = Color(0xFF00D9FF);

  @override
  Widget build(BuildContext context) {
    final pending  = lendList.where((e) => !e.isReceived).toList();
    final received = lendList.where((e) =>  e.isReceived).toList();

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: _SummaryCard(
              label: "Total Pending Amount",
              amount: totalLent,
              accentColor: _cyan,
              icon: Icons.arrow_upward_rounded,
              pendingCount: pending.length,
              receivedCount: received.length,
            ),
          ),
        ),

        if (pending.isNotEmpty) ...[
          _SectionHeader(label: "Pending (${pending.length})"),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                    (_, i) {
                  final originalIndex = lendList.indexOf(pending[i]);
                  return _LendCard(
                    entry: pending[i],
                    onToggleReceived: () => onToggleReceived(originalIndex),
                    onDelete: () => onDelete(originalIndex),
                  );
                },
                childCount: pending.length,
              ),
            ),
          ),
        ],

        if (received.isNotEmpty) ...[
          _SectionHeader(label: "Received (${received.length})"),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                    (_, i) {
                  final originalIndex = lendList.indexOf(received[i]);
                  return _LendCard(
                    entry: received[i],
                    onToggleReceived: () => onToggleReceived(originalIndex),
                    onDelete: () => onDelete(originalIndex),
                  );
                },
                childCount: received.length,
              ),
            ),
          ),
        ],

        if (lendList.isEmpty)
          SliverFillRemaining(
            child: _EmptyState(
              icon: Icons.attach_money_rounded,
              message: "No lend records yet.\nTap + to add an entry.",
              accentColor: _cyan,
            ),
          ),

        const SliverToBoxAdapter(child: SizedBox(height: 90)),
      ],
    );
  }
}

// ─────────────────────────────────────────────
//  LIABILITY TAB
// ─────────────────────────────────────────────

class _LiabilityTab extends StatelessWidget {
  final List<LiabilityEntry> liabilityList;
  final double totalLiability;
  final Future<void> Function(int) onTogglePaid;
  final Future<void> Function(int) onDelete;

  const _LiabilityTab({
    required this.liabilityList,
    required this.totalLiability,
    required this.onTogglePaid,
    required this.onDelete,
  });

  static const Color _cyan = Color(0xFF00D9FF);

  @override
  Widget build(BuildContext context) {
    final unpaid = liabilityList.where((e) => !e.isPaid).toList();
    final paid   = liabilityList.where((e) =>  e.isPaid).toList();

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: _SummaryCard(
              label: "Total Amount I Owe",
              amount: totalLiability,
              accentColor: _cyan,
              icon: Icons.arrow_downward_rounded,
              pendingCount: unpaid.length,
              receivedCount: paid.length,
              pendingLabel: "Unpaid",
              receivedLabel: "Paid",
            ),
          ),
        ),

        if (unpaid.isNotEmpty) ...[
          _SectionHeader(label: "Unpaid (${unpaid.length})"),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                    (_, i) {
                  final originalIndex = liabilityList.indexOf(unpaid[i]);
                  return _LiabilityCard(
                    entry: unpaid[i],
                    onTogglePaid: () => onTogglePaid(originalIndex),
                    onDelete: () => onDelete(originalIndex),
                  );
                },
                childCount: unpaid.length,
              ),
            ),
          ),
        ],

        if (paid.isNotEmpty) ...[
          _SectionHeader(label: "Paid (${paid.length})"),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                    (_, i) {
                  final originalIndex = liabilityList.indexOf(paid[i]);
                  return _LiabilityCard(
                    entry: paid[i],
                    onTogglePaid: () => onTogglePaid(originalIndex),
                    onDelete: () => onDelete(originalIndex),
                  );
                },
                childCount: paid.length,
              ),
            ),
          ),
        ],

        if (liabilityList.isEmpty)
          SliverFillRemaining(
            child: _EmptyState(
              icon: Icons.account_balance_wallet_rounded,
              message: "No liability records yet.\nTap + to add an entry.",
              accentColor: _cyan,
            ),
          ),

        const SliverToBoxAdapter(child: SizedBox(height: 90)),
      ],
    );
  }
}

// ─────────────────────────────────────────────
//  LEND CARD
// ─────────────────────────────────────────────

class _LendCard extends StatelessWidget {
  final LendEntry entry;
  final VoidCallback onToggleReceived;
  final VoidCallback onDelete;

  const _LendCard({
    required this.entry,
    required this.onToggleReceived,
    required this.onDelete,
  });

  static const Color _cyan  = Color(0xFF00D9FF);
  static const Color _green = Color(0xFF00E5A0);
  static const Color _card  = Color(0xFF13131A);

  @override
  Widget build(BuildContext context) {
    final bool isRcv = entry.isReceived;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isRcv ? _green.withValues(alpha: 0.5) : _cyan.withValues(alpha: 0.4),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: (isRcv ? _green : _cyan).withValues(alpha: 0.06),
            blurRadius: 20,
          ),
        ],
      ),
      child: Column(
        children: [
          // ── Header ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isRcv
                    ? [_green.withValues(alpha: 0.12), Colors.transparent]
                    : [_cyan.withValues(alpha: 0.10),  Colors.transparent],
                begin: Alignment.centerLeft,
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: (isRcv ? _green : _cyan).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: (isRcv ? _green : _cyan).withValues(alpha: 0.4)),
                  ),
                  child: Center(
                    child: Text(
                      entry.name.isNotEmpty ? entry.name[0].toUpperCase() : "?",
                      style: TextStyle(
                        color: isRcv ? _green : _cyan,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(entry.name,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 16)),
                      const SizedBox(height: 2),
                      Text(entry.reason,
                          style: const TextStyle(
                              color: Color(0xFF8A8AA0), fontSize: 12.5),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: isRcv
                        ? _green.withValues(alpha: 0.18)
                        : _cyan.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isRcv
                          ? _green.withValues(alpha: 0.5)
                          : _cyan.withValues(alpha: 0.5),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    isRcv ? "✓ Received" : "⏳ Pending",
                    style: TextStyle(
                      color: isRcv ? _green : _cyan,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Body ──
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _InfoChip(
                        icon: Icons.currency_rupee_rounded,
                        label: "Amount",
                        value: "₹${entry.amount}",
                        color: isRcv ? _green : _cyan,
                        large: true,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _InfoChip(
                        icon: Icons.calendar_today_rounded,
                        label: "Due Date",
                        value: entry.date,
                        color: isRcv ? _green : _cyan,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _ActionButton(
                        label: isRcv ? "Set to Pending" : "Received",
                        icon:  isRcv ? Icons.undo_rounded : Icons.check_circle_rounded,
                        color: _cyan,
                        onTap: onToggleReceived,
                      ),
                    ),
                    const SizedBox(width: 10),
                    _DeleteButton(onTap: onDelete),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  LIABILITY CARD
// ─────────────────────────────────────────────

class _LiabilityCard extends StatelessWidget {
  final LiabilityEntry entry;
  final VoidCallback onTogglePaid;
  final VoidCallback onDelete;

  const _LiabilityCard({
    required this.entry,
    required this.onTogglePaid,
    required this.onDelete,
  });

  static const Color _cyan  = Color(0xFF00D9FF);
  static const Color _green = Color(0xFF00E5A0);
  static const Color _card  = Color(0xFF13131A);

  @override
  Widget build(BuildContext context) {
    final bool paid = entry.isPaid;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: paid ? _green.withValues(alpha: 0.5) : _cyan.withValues(alpha: 0.45),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: (paid ? _green : _cyan).withValues(alpha: 0.06),
            blurRadius: 20,
          ),
        ],
      ),
      child: Column(
        children: [
          // ── Header ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: paid
                    ? [_green.withValues(alpha: 0.10), Colors.transparent]
                    : [_cyan.withValues(alpha: 0.10),  Colors.transparent],
                begin: Alignment.centerLeft,
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: (paid ? _green : _cyan).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: (paid ? _green : _cyan).withValues(alpha: 0.4)),
                  ),
                  child: Center(
                    child: Text(
                      entry.name.isNotEmpty ? entry.name[0].toUpperCase() : "?",
                      style: TextStyle(
                        color: paid ? _green : _cyan,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(entry.name,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 16)),
                      const SizedBox(height: 2),
                      Text(entry.reason,
                          style: const TextStyle(
                              color: Color(0xFF8A8AA0), fontSize: 12.5),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: paid
                        ? _green.withValues(alpha: 0.18)
                        : _cyan.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: paid
                          ? _green.withValues(alpha: 0.5)
                          : _cyan.withValues(alpha: 0.5),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    paid ? "✓ Paid" : "💰 Owes Me",
                    style: TextStyle(
                      color: paid ? _green : _cyan,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Body ──
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _InfoChip(
                        icon: Icons.currency_rupee_rounded,
                        label: "Amount",
                        value: "₹${entry.amount}",
                        color: paid ? _green : _cyan,
                        large: true,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _InfoChip(
                        icon: Icons.calendar_today_rounded,
                        label: "Pay By",
                        value: entry.date,
                        color: paid ? _green : _cyan,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _ActionButton(
                        label: paid ? "Owes Me" : "Mark Payable",
                        icon:  paid ? Icons.undo_rounded : Icons.payments_rounded,
                        color: _cyan,
                        onTap: onTogglePaid,
                      ),
                    ),
                    const SizedBox(width: 10),
                    _DeleteButton(onTap: onDelete),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  BOTTOM SHEET FORM
// ─────────────────────────────────────────────

class _BottomSheetForm extends StatefulWidget {
  final String title;
  final Color accentColor;
  final GlobalKey<FormState> formKey;
  final TextEditingController nameCtrl;
  final TextEditingController reasonCtrl;
  final TextEditingController amountCtrl;
  final TextEditingController dateCtrl;
  final Future<void> Function() onPickDate;
  final String buttonLabel;
  final IconData buttonIcon;
  final VoidCallback onSubmit;

  const _BottomSheetForm({
    required this.title,
    required this.accentColor,
    required this.formKey,
    required this.nameCtrl,
    required this.reasonCtrl,
    required this.amountCtrl,
    required this.dateCtrl,
    required this.onPickDate,
    required this.buttonLabel,
    required this.buttonIcon,
    required this.onSubmit,
  });

  @override
  State<_BottomSheetForm> createState() => _BottomSheetFormState();
}

class _BottomSheetFormState extends State<_BottomSheetForm> {
  static const Color _bg = Color(0xFF0F0F18);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        left: 20, right: 20,
      ),
      decoration: const BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 42, height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFF2E2E45),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: widget.accentColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(widget.buttonIcon, color: widget.accentColor, size: 20),
              ),
              const SizedBox(width: 12),
              Text(widget.title,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
            ],
          ),
          const SizedBox(height: 22),
          Form(
            key: widget.formKey,
            child: Column(
              children: [
                _FormField(controller: widget.nameCtrl,   label: "Person Name",  icon: Icons.person_rounded,         accent: widget.accentColor),
                const SizedBox(height: 14),
                _FormField(controller: widget.reasonCtrl, label: "Reason",       icon: Icons.notes_rounded,           accent: widget.accentColor),
                const SizedBox(height: 14),
                _FormField(controller: widget.amountCtrl, label: "Amount (₹)",   icon: Icons.currency_rupee_rounded,  accent: widget.accentColor, keyboardType: TextInputType.number),
                const SizedBox(height: 14),
                GestureDetector(
                  onTap: () async { await widget.onPickDate(); setState(() {}); },
                  child: AbsorbPointer(
                    child: _FormField(controller: widget.dateCtrl, label: "Payable Date", icon: Icons.calendar_month_rounded, accent: widget.accentColor),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity, height: 54,
                  child: ElevatedButton.icon(
                    onPressed: widget.onSubmit,
                    icon: Icon(widget.buttonIcon, size: 20),
                    label: Text(widget.buttonLabel,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, letterSpacing: 0.3)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: widget.accentColor,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  REUSABLE WIDGETS
// ─────────────────────────────────────────────

class _FormField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final Color accent;
  final TextInputType keyboardType;

  const _FormField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.accent,
    this.keyboardType = TextInputType.text,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white, fontSize: 15),
      validator: (v) => (v == null || v.trim().isEmpty) ? "Enter $label" : null,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF6B6B85), fontSize: 14),
        prefixIcon: Icon(icon, color: accent, size: 20),
        filled: true,
        fillColor: const Color(0xFF1A1A28),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: accent.withValues(alpha: 0.3), width: 1.2)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: accent, width: 1.8)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFFF4D6D), width: 1.2)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFFF4D6D), width: 1.8)),
        contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final double amount;
  final Color accentColor;
  final IconData icon;
  final int pendingCount;
  final int receivedCount;
  final String pendingLabel;
  final String receivedLabel;

  const _SummaryCard({
    required this.label,
    required this.amount,
    required this.accentColor,
    required this.icon,
    required this.pendingCount,
    required this.receivedCount,
    this.pendingLabel  = "Pending",
    this.receivedLabel = "Received",
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [accentColor.withValues(alpha: 0.18), accentColor.withValues(alpha: 0.05), const Color(0xFF13131A)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: accentColor.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: accentColor, size: 18),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: accentColor.withValues(alpha: 0.9), fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 10),
          Text("₹${amount.toStringAsFixed(2)}",
              style: TextStyle(color: accentColor, fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
          const SizedBox(height: 14),
          Row(children: [
            _StatPill(label: pendingLabel,  count: pendingCount,  color: const Color(0xFF00D9FF)),
            const SizedBox(width: 10),
            _StatPill(label: receivedLabel, count: receivedCount, color: const Color(0xFF00E5A0)),
          ]),
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _StatPill({required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text("$count", style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 14)),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 12, fontWeight: FontWeight.w500)),
      ]),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final bool large;
  const _InfoChip({required this.icon, required this.label, required this.value, required this.color, this.large = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: Color(0xFF8A8AA0), fontSize: 10.5, fontWeight: FontWeight.w500)),
          const SizedBox(height: 1),
          Text(value,
              style: TextStyle(color: large ? color : Colors.white, fontSize: large ? 15 : 13, fontWeight: large ? FontWeight.w800 : FontWeight.w600),
              overflow: TextOverflow.ellipsis),
        ])),
      ]),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _ActionButton({required this.label, required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 7),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13.5)),
        ]),
      ),
    );
  }
}

class _DeleteButton extends StatelessWidget {
  final VoidCallback onTap;
  const _DeleteButton({required this.onTap});
  static const Color _red = Color(0xFFFF4D6D);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 46, width: 52,
        decoration: BoxDecoration(
          color: _red.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: _red.withValues(alpha: 0.4)),
        ),
        child: const Icon(Icons.delete_rounded, color: _red, size: 20),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final Color color;
  const _SectionHeader({required this.label, this.color = const Color(0xFF00D9FF)});

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 22, 16, 10),
        child: Row(children: [
          Container(width: 3, height: 16,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13, letterSpacing: 0.5)),
        ]),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final Color accentColor;
  const _EmptyState({required this.icon, required this.message, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.1),
            shape: BoxShape.circle,
            border: Border.all(color: accentColor.withValues(alpha: 0.25), width: 1.5),
          ),
          child: Icon(icon, color: accentColor.withValues(alpha: 0.6), size: 36),
        ),
        const SizedBox(height: 18),
        Text(message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF6B6B85), fontSize: 14.5, height: 1.6)),
      ]),
    );
  }
}

class _TabIconBtn extends StatelessWidget {
  final IconData icon;
  final bool active;
  final Color activeAccent;
  final VoidCallback onTap;
  const _TabIconBtn({required this.icon, required this.active, required this.activeAccent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 26, height: 26,
        decoration: BoxDecoration(
          color: active ? Colors.black.withValues(alpha: 0.22) : activeAccent.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: active ? Colors.black.withValues(alpha: 0.35) : activeAccent.withValues(alpha: 0.38),
            width: 1,
          ),
        ),
        child: Icon(icon, size: 15, color: active ? Colors.black : activeAccent),
      ),
    );
  }
}