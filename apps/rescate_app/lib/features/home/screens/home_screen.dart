// Home screen — the app's landing point. Orients the user ("is everything
// ready?"), dispatches one tap to each feature, and keeps the emergency
// dial one tap away. Opens by default instead of dropping the user
// straight into a feature tab.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:offline_data/offline_data.dart';
import 'package:biometric_estimators/biometric_estimators.dart'
    show BiometricMeasurement;

import '../../../core/providers/app_state.dart';
import '../../../core/theme/app_colors.dart';
import '../../educational/screens/educational_screen.dart';
import '../widgets/readiness_strip.dart';
import '../widgets/top_bar.dart';
import 'main_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _openDialer(BuildContext context, String number) async {
    final uri = Uri(scheme: 'tel', path: number);
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && context.mounted) {
        _showDialerError(context, number);
      }
    } on PlatformException {
      if (context.mounted) _showDialerError(context, number);
    }
  }

  void _showDialerError(BuildContext context, String number) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Could not open the dialer — call $number manually.',
          style: GoogleFonts.inter(color: Colors.white),
        ),
        backgroundColor: AppColors.darkRed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = AppStateProvider.of(context);
    final isArabic = appState.isArabic;
    final sosNumber = appState.emergencyNumber;

    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TopBar(
              onLogoTap: () =>
                  mainScreenKey.currentState?.switchTab(MainScreen.tabHome),
              ),
            const SizedBox(height: 6),
            _Greeting(isArabic: isArabic),
            const SizedBox(height: 14),
            const ReadinessStrip(),
            const SizedBox(height: 16),
            _AskRescateCard(isArabic: isArabic),
            const SizedBox(height: 16),
            _FeatureGrid(isArabic: isArabic),
            const SizedBox(height: 16),
            _SosCard(
              number: sosNumber,
              isArabic: isArabic,
              onCall: () => _openDialer(context, sosNumber),
            ),
            const SizedBox(height: 16),
            const _ContinueLearningCard(),
            const SizedBox(height: 16),
            const _RecentVitalsCard(),
            const SizedBox(height: 16),
            _QuickTipBanner(isArabic: isArabic),
          ],
        ),
      ),
    );
  }
}

// ── Greeting ──────────────────────────────────────────────────────────────────

class _Greeting extends StatelessWidget {
  const _Greeting({required this.isArabic});

  final bool isArabic;

  static String _greetingFor(DateTime now, bool isArabic) {
    final hour = now.hour;
    if (hour < 12) {
      return isArabic ? 'صباح الخير' : 'Good morning';
    }
    if (hour < 17) {
      return isArabic ? 'يوم سعيد' : 'Good afternoon';
    }
    return isArabic ? 'مساء الخير' : 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_greetingFor(DateTime.now(), isArabic)} — '
          '${isArabic ? 'أهلاً بك في ريسكات' : 'welcome to Rescate'}',
          style: GoogleFonts.poppins(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: AppColors.textDark,
            height: 1.18,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          isArabic
              ? 'كل شيء يعمل دون اتصال — جاهز لأي طارئ.'
              : 'Everything works offline — ready whenever you need it.',
          style: GoogleFonts.inter(
            fontSize: 13.5,
            color: AppColors.textDark.withOpacity(0.55),
          ),
        ),
      ],
    );
  }
}

// ── Ask Rescate hero ──────────────────────────────────────────────────────────

class _AskRescateCard extends StatelessWidget {
  const _AskRescateCard({required this.isArabic});

  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => mainScreenKey.currentState?.switchTab(MainScreen.tabAiChat),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.primaryRed,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryRed.withOpacity(0.25),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: const BoxDecoration(
                color: AppColors.aiAccentPink,
                shape: BoxShape.circle,
              ),
              child: const Icon(LucideIcons.bot,
                  size: 24, color: AppColors.primaryRed),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isArabic ? 'اسأل ريسكات' : 'Ask Rescate',
                    style: GoogleFonts.poppins(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isArabic
                        ? 'مساعد طبي فوري يعمل دون إنترنت'
                        : 'Instant offline medical guidance',
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      color: Colors.white.withOpacity(0.85),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(LucideIcons.chevronRight, color: Colors.white, size: 22),
          ],
        ),
      ),
    );
  }
}

