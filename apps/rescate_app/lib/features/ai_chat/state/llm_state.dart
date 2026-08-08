// apps/rescate_app/lib/features/ai_chat/state/llm_state.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_inference/ai_inference.dart';
import 'package:dev_profiler/dev_profiler.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../tools/tool_definitions.dart';
import '../tools/tool_dispatcher.dart';

const String _kPrefsConversationsKey = 'ai_chat.conversations.v2';
const String _kPrefsActiveIdKey = 'ai_chat.active_conversation_id';

/// Optional widget rendered below a chat bubble — emitted by tool calls that
/// want to surface an action button (e.g. "Open CPR Tutorial").
enum InlineWidgetType { none, cprTutorialButton }

InlineWidgetType _inlineFromSignal(InlineWidgetSignal s) {
  switch (s) {
    case InlineWidgetSignal.cprTutorialButton:
      return InlineWidgetType.cprTutorialButton;
  }
}

class ChatMessage {
  ChatMessage({
    required this.text,
    required this.isUser,
    this.thoughts = '',
    this.isStreaming = false,
    this.isThinking = false,
    this.ttftMs,
    this.totalMs,
    this.inlineWidget = InlineWidgetType.none,
  });

  String text;

  /// Model's chain-of-thought emitted inside `<|channel>thought…<channel|>`.
  /// Shown in a collapsible section of the bubble; NEVER injected back into
  /// the LLM prompt on subsequent turns.
  String thoughts;
  final bool isUser;
  bool isStreaming;

  /// True while the model is still streaming thought tokens (answer hasn't
  /// started). Used by the UI to keep the thoughts disclosure auto-expanded.
  bool isThinking;

  /// Time-to-first-token in ms. Set only for AI messages, after the first token arrives.
  int? ttftMs;

  /// Total wall-clock time from sendMessage to stream-done in ms. AI messages only.
  int? totalMs;

  /// Optional action widget rendered below the bubble (e.g. CPR tutorial button).
  InlineWidgetType inlineWidget;

  Map<String, dynamic> toJson() => {
    'text': text,
    'isUser': isUser,
    if (thoughts.isNotEmpty) 'thoughts': thoughts,
    if (ttftMs != null) 'ttftMs': ttftMs,
    if (totalMs != null) 'totalMs': totalMs,
    if (inlineWidget != InlineWidgetType.none)
      'inlineWidget': inlineWidget.name,
  };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    text: json['text'] as String? ?? '',
    isUser: json['isUser'] as bool? ?? false,
    thoughts: json['thoughts'] as String? ?? '',
    ttftMs: json['ttftMs'] as int?,
    totalMs: json['totalMs'] as int?,
    inlineWidget: InlineWidgetType.values.firstWhere(
      (e) => e.name == (json['inlineWidget'] as String?),
      orElse: () => InlineWidgetType.none,
    ),
  );
}

class Conversation {
  Conversation({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    required this.title,
    required this.messages,
  });

  final String id;
  final int createdAt;
  int updatedAt;
  String title;
  final List<ChatMessage> messages;

  Map<String, dynamic> toJson() => {
    'id': id,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'title': title,
    'messages': messages.map((m) => m.toJson()).toList(),
  };

  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
    id: json['id'] as String,
    createdAt: json['createdAt'] as int,
    updatedAt: json['updatedAt'] as int,
    title: json['title'] as String? ?? 'New chat',
    messages: (json['messages'] as List<dynamic>? ?? [])
        .map((e) => ChatMessage.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
  );
}

/// App-wide chat state. Singleton so tab switches / screen disposal can't
/// destroy in-flight streams or message history.
class LlmState extends ChangeNotifier {
  LlmState._() {
    LlmService.instance.addListener(_onServiceChanged);
    // Fire-and-forget restore; UI listens for notifyListeners after load.
    _restore();
  }

  static final LlmState instance = LlmState._();

  final List<Conversation> conversations = [];
  Conversation? _active;
  bool _restored = false;
  StreamSubscription<LlmToken>? _streamSubscription;
  RescateToolDispatcher? _toolDispatcher;

