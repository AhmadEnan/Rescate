// Home readiness strip: three pills answering "is this phone ready for an
// emergency right now?" — AI model, sensors, GPS. Each pill deep-links to
// the screen that can fix or expand its status.
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:ai_inference/ai_inference.dart';
import 'package:sensor_availability/sensor_availability.dart';

import '../../../../core/theme/app_colors.dart';
import '../screens/main_screen.dart';
import '../../ai_chat/screens/model_setup_screen.dart';

class ReadinessStrip extends StatelessWidget {
  const ReadinessStrip({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ReadinessPill(
            icon: LucideIcons.bot,
            tint: AppColors.aiAccentPink,
            // Listens to LlmService status transitions (idle/loading/ready).
            content: ListenableBuilder(
              listenable: LlmService.instance,
              builder: (context, _) => _AiPillContent(
                status: LlmService.instance.status,
              ),
            ),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ModelSetupScreen(),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ReadinessPill(
            icon: LucideIcons.cpu,
            tint: AppColors.cardBackgroundLight,
            content: const _SensorPillContent(),
            onTap: () =>
                mainScreenKey.currentState?.switchTab(MainScreen.tabVitals),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ReadinessPill(
            icon: LucideIcons.mapPin,
            tint: AppColors.gpsAccentBlue,
            content: const _GpsPillContent(),
            onTap: () =>
                mainScreenKey.currentState?.switchTab(MainScreen.tabMap),
          ),
        ),
      ],
    );
  }
}

// ── AI pill ───────────────────────────────────────────────────────────────────

class _AiPillContent extends StatelessWidget {
  const _AiPillContent({required this.status});

  final LlmStatus status;

  @override
  Widget build(BuildContext context) {
    final String label;
    final Color dot;
    switch (status) {
      case LlmStatus.ready:
      case LlmStatus.generating:
        label = 'AI ready';
        dot = const Color(0xFF3E9B4F);
      case LlmStatus.loading:
        label = 'AI loading…';
        dot = const Color(0xFFC9930B);
      case LlmStatus.error:
        label = 'AI error';
        dot = AppColors.primaryRed;
      case LlmStatus.idle:
        label = 'Set up AI';
        dot = AppColors.textDark.withOpacity(0.35);
    }
    return _PillText(label: label, dot: dot);
  }
}

// ── Sensor pill ───────────────────────────────────────────────────────────────

class _SensorPillContent extends StatelessWidget {
  const _SensorPillContent();

  static final SensorAvailabilityService _service =
      SensorAvailabilityService.instance;

  @override
  Widget build(BuildContext context) {
    if (!_service.isReady) {
      // Startup probe may still be running (main.dart fires it async).
      return const _PillText(
        label: 'Sensors…',
        dot: Color(0x59202020),
      );
    }
    final reports = _service.reports;
    final available =
        reports.where((r) => r.status == SensorStatus.available).length;
    return _PillText(
      label: '$available/${reports.length} sensors',
      dot: available > 0 ? const Color(0xFF3E9B4F) : AppColors.primaryRed,
    );
  }
}

// ── GPS pill ──────────────────────────────────────────────────────────────────

class _GpsPillContent extends StatelessWidget {
  const _GpsPillContent();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: Geolocator.isLocationServiceEnabled(),
      builder: (context, snapshot) {
        final enabled = snapshot.data ?? false;
        return _PillText(
          label: enabled ? 'GPS on' : 'GPS off',
          dot: enabled ? const Color(0xFF3E9B4F) : AppColors.primaryRed,
        );
      },
    );
  }
}

// ── Shared pill pieces ────────────────────────────────────────────────────────

class _ReadinessPill extends StatelessWidget {
  const _ReadinessPill({
    required this.icon,
    required this.tint,
    required this.content,
    this.onTap,
  });

  final IconData icon;
  final Color tint;
  final Widget content;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: tint.withOpacity(0.45),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: tint.withOpacity(0.8)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppColors.textDark),
            const SizedBox(width: 6),
            Expanded(child: content),
          ],
        ),
      ),
    );
  }
}

class _PillText extends StatelessWidget {
  const _PillText({required this.label, required this.dot});

  final String label;
  final Color dot;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
        ),
      ],
    );
  }
}
