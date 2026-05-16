// apps/rescate_app/lib/features/ai_chat/screens/ai_chat_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:ai_inference/ai_inference.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/providers/app_state.dart';
import '../../home/widgets/top_bar.dart';
import '../state/llm_state.dart';
import 'chat_history_screen.dart';
import 'model_setup_screen.dart';

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

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _llmState.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    _llmState.removeListener(_onStateChanged);
    // Do NOT dispose the singleton.
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onStateChanged() {
    if (!mounted) return;
    setState(() {});
    // Scroll to the bottom whenever the state changes (new token received).
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
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

  void _sendMessage(bool isArabic) {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    _llmState.sendMessage(text, isArabic: isArabic);
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
              _ModelStatusBanner(
                onSetupTap: _openModelSetup,
                llmState: _llmState,
              ),
              _ChatToolbar(
                onNewChat: _newChat,
                onHistory: _openHistory,
                title: _llmState.conversations.isEmpty
                    ? 'New chat'
                    : _llmState.activeConversation.title,
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
      return _EmptyState(isArabic: isArabic, onSetupTap: _openModelSetup);
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
    final canSend = _llmState.isModelReady && !_llmState.isGenerating;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 110),
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
          Row(
            children: [
              // ── Text field ─────────────────────────────────────────────
              Expanded(
                child: Container(
                  height: 50,
                  decoration: BoxDecoration(
                    color: AppColors.aiAccentPink.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: AppColors.aiAccentPink,
                      width: 1.5,
                    ),
                  ),
                  child: TextField(
                    controller: _controller,
                    enabled: canSend,
                    onSubmitted: canSend ? (_) => _sendMessage(isArabic) : null,
                    decoration: InputDecoration(
                      hintText: !_llmState.isModelReady
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
              const SizedBox(width: 10),

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
    required this.title,
  });

  final VoidCallback onNewChat;
  final VoidCallback onHistory;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textDark.withOpacity(0.7),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            tooltip: 'New chat',
            visualDensity: VisualDensity.compact,
            icon: const Icon(LucideIcons.plus,
                size: 18, color: AppColors.primaryRed),
            onPressed: onNewChat,
          ),
          IconButton(
            tooltip: 'History',
            visualDensity: VisualDensity.compact,
            icon: const Icon(LucideIcons.history,
                size: 18, color: AppColors.primaryRed),
            onPressed: onHistory,
          ),
        ],
      ),
    );
  }
}

// ── Model status banner ────────────────────────────────────────────────────────

class _ModelStatusBanner extends StatelessWidget {
  const _ModelStatusBanner({
    required this.onSetupTap,
    required this.llmState,
  });

  final VoidCallback onSetupTap;
  final LlmState llmState;

  @override
  Widget build(BuildContext context) {
    final status = llmState.modelStatus;

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
  const _EmptyState({required this.isArabic, required this.onSetupTap});

  final bool isArabic;
  final VoidCallback onSetupTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.aiAccentPink.withOpacity(0.3),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                LucideIcons.messageSquare,
                size: 36,
                color: AppColors.primaryRed,
              ),
            )
                .animate()
                .fadeIn(duration: 600.ms)
                .scale(begin: const Offset(0.8, 0.8)),
            const SizedBox(height: 20),
            Text(
              isArabic ? 'اسأل Rescate' : 'Ask Rescate',
              style: GoogleFonts.inter(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ).animate().fadeIn(delay: 100.ms),
            const SizedBox(height: 8),
            Text(
              isArabic
                  ? 'مساعدك الطبي الذكي يعمل بدون إنترنت.'
                  : 'Your offline medical AI assistant.\nLoad a model and start asking questions.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: AppColors.textDark.withOpacity(0.55),
                height: 1.5,
              ),
            ).animate().fadeIn(delay: 200.ms),
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

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final color = isUser ? AppColors.primaryRed : AppColors.cardBackground;
    final textColor = isUser ? Colors.white : AppColors.textDark;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (!isUser)
          CustomPaint(
            size: const Size(12, 16),
            painter: _BubbleTail(color, isLeft: true),
          ),
        Container(
          constraints: const BoxConstraints(maxWidth: 270),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomRight: Radius.circular(isUser ? 0 : 18),
              bottomLeft: Radius.circular(isUser ? 18 : 0),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message.text.isEmpty && message.isStreaming)
                _TypingIndicator(color: textColor)
              else if (!isUser && message.isStreaming) ...[
                _StreamingText(
                  text: message.text,
                  style: GoogleFonts.inter(fontSize: 14, color: textColor),
                ),
                const SizedBox(height: 6),
                _TypingIndicator(color: textColor),
              ] else
                Text(
                  message.text,
                  style: GoogleFonts.inter(fontSize: 14, color: textColor),
                ),
              if (!isUser && !message.isStreaming &&
                  (message.ttftMs != null || message.totalMs != null)) ...[
                const SizedBox(height: 6),
                Text(
                  _formatTimings(message),
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: textColor.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (isUser)
          CustomPaint(
            size: const Size(12, 16),
            painter: _BubbleTail(color, isLeft: false),
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