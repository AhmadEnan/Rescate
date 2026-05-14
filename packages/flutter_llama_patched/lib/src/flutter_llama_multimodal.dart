import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'models/generation_params.dart';
import 'models/multimodal_input.dart';
import 'models/multimodal_config.dart';
import 'models/multimodal_response.dart';

/// Мультимодальный класс для работы с llama.cpp моделями
class FlutterLlamaMultimodal {
  static const MethodChannel _channel = MethodChannel(
    'flutter_llama_multimodal',
  );

  static FlutterLlamaMultimodal? _instance;
  bool _isInitialized = false;
  bool _isModelLoaded = false;
  MultimodalConfig? _currentConfig;

  FlutterLlamaMultimodal._();

  /// Get singleton instance
  static FlutterLlamaMultimodal get instance {
    _instance ??= FlutterLlamaMultimodal._();
    return _instance!;
  }

  /// Check if model is loaded
  bool get isModelLoaded => _isModelLoaded;

  /// Check if instance is initialized
  bool get isInitialized => _isInitialized;

  /// Get current multimodal config
  MultimodalConfig? get currentConfig => _currentConfig;

  /// Initialize and load a multimodal GGUF model
  ///
  /// Returns true if successful, false otherwise
  Future<bool> loadMultimodalModel(MultimodalConfig config) async {
    try {
      if (kDebugMode) {
        print(
          '[FlutterLlamaMultimodal] Loading multimodal model: ${config.textModelPath}',
        );
        if (config.mmprojPath != null) {
          print('[FlutterLlamaMultimodal] MMProj path: ${config.mmprojPath}');
        }
      }

      final result = await _channel.invokeMethod<bool>(
        'loadMultimodalModel',
        config.toMap(),
      );

      _isModelLoaded = result ?? false;
      _isInitialized = _isModelLoaded;
      _currentConfig = _isModelLoaded ? config : null;

      if (_isModelLoaded) {
        if (kDebugMode) {
          print(
            '[FlutterLlamaMultimodal] Multimodal model loaded successfully',
          );
          print('[FlutterLlamaMultimodal] Config: $config');
        }
      } else {
        if (kDebugMode) {
          print('[FlutterLlamaMultimodal] Failed to load multimodal model');
        }
      }

      return _isModelLoaded;
    } catch (e) {
      if (kDebugMode) {
        print('[FlutterLlamaMultimodal] Error loading multimodal model: $e');
      }
      _isModelLoaded = false;
      _isInitialized = false;
      _currentConfig = null;
      return false;
    }
  }

