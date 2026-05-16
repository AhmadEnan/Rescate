// apps/rescate_app/lib/features/ai_chat/state/llm_state.dart

import 'dart:async';
import 'dart:convert';

import 'package:ai_inference/ai_inference.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _kPrefsConversationsKey = 'ai_chat.conversations.v1';
const String _kPrefsActiveIdKey = 'ai_chat.active_conversation_id';

class ChatMessage {
  ChatMessage({
    required this.text,
    required this.isUser,
    this.isStreaming = false,
  });

  String text;
  final bool isUser;
  bool isStreaming;

  Map<String, dynamic> toJson() =>
      {'text': text, 'isUser': isUser};

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        text: json['text'] as String? ?? '',
        isUser: json['isUser'] as bool? ?? false,
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
  StreamSubscription<String>? _streamSubscription;

  // ── Forwarded LlmService state ─────────────────────────────────────────────

  LlmStatus get modelStatus => LlmService.instance.status;
  bool get isModelReady => LlmService.instance.isReady;
  bool get isGenerating => LlmService.instance.isGenerating;
  String? get loadedModelPath => LlmService.instance.loadedModelPath;
  String? get modelError => LlmService.instance.lastError;

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
    final match = conversations.where((c) => c.id == id).cast<Conversation?>().firstOrNull;
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

  Future<void> sendMessage(String text, {bool isArabic = false}) async {
    if (!isModelReady || isGenerating) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final convo = activeConversation;

    convo.messages.add(ChatMessage(text: trimmed, isUser: true));
    if (convo.title == 'New chat') {
      convo.title = trimmed.length > 60 ? '${trimmed.substring(0, 60)}…' : trimmed;
    }
    convo.updatedAt = DateTime.now().millisecondsSinceEpoch;

    final aiMessage = ChatMessage(text: '', isUser: false, isStreaming: true);
    convo.messages.add(aiMessage);
    notifyListeners();
    unawaited(_persist());

    try {
      final stream = LlmService.instance.generateStream(trimmed, isArabic: isArabic);

      _streamSubscription = stream.listen(
        (token) {
          aiMessage.text += token;
          convo.updatedAt = DateTime.now().millisecondsSinceEpoch;
          notifyListeners();
        },
        onDone: () {
          aiMessage.isStreaming = false;
          convo.updatedAt = DateTime.now().millisecondsSinceEpoch;
          notifyListeners();
          unawaited(_persist());
        },
        onError: (Object e) {
          aiMessage.text = 'Error: ${e.toString()}';
          aiMessage.isStreaming = false;
          notifyListeners();
          unawaited(_persist());
        },
        cancelOnError: true,
      );
    } catch (e) {
      aiMessage.text = 'Error: ${e.toString()}';
      aiMessage.isStreaming = false;
      notifyListeners();
      unawaited(_persist());
    }
  }

  // ── Persistence ────────────────────────────────────────────────────────────

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kPrefsConversationsKey);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List<dynamic>;
        conversations
          ..clear()
          ..addAll(list.map((e) =>
              Conversation.fromJson(Map<String, dynamic>.from(e as Map))));
        // Any message marked streaming on disk wasn't actually still streaming.
        for (final c in conversations) {
          for (final m in c.messages) {
            m.isStreaming = false;
          }
        }
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
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Drop fully-empty draft conversations from disk so we don't pile up.
      final keep =
          conversations.where((c) => c.messages.isNotEmpty || c == _active).toList();
      final encoded = jsonEncode(keep.map((c) => c.toJson()).toList());
      await prefs.setString(_kPrefsConversationsKey, encoded);
      if (_active != null) {
        await prefs.setString(_kPrefsActiveIdKey, _active!.id);
      } else {
        await prefs.remove(_kPrefsActiveIdKey);
      }
    } catch (e) {
      debugPrint('[LlmState] persist failed: $e');
    }
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