  /// Wire the tool dispatcher and register tools with LlmService. Called once
  /// at app bootstrap (from RescateApp.initState) when the MeasurementStore
  /// future has resolved.
  void attachToolDispatcher(RescateToolDispatcher dispatcher) {
    _toolDispatcher = dispatcher;
    LlmService.instance.attachToolRegistry(
      ToolRegistry(schemas: kRescateTools, executor: dispatcher.dispatch),
    );
  }

  // ── Forwarded LlmService state ─────────────────────────────────────────────

  LlmStatus get modelStatus => LlmService.instance.status;
  bool get isModelReady => LlmService.instance.isReady;
  bool get isGenerating => LlmService.instance.isGenerating;
  String? get loadedModelPath => LlmService.instance.loadedModelPath;
  String? get modelError => LlmService.instance.lastError;

  bool get canChat => LlmService.instance.isReady;

  // ── Conversations ──────────────────────────────────────────────────────────

  bool get isRestored => _restored;

  Conversation get activeConversation {
    final existing = _active;
    if (existing != null) return existing;
    final created = _newConversation();
    conversations.insert(0, created);
    _active = created;
    return created;
  }

  List<ChatMessage> get messages => activeConversation.messages;

  Conversation _newConversation() {
    final now = DateTime.now().millisecondsSinceEpoch;
    return Conversation(
      id: 'c_${now}_${conversations.length}',
      createdAt: now,
      updatedAt: now,
      title: 'New chat',
      messages: [],
    );
  }

  Future<void> startNewConversation() async {
    if (isGenerating) {
      _cancelStream();
    }
    // Drop any leading empty draft to avoid clutter.
    if (_active != null && _active!.messages.isEmpty) {
      conversations.remove(_active);
    }
    final fresh = _newConversation();
    conversations.insert(0, fresh);
    _active = fresh;
    await _persist();
    notifyListeners();
  }

  Future<void> selectConversation(String id) async {
    final match = conversations
        .where((c) => c.id == id)
        .cast<Conversation?>()
        .firstOrNull;
    if (match == null) return;
    if (isGenerating) {
      _cancelStream();
    }
    _active = match;
    await _persist();
    notifyListeners();
  }

  Future<void> deleteConversation(String id) async {
    final wasActive = _active?.id == id;
    conversations.removeWhere((c) => c.id == id);
    if (wasActive) {
      _active = conversations.isNotEmpty ? conversations.first : null;
    }
    await _persist();
    notifyListeners();
  }

  // ── Chat actions ───────────────────────────────────────────────────────────

  Future<void> tryAutoLoadModel() async {
    final svc = LlmService.instance;
    if (svc.status == LlmStatus.loading ||
        svc.status == LlmStatus.generating ||
        svc.isReady) {
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final path = prefs.getString('ai_chat.model_path');
      if (path == null || path.isEmpty) {
        debugPrint('[LlmState] tryAutoLoadModel: no saved model path');
        return;
      }
      if (!await File(path).exists()) {
        debugPrint('[LlmState] tryAutoLoadModel: file missing: $path');
        return;
      }

      // Crash-loop guard: if the previous attempt for this model already
      // walked every fallback rung, refuse to auto-retry. The user reaches
      // the model-setup screen which surfaces the diagnostic banner and the
      // Safe-mode toggle.
      final LoadAttempt? previous = await LlmLoadDiagnostics.readAttempt();
      if (previous != null && previous.modelPath == path) {
        // The number of rungs is fixed at 5; if the marker is at or past the
        // last index there is nothing left for loadModel to try.
        if (previous.nextRungAfterCrash >= 5) {
          debugPrint(
            '[LlmState] tryAutoLoadModel: previous attempt exhausted ladder — '
            'skipping auto-load. ($previous)',
          );
          return;
        }
        debugPrint(
          '[LlmState] tryAutoLoadModel: resuming after previous crash at $previous',
        );
      }

      // Pre-warm RAG chunks in parallel (idempotent — safe to call multiple times).
      unawaited(LegacyRag.initialize());
      await Profiler.span('chat.autoLoadModel', () => svc.loadModel(path));
    } catch (e) {
      debugPrint('[LlmState] tryAutoLoadModel failed: $e');
    }
  }

