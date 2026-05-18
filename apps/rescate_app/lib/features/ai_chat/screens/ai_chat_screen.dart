// apps/rescate_app/lib/features/ai_chat/screens/ai_chat_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:ai_inference/ai_inference.dart';
import 'package:audio_voice/audio_voice.dart';
import 'package:offline_data/offline_data.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/providers/app_state.dart';
import '../../educational/screens/educational_screen.dart';
import '../../home/widgets/top_bar.dart';
import '../state/llm_state.dart';
import 'chat_history_screen.dart';
import 'model_setup_screen.dart';
import 'voice_chat_screen.dart';
import '../../../core/providers/demo_state.dart';

class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final LlmState _llmState = LlmState.instance;
  final TtsService _tts = TtsService.instance;
  final SttService _stt = SttService.instance;

  /// Track the last AI message index we already triggered TTS for so we
  /// don't re-read the same message on every state change.
  int _lastTtsMessageIndex = -1;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _llmState.addListener(_onStateChanged);
    _tts.addListener(_onVoiceChanged);
    _stt.addListener(_onVoiceChanged);
  }

  @override
  void dispose() {
    _llmState.removeListener(_onStateChanged);
    _tts.removeListener(_onVoiceChanged);
    _stt.removeListener(_onVoiceChanged);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onVoiceChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _onStateChanged() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    _autoReadIfNeeded();
  }

  /// Automatically read the latest AI message aloud when TTS is enabled
  /// and the message has finished streaming.
  void _autoReadIfNeeded() {
    if (!_tts.isEnabled) return;
    final messages = _llmState.messages;
    if (messages.isEmpty) return;
    final lastIndex = messages.length - 1;
    final last = messages[lastIndex];
    // Only trigger when an AI message just finished streaming.
    if (!last.isUser && !last.isStreaming && lastIndex != _lastTtsMessageIndex) {
      _lastTtsMessageIndex = lastIndex;
      final isArabic = last.text.contains(RegExp(r'[\u0600-\u06FF]'));
      _tts.speak(last.text, isArabic: isArabic);
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
    }
  }

  void _sendMessage(bool isArabic) async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();

    String contextString = '';
    try {
      final store = await MeasurementStore.open();
      final recent = await store.recentAll(limit: 5);
      await store.close();
      if (recent.isNotEmpty) {
        contextString = '\n\n[SYSTEM_VITALS_CONTEXT: Recent Vitals - ';
        for (var m in recent) {
          contextString += '${m.id.name}: ${m.primary?.value?.toStringAsFixed(1)} ${m.primary?.unit}, ';
        }
        contextString += ']';
      }
    } catch (e) {
      // Ignore
    }

    _llmState.sendMessage(text + contextString, isArabic: isArabic);
  }

  void _openModelSetup() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const ModelSetupScreen(),
      ),
    );
  }

  void _openHistory() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const ChatHistoryScreen(),
      ),
    );
  }

  void _openVoiceChat() {
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (_, __, ___) => const VoiceChatScreen(),
        transitionsBuilder: (_, anim, __, child) {
          return FadeTransition(
            opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
            child: child,
          );
        },
      ),
    );
  }

  void _attachVitals(bool isArabic) {
    final demo = DemoState.instance;
    if (demo.isDemoMode && demo.readings.isEmpty) {
      demo.generateMockReadings();
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _VitalsPickerSheet(
        onAttach: (text) {
          _controller.text = text;
          _controller.selection = TextSelection.fromPosition(
            TextPosition(offset: _controller.text.length),
          );
        },
      ),
    );
  }

  Future<void> _newChat() async {
    await _llmState.startNewConversation();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);
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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    isArabic ? 'المساعد الطبي' : 'AI Assistant',
                    style: GoogleFonts.poppins(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDark,
                    ),
                  ),
                ),
              ),
              _ModelStatusBanner(
                onSetupTap: _openModelSetup,
                llmState: _llmState,
                onToggleDemo: () {
                  DemoState.instance.toggle();
                  setState(() {});
                },
              ),
              _ChatToolbar(
                onNewChat: _newChat,
                onHistory: _openHistory,
                onVoiceChat: _openVoiceChat,
                title: _llmState.conversations.isEmpty
                    ? 'New chat'
                    : _llmState.activeConversation.title,
                ttsEnabled: _tts.isEnabled,
                isSpeaking: _tts.isSpeaking,
                onToggleTts: () => _tts.setEnabled(!_tts.isEnabled),
                onStopTts: () => _tts.stop(),
              ),
              Expanded(child: _buildMessageList(isArabic)),
              _buildInputBar(isArabic),
            ],
          ),
        ),
      ),
    );
  }

  // ── Message list ───────────────────────────────────────────────────────────

  Widget _buildMessageList(bool isArabic) {
    final messages = _llmState.messages;

    if (messages.isEmpty) {
      return _EmptyState(
        isArabic: isArabic,
        onSetupTap: _openModelSetup,
        onSuggestionTap: (text) {
          _controller.text = text;
          _sendMessage(isArabic);
        },
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final msg = messages[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Align(
            alignment: msg.isUser ? Alignment.topRight : Alignment.topLeft,
            child: _ChatBubble(message: msg),
          ),
        );
      },
    );
  }

  // ── Input bar ──────────────────────────────────────────────────────────────

  Widget _buildInputBar(bool isArabic) {
    final canSend = _llmState.canChat && !_llmState.isGenerating;
    final view = View.of(context);
    final keyboardHeight = view.viewInsets.bottom / view.devicePixelRatio;
    final bottomPadding = keyboardHeight > 0 ? 8.0 : 110.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, bottomPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_llmState.isGenerating)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primaryRed,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isArabic ? 'الذكاء الاصطناعي يفكر...' : 'AI is thinking…',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppColors.textDark.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),
          // ── STT listening indicator ──────────────────────────────
          if (_stt.isListening)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.primaryRed.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.primaryRed.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    Icon(LucideIcons.mic, size: 14, color: AppColors.primaryRed)
                        .animate(onPlay: (c) => c.repeat(reverse: true))
                        .fadeIn(duration: 600.ms)
                        .then()
                        .fadeOut(duration: 600.ms),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _stt.currentWords.isNotEmpty
                            ? _stt.currentWords
                            : (isArabic ? 'جاري الاستماع…' : 'Listening…'),
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: AppColors.textDark.withOpacity(0.7),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    GestureDetector(
                      onTap: () async {
                        await _stt.stopListening();
                        if (_stt.finalWords.isNotEmpty) {
                          _controller.text = _stt.finalWords;
                          _controller.selection = TextSelection.fromPosition(
                            TextPosition(offset: _controller.text.length),
                          );
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: AppColors.primaryRed,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(LucideIcons.square, size: 12, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Row(
            children: [
              // ── Mic button ──────────────────────────────────────────────
              GestureDetector(
                onTap: canSend
                    ? () async {
                        if (_stt.isListening) {
                          await _stt.stopListening();
                          if (_stt.finalWords.isNotEmpty) {
                            _controller.text = _stt.finalWords;
                            _controller.selection = TextSelection.fromPosition(
                              TextPosition(offset: _controller.text.length),
                            );
                          }
                        } else {
                          // Stop any ongoing TTS before listening.
                          if (_tts.isSpeaking) await _tts.stop();
                          await _stt.startListening(
                            isArabic: isArabic,
                            onResult: (text, isFinal) {
                              _controller.text = text;
                              _controller.selection = TextSelection.fromPosition(
                                TextPosition(offset: text.length),
                              );
                              if (isFinal && text.trim().isNotEmpty) {
                                // Auto-send after final result.
                                _sendMessage(isArabic);
                              }
                            },
                          );
                        }
                      }
                    : null,
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: _stt.isListening
                        ? AppColors.primaryRed
                        : AppColors.aiAccentPink.withOpacity(0.3),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _stt.isListening ? LucideIcons.micOff : LucideIcons.mic,
                    color: _stt.isListening
                        ? Colors.white
                        : (canSend ? AppColors.primaryRed : AppColors.textDark.withOpacity(0.3)),
                    size: 18,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // ── Text field ─────────────────────────────────────────────
              Expanded(
                child: Container(
                  height: 50,
                  decoration: BoxDecoration(
                    color: AppColors.aiAccentPink.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: _stt.isListening
                          ? AppColors.primaryRed
                          : AppColors.aiAccentPink,
                      width: 1.5,
                    ),
                  ),
                  child: TextField(
                    controller: _controller,
                    enabled: canSend,
                    onSubmitted: canSend ? (_) => _sendMessage(isArabic) : null,
                    decoration: InputDecoration(
                      hintText: _stt.isListening
                          ? (isArabic ? 'تحدث الآن…' : 'Speak now…')
                          : !_llmState.isModelReady
                              ? (isArabic
                                  ? 'قم بتحميل نموذج أولاً…'
                                  : 'Load a model first…')
                              : (isArabic
                                  ? 'اكتب رسالتك…'
                                  : 'Type your message…'),
                      hintStyle: GoogleFonts.inter(
                        color: const Color(0xFFB0A0A0),
                        fontSize: 14,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // ── Vitals attach button ────────────────────────────────
              GestureDetector(
                onTap: canSend ? () => _attachVitals(isArabic) : null,
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: canSend
                        ? AppColors.primaryRed.withOpacity(0.1)
                        : AppColors.cardBackground.withOpacity(0.5),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    LucideIcons.heartPulse,
                    color: canSend
                        ? AppColors.primaryRed
                        : AppColors.textDark.withOpacity(0.3),
                    size: 18,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // ── Send button ────────────────────────────────────────────
              GestureDetector(
                onTap: canSend ? () => _sendMessage(isArabic) : null,
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: canSend
                        ? AppColors.primaryRed
                        : AppColors.cardBackground,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _llmState.isGenerating
                        ? LucideIcons.loader
                        : LucideIcons.send,
                    color: canSend
                        ? Colors.white
                        : AppColors.textDark.withOpacity(0.3),
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Chat toolbar (new / history) ───────────────────────────────────────────────

class _ChatToolbar extends StatelessWidget {
  const _ChatToolbar({
    required this.onNewChat,
    required this.onHistory,
    required this.onVoiceChat,
    required this.title,
    required this.ttsEnabled,
    required this.isSpeaking,
    required this.onToggleTts,
    required this.onStopTts,
  });

  final VoidCallback onNewChat;
  final VoidCallback onHistory;
  final VoidCallback onVoiceChat;
  final String title;
  final bool ttsEnabled;
  final bool isSpeaking;
  final VoidCallback onToggleTts;
  final VoidCallback onStopTts;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 6),
      padding: const EdgeInsets.fromLTRB(16, 8, 6, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: AppColors.primaryRed.withOpacity(0.6),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title.replaceAll(RegExp(r'\n\n\[SYSTEM_VITALS_CONTEXT:.*?\]'), ''),
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textDark,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // ── TTS toggle ─────────────────────────────────────────
          GestureDetector(
            onTap: isSpeaking ? onStopTts : onToggleTts,
            child: Tooltip(
              message: isSpeaking
                  ? 'Stop speaking'
                  : (ttsEnabled ? 'Disable auto-read' : 'Enable auto-read'),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: ttsEnabled
                      ? AppColors.primaryRed.withOpacity(0.15)
                      : AppColors.primaryRed.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isSpeaking
                      ? LucideIcons.volumeX
                      : ttsEnabled
                          ? LucideIcons.volume2
                          : LucideIcons.volumeX,
                  size: 16,
                  color: ttsEnabled ? AppColors.primaryRed : AppColors.primaryRed.withOpacity(0.4),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Voice chat button
          _toolbarButton(LucideIcons.headphones, 'Voice chat', onVoiceChat),
          const SizedBox(width: 4),
          _toolbarButton(LucideIcons.plus, 'New chat', onNewChat),
          const SizedBox(width: 4),
          _toolbarButton(LucideIcons.history, 'History', onHistory),
        ],
      ),
    );
  }

  Widget _toolbarButton(IconData icon, String tooltip, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message: tooltip,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppColors.primaryRed.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 16, color: AppColors.primaryRed),
        ),
      ),
    );
  }
}

// ── Model status banner ────────────────────────────────────────────────────────

class _ModelStatusBanner extends StatelessWidget {
  const _ModelStatusBanner({
    required this.onSetupTap,
    required this.llmState,
    required this.onToggleDemo,
  });

  final VoidCallback onSetupTap;
  final LlmState llmState;
  final VoidCallback onToggleDemo;

  @override
  Widget build(BuildContext context) {
    final status = llmState.modelStatus;
    final isDemo = DemoState.instance.isDemoMode;

    // Demo mode banner
    if (isDemo && status != LlmStatus.ready) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF34C759).withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF34C759).withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Color(0xFF34C759),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Demo Mode — no model needed',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppColors.textDark.withOpacity(0.7),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              GestureDetector(
                onTap: onToggleDemo,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primaryRed.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'OFF',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryRed,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Hide banner when model is ready and generating (or idle after ready).
    if (status == LlmStatus.ready || status == LlmStatus.generating) {
      // Show a slim "model loaded" pill.
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Color(0xFF4CAF50),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                llmState.loadedModelPath != null
                    ? _basename(llmState.loadedModelPath!)
                    : 'Model ready',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: AppColors.textDark.withOpacity(0.5),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            GestureDetector(
              onTap: onSetupTap,
              child: Text(
                'Change',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: AppColors.primaryRed,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (status == LlmStatus.loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        child: Row(
          children: [
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: AppColors.primaryRed,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Loading model…',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: AppColors.textDark.withOpacity(0.6),
              ),
            ),
          ],
        ),
      );
    }

    if (status == LlmStatus.error) {
      return GestureDetector(
        onTap: onSetupTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFFFEAEA),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              const Icon(LucideIcons.alertCircle,
                  size: 16, color: AppColors.primaryRed),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  llmState.modelError ?? 'Model failed to load.',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppColors.primaryRed,
                  ),
                  maxLines: 2,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Retry',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryRed,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // status == idle — primary CTA to load a model.
    return GestureDetector(
      onTap: onSetupTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.aiAccentPink.withOpacity(0.25),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.aiAccentPink, width: 1),
        ),
        child: Row(
          children: [
            const Icon(LucideIcons.cpu, size: 18, color: AppColors.primaryRed),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Tap to load your GGUF model and start chatting offline.',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppColors.textDark.withOpacity(0.7),
                ),
              ),
            ),
            const Icon(LucideIcons.chevronRight,
                size: 16, color: AppColors.primaryRed),
          ],
        ),
      ),
    );
  }

  String _basename(String path) {
    final sep = path.lastIndexOf(RegExp(r'[/\\]'));
    return sep < 0 ? path : path.substring(sep + 1);
  }
}

