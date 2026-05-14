import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'models/llama_config.dart';
import 'models/generation_params.dart';
import 'models/llama_response.dart';
import 'models/model_source.dart';
import 'models/preset_model.dart';
import 'services/model_manager.dart';

/// Main class for interacting with llama.cpp models
class FlutterLlama {
  static const MethodChannel _channel = MethodChannel('flutter_llama');

  static FlutterLlama? _instance;
  bool _isInitialized = false;
  bool _isModelLoaded = false;
  String? _modelPath;

  FlutterLlama._();

  /// Get singleton instance
  static FlutterLlama get instance {
    _instance ??= FlutterLlama._();
    return _instance!;
  }

  /// Check if model is loaded
  bool get isModelLoaded => _isModelLoaded;

  /// Check if instance is initialized
  bool get isInitialized => _isInitialized;

  /// Get current model path
  String? get modelPath => _modelPath;

  /// Initialize and load a GGUF model
  /// 
  /// Returns true if successful, false otherwise
  Future<bool> loadModel(LlamaConfig config) async {
    try {
      if (kDebugMode) {
        print('[FlutterLlama] Loading model: ${config.modelPath}');
      }

      final result = await _channel.invokeMethod<bool>(
        'loadModel',
        config.toMap(),
      );

      _isModelLoaded = result ?? false;
      _isInitialized = _isModelLoaded;
      
      if (_isModelLoaded) {
        _modelPath = config.modelPath;
        if (kDebugMode) {
          print('[FlutterLlama] Model loaded successfully');
          print('[FlutterLlama] Config: $config');
        }
      } else {
        if (kDebugMode) {
          print('[FlutterLlama] Failed to load model');
        }
      }

      return _isModelLoaded;
    } catch (e) {
      if (kDebugMode) {
        print('[FlutterLlama] Error loading model: $e');
      }
      _isModelLoaded = false;
      _isInitialized = false;
      return false;
    }
  }

  /// Generate text from a prompt
  /// 
  /// Returns [LlamaResponse] with generated text and metadata
  Future<LlamaResponse> generate(GenerationParams params) async {
    if (!_isModelLoaded) {
      throw StateError('Model not loaded. Call loadModel() first.');
    }

    try {
      if (kDebugMode) {
        print('[FlutterLlama] Generating with params: $params');
      }

      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'generate',
        params.toMap(),
      );

      if (result == null) {
        throw Exception('Generation returned null result');
      }

      final response = LlamaResponse.fromMap(Map<String, dynamic>.from(result));
      
      if (kDebugMode) {
        print('[FlutterLlama] Generated: $response');
      }

      return response;
    } catch (e) {
      if (kDebugMode) {
        print('[FlutterLlama] Error generating: $e');
      }
      rethrow;
    }
  }

  /// Generate text as a stream (token by token)
  /// 
  /// Returns Stream of strings (individual tokens)
  Stream<String> generateStream(GenerationParams params) async* {
    if (!_isModelLoaded) {
      throw StateError('Model not loaded. Call loadModel() first.');
    }

    try {
      if (kDebugMode) {
        print('[FlutterLlama] Streaming generation with params: $params');
      }

      // Set up event channel for streaming
      final eventChannel = EventChannel('flutter_llama/stream');
      
      // Send generation request after a small delay to ensure native onListen has fired
      Future.delayed(const Duration(milliseconds: 100), () {
        _channel.invokeMethod('generateStream', params.toMap()).catchError((e) {
          if (kDebugMode) print('[FlutterLlama] invokeMethod error: $e');
        });
      });

      // Listen to token stream (this triggers onListen natively)
      await for (final token in eventChannel.receiveBroadcastStream()) {
        if (token is String) {
          yield token;
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('[FlutterLlama] Error in streaming generation: $e');
      }
      rethrow;
    }
  }

  /// Unload the current model and free resources
  Future<void> unloadModel() async {
    try {
      if (kDebugMode) {
        print('[FlutterLlama] Unloading model');
      }

      await _channel.invokeMethod<void>('unloadModel');
      
      _isModelLoaded = false;
      _modelPath = null;
      
      if (kDebugMode) {
        print('[FlutterLlama] Model unloaded successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[FlutterLlama] Error unloading model: $e');
      }
      rethrow;
    }
  }

  /// Get model information
  Future<Map<String, dynamic>?> getModelInfo() async {
    if (!_isModelLoaded) {
      return null;
    }

    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getModelInfo',
      );
      
      return result != null ? Map<String, dynamic>.from(result) : null;
    } catch (e) {
      if (kDebugMode) {
        print('[FlutterLlama] Error getting model info: $e');
      }
      return null;
    }
  }

  /// Stop ongoing generation
  Future<void> stopGeneration() async {
    try {
      await _channel.invokeMethod<void>('stopGeneration');
    } catch (e) {
      if (kDebugMode) {
        print('[FlutterLlama] Error stopping generation: $e');
      }
    }
  }
  
  /// Load model with automatic download from HuggingFace or Ollama
  /// 
  /// This method will:
  /// 1. Check if model is already downloaded
  /// 2. If not, download it from the specified source
  /// 3. Load the model into memory
  /// 
  /// Returns true if successful, false otherwise
  Future<bool> loadModelWithAutoDownload({
    required String modelId,
    ModelSource source = ModelSource.huggingFace,
    String? variant,
    String? specificFile,
    LlamaConfig? config,
    required DownloadProgressCallback onProgress,
    bool autoDownload = true,
  }) async {
    try {
      if (kDebugMode) {
        print('[FlutterLlama] Loading model with auto-download: $modelId');
      }
      
      // Create model manager
      final manager = ModelManager(
        modelId: modelId,
        source: source,
        variant: variant,
        specificFile: specificFile,
      );
      
      // Ensure model is loaded (with auto-download if needed)
      final modelPath = await manager.ensureModelLoaded(
        onProgress: onProgress,
        autoDownload: autoDownload,
      );
      
      if (kDebugMode) {
        print('[FlutterLlama] Model path: $modelPath');
      }
      
      // Create config or use provided one
      final llamaConfig = config ?? LlamaConfig(
        modelPath: modelPath,
        nThreads: 8,
        nGpuLayers: -1, // Use all GPU layers
        contextSize: 2048,
        batchSize: 512,
        useGpu: true,
        verbose: false,
      );
      
      // Load model into llama.cpp
      return await loadModel(llamaConfig.copyWith(modelPath: modelPath));
    } catch (e) {
      if (kDebugMode) {
        print('[FlutterLlama] Error loading model with auto-download: $e');
      }
      return false;
    }
  }
  
  /// Load preset model with automatic download
  /// 
  /// Convenience method for loading predefined models
  Future<bool> loadPresetModel({
    required PresetModel preset,
    LlamaConfig? config,
    required DownloadProgressCallback onProgress,
  }) async {
    return await loadModelWithAutoDownload(
      modelId: preset.id,
      source: preset.source,
      variant: preset.variant,
      specificFile: preset.files.isNotEmpty ? preset.files.first : null,
      config: config,
      onProgress: onProgress,
    );
  }
}





