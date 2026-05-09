import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../home/widgets/top_bar.dart';
import '../../home/screens/main_screen.dart';
import '../../../core/providers/app_state.dart';

class EducationalScreen extends StatefulWidget {
  const EducationalScreen({super.key});

  @override
  State<EducationalScreen> createState() => _EducationalScreenState();
}

class _EducationalScreenState extends State<EducationalScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  final List<Map<String, String>> _allLessons = [
    {'title_ar': 'الجدول الدوري', 'title_en': 'Periodic Table', 'sub_ar': 'كيمياء 101', 'sub_en': 'Chemistry 101'},
    {'title_ar': 'أساسيات الإنعاش', 'title_en': 'CPR Basics', 'sub_ar': 'الإسعافات الأولية', 'sub_en': 'First Aid'},
    {'title_ar': 'العناية بالجروح', 'title_en': 'Wound Care', 'sub_ar': 'الإسعافات الأولية', 'sub_en': 'First Aid'},
    {'title_ar': 'الكسور والجبائر', 'title_en': 'Fractures & Splints', 'sub_ar': 'الإسعافات الأولية', 'sub_en': 'First Aid'},
  ];

  @override
  Widget build(BuildContext context) {
    final isArabic = AppStateProvider.of(context).isArabic;

    return Container(
      color: AppColors.background,
      child: SafeArea(
        bottom: false, // Don't safe area the bottom so it flows behind the nav bar
        child: SingleChildScrollView(
          child: Directionality(
            textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const TopBar(),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Search Bar + Circle ───────────────────────────
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.cardBackground,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: TextField(
                        controller: _searchController,
                        onChanged: (val) {
                          setState(() {
                            _searchQuery = val.toLowerCase();
                          });
                        },
                        decoration: InputDecoration(
                          hintText: isArabic ? 'البحث عن الأدلة...' : 'Search guides...',
                          hintStyle: const TextStyle(color: Color(0xFFB0A0A0), fontSize: 14),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.cardBackground,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(LucideIcons.slidersHorizontal,
                        color: AppColors.textDark, size: 18),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // ── Hero Card ────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.cardBackground,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isArabic ? 'أسئلة عاجلة؟' : 'Urgent questions?',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isArabic 
                          ? 'استشر الذكاء الاصطناعي الطبي للحصول على إجابات فورية.' 
                          : 'Consult our Medical AI for instant answers.',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textDark.withOpacity(0.7),
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () {
                        mainScreenKey.currentState?.switchTab(2);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryRed,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                        elevation: 0,
                      ),
                      child: Text(isArabic ? 'اسأل الذكاء الاصطناعي' : 'Ask AI',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ── Lessons Header ───────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isArabic ? 'الدروس' : 'Lessons',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDark,
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(isArabic ? 'عرض كل الدروس غير متوفر حالياً' : 'Show All lessons not available yet')),
                      );
                    },
                    child: Text(
                      isArabic ? 'عرض الكل' : 'Show All',
                      style: TextStyle(
                        color: AppColors.textDark,
                        fontSize: 13,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // ── Lessons Grid ─────────────────────────────────
              Builder(
                builder: (context) {
                  final filtered = _allLessons.where((l) {
                    final tEn = l['title_en']!.toLowerCase();
                    final tAr = l['title_ar']!.toLowerCase();
                    return tEn.contains(_searchQuery) || tAr.contains(_searchQuery);
                  }).toList();

                  if (filtered.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Text(
                          isArabic ? 'لم يتم العثور على نتائج.' : 'No results found.',
                          style: TextStyle(color: AppColors.textDark.withValues(alpha: 0.5)),
                        ),
                      ),
                    );
                  }

                  return GridView.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 0.85,
                    ),
                    itemCount: filtered.length,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemBuilder: (context, index) {
                      final item = filtered[index];
                      return _LessonCard(
                        title: isArabic ? item['title_ar']! : item['title_en']!,
                        subtitle: isArabic ? item['sub_ar']! : item['sub_en']!,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => _LessonDetailScreen(
                                title: isArabic ? item['title_ar']! : item['title_en']!,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  );
                }
              ),

              const SizedBox(height: 100), // Add padding for bottom nav
                  ],
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}

class _LessonCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _LessonCard({required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Thumbnail area
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFCFC3B0),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: AppColors.textDark)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textDark)),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }
}

class _LessonDetailScreen extends StatelessWidget {
  final String title;
  const _LessonDetailScreen({required this.title});

  @override
  Widget build(BuildContext context) {
    final isArabic = AppStateProvider.of(context).isArabic;
    return Directionality(
      textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(LucideIcons.arrowLeft, color: AppColors.textDark),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(title, style: const TextStyle(color: AppColors.textDark)),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.bookOpen, size: 80, color: AppColors.primaryRed.withValues(alpha: 0.5)),
              const SizedBox(height: 20),
              Text(
                isArabic ? 'محتوى الدرس غير متوفر حالياً' : 'Course content not available yet.',
                style: const TextStyle(fontSize: 18, color: AppColors.textDark),
              ),
              const SizedBox(height: 10),
              Text(
                isArabic ? 'سيتم تنزيل الدروس لاحقاً للوصول دون اتصال' : 'Lessons will be downloaded later for offline access.',
                style: TextStyle(fontSize: 14, color: AppColors.textDark.withValues(alpha: 0.6)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}