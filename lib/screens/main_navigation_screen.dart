import 'package:flutter/material.dart';
import 'card_home.dart';
import 'view_card_screen.dart';
import 'view_reminder_page.dart';
import 'profile_screen.dart';
import '../widgets/qfin_nav_bar.dart';

class MainNavigationScreen extends StatefulWidget {
  final String userId;
  final String userName;
  final int initialIndex;

  const MainNavigationScreen({
    super.key,
    required this.userId,
    required this.userName,
    this.initialIndex = 0,
  });

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  late int _currentIndex;
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onTabSelected(int index) {
    if (index == _currentIndex) return;
    setState(() {
      _currentIndex = index;
    });
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOutCubic,
    );
  }

  void _onPageChanged(int index) {
    if (index != _currentIndex) {
      setState(() {
        _currentIndex = index;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F4EB),
      body: PageView(
        controller: _pageController,
        onPageChanged: _onPageChanged,
        physics: const BouncingScrollPhysics(),
        children: [
          CardHome(userId: widget.userId, userName: widget.userName),
          ViewCardScreen(userId: widget.userId, userName: widget.userName),
          ViewReminderPage(userId: widget.userId, userName: widget.userName),
          ProfileScreen(userId: widget.userId, userName: widget.userName),
        ],
      ),
      bottomNavigationBar: QFinNavBar(
        selectedIndex: _currentIndex,
        userId: widget.userId,
        userName: widget.userName,
        onTap: _onTabSelected,
        pageController: _pageController,
      ),
    );
  }
}
