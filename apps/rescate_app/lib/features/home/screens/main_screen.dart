import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../map/screens/map_screen.dart';
import '../../ai_chat/screens/ai_chat_screen.dart';
import '../../educational/screens/educational_screen.dart';
import '../../community/screens/community_screen.dart';

final GlobalKey<MainScreenState> mainScreenKey = GlobalKey<MainScreenState>();

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => MainScreenState();
}

class MainScreenState extends State<MainScreen> {
  int _currentIndex = 2; // AI Chat is default

  void switchTab(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  final List<Widget> _screens = [
    const EducationalScreen(),
    const MapScreen(),
    const AiChatScreen(),
    const CommunityScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: true,
      body: _screens[_currentIndex],
      bottomNavigationBar: SizedBox(
        height: 100,
        child: Stack(
          alignment: Alignment.bottomCenter,
          clipBehavior: Clip.none,
          children: [
            // The shortened background
            Container(
              height: 70,
              decoration: const BoxDecoration(
                color: AppColors.background,
              ),
            ),
            // The floating icons
            Positioned(
              top: 4, // Adjusting so they sit exactly halfway (52/2 = 26. 100 - 70 = 30. 30 - 26 = 4)
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _NavItem(
                    icon: LucideIcons.bookOpen,
                    index: 0,
                    currentIndex: _currentIndex,
                    onTap: (i) => setState(() => _currentIndex = i),
                  ),
                  _NavItem(
                    icon: LucideIcons.map,
                    index: 1,
                    currentIndex: _currentIndex,
                    onTap: (i) => setState(() => _currentIndex = i),
                  ),
                  _NavItem(
                    icon: LucideIcons.bot,
                    index: 2,
                    currentIndex: _currentIndex,
                    onTap: (i) => setState(() => _currentIndex = i),
                  ),
                  _NavItem(
                    icon: LucideIcons.messageSquare,
                    index: 3,
                    currentIndex: _currentIndex,
                    onTap: (i) => setState(() => _currentIndex = i),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final int index;
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _NavItem({
    required this.icon,
    required this.index,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool isActive = index == currentIndex;

    return GestureDetector(
      onTap: () => onTap(index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        width: isActive ? 100 : 52,
        height: 52,
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFFA11F2B) : const Color(0xFFD9D0C7),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: const Color(0xFFE5DDD3), width: 6),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            if (isActive)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Container(
                  width: 40, // 52 - 6*2 = 40 inner space
                  decoration: const BoxDecoration(
                    color: Color(0xFFEFAEB2),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: SizedBox(
                width: 40,
                child: Center(
                  child: Icon(
                    icon,
                    size: 22,
                    color: isActive ? const Color(0xFFA11F2B) : const Color(0xFF202020),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}