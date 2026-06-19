import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/card_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'home_screen.dart';
import 'card_home.dart';
import 'view_reminder_page.dart';
import 'view_card_screen.dart';


class CardCreateScreen extends StatefulWidget {
  final String userId;
  final String userName;

  const CardCreateScreen({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<CardCreateScreen> createState() =>
      _CardCreateScreenState();
}

class _CardCreateScreenState
    extends State<CardCreateScreen> {
  int _selectedIndex = 0;
  final bankController = TextEditingController();
  final cardController = TextEditingController();
  final last4Controller = TextEditingController();

  DateTime? selectedStatementDate;
  DateTime? paymentDueDate;

  bool loading = false;

  Future<void> pickDate(bool isStatement) async {

    DateTime initialDate = DateTime.now();

    final picked = await showDatePicker(

      context: context,

      initialDate: initialDate,

      firstDate: DateTime(2020),
      lastDate: DateTime(2100),

      builder: (context, child) {

        return Theme(

          data: ThemeData.dark().copyWith(

            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF00D9FF),
              surface: Color(0xFF111111),
            ),
          ),

          child: child!,
        );
      },
    );

    if (picked != null) {

      setState(() {

        if (isStatement) {
          selectedStatementDate = picked;
        } else {
          paymentDueDate = picked;
        }
      });
    }
  }

