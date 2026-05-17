// packages/audio_voice/lib/src/tts_service.dart

import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Singleton service wrapping the device's native TTS engine.
///
/// Supports automatic language switching between Arabic and English.
/// Arabic dialect is resolved from the system locale with a fallback to
/// Egyptian Arabic (`ar-EG`).
///
/// ### Usage
/// ```dart
/// final tts = TtsService.instance;
/// tts.setEnabled(true);
/// await tts.speak('Hello world', isArabic: false);
/// ```
class TtsService extends ChangeNotifier {
  TtsService._() {
    _init();
  }

  static final TtsService instance = TtsService._();

  FlutterTts? _tts;
  bool _initialized = false;
  bool _enabled = true;
  bool _isSpeaking = false;
  String _arabicLocale = 'ar-EG'; // default to Egyptian Arabic

  // ── Public getters ──────────────────────────────────────────────────────────

  /// Whether auto-read TTS is enabled.
  bool get isEnabled => _enabled;

  /// Whether the engine is currently speaking.
  bool get isSpeaking => _isSpeaking;

  /// The resolved Arabic locale (e.g. `ar-EG`, `ar-SA`).
  String get arabicLocale => _arabicLocale;

  // ── Lifecycle ───────────────────────────────────────────────────────────────

  Future<void> _init() async {
    try {
      _tts = FlutterTts();

      // Use the best available engine quality.
      if (Platform.isAndroid) {
        await _tts!.setQueueMode(1); // QUEUE_ADD so calls don't clobber each other
        // Prefer the highest quality voice synthesis.
        final engines = await _tts!.getEngines;
        if (engines is List && engines.isNotEmpty) {
          debugPrint('[TtsService] Available engines: $engines');
        }
      }

      // Resolve Arabic locale from the system.
      _arabicLocale = _resolveArabicLocale();

      // Set comfortable defaults.
      await _tts!.setSpeechRate(0.5); // moderate pace
      await _tts!.setVolume(1.0);
      await _tts!.setPitch(1.0);

      _tts!.setStartHandler(() {
        _isSpeaking = true;
        notifyListeners();
      });

      _tts!.setCompletionHandler(() {
        _isSpeaking = false;
        notifyListeners();
      });

      _tts!.setCancelHandler(() {
        _isSpeaking = false;
        notifyListeners();
      });

      _tts!.setErrorHandler((msg) {
        debugPrint('[TtsService] Error: $msg');
        _isSpeaking = false;
        notifyListeners();
      });

      _initialized = true;
      debugPrint('[TtsService] Initialized. Arabic locale: $_arabicLocale');
    } catch (e) {
      debugPrint('[TtsService] Init failed: $e');
    }
  }

  /// Toggles auto-read on/off. Persists across the session.
  void setEnabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    if (!_enabled && _isSpeaking) {
      stop();
    }
    notifyListeners();
  }

  // ── TTS actions ─────────────────────────────────────────────────────────────

  /// Speaks [text] using the device's native TTS engine.
  ///
  /// Automatically selects the correct language based on [isArabic].
  /// Does nothing if TTS is disabled via [setEnabled].
  Future<void> speak(String text, {bool isArabic = false}) async {
    if (!_enabled || !_initialized || _tts == null) return;

    final cleaned = _cleanForTts(text);
    if (cleaned.isEmpty) return;

    final locale = isArabic ? _arabicLocale : 'en-US';
    await _tts!.setLanguage(locale);

    // On Android, adjust speech rate slightly for Arabic (tends to be faster).
    if (isArabic) {
      await _tts!.setSpeechRate(0.45);
    } else {
      await _tts!.setSpeechRate(0.5);
    }

    await _tts!.speak(cleaned);
  }

  /// Stops any in-progress speech.
  Future<void> stop() async {
    if (_tts == null) return;
    await _tts!.stop();
    _isSpeaking = false;
    notifyListeners();
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  /// Strip internal system context tags and markdown-style noise that
  /// shouldn't be read aloud.
  String _cleanForTts(String raw) {
    var text = raw;
    // Remove [SYSTEM_VITALS_CONTEXT: …] blocks.
    text = text.replaceAll(RegExp(r'\[SYSTEM_VITALS_CONTEXT:.*?\]'), '');
    // Remove markdown bold/italic markers.
    text = text.replaceAll(RegExp(r'[*_]{1,3}'), '');
    // Collapse multiple whitespace.
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return text;
  }

  /// Resolves the best Arabic locale from the system.
  /// Falls back to `ar-EG` (Egyptian Arabic) if no Arabic locale is set.
  String _resolveArabicLocale() {
    try {
      // PlatformDispatcher gives us the system locale list.
      final locales = PlatformDispatcher.instance.locales;
      for (final locale in locales) {
        if (locale.languageCode == 'ar') {
          final country = locale.countryCode;
          if (country != null && country.isNotEmpty) {
            return 'ar-$country';
          }
          return 'ar-EG'; // Arabic without country → default Egypt
        }
      }
    } catch (e) {
      debugPrint('[TtsService] Locale resolution failed: $e');
    }
    return 'ar-EG';
  }

  @override
  void dispose() {
    _tts?.stop();
    super.dispose();
  }
}