// ── Feature grid ──────────────────────────────────────────────────────────────

class _FeatureGrid extends StatelessWidget {
  const _FeatureGrid({required this.isArabic});

  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _FeatureCard(
            icon: LucideIcons.bookOpen,
            tint: AppColors.onboardAccent1,
            title: isArabic ? 'تعلّم' : 'Learn',
            subtitle: isArabic ? 'إسعافات أولية' : 'First aid',
            tabIndex: MainScreen.tabLearn,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _FeatureCard(
            icon: LucideIcons.map,
            tint: AppColors.gpsAccentBlue,
            title: isArabic ? 'الخريطة' : 'Map',
            subtitle: isArabic ? 'خرائط دون اتصال' : 'Offline maps',
            tabIndex: MainScreen.tabMap,
          ),
        ),
      ],
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.icon,
    required this.tint,
    required this.title,
    required this.subtitle,
    required this.tabIndex,
  });

  final IconData icon;
  final Color tint;
  final String title;
  final String subtitle;
  final int tabIndex;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => mainScreenKey.currentState?.switchTab(tabIndex),
      child: Container(
        height: 92,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.cardBackground.withOpacity(0.55),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.cardBackgroundLight),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
              child: Icon(icon, size: 20, color: AppColors.textDark),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: AppColors.textDark.withOpacity(0.55),
                    ),
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

// ── SOS ───────────────────────────────────────────────────────────────────────

class _SosCard extends StatelessWidget {
  const _SosCard({
    required this.number,
    required this.isArabic,
    required this.onCall,
  });

  final String number;
  final bool isArabic;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.darkRed.withOpacity(0.92),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: onCall,
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.16),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withOpacity(0.4)),
              ),
              child: const Icon(LucideIcons.phone,
                  size: 24, color: Colors.white),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isArabic ? 'اتصل بالإسعاف' : 'Call emergency services',
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isArabic
                      ? 'رقم الطوارئ: $number — يعمل بدون إنترنت'
                      : 'Emergency number: $number — no internet needed',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onCall,
            style: TextButton.styleFrom(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            child: Text(
              isArabic ? 'اتصل' : 'Dial',
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.darkRed,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Continue learning ─────────────────────────────────────────────────────────

class _ContinueLearningCard extends StatelessWidget {
  const _ContinueLearningCard();

  static const String _cprLessonId = 'cpr_basics';

  @override
  Widget build(BuildContext context) {
    final isArabic = AppStateProvider.of(context).isArabic;
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const CprLessonScreen()),
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.cardBackgroundLight),
        ),
        child: FutureBuilder<(int, int, bool)>(
          // (furthestStepReached, totalSteps, completed) — persisted by the
          // lesson screen so progress survives launches.
          future: LessonProgress.load(_cprLessonId),
          builder: (context, snapshot) {
            final (reached, total, completed) = snapshot.data ?? (0, 0, false);
            final effectiveTotal = total > 0 ? total : 4;

            final String overline;
            final Color overlineColor;
            final String subtitle;
            if (completed) {
              overline = isArabic ? 'أكملت الدرس ✓' : 'Lesson complete ✓';
              overlineColor = const Color(0xFF3E9B4F);
              subtitle = isArabic ? 'اضغط للمراجعة' : 'Tap to review';
            } else if (reached > 0) {
              overline = isArabic ? 'تابع التعلّم' : 'Continue learning';
              overlineColor = AppColors.primaryRed;
              subtitle = isArabic
                  ? 'الخطوة $reached من $effectiveTotal'
                  : 'Step $reached of $effectiveTotal';
            } else {
              overline = isArabic ? 'تابع التعلّم' : 'Continue learning';
              overlineColor = AppColors.primaryRed;
              subtitle =
                  isArabic ? '٤ خطوات · ١٢ دقيقة' : '4 steps · 12 min';
            }

            return Column(
              children: [
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.asset(
                        'assets/learn/cpr/step1/frame1.png',
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            overline,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                              color: overlineColor,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            isArabic ? 'أساسيات الإنعاش القلبي' : 'CPR Basics',
                            style: GoogleFonts.poppins(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textDark,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: GoogleFonts.inter(
                              fontSize: 11.5,
                              color: AppColors.textDark.withOpacity(0.55),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(LucideIcons.chevronRight,
                        size: 20, color: AppColors.textDark),
                  ],
                ),
                if (!completed && reached > 0) ...[
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: reached / effectiveTotal,
                      minHeight: 5,
                      backgroundColor:
                          AppColors.cardBackground.withOpacity(0.6),
                      valueColor:
                          const AlwaysStoppedAnimation(AppColors.primaryRed),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

// ── Recent vitals ─────────────────────────────────────────────────────────────

class _RecentVitalsCard extends StatelessWidget {
  const _RecentVitalsCard();

  Future<List<BiometricMeasurement>> _load() async {
    final store = await MeasurementStore.open();
    return store.recentAll(limit: 3);
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = AppStateProvider.of(context).isArabic;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardBackground.withOpacity(0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBackgroundLight),
      ),
      child: FutureBuilder<List<BiometricMeasurement>>(
        future: _load(),
        builder: (context, snapshot) {
          // Readings are optional garnish: on DB errors (e.g. tests) the
          // section renders as an empty-state link to the Vitals tab.
          final readings =
              (snapshot.hasData && snapshot.data!.isNotEmpty) ? snapshot.data! : const <BiometricMeasurement>[];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () =>
                    mainScreenKey.currentState?.switchTab(MainScreen.tabVitals),
                child: Row(
                  children: [
                    Icon(LucideIcons.activity,
                        size: 15, color: AppColors.primaryRed),
                    const SizedBox(width: 6),
                    Text(
                      isArabic ? 'آخر القياسات' : 'Recent vitals',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: AppColors.primaryRed,
                      ),
                    ),
                    const Spacer(),
                    const Icon(LucideIcons.chevronRight,
                        size: 16, color: AppColors.textDark),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              if (readings.isEmpty)
                Text(
                  isArabic
                      ? 'لا قياسات بعد — افتح تبويب الحيوية لبدء قياس.'
                      : 'No readings yet — open the Vitals tab to measure.',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppColors.textDark.withOpacity(0.55),
                  ),
                )
              else
                ...readings.map((m) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              m.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 12.5,
                                color: AppColors.textDark,
                              ),
                            ),
                          ),
                          Text(
                            m.primary == null
                                ? '--'
                                : '${m.primary!.value.toStringAsFixed(1)} ${m.primary!.unit}',
                            style: GoogleFonts.inter(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textDark,
                            ),
                          ),
                        ],
                      ),
                    )),
            ],
          );
        },
      ),
    );
  }
}

