import 'package:flutter/material.dart';
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
              primary: Color(0xFF00D9FF),
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
      children: [

        Radio<int>(
          value: value,
          groupValue:
          reminders[key]?["count"] ?? 1,

          activeColor:
          const Color(0xFF00D9FF),

          onChanged: (val) {

            if (val == null) return;

            setState(() {
              reminders[key]!["count"] = val;
              reminders[key]!["times"] =
              <TimeOfDay>[];
            });
          },
        ),

        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
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
      margin: const EdgeInsets.only(bottom: 15),

      padding: const EdgeInsets.all(15),

      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius:
        BorderRadius.circular(20),

        border: Border.all(
          color: const Color(0xFF00D9FF),
          width: 2,
        ),
      ),

      child: Column(
        children: [

          Row(
            children: [

              Checkbox(
                value: selected,

                activeColor:
                const Color(0xFF00D9FF),

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
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),

          if (selected)
            Column(
              children: [

                Row(
                  mainAxisAlignment:
                  MainAxisAlignment.spaceEvenly,

                  children: [

                    radioBtn(
                      key,
                      1,
                      "Once",
                    ),

                    radioBtn(
                      key,
                      2,
                      "Twice",
                    ),

                    radioBtn(
                      key,
                      3,
                      "Thrice",
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                ElevatedButton(
                  style:
                  ElevatedButton.styleFrom(
                    backgroundColor:
                    const Color(0xFF00D9FF),

                    foregroundColor:
                    Colors.black,
                  ),

                  onPressed: () =>
                      pickTimes(key),

                  child: const Text(
                    "Select Time",
                  ),
                ),

                const SizedBox(height: 10),

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
                          bottom: 5,
                        ),

                        child: Text(
                          "${t.hour.toString().padLeft(2, '0')}:"
                              "${t.minute.toString().padLeft(2, '0')}",

                          style: const TextStyle(
                            color: Colors.white,
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

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      backgroundColor: Colors.black,

      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.all(8.0),

          child: CircleAvatar(
            backgroundColor: Colors.transparent,

            child: Image.asset(
              "assets/images/logo.png",
            ),
          ),
        ),
        centerTitle: true,

        title: ShaderMask(
          shaderCallback: (bounds) {

            return const LinearGradient(
              colors: [

                Color(0xFF7DF9FF),
                Color(0xFF4DEEFF),
                Color(0xFF00D9FF),

              ],
            ).createShader(bounds);
          },

          child: const Text(
            "Add Reminder",

            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
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
      ),

      body: SingleChildScrollView(

        padding: const EdgeInsets.all(16),

        child: Column(
          children: [

            // TOP DESIGN

            Container(
              width: double.infinity,

              padding:
              const EdgeInsets.symmetric(
                vertical: 35,
                horizontal: 20,
              ),

              decoration: BoxDecoration(

                borderRadius:
                BorderRadius.circular(30),

                gradient:
                const LinearGradient(

                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,

                  colors: [

                    Color(0xFF7DF9FF),
                    Color(0xFF4DEEFF),
                    Color(0xFF00D9FF),

                  ],
                ),

                boxShadow: [

                  BoxShadow(
                    color:
                    const Color(0xFF00D9FF)
                        .withOpacity(0.5),

                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),

              child: Column(
                children: const [

                  Icon(
                    Icons.notifications_active,
                    size: 70,
                    color: Colors.black,
                  ),

                  SizedBox(height: 15),

                  Text(
                    "Smart Payment Reminder",

                    textAlign: TextAlign.center,

                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  SizedBox(height: 8),

                  Text(
                    "Never miss your payment",

                    textAlign: TextAlign.center,

                    style: TextStyle(
                      color: Colors.black87,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 30),

            // BANK DROPDOWN

            DropdownButtonFormField<String>(

              dropdownColor: Colors.black,

              style: const TextStyle(
                color: Colors.white,
              ),

              decoration: InputDecoration(

                labelText: "Select Bank",

                labelStyle: const TextStyle(
                  color: Color(0xFF7DF9FF),
                ),

                filled: true,
                fillColor: Colors.black,

                enabledBorder:
                OutlineInputBorder(

                  borderRadius:
                  BorderRadius.circular(18),

                  borderSide: const BorderSide(
                    color: Color(0xFF00D9FF),
                    width: 2,
                  ),
                ),

                focusedBorder:
                OutlineInputBorder(

                  borderRadius:
                  BorderRadius.circular(18),

                  borderSide: const BorderSide(
                    color: Color(0xFF7DF9FF),
                    width: 2.5,
                  ),
                ),
              ),

              items:
              cards.map<DropdownMenuItem<String>>(
                      (card) {

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

                final selected =
                cards.firstWhere(
                        (c) => c["_id"] == value);

                setState(() {

                  selectedBankName =
                  selected["bankName"];

                  selectedCardId = value;

                  statementDate =
                  selected["statementDate"] !=
                      null
                      ? DateTime.parse(
                    selected[
                    "statementDate"],
                  )
                      : null;

                  paymentDate =
                  selected["paymentDueDate"] !=
                      null
                      ? DateTime.parse(
                    selected[
                    "paymentDueDate"],
                  )
                      : null;
                });
              },
            ),

            const SizedBox(height: 20),

            // AMOUNT FIELD

            TextField(

              controller: amountController,

              style: const TextStyle(
                color: Colors.white,
              ),

              decoration: InputDecoration(

                labelText: "Amount",

                labelStyle: const TextStyle(
                  color: Color(0xFF7DF9FF),
                ),

                prefixIcon: const Icon(
                  Icons.currency_rupee,
                  color: Color(0xFF7DF9FF),
                ),

                filled: true,
                fillColor: Colors.black,

                enabledBorder:
                OutlineInputBorder(

                  borderRadius:
                  BorderRadius.circular(18),

                  borderSide: const BorderSide(
                    color: Color(0xFF00D9FF),
                    width: 2,
                  ),
                ),

                focusedBorder:
                OutlineInputBorder(

                  borderRadius:
                  BorderRadius.circular(18),

                  borderSide: const BorderSide(
                    color: Color(0xFF7DF9FF),
                    width: 2.5,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // STATEMENT DATE

            InkWell(

              onTap: () => pickDate(true),

              child: Container(

                width: double.infinity,

                padding: const EdgeInsets.all(18),

                decoration: BoxDecoration(

                  color: Colors.black,

                  borderRadius:
                  BorderRadius.circular(18),

                  border: Border.all(
                    color:
                    const Color(0xFF00D9FF),
                    width: 2,
                  ),
                ),

                child: Row(
                  children: [

                    const Icon(
                      Icons.calendar_month,
                      color: Color(0xFF7DF9FF),
                    ),

                    const SizedBox(width: 12),

                    Text(
                      "Statement: "
                          "${formatDate(statementDate)}",

                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 15),

            // PAYMENT DATE

            InkWell(

              onTap: () => pickDate(false),

              child: Container(

                width: double.infinity,

                padding: const EdgeInsets.all(18),

                decoration: BoxDecoration(

                  color: Colors.black,

                  borderRadius:
                  BorderRadius.circular(18),

                  border: Border.all(
                    color:
                    const Color(0xFF00D9FF),
                    width: 2,
                  ),
                ),

                child: Row(
                  children: [

                    const Icon(
                      Icons.access_time_filled,
                      color: Color(0xFF7DF9FF),
                    ),

                    const SizedBox(width: 12),

                    Text(
                      "Payment: "
                          "${formatDate(paymentDate)}",

                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 25),

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

            const SizedBox(height: 25),

            // SAVE BUTTON

            SizedBox(

              width: double.infinity,
              height: 60,

              child: ElevatedButton(

                style:
                ElevatedButton.styleFrom(

                  backgroundColor:
                  Colors.black,

                  elevation: 10,

                  shadowColor:
                  const Color(0xFF00D9FF),

                  shape:
                  RoundedRectangleBorder(

                    borderRadius:
                    BorderRadius.circular(20),

                    side: const BorderSide(
                      color: Color(0xFF00D9FF),
                      width: 2,
                    ),
                  ),
                ),

                onPressed:
                onSaveReminderButtonClick,

                child: const Text(

                  "Save Reminder",

                  style: TextStyle(
                    color: Color(0xFF7DF9FF),
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),
          ],
        ),
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