  Future<void> saveCard() async {

    if (bankController.text.isEmpty ||
        cardController.text.isEmpty ||
        selectedStatementDate == null ||
        paymentDueDate == null) {

      ScaffoldMessenger.of(context).showSnackBar(

        const SnackBar(
          content: Text("Please fill all fields"),
        ),
      );

      return;
    }

    String digits =
    last4Controller.text.trim();

    if (digits.length > 4) {
      digits =
          digits.substring(digits.length - 4);
    }

    if (digits.length < 4) {

      ScaffoldMessenger.of(context).showSnackBar(

        const SnackBar(
          content: Text("Enter valid 4 digits"),
        ),
      );

      return;
    }

    setState(() => loading = true);

    try {

      final res = await CardService.addCard(

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

      ScaffoldMessenger.of(context).showSnackBar(

        SnackBar(

          content: Text(
            res["message"] ?? "Saved",
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

      ScaffoldMessenger.of(context).showSnackBar(

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

  Widget buildField({
    required String label,
    required IconData icon,
    required TextEditingController controller,
    TextInputType? keyboardType,
    int? maxLength,
  }) {

    return Container(

      margin: const EdgeInsets.only(bottom: 18),

      decoration: BoxDecoration(

        color: const Color(0xFF111111),

        borderRadius:
        BorderRadius.circular(18),

        border: Border.all(
          color: const Color(0xFF00D9FF),
        ),
      ),

      child: TextField(

        controller: controller,

        keyboardType: keyboardType,

        maxLength: maxLength,

        style: const TextStyle(
          color: Colors.white,
        ),

        decoration: InputDecoration(

          counterText: "",

          prefixIcon: Icon(
            icon,
            color: const Color(0xFF00D9FF),
          ),

          labelText: label,

          labelStyle: const TextStyle(
            color: Colors.white70,
          ),

          border: InputBorder.none,

          contentPadding:
          const EdgeInsets.symmetric(
            vertical: 22,
          ),
        ),
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

        color: const Color(0xFF111111),

        borderRadius:
        BorderRadius.circular(18),

        border: Border.all(
          color: const Color(0xFF00D9FF),
        ),
      ),

      child: ListTile(

        onTap: onTap,

        leading: Container(

          padding: const EdgeInsets.all(10),

          decoration: BoxDecoration(

            color: const Color(0xFF00D9FF)
                .withValues(alpha: 0.2),

            shape: BoxShape.circle,
          ),

          child: const Icon(
            Icons.calendar_month,
            color: Color(0xFF00D9FF),
          ),
        ),

        title: Text(

          title,

          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),

        subtitle: Text(

          value,

          style: const TextStyle(
            color: Colors.white70,
          ),
        ),

        trailing: const Icon(
          Icons.arrow_forward_ios,
          color: Colors.white54,
          size: 18,
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

    final dateFormat =
    DateFormat("dd MMM yyyy");

    return Scaffold(

      backgroundColor:
      Colors.black,

      appBar: AppBar(

        elevation: 0,

        backgroundColor: Colors.black,

        leading: Padding(

          padding: const EdgeInsets.all(8),

          child: CircleAvatar(

            backgroundColor: Colors.black,

            child: Image.asset(
              "assets/images/logo.png",
            ),
          ),
        ),

        title: const Text(
          "Add Credit Card",
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
              Icons.logout,
              color: const Color(0xFF00D9FF),
            ),

            onPressed: () {

              showDialog(

                context: context,

                builder: (context) =>
                    AlertDialog(

                      backgroundColor:
                      const Color(0xFF111111),

                      title: const Text(
                        "Logout",
                        style: TextStyle(
                          color: Colors.white,
                        ),
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
                          ),
                        ),

                        ElevatedButton(

                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                            const Color(0xFF00D9FF),
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
                                builder: (_) =>
                                const HomeScreen(),
                              ),

                                  (route) => false,
                            );
                          },

                          child: const Text(
                            "Logout",
                            style: TextStyle(
                              color: Colors.black,
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

      body: SingleChildScrollView(

        padding: const EdgeInsets.all(18),

        child: Column(

          children: [

            Container(

              width: double.infinity,
              height: 220,

              decoration: BoxDecoration(

                borderRadius:
                BorderRadius.circular(28),

                gradient: const LinearGradient(

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

                    color: const Color(0xFF00D9FF)
                        .withValues(alpha: 0.4),

                    blurRadius: 25,

                    offset: const Offset(0, 12),
                  ),
                ],
              ),

              child: Stack(

                children: [

                  Positioned(

                    top: -40,
                    right: -30,

                    child: Container(

                      width: 180,
                      height: 180,

                      decoration: BoxDecoration(

                        shape: BoxShape.circle,

                        color: Colors.white
                            .withValues(alpha: 0.05),
                      ),
                    ),
                  ),

                  Padding(

                    padding:
                    const EdgeInsets.all(24),

                    child: Column(

                      crossAxisAlignment:
                      CrossAxisAlignment.start,

                      children: [

                        Row(

                          mainAxisAlignment:
                          MainAxisAlignment
                              .spaceBetween,

                          children: [

                            const Text(

                              "CARD REMINDER",

                              style: TextStyle(

                                color: Colors.black,

                                fontWeight:
                                FontWeight.bold,

                                letterSpacing: 1.5,

                                fontSize: 18,
                              ),
                            ),

                            Container(

                              width: 55,
                              height: 40,

                              decoration: BoxDecoration(

                                borderRadius:
                                BorderRadius.circular(
                                    10),

                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFFFFE082),
                                    Color(0xFFFFC107),
                                    Color(0xFFFFA000),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),

                        const Spacer(),

                        const Text(

                          "****   ****   ****   4589",

                          style: TextStyle(

                            color: Colors.black,

                            fontSize: 28,

                            letterSpacing: 4,

                            fontWeight:
                            FontWeight.bold,
                          ),
                        ),

                        const SizedBox(height: 18),

                        Row(

                          mainAxisAlignment:
                          MainAxisAlignment
                              .spaceBetween,

                          children: [

                            Column(

                              crossAxisAlignment:
                              CrossAxisAlignment
                                  .start,

                              children: const [

                                Text(

                                  "CARD HOLDER",

                                  style: TextStyle(
                                    color:
                                    Colors.black54,
                                    fontSize: 11,
                                  ),
                                ),

                                SizedBox(height: 5),

                                Text(

                                  "YOUR NAME",

                                  style: TextStyle(

                                    color:
                                    Colors.black,

                                    fontWeight:
                                    FontWeight.bold,

                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),

                            const Text(

                              "VISA",

                              style: TextStyle(

                                color: Colors.black,

                                fontSize: 30,

                                fontWeight:
                                FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            buildField(
              label: "Bank Name",
              icon: Icons.account_balance,
              controller: bankController,
            ),

            buildField(
              label: "Card Name",
              icon: Icons.credit_card,
              controller: cardController,
            ),

            buildField(
              label: "Last 4 Digits",
              icon: Icons.password,
              controller: last4Controller,
              keyboardType: TextInputType.number,
              maxLength: 4,
            ),

            buildDateTile(

              title: "Statement Date",

              value:
              selectedStatementDate == null
                  ? "Select statement date"
                  : dateFormat.format(
                selectedStatementDate!,
              ),

              onTap: () => pickDate(true),
            ),

            buildDateTile(

              title: "Payment Due Date",

              value:
              paymentDueDate == null
                  ? "Select payment due date"
                  : dateFormat.format(
                paymentDueDate!,
              ),

              onTap: () => pickDate(false),
            ),

            const SizedBox(height: 20),

            SizedBox(

              width: double.infinity,
              height: 58,

              child: ElevatedButton(

                style:
                ElevatedButton.styleFrom(

                  backgroundColor:
                  const Color(0xFF00D9FF),

                  shape: RoundedRectangleBorder(

                    borderRadius:
                    BorderRadius.circular(18),
                  ),

                  elevation: 10,
                ),

                onPressed:
                loading ? null : saveCard,

                child: loading
                    ? const CircularProgressIndicator(
                  color: Colors.black,
                )
                    : const Text(

                  "Save Card",

                  style: TextStyle(

                    color: Colors.black,

                    fontSize: 18,

                    fontWeight:
                    FontWeight.bold,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 30),
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