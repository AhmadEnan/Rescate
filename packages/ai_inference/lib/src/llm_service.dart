// packages/ai_inference/lib/src/llm_service.dart

import 'dart:async';
import 'dart:io';

import 'package:dev_profiler/dev_profiler.dart';
import 'package:flutter/foundation.dart';
import 'package:llamadart/llamadart.dart';

import 'legacy_rag.dart';
import 'llm_config.dart';

/// Status of the [LlmService] model lifecycle.
enum LlmStatus {
  /// No model has been loaded yet.
  idle,

  /// A model is currently being loaded from disk.
  loading,

  /// Model is loaded and ready for inference.
  ready,

  /// Model is actively generating a response.
  generating,

  /// An unrecoverable error occurred. Check [LlmService.lastError].
  error,
}

/// Singleton service that wraps `llamadart`'s [LlamaEngine] to provide:
/// - Model lifecycle management (load / unload).
/// - Streaming token generation via [generateStream].
/// - Observable [status] and [lastError] for UI state binding.
///
/// ### Usage
/// ```dart
/// final service = LlmService.instance;
/// await service.loadModel('/path/to/model.gguf');
/// await for (final token in service.generateStream('Hello', isArabic: false)) {
///   buffer.write(token);
/// }
/// ```
class LlmService extends ChangeNotifier {
  LlmService._();

  static final LlmService instance = LlmService._();

  LlamaEngine? _engine;

  LlmStatus _status = LlmStatus.idle;
  String? _lastError;
  String? _loadedModelPath;

  // ── Public getters ─────────────────────────────────────────────────────────

  /// Current lifecycle status.
  LlmStatus get status => _status;

  /// The last error message, non-null only when [status] is [LlmStatus.error].
  String? get lastError => _lastError;

  /// Absolute path of the currently loaded model file, or null.
  String? get loadedModelPath => _loadedModelPath;

  /// Returns `true` when the model is loaded and idle (ready to generate).
  bool get isReady => _status == LlmStatus.ready;

  /// Returns `true` when a generation is in progress.
  bool get isGenerating => _status == LlmStatus.generating;

  // ── Model lifecycle ────────────────────────────────────────────────────────

  /// Loads the GGUF model at [modelPath].
  ///
  /// Safe to call multiple times — will unload a previously loaded model first.
  /// Throws [LlmException] if loading fails.
  Future<void> loadModel(String modelPath) async {
    return Profiler.span('llm.loadModel', () async {
      if (_status == LlmStatus.generating) {
        throw const LlmException('Cannot load a new model while generating.');
      }

      // Unload any existing model first.
      if (_status == LlmStatus.ready || _engine != null) {
        await _unloadSilently();
      }

      _setStatus(LlmStatus.loading);
      _lastError = null;

      try {
        _engine = LlamaEngine(LlamaBackend());
        final params = LlmDefaults.buildModelParams();

        await Profiler.span(
          'llm.engine.loadModel',
          () => _engine!.loadModel(modelPath, modelParams: params),
        );

        // Load RAG chunks into memory if not already loaded.
        await Profiler.span('rag.initialize', LegacyRag.initialize);

        _loadedModelPath = modelPath;
        _setStatus(LlmStatus.ready);
        debugPrint('[LlmService] Model loaded: $modelPath');
      } catch (e) {
        _lastError = e.toString();
        _loadedModelPath = null;
        _setStatus(LlmStatus.error);
        rethrow;
      }
    });
  }

  /// Unloads the current model and releases native memory.
  Future<void> unloadModel() async {
    await _unloadSilently();
    _setStatus(LlmStatus.idle);
  }

  // ── Inference ──────────────────────────────────────────────────────────────

