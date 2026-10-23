// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:card/config/app_config.dart';
import 'card_create_screen.dart';
import '../services/email_sync_service.dart';

class AddReminderPage extends StatefulWidget {
  final String userId;
  final String userName;
  final Map<String, dynamic>? initialBill;

  const AddReminderPage({
    super.key,
    required this.userId,
    required this.userName,
    this.initialBill,
  });

  @override
  State<AddReminderPage> createState() =>
      _AddReminderPageState();
}

class _AddReminderPageState extends State<AddReminderPage> {

  List cards = [];
  bool isLoadingCards = true;
  String? selectedBankName;
  String? selectedCardId;

  DateTime? statementDate;
  DateTime? paymentDate;

  final TextEditingController amountController = TextEditingController();

  Map<String, Map<String, dynamic>> reminders = {};
  bool gmailConnected = false;
  bool isFetchingGmail = false;

  static const Color _bg         = Color(0xFF195754);
  static const Color _forestDark = Color(0xFF195754);
  static const Color _darkText   = Colors.white;
  static const Color _terracotta = Color(0xFFB8452D);

  @override
  void initState() {
    super.initState();
    fetchCards();
    _loadGmailStatus();
  }

  Future<void> _loadGmailStatus() async {
    try {
      final status = await EmailSyncService.getStatus(widget.userId);
      if (mounted) {
        setState(() {
          gmailConnected = status['connected'] == true;
        });
      }
    } catch (_) {}
  }

  Future<void> _connectGmail() async {
    final result = await EmailSyncService.connectGmail(widget.userId);
    if (!mounted) return;
    if (result['success'] == true) {
      setState(() => gmailConnected = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: _forestDark,
          content: Text(
            'Gmail connected: ${result['googleEmail'] ?? ''}',
            style: GoogleFonts.inter(color: Colors.white),
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: _terracotta,
          content: Text(
            result['message'] ?? 'Gmail connect failed',
            style: GoogleFonts.inter(color: Colors.white),
          ),
        ),
      );
    }
  }

  void _applyBillToForm(Map<String, dynamic> bill) {
    setState(() {
      if (bill['amount'] != null) {
        amountController.text = bill['amount'].toString();
      }
      if (bill['statementDate'] != null) {
        statementDate = DateTime.tryParse(bill['statementDate'].toString());
      }
      if (bill['paymentDueDate'] != null) {
        paymentDate = DateTime.tryParse(bill['paymentDueDate'].toString());
      }
      final cardId = bill['cardId'];
      if (cardId != null) {
        final idStr = cardId is Map ? cardId['_id']?.toString() : cardId.toString();
        if (idStr != null && cards.any((c) => c['_id'] == idStr)) {
          selectedCardId = idStr;
          selectedBankName = bill['bankName']?.toString();
        }
      } else if (bill['bankName'] != null) {
        final match = cards.cast<Map>().where(
          (c) => (c['bankName'] as String?)
              ?.toLowerCase()
              .contains(bill['bankName'].toString().toLowerCase()) ?? false,
        );
        if (match.length == 1) {
          selectedCardId = match.first['_id'];
          selectedBankName = match.first['bankName'];
        }
      }
    });
  }

  Future<void> _fetchFromGmail() async {
    if (!gmailConnected) {
      await _connectGmail();
      if (!gmailConnected) return;
    }

    setState(() => isFetchingGmail = true);

    try {
      final syncResult = await EmailSyncService.syncBills(widget.userId);
      if (!mounted) return;

      if (syncResult['success'] != true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: _terracotta,
            content: Text(
              syncResult['message'] ?? 'Sync failed',
              style: GoogleFonts.inter(color: Colors.white),
            ),
          ),
        );
        return;
      }

      final suggestions =
          await EmailSyncService.getSuggestions(widget.userId);
      if (!mounted) return;