  Future<void> sendMessage(String text, {bool isArabic = false}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    if (!isModelReady) return;
    if (isGenerating) return;

    final convo = activeConversation;

    convo.messages.add(ChatMessage(text: trimmed, isUser: true));
    if (convo.title == 'New chat') {
      convo.title = trimmed.length > 60
          ? '${trimmed.substring(0, 60)}…'
          : trimmed;
    }
    convo.updatedAt = DateTime.now().millisecondsSinceEpoch;

    final aiMessage = ChatMessage(
      text: '',
      isUser: false,
      isStreaming: true,
      // The model may emit a thought channel, but visible answers are always
      // kept separate from any hidden reasoning.
      isThinking: true,
    );
    convo.messages.add(aiMessage);
    notifyListeners();
    unawaited(_persist());

    final sendSw = Stopwatch()..start();
    var firstToken = true;
    // Word-boundary buffer: collect raw tokens (often subword pieces) and only
    // flush to the destination string when a natural break appears, or after
    // a small length cap. Makes streaming look like word-by-word typing
    // instead of character-by-character jitter. We keep one buffer per
    // channel so a mid-token channel switch never bleeds across.
    final answerBuffer = StringBuffer();
    final thoughtBuffer = StringBuffer();
    const flushChars = <int>{
      0x20, 0x09, 0x0A, 0x0D, // space, tab, LF, CR
      0x2C, 0x2E, 0x3B, 0x3A, 0x21, 0x3F, // , . ; : ! ?
      0x060C, 0x061B, 0x061F, // Arabic comma, semicolon, question mark
    };
    void flushAnswer() {
      if (answerBuffer.isEmpty) return;
      aiMessage.text += answerBuffer.toString();
      answerBuffer.clear();
      convo.updatedAt = DateTime.now().millisecondsSinceEpoch;
      notifyListeners();
    }

    void flushThought() {
      if (thoughtBuffer.isEmpty) return;
      aiMessage.thoughts += thoughtBuffer.toString();
      thoughtBuffer.clear();
      convo.updatedAt = DateTime.now().millisecondsSinceEpoch;
      notifyListeners();
    }

    // ── Real model path ──────────────────────────────────────────────────
    final trace = Profiler.openTrace(
      'chat.turn',
      data: <String, Object?>{'lang': isArabic ? 'ar' : 'en'},
    );
    final prepareStep = trace?.begin('chat.prepare');
    try {
      final dispatcher = _toolDispatcher;
      final useTools = dispatcher != null && shouldUseRescateTools(trimmed);
      // Drain any leftover inline-widget signals from a previous turn so they
      // don't bleed into this one.
      dispatcher?.pendingInlineWidgets.clear();
      prepareStep?.op(1);
      prepareStep?.end();
      final stream = useTools
          ? LlmService.instance.generateStreamWithTools(
              trimmed,
              isArabic: isArabic,
              trace: trace,
            )
          : LlmService.instance.generateStream(
              trimmed,
              isArabic: isArabic,
              trace: trace,
            );

      _streamSubscription = stream.listen(
        (tok) {
          if (firstToken) {
            firstToken = false;
            final ttft = sendSw.elapsedMilliseconds;
            aiMessage.ttftMs = ttft;
            Profiler.event(
              'chat.firstToken',
              data: <String, Object?>{'ms': ttft},
            );
          }
          final text = tok.text;
          if (text.isEmpty) return;
          if (tok.channel == LlmChannel.thought) {
            thoughtBuffer.write(text);
            final last = text.codeUnitAt(text.length - 1);
            if (flushChars.contains(last) || thoughtBuffer.length >= 16) {
              flushThought();
              Profiler.count('chat.flush_thought', 1);
            }
          } else {
            // First answer token — the model is done thinking. Flush any
            // pending thought fragment so the UI collapses cleanly, then
            // route the rest of the stream to the answer.
            if (aiMessage.isThinking) {
              flushThought();
              aiMessage.isThinking = false;
              notifyListeners();
            }
            answerBuffer.write(text);
            final last = text.codeUnitAt(text.length - 1);
            if (flushChars.contains(last) || answerBuffer.length >= 16) {
              flushAnswer();
              Profiler.count('chat.flush_answer', 1);
            }
          }
        },
        onDone: () {
          flushThought();
          flushAnswer();
          // Drain any inline-widget signals raised by tool executors this
          // turn. We keep the first only — multiple signals in one turn are
          // unexpected for MVP.
          final pending =
              _toolDispatcher?.pendingInlineWidgets ??
              const <PendingInlineWidget>[];
          if (pending.isNotEmpty) {
            aiMessage.inlineWidget = _inlineFromSignal(pending.first.type);
            _toolDispatcher?.pendingInlineWidgets.clear();
          }
          sendSw.stop();
          final total = sendSw.elapsedMilliseconds;
          aiMessage.totalMs = total;
          Profiler.recordSpan('chat.sendMessage', total);
          final finalizeStep = trace?.begin('chat.finalize');
          finalizeStep?.op(1);
          finalizeStep?.end();
          trace?.end();
          aiMessage.isStreaming = false;
          aiMessage.isThinking = false;
          convo.updatedAt = DateTime.now().millisecondsSinceEpoch;
          notifyListeners();
          unawaited(_persist());
          unawaited(Profiler.exportJson(label: 'chat_turn'));
        },
        onError: (Object e) {
          flushThought();
          flushAnswer();
          aiMessage.text = 'Error: ${e.toString()}';
          aiMessage.isStreaming = false;
          aiMessage.isThinking = false;
          trace?.end();
          notifyListeners();
          unawaited(_persist());
        },
        cancelOnError: true,
      );
    } catch (e) {
      aiMessage.text = 'Error: ${e.toString()}';
      aiMessage.isStreaming = false;
      aiMessage.isThinking = false;
      trace?.end();
      notifyListeners();
      unawaited(_persist());
    }
  }

