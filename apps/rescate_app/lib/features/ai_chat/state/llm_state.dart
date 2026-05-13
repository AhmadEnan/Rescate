// apps/rescate_app/lib/features/ai_chat/state/llm_state.dart

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:ai_inference/ai_inference.dart';

/// Represents a single chat message.
class ChatMessage {
  ChatMessage({
    required this.text,
    required this.isUser,
    this.isStreaming = false,
  });

  /// The accumulated text content of this message.
  String text;

  /// Whether this message was sent by the user (true) or the AI (false).
  final bool isUser;

  /// Whether this AI message is currently receiving streamed tokens.
  bool isStreaming;
}

/// Feature-scoped state for the AI Chat screen.
///
/// Bridges [LlmService] (in `ai_inference` package) to the UI by:
/// - Holding the chat [messages] list.
/// - Exposing [sendMessage] which streams tokens into a growing [ChatMessage].
/// - Propagating [LlmService.status] changes to rebuild listeners.
class LlmState extends ChangeNotifier {
  LlmState() {
    // Mirror LlmService status changes so the UI rebuilds automatically.
    LlmService.instance.addListener(_onServiceChanged);
  }

  final List<ChatMessage> messages = [];

  StreamSubscription<String>? _streamSubscription;

  // ── Forwarded LlmService state ─────────────────────────────────────────────

  LlmStatus get modelStatus => LlmService.instance.status;
  bool get isModelReady => LlmService.instance.isReady;
  bool get isGenerating => LlmService.instance.isGenerating;
  String? get loadedModelPath => LlmService.instance.loadedModelPath;
  String? get modelError => LlmService.instance.lastError;

  // ── Chat actions ───────────────────────────────────────────────────────────

  /// Sends [text] to the LLM and streams the response into [messages].
  ///
  /// [isArabic] selects the Arabic or English system prompt.
  Future<void> sendMessage(String text, {bool isArabic = false}) async {
    if (!isModelReady || isGenerating) return;
    if (text.trim().isEmpty) return;

    // Add user message.
    messages.add(ChatMessage(text: text.trim(), isUser: true));

    // Add a placeholder AI message that will be filled token by token.
    final aiMessage = ChatMessage(text: '', isUser: false, isStreaming: true);
    messages.add(aiMessage);
    notifyListeners();

    try {
      final stream = LlmService.instance.generateStream(
        text.trim(),
        isArabic: isArabic,
      );

      _streamSubscription = stream.listen(
        (token) {
          aiMessage.text += token;
          notifyListeners();
        },
        onDone: () {
          aiMessage.isStreaming = false;
          notifyListeners();
        },
        onError: (Object e) {
          aiMessage.text = 'Error: ${e.toString()}';
          aiMessage.isStreaming = false;
          notifyListeners();
        },
        cancelOnError: true,
      );
    } catch (e) {
      aiMessage.text = 'Error: ${e.toString()}';
      aiMessage.isStreaming = false;
      notifyListeners();
    }
  }

  /// Clears all chat messages.
  void clearHistory() {
    _cancelStream();
    messages.clear();
    notifyListeners();
  }

  // ── Internal ───────────────────────────────────────────────────────────────

  void _onServiceChanged() {
    notifyListeners();
  }

  void _cancelStream() {
    _streamSubscription?.cancel();
    _streamSubscription = null;
  }

  @override
  void dispose() {
    _cancelStream();
    LlmService.instance.removeListener(_onServiceChanged);
    super.dispose();
  }
}
