import sys

file_path = r"f:\Rescate\apps\rescate_app\lib\features\onboarding\screens\onboarding_screen.dart"

new_content = """import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../home/screens/main_screen.dart';

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
      'desc': 'Accédez aux guides médicaux et à l\\'IA d\\'urgence même sans connexion Internet.'
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
  final Color textColor;
  final _PanelConfig panel;
  final _LogoPosition logoPosition;

  const _PageData({
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
  String _selectedLanguage = 'English';

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
                maxHeight: MediaQuery.of(context).size.height * 0.7,
              ),
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
                          children: [
                            _buildLangOption('English', setModalState),
                            _buildLangOption('Español', setModalState),
                            _buildLangOption('Français', setModalState),
                            _buildLangOption('Deutsch', setModalState),
                            _buildLangOption('Português', setModalState),
                            _buildLangOption('العربية', setModalState),
                            _buildLangOption('हिन्दी', setModalState),
                            _buildLangOption('中文', setModalState),
                          ],
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
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) Navigator.pop(context);
        });
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: isSelected ? _OnboardingColors.textBrown : Colors.transparent,
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
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected ? Colors.white : _OnboardingColors.textBrown,
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

  static const List<_PageData> _pages = [
    // ── Page 1: Language Selection ──────────────────────────────────────────
    _PageData(
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

            // ── Giant Background Icons (Parallax) ──
            // Placing these outside the panel container guarantees they render correctly
            // and clip purely against the edge of the screen, just as requested!
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: panelH,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Page 1 Icon (Globe)
                  if (p < 1.0)
                    Positioned(
                      right: -panelH * 0.45,
                      top: 0,
                      bottom: 0,
                      width: panelH,
                      child: Opacity(
                        opacity: (1.0 - p).clamp(0.0, 1.0),
                        child: Icon(
                          LucideIcons.globe,
                          size: panelH * 0.95,
                          // SOLID dark red, as requested.
                          color: _OnboardingColors.textBrown,
                        ),
                      ),
                    ),
                  // Page 2 Icon (WifiOff)
                  if (p > 0.0 && p < 2.0)
                    Positioned(
                      left: -panelH * 0.45,
                      top: 0,
                      bottom: 0,
                      width: panelH,
                      child: Opacity(
                        opacity: (1.0 - (p - 1.0).abs()).clamp(0.0, 1.0),
                        child: Icon(
                          LucideIcons.wifiOff,
                          size: panelH * 0.95,
                          // SOLID border green for Page 2
                          color: _OnboardingColors.borderGreen,
                        ),
                      ),
                    ),
                  // Page 3 Icon (Radio)
                  if (p > 1.0)
                    Positioned(
                      bottom: -panelH * 0.45,
                      left: 0,
                      right: 0,
                      height: panelH,
                      child: Opacity(
                        opacity: (p - 1.0).clamp(0.0, 1.0),
                        child: Icon(
                          LucideIcons.radio,
                          size: panelH * 0.95,
                          color: _OnboardingColors.textBrown,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // ── Logo (Parallax) ──
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.only(left: 32, right: 32, bottom: 36, top: 60),
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

            // ── Page swiper (Text only now) ───────────────────────────────
            PageView.builder(
              controller: _pageController,
              itemCount: _pages.length,
              itemBuilder: (_, i) => _OnboardingPage(
                data: _pages[i], 
                pageIndex: i,
                selectedLanguage: _selectedLanguage,
                onLanguageTap: _showLanguageModal,
                title: _localizedContent[_selectedLanguage]![i]['title']!,
                description: _localizedContent[_selectedLanguage]![i]['desc']!,
              ),
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
  final String selectedLanguage;
  final VoidCallback onLanguageTap;
  final String title;
  final String description;

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
    final isPage3 = pageIndex == 2;
    final isArabic = selectedLanguage == 'العربية';

    return Directionality(
      textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: Stack(
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
                  title,
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
                  description,
                  textAlign:
                      isPage3 ? TextAlign.center : TextAlign.start,
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    color: data.textColor.withOpacity(0.75),
                    height: 1.55,
                  ),
                ),
                if (pageIndex == 0) ...[
                  const SizedBox(height: 40),
                  GestureDetector(
                    onTap: onLanguageTap,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: data.textColor.withOpacity(0.15)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.globe, color: data.textColor, size: 20),
                          const SizedBox(width: 12),
                          Text(
                            selectedLanguage,
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: data.textColor,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Icon(LucideIcons.chevronDown, color: data.textColor, size: 20),
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
"""

with open(file_path, "w", encoding="utf-8") as f:
    f.write(new_content)

print("Done")