// ── Empty state ────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.isArabic,
    required this.onSetupTap,
    required this.onSuggestionTap,
  });

  final bool isArabic;
  final VoidCallback onSetupTap;
  final ValueChanged<String> onSuggestionTap;

  static const _suggestions = [
    'What are signs of a heart attack?',
    'How to treat a burn?',
    'Normal blood pressure range?',
    'CPR steps for adults',
  ];

  static const _suggestionsAr = [
    'ما هي علامات النوبة القلبية؟',
    'كيف أعالج الحرق؟',
    'ما هو ضغط الدم الطبيعي؟',
    'خطوات الإنعاش القلبي',
  ];

  @override
  Widget build(BuildContext context) {
    final chips = isArabic ? _suggestionsAr : _suggestions;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Layered circles
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: AppColors.primaryRed.withOpacity(0.05),
                    shape: BoxShape.circle,
                  ),
                ),
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: AppColors.primaryRed.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                ),
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.primaryRed,
                        AppColors.primaryRed.withOpacity(0.8),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primaryRed.withOpacity(0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Icon(
                    LucideIcons.stethoscope,
                    size: 28,
                    color: Colors.white,
                  ),
                ),
              ],
            )
                .animate()
                .fadeIn(duration: 600.ms)
                .scale(begin: const Offset(0.7, 0.7)),
            const SizedBox(height: 24),
            Text(
              isArabic ? 'اسأل Rescate' : 'Ask Rescate',
              style: GoogleFonts.poppins(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppColors.textDark,
              ),
            ).animate().fadeIn(delay: 100.ms),
            const SizedBox(height: 6),
            Text(
              isArabic
                  ? 'مساعدك الطبي الذكي يعمل بدون إنترنت'
                  : 'Your offline medical AI assistant',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: AppColors.textDark.withOpacity(0.5),
                height: 1.5,
              ),
            ).animate().fadeIn(delay: 200.ms),
            const SizedBox(height: 28),
            // Suggestion chips
            Text(
              isArabic ? 'جرب أن تسأل:' : 'Try asking:',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textDark.withOpacity(0.35),
              ),
            ).animate().fadeIn(delay: 300.ms),
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: chips.asMap().entries.map((e) {
                return GestureDetector(
                  onTap: () => onSuggestionTap(e.value),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppColors.primaryRed.withOpacity(0.12),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.02),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      e.value,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppColors.textDark.withOpacity(0.65),
                      ),
                    ),
                  ),
                )
                    .animate()
                    .fadeIn(delay: (350 + e.key * 80).ms)
                    .slideY(begin: 0.15);
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Chat bubble ────────────────────────────────────────────────────────────────