      if (suggestions.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: _forestDark,
            content: Text(
              'No credit card bills found in Gmail (last 45 days)',
              style: GoogleFonts.inter(color: Colors.white),
            ),
          ),
        );
        return;
      }

      await showModalBottomSheet(
        context: context,
        backgroundColor: _bg,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (ctx) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Bills from Gmail',
                    style: GoogleFonts.inter(
                      color: _darkText,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 14),
                  ...suggestions.map((bill) {
                    final bank = bill['bankName'] ?? 'Card';
                    final last4 = bill['last4Digits'] ?? '****';
                    final amount = bill['amount']?.toString() ?? '?';
                    final due = bill['paymentDueDate'] != null
                        ? DateFormat('dd MMM yyyy').format(
                            DateTime.parse(bill['paymentDueDate'].toString()),
                          )
                        : 'Unknown';

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
                      ),
                      child: ListTile(
                        title: Text(
                          '$bank •••• $last4',
                          style: GoogleFonts.inter(color: _darkText, fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          '₹$amount due $due',
                          style: GoogleFonts.inter(color: Colors.black54, fontSize: 13),
                        ),
                        trailing: const Icon(
                          Icons.arrow_forward_ios_rounded,
                          color: _forestDark,
                          size: 16,
                        ),
                        onTap: () async {
                          await EmailSyncService.applyBill(
                            userId: widget.userId,
                            parsedBillId: bill['_id'].toString(),
                            cardId: bill['cardId'] is Map
                                ? bill['cardId']['_id']?.toString()
                                : bill['cardId']?.toString(),
                          );
                          if (ctx.mounted) Navigator.pop(ctx);
                          _applyBillToForm(bill);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: _forestDark,
                                content: Text(
                                  'Bill details applied — set reminder schedule',
                                  style: GoogleFonts.inter(color: Colors.white),
                                ),
                              ),
                            );
                          }
                        },
                      ),
                    );
                  }),
                ],
              ),
            ),
          );
        },
      );
    } finally {
      if (mounted) setState(() => isFetchingGmail = false);
    }
  }

  Future<void> fetchCards() async {
    try {
      final res = await http.get(
        Uri.parse(
          "${AppConfig.cards}?userId=${widget.userId}",
        ),
      );

      final data = jsonDecode(res.body);

      if (!mounted) return;

      setState(() {
        cards = data["data"] ?? [];
        isLoadingCards = false;
        if (widget.initialBill != null) {
          _applyBillToForm(widget.initialBill!);
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() => isLoadingCards = false);
      }
    }
  }

  Future<void> onSaveReminderButtonClick() async {
    if (selectedCardId == null ||
        amountController.text.isEmpty ||
        statementDate == null ||
        paymentDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: _terracotta,
          content: Text(
            "Please fill all fields",
            style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600),
          ),
        ),
      );
      return;
    }

    final Map<String, dynamic> formattedReminders = {};

    reminders.forEach((key, value) {
      final List<TimeOfDay> timesList =
      (value["times"] as List? ?? []).cast<TimeOfDay>();

      final List<String> times = timesList.map((t) {
        final hour = t.hour.toString().padLeft(2, '0');
        final minute = t.minute.toString().padLeft(2, '0');
        return "$hour:$minute";
      }).toList();

      formattedReminders[key] = {
        "count": value["count"],
        "times": times,
      };
    });

    String? bName = selectedBankName;
    if (bName == null && selectedCardId != null && cards.isNotEmpty) {
      final cardMatch = cards.firstWhere(
        (c) => c['_id'] == selectedCardId,
        orElse: () => null,
      );
      if (cardMatch != null) {
        bName = cardMatch['bankName']?.toString();
      }
    }

    final body = {
      "userId": widget.userId,
      "cardId": selectedCardId,
      "bankName": bName ?? "Bank",
      "amount": amountController.text.trim(),
      "statementDate": statementDate!.toIso8601String(),
      "paymentDate": paymentDate!.toIso8601String(),
      "paymentDueDate": paymentDate!.toIso8601String(),
      "reminders": formattedReminders,
    };

    try {
      final res = await http.post(
        Uri.parse(AppConfig.reminderAdd),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(body),
      );

      Map<String, dynamic> data = {};
      try {
        if (res.body.isNotEmpty) {
          data = jsonDecode(res.body) as Map<String, dynamic>;
        }
      } catch (_) {}

      if (!mounted) return;

      if (res.statusCode == 200 || res.statusCode == 201) {
        if (widget.initialBill != null && widget.initialBill!['_id'] != null) {
          try {
            await EmailSyncService.applyBill(
              userId: widget.userId,
              parsedBillId: widget.initialBill!['_id'].toString(),
              cardId: selectedCardId,
            );
          } catch (_) {}
        }

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: _forestDark,
            content: Text(
              "Reminder Saved Successfully!",
              style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        );
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: _terracotta,
            content: Text(
              data["message"] ?? "Failed to save reminder (${res.statusCode})",
              style: GoogleFonts.inter(color: Colors.white),
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: _terracotta,
          content: Text(
            "Error saving reminder: $e",
            style: GoogleFonts.inter(color: Colors.white),
          ),
        ),
      );
    }
  }

  Future<void> pickDate(bool isStatement) async {
    DateTime initialDate = DateTime.now();

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(
              primary: _forestDark,
              onPrimary: Colors.white,
              surface: _bg,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        if (isStatement) {
          statementDate = picked;
        } else {
          paymentDate = picked;
        }
      });
    }
  }

  Future<void> pickTimes(String key) async {
    int count = reminders[key]?["count"] ?? 1;
    List<TimeOfDay> times = [];

    for (int i = 0; i < count; i++) {
      final picked = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.now(),
        builder: (context, child) {
          return Theme(
            data: ThemeData.light().copyWith(
              colorScheme: const ColorScheme.light(
                primary: _forestDark,
                onPrimary: Colors.white,
                surface: _bg,
              ),
            ),
            child: child!,
          );
        },
      );

      if (picked != null) {
        times.add(picked);
      }
    }

    setState(() {
      reminders[key]!["times"] = times;
    });
  }

  Widget radioBtn(
    String key,
    int value,
    String label,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Radio<int>(
          value: value,
          groupValue: reminders[key]?["count"] ?? 1,
          activeColor: const Color(0xFF195754),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          onChanged: (val) {
            if (val == null) return;
            setState(() {
              reminders[key]!["count"] = val;
              reminders[key]!["times"] = <TimeOfDay>[];
            });
          },
        ),
        const SizedBox(width: 2),
        Flexible(
          child: Text(
            label,
            style: GoogleFonts.inter(
              color: const Color(0xFF1E293B),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget buildReminderTile(
    String key,
    String title,
  ) {
    bool selected = reminders.containsKey(key);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected
              ? const Color(0xFF195754)
              : Colors.black.withValues(alpha: 0.08),
          width: selected ? 1.5 : 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Checkbox(
                value: selected,
                activeColor: const Color(0xFF195754),
                checkColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                side: BorderSide(
                  color: selected ? const Color(0xFF195754) : Colors.black38,
                  width: 1.5,
                ),
                onChanged: (val) {
                  setState(() {
                    if (val == true) {
                      reminders[key] = {
                        "count": 1,
                        "times": <TimeOfDay>[],
                      };
                    } else {
                      reminders.remove(key);
                    }
                  });
                },
              ),
              const SizedBox(width: 4),
              Text(
                title,
                style: GoogleFonts.inter(
                  color: const Color(0xFF1E293B),
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          if (selected)
            Column(
              children: [
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Expanded(
                      child: radioBtn(
                        key,
                        1,
                        "Once",
                      ),
                    ),
                    Expanded(
                      child: radioBtn(
                        key,
                        2,
                        "Twice",
                      ),
                    ),
                    Expanded(
                      child: radioBtn(
                        key,
                        3,
                        "Thrice",
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF195754).withValues(alpha: 0.08),
                    foregroundColor: const Color(0xFF195754),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: const Color(0xFF195754).withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  icon: const Icon(Icons.access_time_rounded, size: 16, color: Color(0xFF195754)),
                  onPressed: () => pickTimes(key),
                  label: Text(
                    "Select Time",
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: const Color(0xFF195754),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Column(
                  children: (reminders[key]?["times"] as List? ?? []).map((t) {
                    if (t is TimeOfDay) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          "${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}",
                          style: GoogleFonts.inter(
                            color: const Color(0xFF195754),
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      );
                    }
                    return const SizedBox();
                  }).toList(),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget buildDateTile({
    required String title,
    required String value,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.black.withValues(alpha: 0.08),
          width: 1.2,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          onTap: onTap,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF195754).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.calendar_month_rounded,
              color: Color(0xFF195754),
              size: 20,
            ),
          ),
          title: Text(
            title,
            style: GoogleFonts.inter(
              color: Colors.black45,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              value,
              style: GoogleFonts.inter(
                color: const Color(0xFF1E293B),
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          trailing: const Icon(
            Icons.chevron_right_rounded,
            color: Colors.black38,
            size: 20,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat("dd MMM yyyy");

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
            ),
            child: const Icon(
              Icons.arrow_back_rounded,
              color: Color(0xFF1E293B),
              size: 20,
            ),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: Text(
          "Add Reminder",
          style: GoogleFonts.inter(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top design header banner
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.black.withValues(alpha: 0.08),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF195754).withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.notifications_active_rounded,
                        size: 26,
                        color: Color(0xFF195754),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Smart Payment Reminder",
                            style: GoogleFonts.inter(
                              color: const Color(0xFF1E293B),
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Never miss your bill due date",
                            style: GoogleFonts.inter(
                              color: Colors.black54,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Temporary: Gmail sign-in is disabled on iOS until an OAuth client exists.
              if (!Platform.isIOS) ...[
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: isFetchingGmail ? null : _fetchFromGmail,
                  icon: isFetchingGmail
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF195754)),
                        )
                      : const Icon(Icons.mail_outline_rounded, size: 18, color: Color(0xFF195754)),
                  label: Text(
                    gmailConnected ? 'Fetch from Gmail' : 'Connect & Fetch Gmail',
                    style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14, color: const Color(0xFF195754)),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: Colors.black.withValues(alpha: 0.08),
                        width: 1.2,
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // QFin Form Container
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: Colors.black.withValues(alpha: 0.08),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      "Reminder Details",
                      style: GoogleFonts.inter(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // BANK DROPDOWN
                    if (isLoadingCards)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.black.withValues(alpha: 0.1),
                            width: 1.2,
                          ),
                        ),
                        child: Row(
                          children: [
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2.2, color: Color(0xFF195754)),
                            ),
                            const SizedBox(width: 14),
                            Text(
                              "Loading cards...",
                              style: GoogleFonts.inter(
                                color: Colors.black45,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      )
                    else if (cards.isEmpty)
                      GestureDetector(
                        onTap: () async {
                          final added = await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CardCreateScreen(
                                userId: widget.userId,
                                userName: widget.userName,
                              ),
                            ),
                          );
                          if (added == true) {
                            fetchCards();
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: _terracotta.withValues(alpha: 0.4),
                              width: 1.2,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: _terracotta.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.account_balance_rounded,
                                  color: _terracotta,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "Select Bank",
                                      style: GoogleFonts.inter(
                                        color: Colors.black45,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      "No bank is added",
                                      style: GoogleFonts.inter(
                                        color: _terracotta,
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF195754),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.add_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      DropdownButtonFormField<String>(
                        value: selectedCardId,
                        isExpanded: true,
                        dropdownColor: Colors.white,
                        style: GoogleFonts.inter(
                          color: const Color(0xFF1E293B),
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: InputDecoration(
                          labelText: selectedBankName != null && cards.isEmpty
                              ? "Bank: $selectedBankName"
                              : "Select Bank",
                          hintText: cards.isEmpty ? "No saved cards (Add card first)" : "Select Bank",
                          labelStyle: GoogleFonts.inter(
                            color: Colors.black45,
                            fontSize: 14,
                          ),
                          prefixIcon: const Icon(
                            Icons.account_balance_rounded,
                            color: Color(0xFF195754),
                            size: 20,
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color: Colors.black.withValues(alpha: 0.08),
                              width: 1.2,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(
                              color: Color(0xFF195754),
                              width: 1.5,
                            ),
                          ),
                        ),
                        items: cards.map<DropdownMenuItem<String>>((card) {
                          return DropdownMenuItem(
                            value: card["_id"],
                            child: Text(
                              card["bankName"] ?? "Bank",
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                color: const Color(0xFF1E293B),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          final selected = cards.firstWhere((c) => c["_id"] == value);
                          setState(() {
                            selectedBankName = selected["bankName"];
                            selectedCardId = value;
                            statementDate = selected["statementDate"] != null
                                ? DateTime.parse(selected["statementDate"])
                                : statementDate;
                            paymentDate = selected["paymentDueDate"] != null
                                ? DateTime.parse(selected["paymentDueDate"])
                                : paymentDate;
                          });
                        },
                      ),

                    const SizedBox(height: 18),

                    // AMOUNT FIELD
                    TextField(
                      controller: amountController,
                      keyboardType: TextInputType.number,
                      style: GoogleFonts.inter(
                        color: const Color(0xFF1E293B),
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: InputDecoration(
                        labelText: "Amount (₹)",
                        labelStyle: GoogleFonts.inter(
                          color: Colors.black45,
                          fontSize: 14,
                        ),
                        prefixIcon: const Icon(
                          Icons.currency_rupee_rounded,
                          color: Color(0xFF195754),
                          size: 20,
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                            color: Colors.black.withValues(alpha: 0.08),
                            width: 1.2,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(
                            color: Color(0xFF195754),
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 18),

                    // STATEMENT DATE
                    buildDateTile(
                      title: "Statement Date",
                      value: statementDate == null
                          ? "Select Date"
                          : dateFormat.format(statementDate!),
                      onTap: () => pickDate(true),
                    ),

                    // PAYMENT DATE
                    buildDateTile(
                      title: "Payment Date",
                      value: paymentDate == null
                          ? "Select Date"
                          : dateFormat.format(paymentDate!),
                      onTap: () => pickDate(false),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              Text(
                "Reminder Settings",
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),

              const SizedBox(height: 12),

              buildReminderTile(
                "7_days_before",
                "7 Days Before",
              ),

              buildReminderTile(
                "3_days_before",
                "3 Days Before",
              ),

              buildReminderTile(
                "1_day_before",
                "1 Day Before",
              ),

              buildReminderTile(
                "due_date",
                "Due Date",
              ),

              buildReminderTile(
                "1_day_after",
                "1 Day After",
              ),

              const SizedBox(height: 24),

              // SAVE BUTTON
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: onSaveReminderButtonClick,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF195754),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    "Save Reminder",
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
