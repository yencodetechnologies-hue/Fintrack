import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../screens/card_home.dart';
import '../screens/view_card_screen.dart';
import '../screens/view_reminder_page.dart';
import '../screens/profile_screen.dart';

class QFinNavBar extends StatelessWidget {
  final int selectedIndex;
  final String userId;
  final String userName;
  final ValueChanged<int>? onTap;
  final PageController? pageController;

  const QFinNavBar({
    super.key,
    required this.selectedIndex,
    required this.userId,
    required this.userName,
    this.onTap,
    this.pageController,
  });

  void _onTap(BuildContext context, int index) {
    if (index == selectedIndex) return;

    if (onTap != null) {
      onTap!(index);
      return;
    }

    Widget page;
    switch (index) {
      case 0:
        page = CardHome(userId: userId, userName: userName);
        break;
      case 1:
        page = ViewCardScreen(userId: userId, userName: userName);
        break;
      case 2:
        page = ViewReminderPage(userId: userId, userName: userName);
        break;
      case 3:
        page = ProfileScreen(userId: userId, userName: userName);
        break;
      default:
        return;
    }

    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => page,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const Color forestDark = Color(0xFF0F261C);
    const Color creamBg    = Color(0xFFF6F4EB);
    const Color milkyGlass = Color(0xFFEDE8D8);
    const Color unselectedGreen = Color(0xFF234433);

    final items = [
      _NavItemData(icon: Icons.grid_view_outlined, activeIcon: Icons.grid_view_rounded, label: "Home"),
      _NavItemData(icon: Icons.credit_card_outlined, activeIcon: Icons.credit_card_rounded, label: "Cards"),
      _NavItemData(icon: Icons.notifications_none_rounded, activeIcon: Icons.notifications_active_rounded, label: "Reminders"),
      _NavItemData(icon: Icons.person_outline_rounded, activeIcon: Icons.person_rounded, label: "Profile"),
    ];

    Widget buildBar(double currentOffset) {
      final mediaWidth = MediaQuery.of(context).size.width;
      final isSmallScreen = mediaWidth < 360;

      final horizontalPadding = mediaWidth < 360 ? 8.0 : (mediaWidth < 400 ? 10.0 : 12.0);
      final iconSize = isSmallScreen ? 17.0 : 19.0;
      final fontSize = isSmallScreen ? 10.5 : 11.5;

      return Container(
        color: creamBg,
        padding: EdgeInsets.fromLTRB(horizontalPadding, 6, horizontalPadding, 16),
        child: SafeArea(
          top: false,
          child: Container(
            height: 64,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: milkyGlass.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: const Color(0xFFDCD5C3), width: 1.4),
              boxShadow: [
                BoxShadow(
                  color: forestDark.withValues(alpha: 0.12),
                  blurRadius: 20,
                  spreadRadius: 1,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.8),
                  blurRadius: 6,
                  spreadRadius: -1,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final totalWidth = constraints.maxWidth;
                final count = items.length;
                final itemWidth = totalWidth / count;

                final activeLeft = currentOffset * itemWidth;

                return Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    // Smoothly Sliding Milky-Theme Forest Green Active Pill
                    Positioned(
                      left: activeLeft.clamp(0.0, totalWidth - itemWidth),
                      top: 0,
                      bottom: 0,
                      width: itemWidth,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xFF163828),
                              forestDark,
                              Color(0xFF0A1B14),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(color: const Color(0xFF1E4532), width: 1),
                          boxShadow: [
                            BoxShadow(
                              color: forestDark.withValues(alpha: 0.25),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Navigation Items Row
                    Row(
                      children: List.generate(count, (index) {
                        final diff = (currentOffset - index).abs();
                        final isSelected = diff < 0.5;
                        final item = items[index];

                        return Expanded(
                          child: GestureDetector(
                            onTap: () => _onTap(context, index),
                            behavior: HitTestBehavior.opaque,
                            child: Container(
                              alignment: Alignment.center,
                              padding: const EdgeInsets.symmetric(horizontal: 2.0),
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 200),
                                opacity: isSelected ? 1.0 : 0.75,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      isSelected ? item.activeIcon : item.icon,
                                      color: isSelected ? Colors.white : unselectedGreen,
                                      size: iconSize,
                                    ),
                                    if (isSelected) ...[
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(
                                            item.label,
                                            style: GoogleFonts.inter(
                                              color: Colors.white,
                                              fontSize: fontSize,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 0.1,
                                            ),
                                            maxLines: 1,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );
    }

    if (pageController != null) {
      return AnimatedBuilder(
        animation: pageController!,
        builder: (context, _) {
          double offset = selectedIndex.toDouble();
          if (pageController!.hasClients && pageController!.position.hasContentDimensions) {
            offset = pageController!.page ?? selectedIndex.toDouble();
          }
          return buildBar(offset);
        },
      );
    }

    return buildBar(selectedIndex.toDouble());
  }
}

class _NavItemData {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  _NavItemData({required this.icon, required this.activeIcon, required this.label});
}
