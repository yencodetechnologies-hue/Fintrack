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
    const Color outerPillBg   = Color(0xFF073523); // Balanced deep green floating container (#073523)
    const Color activePillBg  = Color(0xFF195754); // Vibrant #195754 green active pill
    const Color activeTextCol = Colors.white;      // Crisp white active label/icon
    const Color unselectedCol = Color(0xFFA7F3D0); // Muted mint green for unselected icons

    final items = [
      _NavItemData(icon: Icons.grid_view_outlined, activeIcon: Icons.grid_view_rounded, label: "Home"),
      _NavItemData(icon: Icons.credit_card_outlined, activeIcon: Icons.credit_card_rounded, label: "Cards"),
      _NavItemData(icon: Icons.notifications_none_rounded, activeIcon: Icons.notifications_active_rounded, label: "Reminders"),
      _NavItemData(icon: Icons.person_outline_rounded, activeIcon: Icons.person_rounded, label: "Profile"),
    ];

    Widget buildBar(double currentOffset) {
      return Container(
        color: Colors.transparent,
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
        child: SafeArea(
          top: false,
          child: Container(
            height: 60,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: outerPillBg,
              borderRadius: BorderRadius.circular(36),
              border: Border.all(color: const Color(0xFF195754).withValues(alpha: 0.5), width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
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
                    // Active #195754 Green Pill Indicator with Glowing Mint Border
                    Positioned(
                      left: activeLeft.clamp(0.0, totalWidth - itemWidth),
                      top: 0,
                      bottom: 0,
                      width: itemWidth,
                      child: Container(
                        decoration: BoxDecoration(
                          color: activePillBg,
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 1.2),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF195754).withValues(alpha: 0.5),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Items Row
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
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isSelected ? item.activeIcon : item.icon,
                                    color: isSelected ? activeTextCol : unselectedCol.withValues(alpha: 0.75),
                                    size: isSelected ? 18 : 20,
                                  ),
                                  if (isSelected) ...[
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          item.label,
                                          style: GoogleFonts.inter(
                                            color: activeTextCol,
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
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