// ── Quick tip ─────────────────────────────────────────────────────────────────

class _QuickTipBanner extends StatelessWidget {
  const _QuickTipBanner({required this.isArabic});

  final bool isArabic;

  static const List<(String, String)> _tipsEn = <(String, String)>[
    ('CPR', 'Push hard and fast: 100–120 compressions per minute.'),
    ('Burns', 'Cool the burn with running water for 20 minutes.'),
    ('Choking', 'Give 5 back blows between the shoulder blades.'),
    ('Bleeding', 'Press firmly on the wound and keep pressing.'),
    ('Recovery', 'Put an unconscious breather on their side.'),
  ];

  static const List<(String, String)> _tipsAr = <(String, String)>[
    ('الإنعاش', 'اضغط بقوة وسرعة: ١٠٠–١٢٠ ضغطة في الدقيقة.'),
    ('الحروق', 'برّد الحرق بماء جارٍ لمدة ٢٠ دقيقة.'),
    ('الاختناق', 'أعطِ ٥ ضربات على الظهر بين لوحي الكتف.'),
    ('النزيف', 'اضغط بإحكام على الجرح واستمر في الضغط.'),
    ('الوعي', 'ضع الفاقد للوعي الذي يتنفس على جنبه.'),
  ];

  @override
  Widget build(BuildContext context) {
    final tips = isArabic ? _tipsAr : _tipsEn;
    final dayOfYear = DateTime.now().difference(
      DateTime(DateTime.now().year),
    ).inDays;
    final (topic, tip) = tips[dayOfYear % tips.length];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.aiAccentPink.withOpacity(0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.aiAccentPink),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(LucideIcons.lightbulb,
              size: 18, color: AppColors.primaryRed),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$topic — ',
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryRed,
                    ),
                  ),
                  TextSpan(
                    text: tip,
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      color: AppColors.textDark,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
