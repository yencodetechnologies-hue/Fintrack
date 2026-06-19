import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:card/config/app_config.dart';
import 'card_home.dart';
import 'view_card_screen.dart';
import 'view_reminder_page.dart';
import 'home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
class AddReminderPage extends StatefulWidget {
  final String userId;
  final String userName;
  const AddReminderPage({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<AddReminderPage> createState() =>
      _AddReminderPageState();
}

class _AddReminderPageState
    extends State<AddReminderPage> {

  List cards = [];
  int _selectedIndex = 0;
  String? selectedBankName;
  String? selectedCardId;

  DateTime? statementDate;
  DateTime? paymentDate;

  final TextEditingController amountController =
  TextEditingController();

  Map<String, Map<String, dynamic>> reminders = {};

  @override
  void initState() {
    super.initState();
    fetchCards();
  }

  Future<void> fetchCards() async {
    final res = await http.get(
      Uri.parse(
        "${AppConfig.cards}?userId=${widget.userId}",
      ),
    );

    final data = jsonDecode(res.body);

    if (!mounted) return;

    setState(() {
      cards = data["data"] ?? [];
    });
  }

  Future<void> onSaveReminderButtonClick() async {

    if (selectedCardId == null ||
        amountController.text.isEmpty ||
        statementDate == null ||
        paymentDate == null) {

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please fill all fields"),
        ),
      );

      return;
    }

    final res = await http.post(
      Uri.parse(AppConfig.reminderAdd),

      headers: {
        "Content-Type": "application/json",
      },

      body: jsonEncode({
        "bankName": selectedBankName,
        "userId": widget.userId,
        "cardId": selectedCardId,
        "amount": amountController.text,
        "statementDate":
        statementDate!.toIso8601String(),
        "paymentDate":
        paymentDate!.toIso8601String(),

        "reminders":
        reminders.entries.map((entry) {
          return {
            "key": entry.key,
            "count": entry.value["count"],
            "times":
            (entry.value["times"] as List)
                .map((t) {

              if (t is TimeOfDay) {
                return
                  "${t.hour.toString().padLeft(2, '0')}:"
                      "${t.minute.toString().padLeft(2, '0')}";
              }

              return t.toString();

            }).toList(),
          };
        }).toList(),
      }),
    );

    final data = jsonDecode(res.body);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          data["message"] ?? "Saved",
        ),
      ),
    );

    Navigator.pop(context);
  }

  Future<void> pickDate(bool isStatement) async {

    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      builder: (context, child) {

        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppConfig.primaryTeal,
              surface: AppConfig.darkSlate,
            ),
          ),

          child: child!,
        );
      },
    );

    if (picked == null) return;

    setState(() {

      if (isStatement) {
        statementDate = picked;
      } else {
        paymentDate = picked;
      }

    });
  }

  String formatDate(DateTime? date) {

    if (date == null) {
      return "Select Date";
    }

    return
      "${date.day}-${date.month}-${date.year}";
  }

  Future<void> pickTimes(String key) async {

    int count = reminders[key]?["count"] ?? 1;

    List<TimeOfDay> times = [];

    for (int i = 0; i < count; i++) {

      final picked = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.now(),
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
          groupValue:
          reminders[key]?["count"] ?? 1,

          activeColor: AppConfig.primaryTeal,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,

          onChanged: (val) {

            if (val == null) return;

            setState(() {
              reminders[key]!["count"] = val;
              reminders[key]!["times"] =
              <TimeOfDay>[];
            });
          },
        ),

        const SizedBox(width: 4),

        Flexible(
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
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

    bool selected =
    reminders.containsKey(key);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: selected ? Colors.white.withOpacity(0.04) : Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: selected
              ? AppConfig.primaryTeal.withOpacity(0.4)
              : Colors.white.withOpacity(0.08),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
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
                activeColor: AppConfig.primaryTeal,
                checkColor: const Color(0xFF0F172A),
                side: BorderSide(
                  color: selected ? AppConfig.primaryTeal : Colors.white30,
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

              Text(
                title,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white70,
                  fontSize: 16,
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
                  mainAxisAlignment:
                  MainAxisAlignment.spaceEvenly,

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

                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppConfig.primaryTeal.withOpacity(0.1),
                    foregroundColor: AppConfig.primaryTeal,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: AppConfig.primaryTeal.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  onPressed: () => pickTimes(key),
                  child: const Text(
                    "Select Time",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                Column(
                  children:
                  (reminders[key]?["times"]
                  as List? ??
                      [])
                      .map((t) {

                    if (t is TimeOfDay) {

                      return Padding(
                        padding:
                        const EdgeInsets.only(
                          bottom: 6,
                        ),

                        child: Text(
                          "${t.hour.toString().padLeft(2, '0')}:"
                              "${t.minute.toString().padLeft(2, '0')}",

                          style: const TextStyle(
                            color: AppConfig.primaryTeal,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
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
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.08),
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
              color: AppConfig.primaryTeal.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.calendar_month,
              color: AppConfig.primaryTeal.withOpacity(0.8),
              size: 20,
            ),
          ),
          title: Text(
            title,
            style: const TextStyle(
              color: AppConfig.hintColor,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          trailing: const Icon(
            Icons.arrow_forward_ios,
            color: Colors.white30,
            size: 16,
          ),
        ),
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat("dd MMM yyyy");

    return Scaffold(
      backgroundColor: AppConfig.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.03),
              border: Border.all(
                color: AppConfig.primaryTeal.withOpacity(0.2),
                width: 1,
              ),
            ),
            padding: const EdgeInsets.all(4.0),
            child: Image.asset(
              "assets/images/logo.png",
            ),
          ),
        ),
        centerTitle: true,
        title: const Text(
          "Add Reminder",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 22,
            letterSpacing: 0.5,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.logout_rounded,
              color: AppConfig.primaryTeal,
              size: 26,
            ),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  backgroundColor: AppConfig.darkSlate,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: Colors.white.withOpacity(0.08),
                      width: 1.5,
                    ),
                  ),
                  title: const Text(
                    "Logout",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  content: const Text(
                    "Are you sure you want to logout?",
                    style: TextStyle(color: Colors.white70),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      child: const Text(
                        "Cancel",
                        style: TextStyle(color: Colors.white60),
                      ),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppConfig.primaryTeal,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () async {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.clear();
                        if (!context.mounted) return;
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const HomeScreen(),
                          ),
                          (route) => false,
                        );
                      },
                      child: const Text(
                        "Logout",
                        style: TextStyle(
                          color: Color(0xFF0F172A),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // Background soft glowing teal orb 1
          Positioned(
            top: -80,
            left: -80,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppConfig.primaryTeal.withOpacity(0.12),
              ),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 90, sigmaY: 90),
                child: Container(color: Colors.transparent),
              ),
            ),
          ),
          // Background soft glowing blue orb 2
          Positioned(
            bottom: -100,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppConfig.gradientEnd.withOpacity(0.08),
              ),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 80, sigmaY: 80),
                child: Container(color: Colors.transparent),
              ),
            ),
          ),

          SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Sleek, compact top design header banner
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      vertical: 18,
                      horizontal: 20,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.03),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.08),
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppConfig.primaryTeal.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.notifications_active,
                            size: 28,
                            color: AppConfig.primaryTeal,
                          ),
                        ),
                        const SizedBox(width: 16),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Smart Payment Reminder",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                "Never miss your payment",
                                style: TextStyle(
                                  color: AppConfig.hintColor,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Glassmorphic Form Container
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.02),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.06),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.4),
                          blurRadius: 25,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          "Reminder Details",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 20),

                        // BANK DROPDOWN
                        DropdownButtonFormField<String>(
                          dropdownColor: AppConfig.darkSlate,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                          ),
                          decoration: InputDecoration(
                            labelText: "Select Bank",
                            labelStyle: const TextStyle(
                              color: AppConfig.hintColor,
                              fontSize: 14,
                            ),
                            prefixIcon: const Icon(
                              Icons.account_balance_rounded,
                              color: AppConfig.primaryTeal,
                              size: 20,
                            ),
                            filled: true,
                            fillColor: Colors.white.withOpacity(0.03),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(
                                color: Colors.white.withOpacity(0.08),
                                width: 1.2,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(
                                color: AppConfig.primaryTeal,
                                width: 1.5,
                              ),
                            ),
                          ),
                          items: cards.map<DropdownMenuItem<String>>((card) {
                            return DropdownMenuItem(
                              value: card["_id"],
                              child: Text(
                                card["bankName"],
                                style: const TextStyle(
                                  color: Colors.white,
                                ),
                              ),
                            );
                          }).toList(),
                          onChanged: (value) {
                            final selected = cards.firstWhere((c) => c["_id"] == value);
                            setState(() {
                              selectedBankName = selected["bankName"];
                              selectedCardId = value;
                              statementDate = selected["statementDate"] != null
                                  ? DateTime.parse(selected["statementDate"])
                                  : null;
                              paymentDate = selected["paymentDueDate"] != null
                                  ? DateTime.parse(selected["paymentDueDate"])
                                  : null;
                            });
                          },
                        ),

                        const SizedBox(height: 18),

                        // AMOUNT FIELD
                        TextField(
                          controller: amountController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                          ),
                          decoration: InputDecoration(
                            labelText: "Amount",
                            labelStyle: const TextStyle(
                              color: AppConfig.hintColor,
                              fontSize: 14,
                            ),
                            prefixIcon: const Icon(
                              Icons.currency_rupee,
                              color: AppConfig.primaryTeal,
                              size: 20,
                            ),
                            filled: true,
                            fillColor: Colors.white.withOpacity(0.03),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(
                                color: Colors.white.withOpacity(0.08),
                                width: 1.2,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(
                                color: AppConfig.primaryTeal,
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

                  const Text(
                    "Reminder Settings",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Colors.white70,
                      letterSpacing: -0.2,
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
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: const LinearGradient(
                        colors: [
                          AppConfig.gradientStart,
                          AppConfig.gradientEnd,
                        ],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppConfig.gradientStart.withOpacity(0.3),
                          blurRadius: 15,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: ElevatedButton(
                      onPressed: onSaveReminderButtonClick,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        minimumSize: const Size(double.infinity, 56),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        "Save Reminder",
                        style: TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: AppConfig.darkSlate,
        selectedItemColor: AppConfig.primaryTeal,
        unselectedItemColor: Colors.white30,
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        onTap: (index) {
          if (index == _selectedIndex) return;
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
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => ViewCardScreen(
                  userId: widget.userId,
                  userName: widget.userName,
                ),
              ),
            );
          }

          if (index == 2) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => ViewReminderPage(
                  userId: widget.userId,
                  userName: widget.userName,
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