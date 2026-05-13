import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../home/screens/main_screen.dart';
import '../../../core/providers/app_state.dart';

// ─── Localization Data ────────────────────────────────────────────────────────
const Map<String, List<Map<String, String>>> _localizedContent = {
  'English': [
    {
      'title': 'Language Selection',
      'desc': 'Choose your preferred language to get a personalized experience tailored just for you.'
    },
    {
      'title': 'Offline First',
      'desc': 'Access medical guides and emergency AI even without an internet connection.'
    },
    {
      'title': 'Rescate',
      'desc': 'Connect directly with nearby responders when cellular networks fail.'
    }
  ],
  'Español': [
    {
      'title': 'Selección de Idioma',
      'desc': 'Elige tu idioma preferido para obtener una experiencia personalizada adaptada a ti.'
    },
    {
      'title': 'Primero Sin Conexión',
      'desc': 'Accede a guías médicas y a la IA de emergencia incluso sin conexión a internet.'
    },
    {
      'title': 'Rescate',
      'desc': 'Conéctate directamente con los socorristas cercanos cuando fallan las redes celulares.'
    }
  ],
  'Français': [
    {
      'title': 'Sélection de la Langue',
      'desc': 'Choisissez votre langue préférée pour obtenir une expérience personnalisée adaptée à vos besoins.'
    },
    {
      'title': 'Priorité Hors Ligne',
      'desc': 'Accédez aux guides médicaux et à l\'IA d\'urgence même sans connexion Internet.'
    },
    {
      'title': 'Rescate',
      'desc': 'Connectez-vous directement avec les intervenants à proximité lorsque les réseaux cellulaires échouent.'
    }
  ],
  'Deutsch': [
    {
      'title': 'Sprachauswahl',
      'desc': 'Wählen Sie Ihre bevorzugte Sprache, um ein auf Sie zugeschnittenes Erlebnis zu erhalten.'
    },
    {
      'title': 'Offline Zuerst',
      'desc': 'Greifen Sie auch ohne Internetverbindung auf medizinische Leitfäden und Notfall-KI zu.'
    },
    {
      'title': 'Rescate',
      'desc': 'Verbinden Sie sich direkt mit Helfern in der Nähe, wenn Mobilfunknetze ausfallen.'
    }
  ],
  'Português': [
    {
      'title': 'Seleção de Idioma',
      'desc': 'Escolha o seu idioma preferido para obter uma experiência personalizada adaptada para você.'
    },
    {
      'title': 'Primeiro Offline',
      'desc': 'Acesse guias médicos e IA de emergência mesmo sem conexão com a internet.'
    },
    {
      'title': 'Rescate',
      'desc': 'Conecte-se diretamente com socorristas próximos quando as redes de celular falharem.'
    }
  ],
  'العربية': [
    {
      'title': 'اختيار اللغة',
      'desc': 'اختر لغتك المفضلة للحصول على تجربة مخصصة لك بالكامل.'
    },
    {
      'title': 'العمل بدون إنترنت',
      'desc': 'الوصول إلى الأدلة الطبية والذكاء الاصطناعي للطوارئ حتى بدون اتصال بالإنترنت.'
    },
    {
      'title': 'Rescate',
      'desc': 'تواصل مباشرة مع المستجيبين القريبين عندما تفشل شبكات الاتصال الخلوي.'
    }
  ],
  'हिन्दी': [
    {
      'title': 'भाषा चयन',
      'desc': 'अपने लिए तैयार किया गया व्यक्तिगत अनुभव प्राप्त करने के लिए अपनी पसंदीदा भाषा चुनें।'
    },
    {
      'title': 'ऑफ़लाइन प्रथम',
      'desc': 'इंटरनेट कनेक्शन के बिना भी चिकित्सा गाइड और आपातकालीन एआई तक पहुंचें।'
    },
    {
      'title': 'Rescate',
      'desc': 'सेलुलर नेटवर्क विफल होने पर सीधे आस-पास के उत्तरदाताओं से जुड़ें।'
    }
  ],
  '中文': [
    {
      'title': '语言选择',
      'desc': '选择您偏好的语言，以获得为您量身定制的个性化体验。'
    },
    {
      'title': '离线优先',
      'desc': '即使没有互联网连接，也能访问医疗指南和紧急AI。'
    },
    {
      'title': 'Rescate',
      'desc': '当蜂窝网络失效时，直接与附近的救援人员联系。'
    }
  ],
};

