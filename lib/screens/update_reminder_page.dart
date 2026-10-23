// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:card/config/app_config.dart';

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

class _UpdateReminderPageState extends State<UpdateReminderPage> {
  static const Color _bg = Color(0xFF195754);
  static const Color _forestDark = Color(0xFF195754);
  static const Color _darkText = Color(0xFF1E293B);

  List cards = [];

  String? selectedBankName;
  String? selectedCardId;

  DateTime? statementDate;
  DateTime? paymentDate;

  final TextEditingController amountController = TextEditingController();

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

    selectedCardId = r["cardId"] is Map ? r["cardId"]["_id"] : r["cardId"];

    amountController.text = r["amount"].toString();

    statementDate = DateTime.parse(r["statementDate"]).toLocal();

    final p = DateTime.parse(r["paymentDate"]);

    paymentDate = DateTime(p.year, p.month, p.day);

    reminders = {};

    for (var item in r["reminders"]) {
      reminders[item["key"]] = {
        "count": item["count"],
        "times": (item["times"] as List).map((t) {
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
      Uri.parse("${AppConfig.cards}?userId=${widget.userId}"),
    );

    final data = jsonDecode(res.body);

    if (!mounted) return;

    setState(() {
      cards = data["data"] ?? [];
    });
  }

  Future<void> updateReminder() async {
    final res = await http.put(
      Uri.parse("${AppConfig.reminders}/update/${widget.reminderData['_id']}"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "bankName": selectedBankName,
        "userId": widget.userId,
        "cardId": selectedCardId,
        "amount": int.parse(amountController.text),
        "statementDate": "${statementDate!.year}-"
            "${statementDate!.month.toString().padLeft(2, '0')}-"
            "${statementDate!.day.toString().padLeft(2, '0')}",
        "paymentDate": "${paymentDate!.year}-"
            "${paymentDate!.month.toString().padLeft(2, '0')}-"
            "${paymentDate!.day.toString().padLeft(2, '0')}",
        "reminders": reminders.entries.map((entry) {
          return {
            "key": entry.key,
            "count": entry.value["count"],
            "times": (entry.value["times"] as List).map((t) {
              return "${t.hour.toString().padLeft(2, '0')}:"
                  "${t.minute.toString().padLeft(2, '0')}";
            }).toList(),
          };
        }).toList(),
      }),
    );

    final data = jsonDecode(res.body);

    if (!mounted) return;

    if (res.statusCode == 200) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(data["message"] ?? "Updated")),
      );
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: ${data["message"]}")),
      );
    }
  }

  Future<void> pickDate(bool isStatement) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: statementDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(
              primary: _forestDark,
              onPrimary: Colors.white,
              surface: Colors.white,
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
    if (date == null) return "Select Date";
    return "${date.day}-${date.month}-${date.year}";
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

  Widget radioBtn(String key, int value, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Radio<int>(
          value: value,
          groupValue: reminders[key]?["count"] ?? 1,
          activeColor: _forestDark,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          onChanged: (val) {
            if (val == null) return;
            setState(() {
              reminders[key]!["count"] = val;
              reminders[key]!["times"] = <TimeOfDay>[];
            });
          },
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            style: const TextStyle(
              color: _darkText,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget buildReminderTile(String key, String title) {
    bool selected = reminders.containsKey(key);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected ? _forestDark : Colors.black.withValues(alpha: 0.08),
          width: selected ? 1.5 : 1,
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
                activeColor: _forestDark,
                checkColor: Colors.white,
                side: BorderSide(
                  color: selected ? _forestDark : Colors.black38,
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
                style: const TextStyle(
                  color: _darkText,
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
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Expanded(child: radioBtn(key, 1, "Once")),
                    Expanded(child: radioBtn(key, 2, "Twice")),
                    Expanded(child: radioBtn(key, 3, "Thrice")),
                  ],
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _forestDark.withValues(alpha: 0.1),
                    foregroundColor: _forestDark,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: _forestDark.withValues(alpha: 0.3),
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
                  children: (reminders[key]?["times"] as List? ?? []).map((t) {
                    if (t is TimeOfDay) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          "${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}",
                          style: const TextStyle(
                            color: _forestDark,
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
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F8F7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.black.withValues(alpha: 0.12),
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
              color: _forestDark.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.calendar_month,
              color: _forestDark,
              size: 20,
            ),
          ),
          title: Text(
            title,
            style: const TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              value,
              style: const TextStyle(
                color: _darkText,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          trailing: const Icon(
            Icons.chevron_right_rounded,
            color: _forestDark,
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
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.15),
            ),
            child: const Icon(
              Icons.arrow_back_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: const Text(
          "Update Reminder",
          style: TextStyle(
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
              // White Card Form Container
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.black.withValues(alpha: 0.08),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      "Update Details",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: _darkText,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // BANK DROPDOWN
                    DropdownButtonFormField<String>(
                      value: selectedCardId,
                      dropdownColor: Colors.white,
                      style: const TextStyle(
                        color: _darkText,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: InputDecoration(
                        labelText: "Select Bank",
                        labelStyle: const TextStyle(
                          color: Color(0xFF6B7280),
                          fontSize: 14,
                        ),
                        prefixIcon: const Icon(
                          Icons.account_balance_rounded,
                          color: _forestDark,
                          size: 20,
                        ),
                        filled: true,
                        fillColor: const Color(0xFFF6F8F7),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                            color: Colors.black.withValues(alpha: 0.12),
                            width: 1.2,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(
                            color: _forestDark,
                            width: 1.5,
                          ),
                        ),
                      ),
                      items: cards.map<DropdownMenuItem<String>>((card) {
                        return DropdownMenuItem(
                          value: card["_id"],
                          child: Text(
                            card["bankName"],
                            style: const TextStyle(color: _darkText),
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        final selected = cards.firstWhere((c) => c["_id"] == value);
                        setState(() {
                          selectedBankName = selected["bankName"];
                          selectedCardId = value;
                        });
                      },
                    ),

                    const SizedBox(height: 18),

                    // AMOUNT FIELD
                    TextField(
                      controller: amountController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(
                        color: _darkText,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: InputDecoration(
                        labelText: "Amount",
                        labelStyle: const TextStyle(
                          color: Color(0xFF6B7280),
                          fontSize: 14,
                        ),
                        prefixIcon: const Icon(
                          Icons.currency_rupee,
                          color: _forestDark,
                          size: 20,
                        ),
                        filled: true,
                        fillColor: const Color(0xFFF6F8F7),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                            color: Colors.black.withValues(alpha: 0.12),
                            width: 1.2,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(
                            color: _forestDark,
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

              // UPDATE BUTTON
              SizedBox(
                height: 54,
                child: ElevatedButton(
                  onPressed: updateReminder,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _forestDark,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    "Update Reminder",
                    style: TextStyle(
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