  /// Generate text from multimodal input
  ///
  /// Returns [MultimodalResponse] with generated text and metadata
  Future<MultimodalResponse> generateMultimodal(
    MultimodalInput input,
    GenerationParams params,
  ) async {
    if (!_isModelLoaded) {
      throw StateError(
        'Multimodal model not loaded. Call loadMultimodalModel() first.',
      );
    }

    try {
      if (kDebugMode) {
        print(
          '[FlutterLlamaMultimodal] Generating with multimodal input: $input',
        );
        print('[FlutterLlamaMultimodal] Generation params: $params');
      }

      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'generateMultimodal',
        {'input': input.toMap(), 'params': params.toMap()},
      );

      if (result == null) {
        throw Exception('Multimodal generation returned null result');
      }

      final response = MultimodalResponse.fromMap(
        Map<String, dynamic>.from(result),
      );

      if (kDebugMode) {
        print('[FlutterLlamaMultimodal] Generated: $response');
      }

      return response;
    } catch (e) {
      if (kDebugMode) {
        print('[FlutterLlamaMultimodal] Error generating multimodal: $e');
      }
      rethrow;
    }
  }

  /// Generate text as a stream from multimodal input
  ///
  /// Returns Stream of [MultimodalResponse] (token by token)
  Stream<MultimodalResponse> generateMultimodalStream(
    MultimodalInput input,
    GenerationParams params,
  ) async* {
    if (!_isModelLoaded) {
      throw StateError(
        'Multimodal model not loaded. Call loadMultimodalModel() first.',
      );
    }

    try {
      if (kDebugMode) {
        print(
          '[FlutterLlamaMultimodal] Streaming multimodal generation with input: $input',
        );
        print('[FlutterLlamaMultimodal] Generation params: $params');
      }

      // Set up event channel for streaming
      final eventChannel = EventChannel('flutter_llama_multimodal/stream');

      // Send generation request
      await _channel.invokeMethod('generateMultimodalStream', {
        'input': input.toMap(),
        'params': params.toMap(),
      });

      // Listen to response stream
      await for (final responseData in eventChannel.receiveBroadcastStream()) {
        if (responseData is Map) {
          final response = MultimodalResponse.fromMap(
            Map<String, dynamic>.from(responseData),
          );
          yield response;
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print(
          '[FlutterLlamaMultimodal] Error in streaming multimodal generation: $e',
        );
      }
      rethrow;
    }
  }

  /// Process image and get description
  Future<MultimodalResponse> describeImage(
    String imagePath,
    String prompt, {
    GenerationParams? params,
  }) async {
    final input = MultimodalInput.image(imagePath, text: prompt);
    final generationParams = params ?? GenerationParams(prompt: prompt);

    return generateMultimodal(input, generationParams);
  }

  /// Process audio and get transcription/analysis
  Future<MultimodalResponse> processAudio(
    String audioPath,
    String prompt, {
    GenerationParams? params,
  }) async {
    final input = MultimodalInput.audio(audioPath, text: prompt);
    final generationParams = params ?? GenerationParams(prompt: prompt);

    return generateMultimodal(input, generationParams);
  }

  /// Process mixed input (text + image + audio)
  Future<MultimodalResponse> processMixedInput({
    String? text,
    String? imagePath,
    String? audioPath,
    GenerationParams? params,
  }) async {
    final input = MultimodalInput.mixed(
      text: text,
      imagePath: imagePath,
      audioPath: audioPath,
    );
    final generationParams = params ?? GenerationParams(prompt: text ?? '');

    return generateMultimodal(input, generationParams);
  }

  /// Get multimodal model information
  Future<Map<String, dynamic>?> getMultimodalModelInfo() async {
    if (!_isModelLoaded) {
      return null;
    }

    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getMultimodalModelInfo',
      );

      return result != null ? Map<String, dynamic>.from(result) : null;
    } catch (e) {
      if (kDebugMode) {
        print(
          '[FlutterLlamaMultimodal] Error getting multimodal model info: $e',
        );
      }
      return null;
    }
  }

  /// Check if current model supports specific modality
  bool supportsModality(String modality) {
    if (_currentConfig == null) return false;

    switch (modality.toLowerCase()) {
      case 'image':
      case 'vision':
        return _currentConfig!.supportsImages;
      case 'audio':
        return _currentConfig!.supportsAudio;
      case 'text':
        return true;
      default:
        return false;
    }
  }

  /// Get supported modalities
  List<String> getSupportedModalities() {
    if (_currentConfig == null) return ['text'];

    final modalities = <String>['text'];
    if (_currentConfig!.supportsImages) modalities.add('image');
    if (_currentConfig!.supportsAudio) modalities.add('audio');

    return modalities;
  }

  /// Unload the current multimodal model and free resources
  Future<void> unloadMultimodalModel() async {
    try {
      if (kDebugMode) {
        print('[FlutterLlamaMultimodal] Unloading multimodal model');
      }

      await _channel.invokeMethod<void>('unloadMultimodalModel');

      _isModelLoaded = false;
      _currentConfig = null;

      if (kDebugMode) {
        print(
          '[FlutterLlamaMultimodal] Multimodal model unloaded successfully',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('[FlutterLlamaMultimodal] Error unloading multimodal model: $e');
      }
      rethrow;
    }
  }

  /// Stop ongoing multimodal generation
  Future<void> stopMultimodalGeneration() async {
    try {
      await _channel.invokeMethod<void>('stopMultimodalGeneration');
    } catch (e) {
      if (kDebugMode) {
        print(
          '[FlutterLlamaMultimodal] Error stopping multimodal generation: $e',
        );
      }
    }
  }
}