const Map<String, String> _localizedSelectLanguage = {
  'English': 'Select Language',
  'Español': 'Seleccionar Idioma',
  'Français': 'Choisir la Langue',
  'Deutsch': 'Sprache Wählen',
  'Português': 'Selecionar Idioma',
  'العربية': 'اختر اللغة',
  'हिन्दी': 'भाषा चुनें',
  '中文': '选择语言'
};

// ─── Color Palette ────────────────────────────────────────────────────────────
class _OnboardingColors {
  static const background  = Color(0xFFEAE3DC);
  static const textBrown   = Color(0xFF3B2226);
  static const textGreen   = Color(0xFF2D4A35);
  static const panelMauve  = Color(0xFFB08085);
  static const panelGreen  = Color(0xFF7EAF82);
  static const borderBrown = Color(0xFF5A3840);
  static const borderGreen = Color(0xFF3D6647);
}

// ─── Per-page static data ─────────────────────────────────────────────────────
class _PageData {
  final Color textColor;
  final _LogoPosition logoPosition;
  const _PageData({required this.textColor, required this.logoPosition});
}

enum _LogoPosition { bottomLeft, bottomRight, topCenter }

// ─── Screen ───────────────────────────────────────────────────────────────────
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  double _pageProgress   = 0.0;
  String _selectedLanguage = 'English';

  static const List<_PageData> _pages = [
    _PageData(textColor: _OnboardingColors.textBrown, logoPosition: _LogoPosition.bottomLeft),
    _PageData(textColor: _OnboardingColors.textGreen, logoPosition: _LogoPosition.bottomRight),
    _PageData(textColor: _OnboardingColors.textBrown, logoPosition: _LogoPosition.topCenter),
  ];

  @override
  void initState() {
    super.initState();
    _pageController.addListener(() {
      if (_pageController.hasClients &&
          _pageController.position.haveDimensions) {
        setState(() => _pageProgress = _pageController.page ?? 0.0);
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // ── Language modal ──────────────────────────────────────────────────────────
  void _showLanguageModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final isArabic = _selectedLanguage == 'العربية';
          return Directionality(
            textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
            child: Container(
              padding: const EdgeInsets.all(24),
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.7),
              decoration: const BoxDecoration(
                color: _OnboardingColors.background,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(32),
                  topRight: Radius.circular(32),
                ),
              ),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: _OnboardingColors.textBrown.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      _localizedSelectLanguage[_selectedLanguage]!,
                      style: GoogleFonts.poppins(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: _OnboardingColors.textBrown,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: _localizedContent.keys
                              .map((lang) =>
                                  _buildLangOption(lang, setModalState))
                              .toList(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLangOption(String name, StateSetter setModalState) {
    final isSelected = _selectedLanguage == name;
    return GestureDetector(
      onTap: () {
        setModalState(() => _selectedLanguage = name);
        setState(() => _selectedLanguage = name);
        AppStateProvider.of(context).setLanguage(name);
        Future.delayed(
            const Duration(milliseconds: 300),
            () { if (mounted) Navigator.pop(context); });
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: isSelected
              ? _OnboardingColors.textBrown
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? _OnboardingColors.textBrown
                : _OnboardingColors.textBrown.withOpacity(0.2),
          ),
        ),
        child: Row(
          children: [
            Text(
              name,
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight:
                    isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected
                    ? Colors.white
                    : _OnboardingColors.textBrown,
              ),
            ),
            const Spacer(),
            if (isSelected)
              const Icon(LucideIcons.check, color: Colors.white, size: 20),
          ],
        ),
      ),
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final size  = MediaQuery.of(context).size;
    final p     = _pageProgress.clamp(0.0, 2.0);
    final panelH = size.height * 0.5;
    const radius = 28.0;
    const borderW = 8.0;

    // ── Derive panel geometry from scroll progress ──────────────────────────
    final Alignment panelAlignment;
    final double    panelW;
    final Color     panelColor1, panelColor2;
    final Color     topBorderColor, leftBorderColor, rightBorderColor;
    final double    topLeftRadius, topRightRadius;
    final Alignment logoAlignment;

    const b0 = _OnboardingColors.borderBrown;
    const b1 = _OnboardingColors.borderGreen;
    const b2 = _OnboardingColors.borderBrown;

    if (p <= 1.0) {
      panelAlignment  = Alignment.lerp(Alignment.bottomRight, Alignment.bottomLeft, p)!;
      panelW          = size.width * 0.5;
      panelColor1     = Color.lerp(_OnboardingColors.panelMauve, _OnboardingColors.panelGreen, p)!;
      panelColor2     = panelColor1;
      topBorderColor  = Color.lerp(b0, b1, p)!;
      leftBorderColor  = Color.lerp(topBorderColor, Colors.transparent, p)!;
      rightBorderColor = Color.lerp(Colors.transparent, topBorderColor, p)!;
      topLeftRadius   = lerpDouble(radius, 0.0, p)!;
      topRightRadius  = lerpDouble(0.0, radius, p)!;
      logoAlignment   = Alignment.lerp(Alignment.bottomLeft, Alignment.bottomRight, p)!;
    } else {
      final t         = p - 1.0;
      panelAlignment  = Alignment.lerp(Alignment.bottomLeft, Alignment.bottomCenter, t)!;
      panelW          = lerpDouble(size.width * 0.5, size.width, t)!;
      panelColor1     = Color.lerp(_OnboardingColors.panelGreen, _OnboardingColors.panelMauve, t)!;
      panelColor2     = Color.lerp(_OnboardingColors.panelGreen, _OnboardingColors.panelGreen, t)!;
      topBorderColor  = Color.lerp(b1, b2, t)!;
      leftBorderColor  = Color.lerp(Colors.transparent, topBorderColor, t)!;
      rightBorderColor = topBorderColor;
      topLeftRadius   = lerpDouble(0.0, radius, t)!;
      topRightRadius  = radius;
      logoAlignment   = Alignment.lerp(Alignment.bottomRight, Alignment.topCenter, t)!;
    }

    final currentIndex = p.round().clamp(0, 2);

    double nextButtonBottom;
    if (p <= 1.0) {
      nextButtonBottom = lerpDouble(40, 100, p)!;
    } else {
      nextButtonBottom = lerpDouble(100, 40, p - 1.0)!;
    }

    return Scaffold(
      backgroundColor: _OnboardingColors.background,
      body: SafeArea(
        child: Stack(
          children: [

            // ── 1. Panel & Icons ────────────────────────────────────────────
            Positioned(
              left: 0, right: 0, bottom: 0,
              height: panelH,
              child: Align(
                alignment: panelAlignment,
                child: Container(
                  width: panelW,
                  height: panelH,
                  decoration: BoxDecoration(
                    // Using CustomPaint for borders since non-uniform colored borders with borderRadius throw an error
                    borderRadius: BorderRadius.only(
                      topLeft:  Radius.circular(topLeftRadius),
                      topRight: Radius.circular(topRightRadius),
                    ),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end:   Alignment.bottomCenter,
                      colors: [panelColor1, panelColor2],
                    ),
                  ),
                  child: CustomPaint(
                    foregroundPainter: _PanelBorderPainter(
                      topColor: topBorderColor,
                      leftColor: leftBorderColor,
                      rightColor: rightBorderColor,
                      width: borderW,
                      topLeftRadius: topLeftRadius,
                      topRightRadius: topRightRadius,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.only(
                      topLeft:  Radius.circular(topLeftRadius),
                      topRight: Radius.circular(topRightRadius),
                    ),
                    child: Stack(
                      children: [
                        // Page 1 — Globe (Half clipped on the right edge)
                        if (p < 1.0)
                          Positioned(
                            right:  -(panelH * 0.5),
                            top:    -(panelH * 0.001),
                            width:  panelH * 0.95,
                            height: panelH * 0.95,
                            child: Opacity(
                              opacity: ((1.0 - p) * 0.20).clamp(0.0, 0.20),
                              child: Icon(
                                LucideIcons.globe,
                                size:  panelH * 0.95,
                                color: _OnboardingColors.borderBrown,
                              ),
                            ),
                          ),
                        // Page 2 — WifiOff (Half clipped on the left edge)
                        if (p > 0.0 && p < 2.0)
                          Positioned(
                            left:   -(panelH * 0.28),
                            top:    -(panelH * 0.08),
                            width:  panelH * 0.95,
                            height: panelH * 0.95,
                            child: Opacity(
                              opacity: ((1.0 - (p - 1.0).abs()) * 0.20).clamp(0.0, 0.20),
                              child: Icon(
                                LucideIcons.wifiOff,
                                size:  panelH * 0.95,
                                color: _OnboardingColors.borderGreen,
                              ),
                            ),
                          ),
                        // Page 3 — Radio (Centered, fully filling the rect, NOT clipped)
                        if (p > 1.0)
                          Align(
                            alignment: Alignment.center,
                            child: Opacity(
                              opacity: ((p - 1.0) * 0.20).clamp(0.0, 0.20),
                              child: Icon(
                                LucideIcons.radio,
                                size: panelH * 0.6,
                                color: _OnboardingColors.borderBrown,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  ),
                ),
              ),
            ),

            // ── 3. Logo ─────────────────────────────────────────────────────
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.only(
                    left: 32, right: 32, bottom: 36, top: 60),
                child: Align(
                  alignment: logoAlignment,
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Image.asset('assets/logo.png'),
                  ),
                ),
              ),
            ),

            // ── 4. Page content (text + language picker) ────────────────────
            PageView.builder(
              controller: _pageController,
              itemCount: _pages.length,
              itemBuilder: (_, i) => _OnboardingPage(
                data: _pages[i],
                pageIndex: i,
                selectedLanguage: _selectedLanguage,
                onLanguageTap: _showLanguageModal,
                title:       _localizedContent[_selectedLanguage]![i]['title']!,
                description: _localizedContent[_selectedLanguage]![i]['desc']!,
              ),
            ),

            // ── 5. Top progress dashes ───────────────────────────────────────
            Positioned(
              top: 16, left: 32, right: 32,
              child: Row(
                children: List.generate(3, (i) {
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

            // ── 6. Next / Start button ───────────────────────────────────────
            Positioned(
              bottom: nextButtonBottom, right: 32,
              child: GestureDetector(
                onTap: () async {
                  final next = currentIndex + 1;
                  if (next < _pages.length) {
                    _pageController.animateToPage(
                      next,
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeInOut,
                    );
                  } else {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('isFirstLaunch', false);
                    if (!mounted) return;
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => MainScreen(key: mainScreenKey)),
                    );
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 28, vertical: 14),
                  decoration: BoxDecoration(
                    color: _pages[currentIndex].textColor,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 300),
                    style: GoogleFonts.poppins(
                      color: _OnboardingColors.background,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                    child: Text(
                        currentIndex == _pages.length - 1 ? 'Start' : 'Next'),
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


// ─── Individual page (text + language picker only) ────────────────────────────
class _OnboardingPage extends StatelessWidget {
  final _PageData  data;
  final int        pageIndex;
  final String     selectedLanguage;
  final VoidCallback onLanguageTap;
  final String     title;
  final String     description;

  const _OnboardingPage({
    required this.data,
    required this.pageIndex,
    required this.selectedLanguage,
    required this.onLanguageTap,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final isPage3  = pageIndex == 2;
    final isArabic = selectedLanguage == 'العربية';

    return Directionality(
      textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: Stack(
        children: [
          Positioned(
            top:   isPage3 ? 130 : 70,
            left:  28,
            right: 28,
            child: Column(
              crossAxisAlignment:
                  isPage3 ? CrossAxisAlignment.center : CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  textAlign: isPage3 ? TextAlign.center : TextAlign.start,
                  style: GoogleFonts.poppins(
                    fontSize:     isPage3 ? 70 :48,
                    fontWeight:   FontWeight.w900,
                    color:        data.textColor,
                    height:       1.05,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  description,
                  textAlign: isPage3 ? TextAlign.center : TextAlign.start,
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    color:    data.textColor.withOpacity(0.75),
                    height:   1.55,
                  ),
                ),
                if (pageIndex == 0) ...[
                  const SizedBox(height: 40),
                  GestureDetector(
                    onTap: onLanguageTap,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: data.textColor.withOpacity(0.15)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.globe,
                              color: data.textColor, size: 20),
                          const SizedBox(width: 12),
                          Text(
                            selectedLanguage,
                            style: GoogleFonts.poppins(
                              fontSize:   16,
                              fontWeight: FontWeight.w600,
                              color:      data.textColor,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Icon(LucideIcons.chevronDown,
                              color: data.textColor, size: 20),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelBorderPainter extends CustomPainter {
  final Color topColor;
  final Color leftColor;
  final Color rightColor;
  final double width;
  final double topLeftRadius;
  final double topRightRadius;

  _PanelBorderPainter({
    required this.topColor,
    required this.leftColor,
    required this.rightColor,
    required this.width,
    required this.topLeftRadius,
    required this.topRightRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final halfW = width / 2;

    // LEFT BORDER
    if (leftColor.alpha > 0) {
      final pLeft = Paint()..color = leftColor..style = PaintingStyle.stroke..strokeWidth = width;
      final path = Path();
      path.moveTo(halfW, size.height);
      final leftStartY = topLeftRadius > halfW ? topLeftRadius : halfW;
      path.lineTo(halfW, leftStartY);
      if (topLeftRadius > halfW) {
        path.arcToPoint(
          Offset(leftStartY, halfW),
          radius: Radius.circular(topLeftRadius - halfW),
          clockwise: true,
        );
      }
      canvas.drawPath(path, pLeft);
    }

    // RIGHT BORDER
    if (rightColor.alpha > 0) {
      final pRight = Paint()..color = rightColor..style = PaintingStyle.stroke..strokeWidth = width;
      final path = Path();
      path.moveTo(size.width - halfW, size.height);
      final rightStartY = topRightRadius > halfW ? topRightRadius : halfW;
      path.lineTo(size.width - halfW, rightStartY);
      if (topRightRadius > halfW) {
        path.arcToPoint(
          Offset(size.width - rightStartY, halfW),
          radius: Radius.circular(topRightRadius - halfW),
          clockwise: false,
        );
      }
      canvas.drawPath(path, pRight);
    }

    // TOP BORDER
    if (topColor.alpha > 0) {
      final pTop = Paint()..color = topColor..style = PaintingStyle.stroke..strokeWidth = width;
      final path = Path();
      final startX = topLeftRadius > halfW ? topLeftRadius : halfW;
      final endX = topRightRadius > halfW ? size.width - topRightRadius : size.width - halfW;
      path.moveTo(startX, halfW);
      path.lineTo(endX, halfW);
      canvas.drawPath(path, pTop);
    }
  }

  @override
  bool shouldRepaint(covariant _PanelBorderPainter old) => true;
}