  /// Streams generated tokens for [userMessage].
  ///
  /// Prepends the appropriate system prompt (EN or AR) and wraps the combined
  /// text in the instruct prompt format before sending to llama.cpp.
  ///
  /// Throws [LlmNotReadyException] if no model is loaded.
  /// Throws [LlmException] on generation errors.
  Stream<String> generateStream(
    String userMessage, {
    bool isArabic = false,
  }) async* {
    if (!isReady || _engine == null) {
      throw LlmNotReadyException();
    }

    _setStatus(LlmStatus.generating);

    final totalSw = Stopwatch()..start();
    final ttftSw = Stopwatch()..start();
    final rssStart = _profileRssStart();
    var firstTokenSeen = false;
    var tokenCount = 0;

    // KV prefix reuse: rely on llamadart's in-session `reusePromptPrefix`
    // (set on GenerationParams below). The disk-based stateSaveFile/Load
    // path was unsound — the engine's KV at save time held the FULL turn,
    // not just the system prefix, so loading it on the next turn confused
    // the prefix matcher. Revisit only if measurements show a cross-session
    // win is worth the engineering. For now drop it.
    try {
      final chunks = Profiler.spanSync(
        'rag.search',
        () => LegacyRag.search(userMessage, topK: 2),
      );
      Profiler.count('rag.chunks.searched', chunks.length);

      final fullPrompt = Profiler.spanSync(
        'rag.buildPrompt',
        () => LegacyRag.buildPrompt(
          question: userMessage,
          chunks: chunks,
        ),
      );

      const params = GenerationParams(
        temp: LlmDefaults.temperature,
        topP: LlmDefaults.topP,
        topK: LlmDefaults.topK,
        penalty: LlmDefaults.repeatPenalty,
        maxTokens: LlmDefaults.maxTokens,
        reusePromptPrefix: true,
      );

      final stream = _engine!.generate(
        fullPrompt,
        params: params,
      );

      await for (final token in stream) {
        if (!firstTokenSeen) {
          firstTokenSeen = true;
          ttftSw.stop();
          Profiler.event(
            'llm.ttft',
            data: <String, Object?>{'ms': ttftSw.elapsedMilliseconds},
          );
        }
        tokenCount++;
        yield token;
      }
      Profiler.count('llm.tokens', tokenCount);
    } catch (e) {
      _lastError = e.toString();
      _setStatus(LlmStatus.error);
      throw LlmException('Generation failed: $e');
    } finally {
      totalSw.stop();
      _profileRecordGenerateStream(totalSw.elapsedMilliseconds, rssStart);
      // Only reset to ready if we didn't hit an error.
      if (_status == LlmStatus.generating) {
        _setStatus(LlmStatus.ready);
      }
    }
  }

  // Helpers around Profiler for the async* generator (which can't use Profiler.span).
  int _profileRssStart() {
    if (kReleaseMode) return 0;
    try {
      return ProcessInfo.currentRss;
    } catch (_) {
      return 0;
    }
  }

  void _profileRecordGenerateStream(int ms, int rssStart) {
    if (kReleaseMode) return;
    try {
      var delta = 0;
      try {
        delta = ProcessInfo.currentRss - rssStart;
      } catch (_) {}
      Profiler.recordSpan(
        'llm.generateStream.total',
        ms,
        rssDeltaBytes: delta,
      );
    } catch (_) {}
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _setStatus(LlmStatus newStatus) {
    if (_status == newStatus) return;
    _status = newStatus;
    notifyListeners();
  }

  Future<void> _unloadSilently() async {
    try {
      if (_engine != null) {
        await _engine!.dispose();
        _engine = null;
      }
    } catch (e) {
      debugPrint('[LlmService] unload error (ignored): $e');
    }
    _loadedModelPath = null;
  }
}

// ── Exceptions ────────────────────────────────────────────────────────────────

/// Base class for all [LlmService] exceptions.
class LlmException implements Exception {
  const LlmException(this.message);
  final String message;
  @override
  String toString() => 'LlmException: $message';
}

/// Thrown when [LlmService.generateStream] is called without a loaded model.
class LlmNotReadyException extends LlmException {
  LlmNotReadyException()
      : super('No model is loaded. Call LlmService.instance.loadModel() first.');
}
