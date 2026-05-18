import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/providers/app_state.dart';
import '../../home/widgets/top_bar.dart';
import '../../home/screens/main_screen.dart';

class EducationalScreen extends StatefulWidget {
  const EducationalScreen({super.key});

  @override
  State<EducationalScreen> createState() => _EducationalScreenState();
}

class _EducationalScreenState extends State<EducationalScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Each lesson now has an icon + gradient for consistent thumbnails
  final List<_LessonData> _allLessons = [
    _LessonData(
      titleAr: 'أساسيات الإنعاش',
      titleEn: 'CPR Basics',
      subAr: 'الإسعافات الأولية',
      subEn: 'First Aid',
      icon: LucideIcons.heartPulse,
      gradientColors: [const Color(0xFFCFC3B0), const Color(0xFFD5CBBD)],
      durationMin: 12,
    ),
    _LessonData(
      titleAr: 'العناية بالجروح',
      titleEn: 'Wound Care',
      subAr: 'الإسعافات الأولية',
      subEn: 'First Aid',
      icon: LucideIcons.scissors,
      gradientColors: [const Color(0xFFCFC3B0), const Color(0xFFD5CBBD)],
      durationMin: 8,
    ),
    _LessonData(
      titleAr: 'الكسور والجبائر',
      titleEn: 'Fractures & Splints',
      subAr: 'الإسعافات الأولية',
      subEn: 'First Aid',
      icon: LucideIcons.shield,
      gradientColors: [const Color(0xFFCFC3B0), const Color(0xFFD5CBBD)],
      durationMin: 15,
    ),
    _LessonData(
      titleAr: 'إسعاف الحروق',
      titleEn: 'Burn Treatment',
      subAr: 'الإسعافات الأولية',
      subEn: 'First Aid',
      icon: LucideIcons.flame,
      gradientColors: [const Color(0xFFCFC3B0), const Color(0xFFD5CBBD)],
      durationMin: 10,
    ),
    _LessonData(
      titleAr: 'التسمم الغذائي',
      titleEn: 'Food Poisoning',
      subAr: 'حالات الطوارئ',
      subEn: 'Emergencies',
      icon: LucideIcons.alertTriangle,
      gradientColors: [const Color(0xFFCFC3B0), const Color(0xFFD5CBBD)],
      durationMin: 7,
    ),
    _LessonData(
      titleAr: 'الإختناق',
      titleEn: 'Choking Response',
      subAr: 'حالات الطوارئ',
      subEn: 'Emergencies',
      icon: LucideIcons.wind,
      gradientColors: [const Color(0xFFCFC3B0), const Color(0xFFD5CBBD)],
      durationMin: 6,
    ),
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = AppStateProvider.of(context).isArabic;

    return Container(
      color: AppColors.background,
      child: SafeArea(
        bottom: false,
        child: Directionality(
          textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
          child: Column(
            children: [
              const TopBar(),
              Expanded(
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ── Title ──────────────────────────────────
                            Text(
                              isArabic ? 'التعلم' : 'Learn',
                              style: GoogleFonts.poppins(
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textDark,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isArabic
                                  ? 'أدلة طبية وإسعافات أولية'
                                  : 'Medical guides & first aid training',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: AppColors.textDark.withOpacity(0.5),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // ── Search Bar ──────────────────────────────
                            Container(
                              height: 48,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.04),
                                    blurRadius: 10,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: TextField(
                                controller: _searchController,
                                onChanged: (val) {
                                  setState(() => _searchQuery = val.toLowerCase());
                                },
                                decoration: InputDecoration(
                                  hintText: isArabic
                                      ? 'البحث عن الدروس...'
                                      : 'Search lessons...',
                                  hintStyle: GoogleFonts.inter(
                                    color: AppColors.textDark.withOpacity(0.35),
                                    fontSize: 14,
                                  ),
                                  prefixIcon: Icon(
                                    LucideIcons.search,
                                    size: 18,
                                    color: AppColors.textDark.withOpacity(0.4),
                                  ),
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 14),
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),

                            // ── Hero Card ───────────────────────────────
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(22),
                              decoration: BoxDecoration(
                                color: AppColors.primaryRed,
                                borderRadius: BorderRadius.circular(22),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primaryRed.withOpacity(0.25),
                                    blurRadius: 16,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          isArabic
                                              ? 'أسئلة عاجلة؟'
                                              : 'Urgent questions?',
                                          style: GoogleFonts.poppins(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          isArabic
                                              ? 'استشر الذكاء الاصطناعي الطبي'
                                              : 'Ask our Medical AI for\ninstant answers',
                                          style: GoogleFonts.inter(
                                            fontSize: 13,
                                            color: Colors.white.withOpacity(0.85),
                                            height: 1.4,
                                          ),
                                        ),
                                        const SizedBox(height: 14),
                                        GestureDetector(
                                          onTap: () {
                                            mainScreenKey.currentState
                                                ?.switchTab(2);
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 18, vertical: 10),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius:
                                                  BorderRadius.circular(30),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(LucideIcons.bot,
                                                    size: 16,
                                                    color: AppColors.primaryRed),
                                                const SizedBox(width: 6),
                                                Text(
                                                  isArabic
                                                      ? 'اسأل الذكاء الاصطناعي'
                                                      : 'Ask AI',
                                                  style: GoogleFonts.inter(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w700,
                                                    color: AppColors.primaryRed,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Container(
                                    width: 60,
                                    height: 60,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.15),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      LucideIcons.stethoscope,
                                      color: Colors.white,
                                      size: 30,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),

                            // ── Section Header ──────────────────────────
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  isArabic ? 'الدروس' : 'Lessons',
                                  style: GoogleFonts.poppins(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textDark,
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(isArabic
                                            ? 'عرض كل الدروس غير متوفر حالياً'
                                            : 'Show All not available yet'),
                                        behavior: SnackBarBehavior.floating,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                      ),
                                    );
                                  },
                                  child: Text(
                                    isArabic ? 'عرض الكل' : 'Show All',
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.primaryRed,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                          ],
                        ),
                      ),
                    ),

                    // ── Lessons Grid ─────────────────────────────
                    _buildLessonsGrid(isArabic),

                    const SliverToBoxAdapter(
                      child: SizedBox(height: 120),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLessonsGrid(bool isArabic) {
    final filtered = _allLessons.where((l) {
      final tEn = l.titleEn.toLowerCase();
      final tAr = l.titleAr.toLowerCase();
      final sEn = l.subEn.toLowerCase();
      return tEn.contains(_searchQuery) ||
          tAr.contains(_searchQuery) ||
          sEn.contains(_searchQuery);
    }).toList();

    if (filtered.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Column(
              children: [
                Icon(LucideIcons.searchX,
                    size: 40,
                    color: AppColors.textDark.withOpacity(0.2)),
                const SizedBox(height: 12),
                Text(
                  isArabic ? 'لم يتم العثور على نتائج' : 'No results found',
                  style: GoogleFonts.inter(
                    color: AppColors.textDark.withOpacity(0.4),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverGrid(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final item = filtered[index];
            return _LessonCard(
              title: isArabic ? item.titleAr : item.titleEn,
              subtitle: isArabic ? item.subAr : item.subEn,
              icon: item.icon,
              gradientColors: item.gradientColors,
              durationMin: item.durationMin,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => _LessonDetailScreen(
                      title: isArabic ? item.titleAr : item.titleEn,
                      icon: item.icon,
                      gradientColors: item.gradientColors,
                    ),
                  ),
                );
              },
            );
          },
          childCount: filtered.length,
        ),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
          childAspectRatio: 0.78,
        ),
      ),
    );
  }
}

// ── Data model ──────────────────────────────────────────────────────────────────

class _LessonData {
  final String titleAr;
  final String titleEn;
  final String subAr;
  final String subEn;
  final IconData icon;
  final List<Color> gradientColors;
  final int durationMin;

  const _LessonData({
    required this.titleAr,
    required this.titleEn,
    required this.subAr,
    required this.subEn,
    required this.icon,
    required this.gradientColors,
    required this.durationMin,
  });
}

// ── Lesson Card ─────────────────────────────────────────────────────────────────

class _LessonCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> gradientColors;
  final int durationMin;
  final VoidCallback onTap;

  const _LessonCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradientColors,
    required this.durationMin,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Gradient thumbnail with icon ──────────────────
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: gradientColors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Stack(
                  children: [
                    // Background pattern circle
                    Positioned(
                      right: -15,
                      top: -15,
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: AppColors.primaryRed.withOpacity(0.08),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Positioned(
                      left: -10,
                      bottom: -10,
                      child: Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: AppColors.primaryRed.withOpacity(0.06),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    // Center icon
                    Center(
                      child: Icon(
                        icon,
                        size: 40,
                        color: AppColors.primaryRed.withOpacity(0.6),
                      ),
                    ),
                    // Duration badge
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.primaryRed.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(LucideIcons.clock,
                                size: 10, color: AppColors.primaryRed),
                            const SizedBox(width: 3),
                            Text(
                              '${durationMin}m',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primaryRed,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Text content ────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: gradientColors.first.withOpacity(0.6),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: AppColors.textDark.withOpacity(0.5),
                          ),
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
    );
  }
}

// ── Lesson Detail Screen ────────────────────────────────────────────────────────

class _LessonDetailScreen extends StatefulWidget {
  final String title;
  final IconData icon;
  final List<Color> gradientColors;

  const _LessonDetailScreen({
    required this.title,
    required this.icon,
    required this.gradientColors,
  });

  @override
  State<_LessonDetailScreen> createState() => _LessonDetailScreenState();
}

class _LessonDetailScreenState extends State<_LessonDetailScreen> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;
  Timer? _cprMetronome;

  @override
  void dispose() {
    _pageController.dispose();
    _cprMetronome?.cancel();
    super.dispose();
  }

  void _checkMetronome(List<_StepData> steps) {
    if (steps.isEmpty) return;
    
    // 100-120 BPM means a beat every 500-600ms. We'll do 500ms (120 BPM)
    if (steps[_currentIndex].animationType == _AnimationType.cprCompressions) {
      if (_cprMetronome == null || !_cprMetronome!.isActive) {
        _cprMetronome = Timer.periodic(const Duration(milliseconds: 500), (_) {
          SystemSound.play(SystemSoundType.click);
        });
      }
    } else {
      _cprMetronome?.cancel();
    }
  }

  List<_StepData> _getSteps(bool isArabic) {
    if (widget.title == 'CPR Basics' || widget.title == 'أساسيات الإنعاش') {
      return [
        _StepData(
          title: isArabic ? 'تحقق من الأمان والاستجابة' : 'Check safety and responsiveness',
          body: isArabic
              ? 'تأكد من أن المكان آمن. اربت على كتف الشخص واصرخ: "هل أنت بخير؟".'
              : 'Ensure the scene is safe. Tap the person\'s shoulder and shout, "Are you okay?".',
          animationType: _AnimationType.checkResponse,
          frame1Path: 'assets/learn/cpr/step1/frame1.png',
          frame2Path: 'assets/learn/cpr/step1/frame2.png',
        ),
        _StepData(
          title: isArabic ? 'اطلب المساعدة وتفقد التنفس' : 'Call for help & check breathing',
          body: isArabic
              ? 'اتصل بالإسعاف. راقب صدر المريض لمدة 5-10 ثوانٍ للتحقق من التنفس.'
              : 'Call emergency services. Watch the chest for 5-10 seconds to check for breathing.',
          animationType: _AnimationType.callHelp,
          frame1Path: 'assets/learn/cpr/step2/frame1.png',
          frame2Path: 'assets/learn/cpr/step2/frame2.png',
        ),
        _StepData(
          title: isArabic ? 'ابدأ الضغطات الصدرية' : 'Start chest compressions',
          body: isArabic
              ? 'ضع كعب يدك في منتصف صدر المريض. اشبك أصابعك واضغط بقوة وسرعة (100-120 ضغطة/دقيقة).'
              : 'Place the heel of your hand in the center of the chest. Push hard and fast (100-120 compressions/min).',
          animationType: _AnimationType.cprCompressions,
          frame1Path: 'assets/learn/cpr/step3/frame1.png',
          frame2Path: 'assets/learn/cpr/step3/frame2.png',
        ),
        _StepData(
          title: isArabic ? 'الأنفاس الإنقاذية' : 'Rescue breaths',
          body: isArabic
              ? 'أعطِ نفسين إنقاذيين بعد كل 30 ضغطة. أمل الرأس للخلف، ارفع الذقن، وأغلق الأنف.'
              : 'Give 2 rescue breaths after every 30 compressions. Tilt head back, lift chin, and pinch the nose.',
          animationType: _AnimationType.rescueBreaths,
          frame1Path: 'assets/learn/cpr/step4/frame1.png',
          frame2Path: 'assets/learn/cpr/step4/frame2.png',
        ),
      ];
    } else if (widget.title == 'Burn Treatment' || widget.title == 'إسعاف الحروق') {
      return [
        _StepData(
          title: isArabic ? 'برّد الحرق' : 'Cool the burn',
          body: isArabic
              ? 'ضع منطقة الحرق تحت ماء جارٍ بارد لمدة 10-20 دقيقة. لا تضع الثلج مباشرة.'
              : 'Place the burned area under cool running water for 10-20 minutes. Do not apply ice.',
          animationType: _AnimationType.coolBurn,
        ),
        _StepData(
          title: isArabic ? 'غطِّ الحرق' : 'Cover the burn',
          body: isArabic
              ? 'غطِّ منطقة الحرق بضمادة معقمة غير لاصقة. لا تفقع البثور ولا تضع المراهم.'
              : 'Cover the burn area with a sterile, non-stick bandage. Do not pop blisters.',
          animationType: _AnimationType.coverBurn,
        ),
      ];
    } else if (widget.title == 'Choking Response' || widget.title == 'الإختناق') {
      return [
        _StepData(
          title: isArabic ? '5 ضربات على الظهر' : '5 Back blows',
          body: isArabic
              ? 'قف خلف المريض. استخدم كعب يدك لتوجيه 5 ضربات قوية بين لوحي الكتف.'
              : 'Stand behind the patient. Use the heel of your hand to deliver 5 firm back blows.',
          animationType: _AnimationType.backBlows,
        ),
        _StepData(
          title: isArabic ? '5 ضغطات بطنية' : '5 Abdominal thrusts',
          body: isArabic
              ? 'لف ذراعيك حول خصر المريض. اصنع قبضة وضعها فوق السرة واضغط للداخل وللأعلى.'
              : 'Wrap arms around their waist. Make a fist just above the navel and thrust inward and upward.',
          animationType: _AnimationType.heimlich,
        ),
      ];
    }
    return [];
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = AppStateProvider.of(context).isArabic;
    final steps = _getSteps(isArabic);

    return Directionality(
      textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Column(
          children: [
            // Top App Bar Area
            Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 16,
                left: 20,
                right: 20,
                bottom: 16,
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.cardBackgroundLight),
                      ),
                      child: const Icon(LucideIcons.arrowLeft, size: 20, color: AppColors.textDark),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            if (steps.isEmpty)
              Expanded(
                child: Center(
                  child: Text(
                    isArabic ? 'محتوى الدرس قيد التطوير' : 'Lesson content in development',
                    style: GoogleFonts.inter(fontSize: 16, color: AppColors.textDark.withOpacity(0.5)),
                  ),
                ),
              )
            else ...[
              // Animated Graphic Area (Top Half)
              Expanded(
                flex: 4,
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: widget.gradientColors,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(32),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(32),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      child: steps[_currentIndex].frame1Path != null
                          ? _ImageSequenceAnimation(
                              key: ValueKey(_currentIndex),
                              frame1: steps[_currentIndex].frame1Path!,
                              frame2: steps[_currentIndex].frame2Path!,
                            )
                          : _AnimatedHumanGraphic(
                              key: ValueKey(_currentIndex),
                              type: steps[_currentIndex].animationType,
                            ),
                    ),
                  ),
                ),
              ),

              // Steps PageView Area (Bottom Half)
              Expanded(
                flex: 4,
                child: Column(
                  children: [
                    const SizedBox(height: 32),
                    // Progress Indicator
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(steps.length, (index) {
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: _currentIndex == index ? 24 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: _currentIndex == index
                                ? AppColors.primaryRed
                                : AppColors.primaryRed.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 24),
                    
                    // The PageView
                    Expanded(
                      child: PageView.builder(
                        controller: _pageController,
                        physics: const BouncingScrollPhysics(),
                        onPageChanged: (idx) {
                          setState(() => _currentIndex = idx);
                          _checkMetronome(steps);
                        },
                        itemCount: steps.length,
                        itemBuilder: (context, index) {
                          final step = steps[index];
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  step.title,
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.poppins(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textDark,
                                    height: 1.2,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  step.body,
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.inter(
                                    fontSize: 16,
                                    color: AppColors.textDark.withOpacity(0.7),
                                    height: 1.6,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),

                    // Navigation Buttons
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Row(
                        children: [
                          if (_currentIndex > 0)
                            GestureDetector(
                              onTap: () {
                                _pageController.previousPage(
                                  duration: const Duration(milliseconds: 400),
                                  curve: Curves.easeInOut,
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: AppColors.background,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: AppColors.cardBackgroundLight),
                                ),
                                child: const Icon(LucideIcons.chevronLeft, color: AppColors.textDark),
                              ),
                            )
                          else
                            const SizedBox(width: 58), // spacer
                          const Spacer(),
                          GestureDetector(
                            onTap: () {
                              if (_currentIndex < steps.length - 1) {
                                _pageController.nextPage(
                                  duration: const Duration(milliseconds: 400),
                                  curve: Curves.easeInOut,
                                );
                              } else {
                                Navigator.pop(context);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                              decoration: BoxDecoration(
                                color: AppColors.primaryRed,
                                borderRadius: BorderRadius.circular(30),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primaryRed.withOpacity(0.3),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Text(
                                _currentIndex == steps.length - 1
                                    ? (isArabic ? 'إنهاء' : 'Finish')
                                    : (isArabic ? 'التالي' : 'Next Step'),
                                style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Data Models ──────────────────────────────────────────────────────────────

enum _AnimationType {
  checkResponse,
  callHelp,
  cprCompressions,
  rescueBreaths,
  coolBurn,
  coverBurn,
  backBlows,
  heimlich,
}

class _StepData {
  final String title;
  final String body;
  final _AnimationType animationType;
  final String? frame1Path;
  final String? frame2Path;

  _StepData({
    required this.title,
    required this.body,
    required this.animationType,
    this.frame1Path,
    this.frame2Path,
  });
}

// ── Animated Human Graphics ──────────────────────────────────────────────────

class _AnimatedHumanGraphic extends StatelessWidget {
  final _AnimationType type;
  const _AnimatedHumanGraphic({super.key, required this.type});

  @override
  Widget build(BuildContext context) {
    switch (type) {
      case _AnimationType.cprCompressions:
        return Stack(
          alignment: Alignment.center,
          children: [
            // Patient lying down
            Positioned(
              bottom: 40,
              child: Container(
                width: 140,
                height: 30,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
            ),
            // Rescuer pushing down
            Positioned(
              bottom: 65,
              child: Column(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Container(
                    width: 40,
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const SizedBox(height: 5),
                  // Arms pushing
                  Container(
                    width: 10,
                    height: 30,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                ],
              )
                  .animate(onPlay: (c) => c.repeat())
                  .slideY(begin: 0, end: 0.15, duration: 300.ms, curve: Curves.easeInOut)
                  .then()
                  .slideY(begin: 0.15, end: 0, duration: 300.ms, curve: Curves.easeInOut),
            ),
          ],
        );

      case _AnimationType.coolBurn:
        return Stack(
          alignment: Alignment.center,
          children: [
            // Arm
            Positioned(
              bottom: 60,
              child: Container(
                width: 120,
                height: 30,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
            ),
            // Burn mark
            Positioned(
              bottom: 65,
              child: Container(
                width: 30,
                height: 20,
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(10),
                ),
              ).animate(onPlay: (c) => c.repeat(reverse: true)).fadeOut(duration: 1.seconds),
            ),
            // Water droplets
            ...List.generate(3, (i) {
              return Positioned(
                top: 40,
                child: Icon(
                  LucideIcons.droplet,
                  size: 32,
                  color: Colors.blue.shade200,
                )
                    .animate(onPlay: (c) => c.repeat(), delay: (i * 300).ms)
                    .slideY(begin: 0, end: 3, duration: 800.ms, curve: Curves.easeIn)
                    .fadeIn(duration: 200.ms)
                    .then(delay: 400.ms)
                    .fadeOut(duration: 200.ms),
              );
            }),
          ],
        );

      case _AnimationType.heimlich:
        return Stack(
          alignment: Alignment.center,
          children: [
            // Patient
            Positioned(
              bottom: 40,
              child: Column(
                children: [
                  Container(
                    width: 35,
                    height: 35,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.6),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Container(
                    width: 45,
                    height: 70,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ],
              ),
            ),
            // Rescuer behind
            Positioned(
              bottom: 40,
              left: 40, // offset slightly
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Container(
                    width: 50,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ],
              )
                  .animate(onPlay: (c) => c.repeat())
                  .slide(begin: const Offset(0, 0), end: const Offset(0.1, -0.1), duration: 400.ms, curve: Curves.easeOut)
                  .then()
                  .slide(begin: const Offset(0.1, -0.1), end: const Offset(0, 0), duration: 400.ms, curve: Curves.easeIn),
            ),
          ],
        );

      default:
        // Generic subtle pulse for other steps (Check response, Call help)
        return Center(
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.3),
              shape: BoxShape.circle,
            ),
            child: const Icon(LucideIcons.activity, color: Colors.white, size: 40),
          ).animate(onPlay: (c) => c.repeat(reverse: true)).scaleXY(begin: 1.0, end: 1.2, duration: 1.seconds),
        );
    }
  }
}

class _ImageSequenceAnimation extends StatefulWidget {
  final String frame1;
  final String frame2;

  const _ImageSequenceAnimation({super.key, required this.frame1, required this.frame2});

  @override
  State<_ImageSequenceAnimation> createState() => _ImageSequenceAnimationState();
}

class _ImageSequenceAnimationState extends State<_ImageSequenceAnimation> {
  late Timer _timer;
  bool _showFrame1 = true;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (mounted) setState(() => _showFrame1 = !_showFrame1);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 0),
      child: Image.asset(
        _showFrame1 ? widget.frame1 : widget.frame2,
        key: ValueKey(_showFrame1),
        fit: BoxFit.fitWidth,
        alignment: Alignment.bottomCenter,
        width: double.infinity,
        height: double.infinity,
      ),
    );
  }
}