String _formatTimings(ChatMessage m) {
  final parts = <String>[];
  if (m.ttftMs != null) parts.add('first token ${_fmtMs(m.ttftMs!)}');
  if (m.totalMs != null) parts.add('total ${_fmtMs(m.totalMs!)}');
  return parts.join(' • ');
}

String _fmtMs(int ms) {
  if (ms < 1000) return '${ms}ms';
  final s = ms / 1000.0;
  return s < 10 ? '${s.toStringAsFixed(2)}s' : '${s.toStringAsFixed(1)}s';
}

/// Renders a growing text string with a soft fade-in on each newly-appended
/// chunk. Drives the "word arrives, then settles" feel while streaming.
class _StreamingText extends StatefulWidget {
  const _StreamingText({required this.text, required this.style});
  final String text;
  final TextStyle style;

  @override
  State<_StreamingText> createState() => _StreamingTextState();
}

class _StreamingTextState extends State<_StreamingText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  String _stable = '';
  String _newest = '';

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    )..addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() {
          _stable = _stable + _newest;
          _newest = '';
        });
      }
    });
    _newest = widget.text;
    if (_newest.isNotEmpty) _ctrl.forward(from: 0);
  }

  @override
  void didUpdateWidget(covariant _StreamingText old) {
    super.didUpdateWidget(old);
    if (widget.text == old.text) return;
    final prev = _stable + _newest;
    if (widget.text.startsWith(prev)) {
      final tail = widget.text.substring(prev.length);
      if (tail.isEmpty) return;
      setState(() {
        _stable = prev;
        _newest = tail;
      });
      _ctrl.forward(from: 0);
    } else {
      // Non-append change (e.g. error replacement) — snap to stable.
      setState(() {
        _stable = widget.text;
        _newest = '';
      });
      _ctrl.value = 1;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return Text.rich(
          TextSpan(
            style: widget.style,
            children: <InlineSpan>[
              TextSpan(text: _stable),
              if (_newest.isNotEmpty)
                TextSpan(
                  text: _newest,
                  style: widget.style.copyWith(
                    color: widget.style.color?.withValues(alpha: _ctrl.value),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ChatBubble extends StatefulWidget {
  const _ChatBubble({required this.message});

  final ChatMessage message;

  @override
  State<_ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<_ChatBubble> {
  /// Manual override for the thoughts disclosure. `null` means "follow the
  /// auto rule" (expanded while thinking, collapsed once the answer starts).
  /// Once the user taps the toggle this gets pinned to `true` or `false`.
  bool? _thoughtsManualExpanded;

  bool _resolveExpanded(ChatMessage m) {
    if (_thoughtsManualExpanded != null) return _thoughtsManualExpanded!;
    return m.isThinking;
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final isUser = message.isUser;
    final textColor = isUser ? Colors.white : AppColors.textDark;
    final hasThoughts = !isUser && message.thoughts.isNotEmpty;
    final showAnswerStreaming =
        !isUser && message.isStreaming && !message.isThinking;
    final showAnswerEmpty = message.text.isEmpty && !message.isThinking;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (!isUser)
          Padding(
            padding: const EdgeInsets.only(right: 6, bottom: 2),
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: AppColors.primaryRed.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(LucideIcons.bot,
                  size: 13, color: AppColors.primaryRed),
            ),
          ),
        Container(
          constraints: const BoxConstraints(maxWidth: 280),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isUser ? AppColors.primaryRed : Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(20),
              topRight: const Radius.circular(20),
              bottomRight: Radius.circular(isUser ? 6 : 20),
              bottomLeft: Radius.circular(isUser ? 20 : 6),
            ),
            boxShadow: [
              BoxShadow(
                color: isUser
                    ? AppColors.primaryRed.withOpacity(0.25)
                    : Colors.black.withOpacity(0.04),
                blurRadius: isUser ? 16 : 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasThoughts || message.isThinking) ...[
                _ThoughtsDisclosure(
                  thoughts: message.thoughts,
                  isThinking: message.isThinking,
                  expanded: _resolveExpanded(message),
                  baseColor: textColor,
                  onToggle: () => setState(() {
                    _thoughtsManualExpanded = !_resolveExpanded(message);
                  }),
                ),
                const SizedBox(height: 8),
              ],
              if (showAnswerEmpty && message.isStreaming)
                _TypingIndicator(color: textColor)
              else if (showAnswerStreaming) ...[
                _StreamingText(
                  text: message.text.replaceAll(RegExp(r'\n\n\[SYSTEM_VITALS_CONTEXT:.*?\]'), ''),
                  style: GoogleFonts.inter(fontSize: 14, color: textColor, height: 1.5),
                ),
                const SizedBox(height: 6),
                _TypingIndicator(color: textColor),
              ] else if (message.text.isNotEmpty)
                Text(
                  message.text.replaceAll(RegExp(r'\n\n\[SYSTEM_VITALS_CONTEXT:.*?\]'), ''),
                  style: GoogleFonts.inter(fontSize: 14, color: textColor, height: 1.5),
                ),
              if (!isUser && !message.isStreaming &&
                  (message.ttftMs != null || message.totalMs != null)) ...[
                const SizedBox(height: 6),
                Text(
                  _formatTimings(message),
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: textColor.withValues(alpha: 0.45),
                  ),
                ),
              ],
              if (!isUser &&
                  message.inlineWidget == InlineWidgetType.cprTutorialButton &&
                  !message.isStreaming) ...[
                const SizedBox(height: 10),
                _InlineCprButton(),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _InlineCprButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const CprLessonScreen(),
          ),
        );
      },
      icon: const Icon(LucideIcons.heartPulse,
          size: 16, color: AppColors.primaryRed),
      label: Text(
        'Open CPR Tutorial',
        style: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.primaryRed,
        ),
      ),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: AppColors.primaryRed),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      ),
    );
  }
}

class _ThoughtsDisclosure extends StatelessWidget {
  const _ThoughtsDisclosure({
    required this.thoughts,
    required this.isThinking,
    required this.expanded,
    required this.baseColor,
    required this.onToggle,
  });

  final String thoughts;
  final bool isThinking;
  final bool expanded;
  final Color baseColor;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final muted = baseColor.withValues(alpha: 0.6);
    final label = isThinking ? 'Thinking…' : 'Thoughts';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  expanded ? LucideIcons.chevronDown : LucideIcons.chevronRight,
                  size: 12,
                  color: muted,
                ),
                const SizedBox(width: 4),
                Icon(LucideIcons.brain, size: 12, color: muted),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: muted,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox(width: double.infinity),
          secondChild: Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: baseColor.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: baseColor.withValues(alpha: 0.08)),
            ),
            child: Text(
              thoughts.isEmpty ? '…' : thoughts,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: baseColor.withValues(alpha: 0.75),
                height: 1.4,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          crossFadeState:
              expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 180),
        ),
      ],
    );
  }
}

