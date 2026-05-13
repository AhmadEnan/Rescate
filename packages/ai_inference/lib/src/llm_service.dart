// packages/ai_inference/lib/src/llm_service.dart

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_llama/flutter_llama.dart';

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

/// Singleton service that wraps [FlutterLlama] to provide:
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

  final FlutterLlama _llama = FlutterLlama.instance;

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
    if (_status == LlmStatus.generating) {
      throw const LlmException('Cannot load a new model while generating.');
    }

    // Unload any existing model first.
    if (_status == LlmStatus.ready) {
      await _unloadSilently();
    }

    _setStatus(LlmStatus.loading);
    _lastError = null;

    try {
      final config = LlmDefaults.buildConfig(modelPath);
      final success = await _llama.loadModel(config);

      if (!success) {
        throw const LlmException('loadModel returned false — check the model path and format.');
      }

      _loadedModelPath = modelPath;
      _setStatus(LlmStatus.ready);
      debugPrint('[LlmService] Model loaded: $modelPath');
    } catch (e) {
      _lastError = e.toString();
      _loadedModelPath = null;
      _setStatus(LlmStatus.error);
      rethrow;
    }
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
    if (!isReady) {
      throw LlmNotReadyException();
    }

    _setStatus(LlmStatus.generating);

    try {
      final systemPrompt = systemPromptFor(isArabic: isArabic);
      final fullPrompt = buildPrompt(
        systemPrompt: systemPrompt,
        userMessage: userMessage,
      );

      final params = GenerationParams(
        prompt: fullPrompt,
        temperature: LlmDefaults.temperature,
        topP: LlmDefaults.topP,
        topK: LlmDefaults.topK,
        maxTokens: LlmDefaults.maxTokens,
        repeatPenalty: LlmDefaults.repeatPenalty,
      );

      await for (final token in _llama.generateStream(params)) {
        yield token;
      }
    } catch (e) {
      _lastError = e.toString();
      _setStatus(LlmStatus.error);
      throw LlmException('Generation failed: $e');
    } finally {
      // Only reset to ready if we didn't hit an error.
      if (_status == LlmStatus.generating) {
        _setStatus(LlmStatus.ready);
      }
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _setStatus(LlmStatus newStatus) {
    if (_status == newStatus) return;
    _status = newStatus;
    notifyListeners();
  }

  Future<void> _unloadSilently() async {
    try {
      await _llama.unloadModel();
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
