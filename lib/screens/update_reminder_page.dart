import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:card/config/app_config.dart';
import 'home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'card_home.dart';
import 'view_card_screen.dart';
import 'view_reminder_page.dart';

class UpdateReminderPage extends StatefulWidget {
  final String userId;
  final String userName;
  final Map reminderData;

  const UpdateReminderPage({
    super.key,
    required this.userId,
    required this.userName,
    required this.reminderData,
  });

  @override
  State<UpdateReminderPage> createState() =>
      _UpdateReminderPageState();
}

class _UpdateReminderPageState
    extends State<UpdateReminderPage> {

  List cards = [];

  int _selectedIndex = 2;

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
    loadData();
  }

  void loadData() {

    final r = widget.reminderData;

    selectedBankName = r["bankName"];

    selectedCardId =
    r["cardId"] is Map
        ? r["cardId"]["_id"]
        : r["cardId"];

    amountController.text =
        r["amount"].toString();

    statementDate =
        DateTime.parse(
          r["statementDate"],
        ).toLocal();

    final p =
    DateTime.parse(r["paymentDate"]);

    paymentDate =
        DateTime(
          p.year,
          p.month,
          p.day,
        );

    reminders = {};

    for (var item in r["reminders"]) {

      reminders[item["key"]] = {

        "count": item["count"],

        "times":
        (item["times"] as List).map((t) {

          final parts = t.split(":");

          return TimeOfDay(
            hour: int.parse(parts[0]),
            minute: int.parse(parts[1]),
          );

        }).toList(),
      };
    }
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

  Future<void> updateReminder() async {

    final res = await http.put(

      Uri.parse(
        "${AppConfig.reminders}/update/${widget.reminderData['_id']}",
      ),

      headers: {
        "Content-Type": "application/json",
      },

      body: jsonEncode({

        "bankName": selectedBankName,
        "userId": widget.userId,
        "cardId": selectedCardId,

        "amount":
        int.parse(amountController.text),

        "statementDate":
        "${statementDate!.year}-"
            "${statementDate!.month.toString().padLeft(2, '0')}-"
            "${statementDate!.day.toString().padLeft(2, '0')}",

        "paymentDate":
        "${paymentDate!.year}-"
            "${paymentDate!.month.toString().padLeft(2, '0')}-"
            "${paymentDate!.day.toString().padLeft(2, '0')}",

        "reminders":
        reminders.entries.map((entry) {

          return {

            "key": entry.key,

            "count":
            entry.value["count"],

            "times":
            (entry.value["times"] as List)
                .map((t) {

              return
                "${t.hour.toString().padLeft(2, '0')}:"
                    "${t.minute.toString().padLeft(2, '0')}";

            }).toList(),
          };

        }).toList(),
      }),
    );

    final data = jsonDecode(res.body);

    if (!mounted) return;

    if (res.statusCode == 200) {

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            data["message"] ?? "Updated",
          ),
        ),
      );

      Navigator.pop(context);

    } else {

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            "Error: ${data["message"]}",
          ),
        ),
      );
    }
  }

  Future<void> pickDate(bool isStatement) async {

    final picked = await showDatePicker(

      context: context,

      initialDate:
      statementDate ?? DateTime.now(),

      firstDate: DateTime(2020),
      lastDate: DateTime(2100),

      builder: (context, child) {

        return Theme(

          data: ThemeData.dark().copyWith(

            colorScheme:
            const ColorScheme.dark(
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

    int count =
        reminders[key]?["count"] ?? 1;

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

              reminders[key]!["count"] =
                  val;

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

      margin:
      const EdgeInsets.only(bottom: 15),

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

                        "times":
                        <TimeOfDay>[],
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

  Widget customBox(
      IconData icon,
      String text,
      ) {

    return Container(

      width: double.infinity,

      padding: const EdgeInsets.all(18),

      decoration: BoxDecoration(

        color: Colors.black,

        borderRadius:
        BorderRadius.circular(18),

        border: Border.all(
          color: const Color(0xFF00D9FF),
          width: 2,
        ),
      ),

      child: Row(
        children: [

          Icon(
            icon,
            color: const Color(0xFF7DF9FF),
          ),

          const SizedBox(width: 12),

          Text(
            text,

            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
            ),
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

            "Update Reminder",

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
              color: Color(0xFF00D9FF),
              size: 30,
            ),

            onPressed: () {

              showDialog(

                context: context,

                builder: (context) => AlertDialog(

                  backgroundColor:
                  const Color(0xff1A1A1A),

                  shape: RoundedRectangleBorder(
                    borderRadius:
                    BorderRadius.circular(20),
                  ),

                  title: const Text(
                    "Logout",
                    style:
                    TextStyle(color: Colors.white),
                  ),

                  content: const Text(
                    "Are you sure want to logout?",
                    style: TextStyle(
                      color: Colors.white70,
                    ),
                  ),

                  actions: [

                    TextButton(

                      onPressed: () {
                        Navigator.pop(context);
                      },

                      child: const Text(
                        "Cancel",
                        style:
                        TextStyle(color: Colors.white),
                      ),
                    ),

                    ElevatedButton(

                      style:
                      ElevatedButton.styleFrom(
                        backgroundColor:
                        Colors.white,
                      ),

                      onPressed: () async {

                        final prefs =
                        await SharedPreferences
                            .getInstance();

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
                        style:
                        TextStyle(color: Colors.black),
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

            DropdownButtonFormField<String>(

              value: selectedCardId,

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

                });
              },
            ),

            const SizedBox(height: 20),

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

            InkWell(
              onTap: () => pickDate(true),

              child: customBox(
                Icons.calendar_month,
                "Statement: ${formatDate(statementDate)}",
              ),
            ),

            const SizedBox(height: 15),

            InkWell(
              onTap: () => pickDate(false),

              child: customBox(
                Icons.access_time_filled,
                "Payment: ${formatDate(paymentDate)}",
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

                onPressed: updateReminder,

                child: const Text(

                  "Update Reminder",

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

      bottomNavigationBar:
      BottomNavigationBar(

        backgroundColor: Colors.black,

        selectedItemColor: Colors.blue,

        unselectedItemColor:
        Colors.white60,

        type:
        BottomNavigationBarType.fixed,

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

                builder: (_) =>
                    ViewCardScreen(
                      userId: widget.userId,
                      userName: widget.userName,
                    ),
              ),
            );
          }

          if (index == 2) {

            Navigator.push(

              context,

              MaterialPageRoute(

                builder: (_) =>
                    ViewReminderPage(
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