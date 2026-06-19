import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'add_reminder_page.dart';
import 'card_create_screen.dart';
import 'home_screen.dart';
import 'view_card_screen.dart';
import 'view_reminder_page.dart';
import 'LendLiabilityPage.dart';

class CardHome extends StatelessWidget {
  final String userId;
  final String userName;

  const CardHome({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  Widget build(BuildContext context) {
    return GridViewPage(
      userId: userId,
      userName: userName,
    );
  }
}

class GridViewPage extends StatefulWidget {
  final String userId;
  final String userName;

  const GridViewPage({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<GridViewPage> createState() => _GridViewPageState();
}

class _GridViewPageState extends State<GridViewPage> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> items = [
      {
        "name": "Add Card",
        "subtitle": "Add new card",
        "icon": Icons.add_card_rounded,
        "color": Colors.blue,
        "page": (BuildContext context) =>
            CardCreateScreen(userId: widget.userId,userName: widget.userName,),
      },
      {
        "name": "View Card",
        "subtitle": "View your cards",
        "icon": Icons.credit_card,
        "color": Colors.green,
        "page": (BuildContext context) =>
            ViewCardScreen(userId: widget.userId,userName: widget.userName,),
      },
      {
        "name": "Add Reminder",
        "subtitle": "Add new reminder",
        "icon": Icons.add_alert_rounded,
        "color": Colors.orange,
        "page": (BuildContext context) =>
            AddReminderPage(userId: widget.userId,userName: widget.userName,),
      },
      {
        "name": "View Reminder",
        "subtitle": "View all reminders",
        "icon": Icons.notifications_active,
        "color": Colors.purple,
        "page": (BuildContext context) =>
            ViewReminderPage(userId: widget.userId,userName: widget.userName,),
      },
      {
        "name": "Lend & Liability",
        "subtitle": "Track payments",
        "icon": Icons.account_balance_wallet,
        "color": Colors.cyan,
        "page": (BuildContext context) =>  LendLiabilityPage
          (userId: widget.userId,userName: widget.userName,),
      },
    ];

    return Scaffold(
      backgroundColor: Colors.black,

      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.black,

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
          "Card Reminder",
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
              Icons.notifications_rounded,
              color: Color(0xFF00D9FF),
              size: 30,
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ViewReminderPage(
                    userId: widget.userId,
                    userName: widget.userName,
                  ),
                ),
              );
            },
          ),

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
        child: Padding(
          padding: const EdgeInsets.all(16),

          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,

            children: [
              const Text(
                "Welcome 👋",
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 18,
                ),
              ),

              const SizedBox(height: 5),

              Text(
                widget.userName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 30),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(22),

                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFF7DF9FF),
                      Color(0xFF4DEEFF),
                      Color(0xFF00D9FF),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),

                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Icon(
                         Icons.credit_card,
                          color: Color(0xFF111111),
                          size: 45,
                        ),
                        Icon(
                          Icons.verified_user,
                          color: Color(0xFF111111),
                          size: 40,
                        ),
                      ],
                    ),

                    const SizedBox(height: 30),

                    const Text(
                      "Manage your cards\nand reminders easily",
                      style: TextStyle(
                        color: Color(0xFF111111),
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        height: 1.3,
                      ),
                    ),

                    const SizedBox(height: 15),

                    const Text(
                      "Secure • Fast • Smart",
                      style: TextStyle(
                        color: Color(0xFF111111),
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 35),

              const Text(
                "Quick Actions",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 20),

              GridView.builder(
                shrinkWrap: true,

                physics:
                const NeverScrollableScrollPhysics(),

                itemCount: items.length,

                gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 18,
                  mainAxisSpacing: 18,
                  childAspectRatio: 1,
                ),

                itemBuilder: (context, index) {
                  final item = items[index];

                  return InkWell(
                    borderRadius:
                    BorderRadius.circular(25),

                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              (item["page"]
                              as Widget Function(
                                  BuildContext))(
                                  context),
                        ),
                      );
                    },

                    child: Container(
                      padding: const EdgeInsets.all(18),

                      decoration: BoxDecoration(
                        borderRadius:
                        BorderRadius.circular(25),

                        color: const Color(0xff111111),

                        boxShadow: [
                          BoxShadow(
                            color: Colors.white
                                .withValues(alpha: 0.03),

                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),

                      child: Column(
                        mainAxisAlignment:
                        MainAxisAlignment.center,

                        children: [
                          Container(
                            padding:
                            const EdgeInsets.all(18),

                            decoration: BoxDecoration(
                              shape: BoxShape.circle,

                              color: (item["color"]
                              as Color)
                                  .withValues(alpha: 0.15),
                            ),

                            child: Icon(
                              item["icon"],
                              color: item["color"],
                              size: 38,
                            ),
                          ),

                          const SizedBox(height: 18),

                          Text(
                            item["name"],

                            textAlign: TextAlign.center,

                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight:
                              FontWeight.bold,
                            ),
                          ),

                          const SizedBox(height: 8),

                          Text(
                            item["subtitle"],

                            textAlign: TextAlign.center,

                            style: TextStyle(
                              color: Colors.white
                                  .withValues(alpha: 0.7),

                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 30),

              Container(
                width: double.infinity,

                padding: const EdgeInsets.all(20),

                decoration: BoxDecoration(
                  color: const Color(0xff121212),

                  borderRadius:
                  BorderRadius.circular(25),
                ),

                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(15),

                      decoration: BoxDecoration(
                        shape: BoxShape.circle,

                        color: Colors.blue
                            .withValues(alpha: 0.15),
                      ),

                      child: const Icon(
                        Icons.security,
                        color: Colors.lightBlue,
                        size: 45,
                      ),
                    ),

                    const SizedBox(width: 20),

                    const Expanded(
                      child: Column(
                        crossAxisAlignment:
                        CrossAxisAlignment.start,

                        children: [
                          Text(
                            "Your data is secured",

                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight:
                              FontWeight.bold,
                            ),
                          ),

                          SizedBox(height: 6),

                          Text(
                            "100% encrypted and protected",

                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),
            ],
          ),
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