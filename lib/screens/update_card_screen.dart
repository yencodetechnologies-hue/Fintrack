import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/card_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'home_screen.dart';
import 'card_home.dart';
import 'view_card_screen.dart';
import 'view_reminder_page.dart';

class UpdateCardScreen extends StatefulWidget {
  final Map card;
  final String userId;
  final String userName;

  const UpdateCardScreen({
    super.key,
    required this.card,
    required this.userId,
    required this.userName,
  });

  @override
  State<UpdateCardScreen> createState() =>
      _UpdateCardScreenState();
}

class _UpdateCardScreenState
    extends State<UpdateCardScreen> {

  final bankController =
  TextEditingController();

  final cardController =
  TextEditingController();

  final last4Controller =
  TextEditingController();

  DateTime? selectedStatementDate;
  DateTime? paymentDueDate;

  bool loading = false;

  int _selectedIndex = 1;

  @override
  void initState() {
    super.initState();

    bankController.text =
        widget.card["bankName"] ?? "";

    cardController.text =
        widget.card["cardName"] ?? "";

    last4Controller.text =
        widget.card["last4digits"] ?? "";

    selectedStatementDate =
    widget.card["statementDate"] != null
        ? DateTime.parse(
      widget.card["statementDate"],
    )
        : null;

    paymentDueDate =
    widget.card["paymentDueDate"] != null
        ? DateTime.parse(
      widget.card["paymentDueDate"],
    )
        : null;
  }

  Future<void> pickDate(
      bool isStatement) async {

    final picked = await showDatePicker(

      context: context,

      initialDate: DateTime.now(),

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

    if (picked != null) {

      setState(() {

        if (isStatement) {

          selectedStatementDate =
              picked;

        } else {

          paymentDueDate = picked;
        }
      });
    }
  }

  Future<void> updateCard() async {

    if (bankController.text.isEmpty ||
        cardController.text.isEmpty ||
        selectedStatementDate == null ||
        paymentDueDate == null) {

      ScaffoldMessenger.of(context)
          .showSnackBar(

        const SnackBar(
          content:
          Text("Please fill all fields"),
        ),
      );

      return;
    }

    String digits =
    last4Controller.text.trim();

    if (digits.length > 4) {

      digits = digits.substring(
        digits.length - 4,
      );
    }

    if (digits.length < 4) {

      ScaffoldMessenger.of(context)
          .showSnackBar(

        const SnackBar(
          content:
          Text("Enter valid 4 digits"),
        ),
      );

      return;
    }

    setState(() => loading = true);

    try {

      final res =
      await CardService.updateCard(

        cardId: widget.card["_id"],

        userId: widget.userId,

        bankName:
        bankController.text.trim(),

        cardName:
        cardController.text.trim(),

        last4digits: digits,

        statementDate:
        selectedStatementDate!
            .toIso8601String(),

        paymentDueDate:
        paymentDueDate!
            .toIso8601String(),
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(

        SnackBar(

          content: Text(
            res["message"] ?? "Updated",
          ),

          backgroundColor:
          res["success"] == true
              ? Colors.green
              : Colors.red,
        ),
      );

      if (res["success"] == true) {

        Navigator.pop(context, true);
      }

    } catch (e) {

      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(

        SnackBar(
          content: Text("Error: $e"),
        ),
      );

    } finally {

      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Widget customTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    int? maxLength,
  }) {

    return TextField(

      controller: controller,

      keyboardType: keyboardType,

      maxLength: maxLength,

      style: const TextStyle(
        color: Colors.white,
      ),

      decoration: InputDecoration(

        counterText: "",

        labelText: label,

        labelStyle: const TextStyle(
          color: Color(0xFF7DF9FF),
        ),

        prefixIcon: Icon(
          icon,
          color: const Color(0xFF7DF9FF),
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
    );
  }

  Widget dateBox({
    required String title,
    required DateTime? date,
    required VoidCallback onTap,
  }) {

    final format =
    DateFormat("dd MMM yyyy");

    return InkWell(

      onTap: onTap,

      child: Container(

        width: double.infinity,

        padding:
        const EdgeInsets.all(18),

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

              date == null
                  ? "Select $title"
                  : "$title : ${format.format(date)}",

              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {

    bankController.dispose();

    cardController.dispose();

    last4Controller.dispose();

    super.dispose();
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
            backgroundColor:
            Colors.transparent,

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

            "Update Card",

            style: TextStyle(
              fontSize: 24,
              fontWeight:
              FontWeight.bold,
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

                builder: (context) =>
                    AlertDialog(

                      backgroundColor:
                      const Color(
                        0xff1A1A1A,
                      ),

                      shape:
                      RoundedRectangleBorder(
                        borderRadius:
                        BorderRadius.circular(
                          20,
                        ),
                      ),

                      title: const Text(
                        "Logout",
                        style: TextStyle(
                          color:
                          Colors.white,
                        ),
                      ),

                      content: const Text(
                        "Are you sure want to logout?",
                        style: TextStyle(
                          color:
                          Colors.white70,
                        ),
                      ),

                      actions: [

                        TextButton(

                          onPressed: () {

                            Navigator.pop(
                              context,
                            );
                          },

                          child: const Text(
                            "Cancel",

                            style: TextStyle(
                              color:
                              Colors.white,
                            ),
                          ),
                        ),

                        ElevatedButton(

                          style:
                          ElevatedButton.styleFrom(
                            backgroundColor:
                            Colors.white,
                          ),

                          onPressed:
                              () async {

                            final prefs =
                            await SharedPreferences
                                .getInstance();

                            await prefs.clear();

                            if (!context
                                .mounted) {
                              return;
                            }

                            Navigator.pushAndRemoveUntil(

                              context,

                              MaterialPageRoute(
                                builder:
                                    (context) =>
                                const HomeScreen(),
                              ),

                                  (route) => false,
                            );
                          },

                          child: const Text(
                            "Logout",

                            style: TextStyle(
                              color:
                              Colors.black,
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

      body: SingleChildScrollView(

        padding:
        const EdgeInsets.all(16),

        child: Column(
          children: [

            customTextField(
              controller:
              bankController,

              label: "Bank Name",

              icon: Icons.account_balance,
            ),

            const SizedBox(height: 20),

            customTextField(
              controller:
              cardController,

              label: "Card Name",

              icon: Icons.credit_card,
            ),

            const SizedBox(height: 20),

            customTextField(
              controller:
              last4Controller,

              label: "Last 4 Digits",

              icon: Icons.lock,

              keyboardType:
              TextInputType.number,

              maxLength: 4,
            ),

            const SizedBox(height: 20),

            dateBox(

              title: "Statement Date",

              date:
              selectedStatementDate,

              onTap: () =>
                  pickDate(true),
            ),

            const SizedBox(height: 20),

            dateBox(

              title: "Payment Due Date",

              date: paymentDueDate,

              onTap: () =>
                  pickDate(false),
            ),

            const SizedBox(height: 30),

            SizedBox(

              width: double.infinity,
              height: 60,

              child: loading

                  ? const Center(
                child:
                CircularProgressIndicator(
                  color:
                  Color(0xFF00D9FF),
                ),
              )

                  : ElevatedButton(

                style:
                ElevatedButton.styleFrom(

                  backgroundColor:
                  Colors.black,

                  elevation: 10,

                  shadowColor:
                  const Color(
                    0xFF00D9FF,
                  ),

                  shape:
                  RoundedRectangleBorder(

                    borderRadius:
                    BorderRadius.circular(
                      20,
                    ),

                    side:
                    const BorderSide(
                      color: Color(
                        0xFF00D9FF,
                      ),
                      width: 2,
                    ),
                  ),
                ),

                onPressed:
                updateCard,

                child: const Text(

                  "Update Card",

                  style: TextStyle(
                    color:
                    Color(0xFF7DF9FF),
                    fontSize: 20,
                    fontWeight:
                    FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),

      bottomNavigationBar:
      BottomNavigationBar(

        backgroundColor:
        Colors.black,

        selectedItemColor:
        Colors.blue,

        unselectedItemColor:
        Colors.white60,

        type:
        BottomNavigationBarType.fixed,

        currentIndex:
        _selectedIndex,

        onTap: (index) {

          setState(() {
            _selectedIndex = index;
          });

          if (index == 0) {

            Navigator.pushReplacement(

              context,

              MaterialPageRoute(

                builder: (_) =>
                    CardHome(

                      userId:
                      widget.userId,

                      userName:
                      widget.userName,
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

                      userId:
                      widget.userId,

                      userName:
                      widget.userName,
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

                      userId:
                      widget.userId,

                      userName:
                      widget.userName,
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
            icon:
            Icon(Icons.notifications),
            label: "Reminder",
          ),
        ],
      ),
    );
  }
}