// packages/audio_voice/lib/src/stt_service.dart

import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Status of the [SttService].
enum SttStatus {
  /// Idle — not currently listening.
  idle,

  /// Initializing speech recognition (first-time permission + engine check).
  initializing,

  /// Actively listening for speech.
  listening,

  /// An error occurred (see [SttService.lastError]).
  error,

  /// Speech recognition is not available on this device.
  unavailable,
}

/// Singleton service wrapping the device's native Speech-to-Text engine.
///
/// Supports Arabic and English. The Arabic locale is resolved from the system
/// locale, defaulting to Egyptian Arabic (`ar-EG`).
///
/// ### Usage
/// ```dart
/// final stt = SttService.instance;
/// stt.addListener(() => print(stt.currentWords));
/// await stt.startListening(isArabic: false);
/// ```
class SttService extends ChangeNotifier {
  SttService._();

  static final SttService instance = SttService._();

  final SpeechToText _speech = SpeechToText();
  bool _initialized = false;

  SttStatus _status = SttStatus.idle;
  String? _lastError;

  /// The most recent transcription result (partial or final).
  String _currentWords = '';

  /// The last finalized transcription before the microphone stopped.
  String _finalWords = '';

  String _arabicLocale = 'ar-EG';

  // ── Public getters ──────────────────────────────────────────────────────────

  SttStatus get status => _status;
  String? get lastError => _lastError;
  bool get isListening => _status == SttStatus.listening;

  /// Live transcription (partial + final combined).
  String get currentWords => _currentWords;

  /// Finalized transcription from the last completed session.
  String get finalWords => _finalWords;

  /// The resolved Arabic locale.
  String get arabicLocale => _arabicLocale;

  // ── Lifecycle ───────────────────────────────────────────────────────────────

  /// Initializes the native speech recognition engine and requests microphone
  /// permission. Safe to call multiple times (idempotent after first success).
  Future<bool> initialize() async {
    if (_initialized) return true;

    _setStatus(SttStatus.initializing);

    try {
      final available = await _speech.initialize(
        onError: _onError,
        onStatus: _onStatus,
      );

      if (!available) {
        _setStatus(SttStatus.unavailable);
        _lastError = 'Speech recognition is not available on this device.';
        return false;
      }

      // Resolve Arabic locale from system.
      _arabicLocale = _resolveArabicLocale();

      // Try to find the best matching locale from the engine's supported list.
      final locales = await _speech.locales();
      final arMatch = locales.where((l) => l.localeId.startsWith('ar_')).toList();
      if (arMatch.isNotEmpty) {
        // Prefer system match, otherwise take the first available Arabic locale.
        final systemCountry = _arabicLocale.replaceFirst('ar-', 'ar_');
        final exact = arMatch.where((l) => l.localeId == systemCountry).toList();
        if (exact.isNotEmpty) {
          _arabicLocale = exact.first.localeId.replaceFirst('_', '-');
        } else {
          _arabicLocale = arMatch.first.localeId.replaceFirst('_', '-');
        }
      }

      _initialized = true;
      _setStatus(SttStatus.idle);
      debugPrint('[SttService] Initialized. Arabic locale: $_arabicLocale');
      return true;
    } catch (e) {
      _lastError = e.toString();
      _setStatus(SttStatus.error);
      debugPrint('[SttService] Init failed: $e');
      return false;
    }
  }

  // ── Listening ───────────────────────────────────────────────────────────────

  /// Starts listening for speech.
  ///
  /// Set [isArabic] to `true` to use the Arabic locale.
  /// The [onResult] callback is invoked for every partial/final result.
  /// Returns `false` if initialization fails or speech is unavailable.
  Future<bool> startListening({
    bool isArabic = false,
    void Function(String text, bool isFinal)? onResult,
  }) async {
    if (_status == SttStatus.listening) {
      await stopListening();
    }

    if (!_initialized) {
      final ok = await initialize();
      if (!ok) return false;
    }

    _currentWords = '';
    _finalWords = '';
    _lastError = null;

    final localeId = isArabic
        ? _arabicLocale.replaceFirst('-', '_')
        : 'en_US';

    try {
      _speech.listen(
        onResult: (SpeechRecognitionResult result) {
          _currentWords = result.recognizedWords;
          if (result.finalResult) {
            _finalWords = result.recognizedWords;
          }
          notifyListeners();
          onResult?.call(result.recognizedWords, result.finalResult);
        },
        localeId: localeId,
        listenMode: ListenMode.dictation,
        cancelOnError: true,
        partialResults: true,
      );
      _setStatus(SttStatus.listening);
      return true;
    } catch (e) {
      _lastError = e.toString();
      _setStatus(SttStatus.error);
      debugPrint('[SttService] startListening failed: $e');
      return false;
    }
  }

  /// Stops listening and finalizes the current transcription.
  Future<void> stopListening() async {
    if (!_speech.isListening) return;
    await _speech.stop();
    _setStatus(SttStatus.idle);
  }

  /// Cancels listening without finalizing.
  Future<void> cancel() async {
    await _speech.cancel();
    _currentWords = '';
    _setStatus(SttStatus.idle);
  }

  // ── Internal callbacks ──────────────────────────────────────────────────────

  void _onError(SpeechRecognitionError error) {
    debugPrint('[SttService] Error: ${error.errorMsg} (permanent: ${error.permanent})');
    _lastError = error.errorMsg;
    if (error.permanent) {
      _setStatus(SttStatus.error);
    } else {
      // Transient errors (e.g. no speech detected) just end the session.
      _setStatus(SttStatus.idle);
    }
  }

  void _onStatus(String status) {
    debugPrint('[SttService] Status: $status');
    if (status == 'done' || status == 'notListening') {
      if (_status == SttStatus.listening) {
        _setStatus(SttStatus.idle);
      }
    }
  }

  void _setStatus(SttStatus newStatus) {
    if (_status == newStatus) return;
    _status = newStatus;
    notifyListeners();
  }

  /// Resolves the best Arabic locale from the system.
  /// Falls back to `ar-EG` (Egyptian Arabic) if no Arabic locale is set.
  String _resolveArabicLocale() {
    try {
      final locales = PlatformDispatcher.instance.locales;
      for (final locale in locales) {
        if (locale.languageCode == 'ar') {
          final country = locale.countryCode;
          if (country != null && country.isNotEmpty) {
            return 'ar-$country';
          }
          return 'ar-EG';
        }
      }
    } catch (e) {
      debugPrint('[SttService] Locale resolution failed: $e');
    }
    return 'ar-EG';
  }
}