  // ── Persistence ────────────────────────────────────────────────────────────

  Future<void> _restore() async {
    await Profiler.span('chat.restore', () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString(_kPrefsConversationsKey);
        if (raw != null && raw.isNotEmpty) {
          final list = jsonDecode(raw) as List<dynamic>;
          conversations
            ..clear()
            ..addAll(
              list.map(
                (e) =>
                    Conversation.fromJson(Map<String, dynamic>.from(e as Map)),
              ),
            );
          // Any message marked streaming/thinking on disk wasn't actually still
          // active — the stream died with the process.
          for (final c in conversations) {
            for (final m in c.messages) {
              m.isStreaming = false;
              m.isThinking = false;
            }
          }
          Profiler.count('chat.restored_messages', conversations.length);
        }
        final activeId = prefs.getString(_kPrefsActiveIdKey);
        if (activeId != null) {
          final match = conversations
              .where((c) => c.id == activeId)
              .cast<Conversation?>()
              .firstOrNull;
          if (match != null) _active = match;
        }
        _active ??= conversations.isNotEmpty ? conversations.first : null;
      } catch (e) {
        debugPrint('[LlmState] restore failed: $e');
      } finally {
        _restored = true;
        notifyListeners();
      }
    });
  }

  Future<void> _persist() async {
    await Profiler.span('chat.persist', () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        // Drop fully-empty draft conversations from disk so we don't pile up.
        final keep = conversations
            .where((c) => c.messages.isNotEmpty || c == _active)
            .toList();
        final encoded = jsonEncode(keep.map((c) => c.toJson()).toList());
        Profiler.count('chat.persist.bytes', encoded.length);
        await prefs.setString(_kPrefsConversationsKey, encoded);
        if (_active != null) {
          await prefs.setString(_kPrefsActiveIdKey, _active!.id);
        } else {
          await prefs.remove(_kPrefsActiveIdKey);
        }
      } catch (e) {
        debugPrint('[LlmState] persist failed: $e');
      }
    });
  }

  // ── Internal ───────────────────────────────────────────────────────────────

  void _onServiceChanged() {
    notifyListeners();
  }

  void _cancelStream() {
    _streamSubscription?.cancel();
    _streamSubscription = null;
    for (final c in conversations) {
      for (final m in c.messages) {
        if (m.isStreaming) m.isStreaming = false;
        if (m.isThinking) m.isThinking = false;
      }
    }
  }

  @override
  void dispose() {
    // Singleton — should generally not be disposed during app lifetime.
    _cancelStream();
    LlmService.instance.removeListener(_onServiceChanged);
    super.dispose();
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