// ── Typing indicator (animated dots) ──────────────────────────────────────────

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        return Container(
          width: 5,
          height: 5,
          margin: const EdgeInsets.only(right: 3),
          decoration: BoxDecoration(
            color: color.withOpacity(0.6),
            shape: BoxShape.circle,
          ),
        )
            .animate(onPlay: (c) => c.repeat())
            .fadeIn(delay: (i * 150).ms, duration: 300.ms)
            .then()
            .fadeOut(duration: 300.ms);
      }),
    );
  }
}

// ── Bubble tail ────────────────────────────────────────────────────────────────

class _BubbleTail extends CustomPainter {
  _BubbleTail(this.color, {required this.isLeft});
  final Color color;
  final bool isLeft;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path();
    if (isLeft) {
      path.moveTo(size.width, 0);
      path.lineTo(size.width, size.height);
      path.lineTo(0, size.height);
    } else {
      path.moveTo(0, 0);
      path.lineTo(0, size.height);
      path.lineTo(size.width, size.height);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Vitals picker bottom sheet ────────────────────────────────────────────────

class _VitalsPickerSheet extends StatefulWidget {
  const _VitalsPickerSheet({required this.onAttach});
  final ValueChanged<String> onAttach;

  @override
  State<_VitalsPickerSheet> createState() => _VitalsPickerSheetState();
}

class _VitalsPickerSheetState extends State<_VitalsPickerSheet> {
  final Set<int> _selected = {};

  @override
  Widget build(BuildContext context) {
    final demo = DemoState.instance;
    final readings = demo.readings;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.55,
      ),
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.textDark.withOpacity(0.15),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Icon(LucideIcons.heartPulse,
                    size: 20, color: AppColors.primaryRed),
                const SizedBox(width: 10),
                Text(
                  'Attach Vitals',
                  style: GoogleFonts.poppins(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark,
                  ),
                ),
                const Spacer(),
                if (readings.isEmpty)
                  GestureDetector(
                    onTap: () {
                      demo.generateMockReadings();
                      setState(() {});
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.primaryRed.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'Generate Mock',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primaryRed,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (readings.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'No vitals available.\nGenerate mock data or run a test from the Vitals tab.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppColors.textDark.withOpacity(0.45),
                ),
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: readings.length,
                itemBuilder: (_, i) {
                  final r = readings[i];
                  final isChosen = _selected.contains(i);
                  return GestureDetector(
                    onTap: () => setState(() {
                      isChosen ? _selected.remove(i) : _selected.add(i);
                    }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: isChosen
                            ? AppColors.primaryRed.withOpacity(0.08)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isChosen
                              ? AppColors.primaryRed.withOpacity(0.4)
                              : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isChosen
                                  ? AppColors.primaryRed
                                  : AppColors.cardBackground,
                            ),
                            child: isChosen
                                ? const Icon(LucideIcons.check,
                                    size: 14, color: Colors.white)
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(r.name,
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textDark,
                                    )),
                                Text(r.category,
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      color:
                                          AppColors.textDark.withOpacity(0.4),
                                    )),
                              ],
                            ),
                          ),
                          Text(
                            '${r.formattedValue} ${r.unit}',
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          if (readings.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: GestureDetector(
                onTap: () {
                  final subset = _selected.isEmpty
                      ? readings
                      : _selected.map((i) => readings[i]).toList();
                  final text = demo.formatReadingsForChat(subset);
                  widget.onAttach(text);
                  Navigator.of(context).pop();
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.primaryRed,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primaryRed.withOpacity(0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      _selected.isEmpty
                          ? 'Attach All Vitals'
                          : 'Attach ${_selected.length} Reading${_selected.length > 1 ? "s" : ""}',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
