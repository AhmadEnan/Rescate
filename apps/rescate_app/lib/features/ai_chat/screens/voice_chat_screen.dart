// apps/rescate_app/lib/features/ai_chat/screens/voice_chat_screen.dart
//
// Full-screen AI voice-chat mode. Native voice input is not wired yet.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';

// ── Phase machine ───────────────────────────────────────────────────────────────

// ── Screen ──────────────────────────────────────────────────────────────────────

class VoiceChatScreen extends StatefulWidget {
  const VoiceChatScreen({super.key});

  @override
  State<VoiceChatScreen> createState() => _VoiceChatScreenState();
}

class _VoiceChatScreenState extends State<VoiceChatScreen>
    with TickerProviderStateMixin {
  // Animation controllers
  late final AnimationController _breatheCtrl;
  @override
  void initState() {
    super.initState();

    _breatheCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _breatheCtrl.dispose();
    super.dispose();
  }

  // ── Phase transitions ─────────────────────────────────────────────────────

  void _onMicTap() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Voice chat is unavailable until native voice input is connected.',
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1210),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            const Spacer(flex: 1),
            _buildOrb(),
            const SizedBox(height: 28),
            _buildStatusText(),
            const SizedBox(height: 16),
            _buildResponseArea(),
            const Spacer(flex: 1),
            _buildBottomControls(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // ── Top bar ─────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(LucideIcons.x, color: Colors.white70, size: 20),
            ),
          ),
          const Spacer(),
          Text(
            'Voice Chat',
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.white70,
            ),
          ),
          const Spacer(),
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  // ── Animated orb ──────────────────────────────────────────────────────────

  Widget _buildOrb() {
    return SizedBox(
      width: 220,
      height: 220,
      child: AnimatedBuilder(
        animation: _breatheCtrl,
        builder: (_, __) {
          final breathe = _breatheCtrl.value;

          double outerScale;
          double midScale;
          double innerGlow;

          outerScale = 1.0 + breathe * 0.06;
          midScale = 1.0 + breathe * 0.03;
          innerGlow = 0.3;

          return Stack(
            alignment: Alignment.center,
            children: [
              // Outer ring
              Transform.scale(
                scale: outerScale,
                child: Transform.rotate(
                  angle: 0,
                  child: Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.primaryRed.withValues(alpha: 0.15),
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
              // Mid ring
              Transform.scale(
                scale: midScale,
                child: Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primaryRed.withValues(alpha: 0.08),
                    border: Border.all(
                      color: AppColors.primaryRed.withValues(alpha: 0.2),
                      width: 1,
                    ),
                  ),
                ),
              ),
              // Inner orb
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.primaryRed.withValues(alpha: innerGlow),
                      AppColors.primaryRed.withValues(alpha: innerGlow * 0.4),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.6, 1.0],
                  ),
                ),
              ),
              // Core
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primaryRed,
                      AppColors.primaryRed.withValues(alpha: 0.7),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryRed.withValues(alpha: innerGlow * 0.6),
                      blurRadius: 30,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: const Icon(LucideIcons.micOff, color: Colors.white, size: 22),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Status text ───────────────────────────────────────────────────────────

  Widget _buildStatusText() {
    String text;
    Color color;

    text = 'Voice chat unavailable';
    color = Colors.white38;

    return Column(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Text(
            text,
            key: ValueKey(text),
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResponseArea() {
    return const SizedBox(height: 24);
  }

  // ── Bottom controls ───────────────────────────────────────────────────────

  Widget _buildBottomControls() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // End session button
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  LucideIcons.phoneOff,
                  color: Colors.white54,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(width: 32),
            // Mic button
            GestureDetector(
              onTap: _onMicTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primaryRed.withValues(alpha: 0.8),
                      AppColors.primaryRed.withValues(alpha: 0.5),
                    ],
                  ),
                  boxShadow: const [],
                ),
                child: const Icon(LucideIcons.micOff, color: Colors.white, size: 24),
              ),
            ),
            const SizedBox(width: 32),
            // Clear history
            GestureDetector(
              onTap: () {
                // There is no simulated conversation to clear.
              },
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  LucideIcons.trash2,
                  color: Colors.white54,
                  size: 20,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
