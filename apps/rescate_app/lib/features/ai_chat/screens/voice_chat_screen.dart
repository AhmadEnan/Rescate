// apps/rescate_app/lib/features/ai_chat/screens/voice_chat_screen.dart
//
// Full-screen AI voice-chat mode – inspired by Gemini Live / Claude voice.
// Frontend-only; uses demo mock responses when no real model is loaded.

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/providers/demo_state.dart';
import '../state/llm_state.dart';

// ── Phase machine ───────────────────────────────────────────────────────────────

enum _Phase { idle, listening, processing, speaking }

// ── Screen ──────────────────────────────────────────────────────────────────────

class VoiceChatScreen extends StatefulWidget {
  const VoiceChatScreen({super.key});

  @override
  State<VoiceChatScreen> createState() => _VoiceChatScreenState();
}

class _VoiceChatScreenState extends State<VoiceChatScreen>
    with TickerProviderStateMixin {
  _Phase _phase = _Phase.idle;

  // Animation controllers
  late final AnimationController _breatheCtrl;
  late final AnimationController _pulseCtrl;
  late final AnimationController _spinCtrl;

  // Conversation log shown on screen
  final List<_VoiceTurn> _turns = [];
  String _liveTranscript = '';
  String _currentResponse = '';

  Timer? _demoListenTimer;
  Timer? _demoProcessTimer;
  Timer? _demoSpeakTimer;

  static const _mockTranscripts = [
    'How are my vitals looking today?',
    'What is a normal heart rate range?',
    'Can you analyze my recent readings?',
    'Tell me about blood pressure levels.',
    'What should I do if my SpO₂ drops below 90?',
  ];

  @override
  void initState() {
    super.initState();

    _breatheCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat(reverse: true);

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);

    _spinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _demoListenTimer?.cancel();
    _demoProcessTimer?.cancel();
    _demoSpeakTimer?.cancel();
    _breatheCtrl.dispose();
    _pulseCtrl.dispose();
    _spinCtrl.dispose();
    super.dispose();
  }

  // ── Phase transitions ─────────────────────────────────────────────────────

  void _onMicTap() {
    switch (_phase) {
      case _Phase.idle:
        _startListening();
      case _Phase.listening:
        _stopListening();
      case _Phase.speaking:
        // Interrupt speaking, go back to idle
        _demoSpeakTimer?.cancel();
        setState(() {
          _phase = _Phase.idle;
          _currentResponse = '';
        });
      case _Phase.processing:
        break; // ignore
    }
  }

  void _startListening() {
    setState(() {
      _phase = _Phase.listening;
      _liveTranscript = '';
    });

    // Demo: simulate speech recognition over ~3 seconds
    final transcript =
        _mockTranscripts[Random().nextInt(_mockTranscripts.length)];
    final words = transcript.split(' ');
    int i = 0;
    _demoListenTimer =
        Timer.periodic(const Duration(milliseconds: 400), (timer) {
      if (i >= words.length) {
        timer.cancel();
        _stopListening();
        return;
      }
      setState(() {
        _liveTranscript += (i == 0 ? '' : ' ') + words[i];
      });
      i++;
    });
  }

  void _stopListening() {
    _demoListenTimer?.cancel();
    final userText =
        _liveTranscript.isNotEmpty ? _liveTranscript : 'How are my vitals?';
    setState(() {
      _turns.add(_VoiceTurn(text: userText, isUser: true));
      _phase = _Phase.processing;
      _liveTranscript = '';
    });

    // Demo: simulate "thinking" for 1–2 seconds
    final delay = 1000 + Random().nextInt(1000);
    _demoProcessTimer = Timer(Duration(milliseconds: delay), () {
      _startSpeaking();
    });
  }

  void _startSpeaking() {
    final response = DemoState.instance.getRandomVoiceResponse();
    final words = response.split(' ');
    int i = 0;

    setState(() {
      _phase = _Phase.speaking;
      _currentResponse = '';
    });

    _demoSpeakTimer =
        Timer.periodic(const Duration(milliseconds: 80), (timer) {
      if (i >= words.length) {
        timer.cancel();
        setState(() {
          _turns.add(_VoiceTurn(text: _currentResponse, isUser: false));
          _currentResponse = '';
          _phase = _Phase.idle;
        });
        return;
      }
      setState(() {
        _currentResponse += (i == 0 ? '' : ' ') + words[i];
      });
      i++;
    });
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
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child:
                  const Icon(LucideIcons.x, color: Colors.white70, size: 20),
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
          // Demo badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primaryRed.withOpacity(0.25),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'DEMO',
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryRed,
                letterSpacing: 1.2,
              ),
            ),
          ),
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
        animation: Listenable.merge([_breatheCtrl, _pulseCtrl, _spinCtrl]),
        builder: (_, __) {
          final breathe = _breatheCtrl.value;
          final pulse = _pulseCtrl.value;
          final spin = _spinCtrl.value;

          double outerScale;
          double midScale;
          double innerGlow;

          switch (_phase) {
            case _Phase.idle:
              outerScale = 1.0 + breathe * 0.06;
              midScale = 1.0 + breathe * 0.03;
              innerGlow = 0.3;
            case _Phase.listening:
              outerScale = 1.0 + pulse * 0.15;
              midScale = 1.0 + pulse * 0.10;
              innerGlow = 0.5 + pulse * 0.3;
            case _Phase.processing:
              outerScale = 1.0 + breathe * 0.08;
              midScale = 1.0 + breathe * 0.05;
              innerGlow = 0.6;
            case _Phase.speaking:
              outerScale = 1.0 + pulse * 0.12;
              midScale = 1.0 + pulse * 0.08;
              innerGlow = 0.4 + pulse * 0.4;
          }

          return Stack(
            alignment: Alignment.center,
            children: [
              // Outer ring
              Transform.scale(
                scale: outerScale,
                child: Transform.rotate(
                  angle: _phase == _Phase.processing ? spin * 2 * pi : 0,
                  child: Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.primaryRed.withOpacity(0.15),
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
                    color: AppColors.primaryRed.withOpacity(0.08),
                    border: Border.all(
                      color: AppColors.primaryRed.withOpacity(0.2),
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
                      AppColors.primaryRed.withOpacity(innerGlow),
                      AppColors.primaryRed.withOpacity(innerGlow * 0.4),
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
                      AppColors.primaryRed.withOpacity(0.7),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryRed.withOpacity(innerGlow * 0.6),
                      blurRadius: 30,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: Icon(
                  _phase == _Phase.listening
                      ? LucideIcons.mic
                      : _phase == _Phase.processing
                          ? LucideIcons.loader
                          : _phase == _Phase.speaking
                              ? LucideIcons.volume2
                              : LucideIcons.stethoscope,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              // Orbiting dots for processing
              if (_phase == _Phase.processing)
                ...List.generate(3, (i) {
                  final angle = spin * 2 * pi + (i * 2 * pi / 3);
                  return Positioned(
                    left: 110 + cos(angle) * 80,
                    top: 110 + sin(angle) * 80,
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.primaryRed
                            .withOpacity(0.5 + 0.5 * ((i + 1) / 3)),
                      ),
                    ),
                  );
                }),
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

    switch (_phase) {
      case _Phase.idle:
        text = 'Tap the mic to speak';
        color = Colors.white38;
      case _Phase.listening:
        text = 'Listening…';
        color = AppColors.primaryRed;
      case _Phase.processing:
        text = 'Processing…';
        color = Colors.white60;
      case _Phase.speaking:
        text = 'Rescate is responding';
        color = AppColors.aiAccentPink;
    }

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
        if (_liveTranscript.isNotEmpty) ...[
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              '"$_liveTranscript"',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: Colors.white.withOpacity(0.8),
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ── Response / conversation area ──────────────────────────────────────────

  Widget _buildResponseArea() {
    return Expanded(
      flex: 0,
      child: Container(
        constraints: const BoxConstraints(maxHeight: 220),
        margin: const EdgeInsets.symmetric(horizontal: 28),
        child: SingleChildScrollView(
          reverse: true,
          child: Column(
            children: [
              // Past turns
              for (final turn in _turns)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: turn.isUser
                              ? Colors.white.withOpacity(0.12)
                              : AppColors.primaryRed.withOpacity(0.25),
                        ),
                        child: Icon(
                          turn.isUser ? LucideIcons.user : LucideIcons.bot,
                          size: 11,
                          color: turn.isUser
                              ? Colors.white54
                              : AppColors.primaryRed,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          turn.text,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: turn.isUser
                                ? Colors.white54
                                : Colors.white.withOpacity(0.75),
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              // Current response being "spoken"
              if (_currentResponse.isNotEmpty)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.primaryRed.withOpacity(0.25),
                      ),
                      child: const Icon(
                        LucideIcons.bot,
                        size: 11,
                        color: AppColors.primaryRed,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _currentResponse,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: Colors.white.withOpacity(0.85),
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Bottom controls ───────────────────────────────────────────────────────

  Widget _buildBottomControls() {
    final bool isMicActive = _phase == _Phase.listening;

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
                  color: Colors.white.withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(LucideIcons.phoneOff,
                    color: Colors.white54, size: 20),
              ),
            ),
            const SizedBox(width: 32),
            // Mic button
            GestureDetector(
              onTap: _phase == _Phase.processing ? null : _onMicTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: isMicActive ? 76 : 68,
                height: isMicActive ? 76 : 68,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: isMicActive
                        ? [
                            AppColors.primaryRed,
                            AppColors.primaryRed.withOpacity(0.8),
                          ]
                        : [
                            AppColors.primaryRed.withOpacity(0.8),
                            AppColors.primaryRed.withOpacity(0.5),
                          ],
                  ),
                  boxShadow: [
                    if (isMicActive)
                      BoxShadow(
                        color: AppColors.primaryRed.withOpacity(0.5),
                        blurRadius: 24,
                        spreadRadius: 4,
                      ),
                  ],
                ),
                child: Icon(
                  isMicActive ? LucideIcons.micOff : LucideIcons.mic,
                  color: Colors.white,
                  size: isMicActive ? 28 : 24,
                ),
              ),
            ),
            const SizedBox(width: 32),
            // Clear history
            GestureDetector(
              onTap: () {
                setState(() {
                  _turns.clear();
                  _currentResponse = '';
                });
              },
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(LucideIcons.trash2,
                    color: Colors.white54, size: 20),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Data class ──────────────────────────────────────────────────────────────────

class _VoiceTurn {
  _VoiceTurn({required this.text, required this.isUser});
  final String text;
  final bool isUser;
}
