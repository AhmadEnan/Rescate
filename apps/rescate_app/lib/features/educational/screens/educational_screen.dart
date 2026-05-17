import 'package:flutter/material.dart';
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

class _LessonDetailScreen extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Color> gradientColors;

  const _LessonDetailScreen({
    required this.title,
    required this.icon,
    required this.gradientColors,
  });

  @override
  Widget build(BuildContext context) {
    final isArabic = AppStateProvider.of(context).isArabic;
    return Directionality(
      textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 200,
              pinned: true,
              backgroundColor: gradientColors.first,
              leading: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(LucideIcons.arrowLeft,
                      color: Colors.white, size: 20),
                ),
              ),
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: gradientColors,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Center(
                    child: Icon(icon,
                        size: 64, color: Colors.white.withOpacity(0.3)),
                  ),
                ),
                title: Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            SliverFillRemaining(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: gradientColors.first.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(LucideIcons.bookOpen,
                            size: 36,
                            color: gradientColors.first.withOpacity(0.5)),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        isArabic
                            ? 'محتوى الدرس غير متوفر حالياً'
                            : 'Course content not available yet',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isArabic
                            ? 'سيتم تنزيل الدروس لاحقاً للوصول دون اتصال'
                            : 'Lessons will be downloaded later\nfor offline access',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: AppColors.textDark.withOpacity(0.5),
                          height: 1.5,
                        ),
                      ),
                    ],
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