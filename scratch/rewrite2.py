import sys
import os

file_path = r"f:\Rescate\apps\rescate_app\lib\features\onboarding\screens\onboarding_screen.dart"

with open(file_path, "r", encoding="utf-8") as f:
    lines = f.readlines()

new_content = """import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../home/screens/main_screen.dart';

// ─── Color Palette (extracted from mockups) ──────────────────────────────────
class _OnboardingColors {
  static const background = Color(0xFFEAE3DC); // warm beige/cream
  static const textBrown = Color(0xFF3B2226);   // dark brown (pages 1 & 3)
  static const textGreen = Color(0xFF2D4A35);   // dark forest green (page 2)
  static const panelMauve = Color(0xFFB08085);  // dusky rose / mauve (page 1)
  static const panelGreen = Color(0xFF7EAF82);  // sage green (page 2)
  static const borderBrown = Color(0xFF5A3840); // dark border for panels
  static const borderGreen = Color(0xFF3D6647); // dark border for green panel
}

// ─── Per-page data ────────────────────────────────────────────────────────────
class _PageData {
  final String title;
  final String description;
  final Color textColor;
  final _PanelConfig panel;
  final _LogoPosition logoPosition;

  const _PageData({
    required this.title,
    required this.description,
    required this.textColor,
    required this.panel,
    required this.logoPosition,
  });
}

enum _LogoPosition { bottomLeft, bottomRight, topCenter }

class _PanelConfig {
  final Alignment alignment;    // where the panel bleeds in from
  final Color color;
  final Color? colorEnd;        // for gradient (page 3)
  final Color borderColor;

  const _PanelConfig({
    required this.alignment,
    required this.color,
    this.colorEnd,
    required this.borderColor,
  });
}

// ─── Main Screen ─────────────────────────────────────────────────────────────
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  double _pageProgress = 0.0;

  static const List<_PageData> _pages = [
    // ── Page 1: Language Selection ──────────────────────────────────────────
    _PageData(
      title: 'Language Selection',
      description:
          'Choose your preferred language to get a personalized experience tailored just for you.',
      textColor: _OnboardingColors.textBrown,
      panel: _PanelConfig(
        alignment: Alignment.centerRight,
        color: _OnboardingColors.panelMauve,
        borderColor: _OnboardingColors.borderBrown,
      ),
      logoPosition: _LogoPosition.bottomLeft,
    ),
    // ── Page 2: Offline First ───────────────────────────────────────────────
    _PageData(
      title: 'Offline First',
      description:
          'Access medical guides and emergency AI even without an internet connection.',
      textColor: _OnboardingColors.textGreen,
      panel: _PanelConfig(
        alignment: Alignment.centerLeft,
        color: _OnboardingColors.panelGreen,
        borderColor: _OnboardingColors.borderGreen,
      ),
      logoPosition: _LogoPosition.bottomRight,
    ),
    // ── Page 3: Peer-to-Peer Mesh ────────────────────────────────────────────
    _PageData(
      title: 'Rescate',
      description:
          'Connect directly with nearby responders when cellular networks fail.',
      textColor: _OnboardingColors.textBrown,
      panel: _PanelConfig(
        alignment: Alignment.bottomCenter,
        color: _OnboardingColors.panelMauve,
        colorEnd: _OnboardingColors.panelGreen,
        borderColor: _OnboardingColors.borderBrown,
      ),
      logoPosition: _LogoPosition.topCenter,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pageController.addListener(() {
      if (_pageController.hasClients && _pageController.position.haveDimensions) {
        setState(() {
          _pageProgress = _pageController.page ?? 0.0;
        });
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    
    // Clamp the progress just in case of overscroll bouncing
    final p = _pageProgress.clamp(0.0, 2.0);
    
    final panelH = size.height * 0.5;
    const radius = 28.0;
    const borderW = 2.5;

    Alignment panelAlignment;
    double panelW;
    Color panelColor1, panelColor2;
    Color leftBorderColor, rightBorderColor, topBorderColor;
    double topLeftRadius, topRightRadius;
    Alignment logoAlignment;

    final page0Border = _OnboardingColors.borderBrown;
    final page1Border = _OnboardingColors.borderGreen;
    final page2Border = _OnboardingColors.borderBrown;

    if (p <= 1.0) {
      panelAlignment = Alignment.lerp(Alignment.bottomRight, Alignment.bottomLeft, p)!;
      panelW = size.width * 0.5;
      
      panelColor1 = Color.lerp(_OnboardingColors.panelMauve, _OnboardingColors.panelGreen, p)!;
      panelColor2 = panelColor1;
      
      topBorderColor = Color.lerp(page0Border, page1Border, p)!;
      leftBorderColor = Color.lerp(topBorderColor, Colors.transparent, p)!;
      rightBorderColor = Color.lerp(Colors.transparent, topBorderColor, p)!;
      
      topLeftRadius = lerpDouble(radius, 0.0, p)!;
      topRightRadius = lerpDouble(0.0, radius, p)!;
      
      logoAlignment = Alignment.lerp(Alignment.bottomLeft, Alignment.bottomRight, p)!;
    } else {
      final t = p - 1.0;
      panelAlignment = Alignment.lerp(Alignment.bottomLeft, Alignment.bottomCenter, t)!;
      panelW = lerpDouble(size.width * 0.5, size.width, t)!;
      
      panelColor1 = Color.lerp(_OnboardingColors.panelGreen, _OnboardingColors.panelMauve, t)!;
      panelColor2 = Color.lerp(_OnboardingColors.panelGreen, _OnboardingColors.panelGreen, t)!; 
      
      topBorderColor = Color.lerp(page1Border, page2Border, t)!;
      leftBorderColor = Color.lerp(Colors.transparent, topBorderColor, t)!;
      rightBorderColor = topBorderColor;
      
      topLeftRadius = lerpDouble(0.0, radius, t)!;
      topRightRadius = radius;
      
      logoAlignment = Alignment.lerp(Alignment.bottomRight, Alignment.topCenter, t)!;
    }

    return Scaffold(
      backgroundColor: _OnboardingColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            // ── Background Panel (Parallax) ──
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: panelH,
              child: Align(
                alignment: panelAlignment,
                child: Container(
                  width: panelW,
                  height: panelH,
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: topBorderColor, width: borderW),
                      left: BorderSide(color: leftBorderColor, width: borderW),
                      right: BorderSide(color: rightBorderColor, width: borderW),
                    ),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(topLeftRadius),
                      topRight: Radius.circular(topRightRadius),
                    ),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [panelColor1, panelColor2],
                    ),
                  ),
                ),
              ),
            ),

            // ── Logo (Parallax) ──
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.only(left: 32, right: 32, bottom: 36, top: 60),
                child: Align(
                  alignment: logoAlignment,
                  child: SizedBox(
                    width: 48, // Made smaller based on user request (was 64)
                    height: 48,
                    child: Image.asset('assets/logo.png'),
                  ),
                ),
              ),
            ),

            // ── Page swiper (Text only now) ───────────────────────────────
            PageView.builder(
              controller: _pageController,
              itemCount: _pages.length,
              itemBuilder: (_, i) => _OnboardingPage(data: _pages[i], pageIndex: i),
            ),

            // ── Top progress dashes (Static) ──────────────────────────────
            Positioned(
              top: 16,
              left: 32,
              right: 32,
              child: Row(
                children: List.generate(3, (i) {
                  final currentIndex = p.round().clamp(0, 2);
                  return Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      height: 3,
                      margin: EdgeInsets.only(right: i < 2 ? 8 : 0),
                      decoration: BoxDecoration(
                        color: _pages[currentIndex].textColor
                            .withOpacity(i == currentIndex ? 0.8 : 0.2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Individual onboarding page ───────────────────────────────────────────────
class _OnboardingPage extends StatelessWidget {
  final _PageData data;
  final int pageIndex;
  const _OnboardingPage({required this.data, required this.pageIndex});

  @override
  Widget build(BuildContext context) {
    final isPage3 = pageIndex == 2;

    return Stack(
      children: [
        // ── Text content ─────────────────────────────────────────────────
        Positioned(
          top: isPage3 ? 160 : 70,
          left: 28,
          right: 28,
          child: Column(
            crossAxisAlignment: isPage3
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              Text(
                data.title,
                textAlign:
                    isPage3 ? TextAlign.center : TextAlign.start,
                style: GoogleFonts.poppins(
                  fontSize: 48,
                  fontWeight: FontWeight.w900,
                  color: data.textColor,
                  height: 1.05,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                data.description,
                textAlign:
                    isPage3 ? TextAlign.center : TextAlign.start,
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  color: data.textColor.withOpacity(0.75),
                  height: 1.55,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
"""

with open(file_path, "w", encoding="utf-8") as f:
    f.write(new_content)

print("Done")
