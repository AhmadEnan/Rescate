import 'dart:io';
import 'package:flutter/foundation.dart';
// import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

/// Helper class for downloading GGUF models from Ollama
class OllamaModelDownloader {
  static const String ollamaBaseUrl = 'https://ollama.com';
  static const String defaultModel = 'nativemind/braindler';

  /// Available Braindler model variants
  static const Map<String, String> braindlerModels = {
    'q2_k': 'braindler-q2_k.gguf',
    'q3_k_s': 'braindler-q3_k_s.gguf',
    'q4_k_s': 'braindler-q4_k_s.gguf',
    'q5_k_m': 'braindler-q5_k_m.gguf',
    'q8_0': 'braindler-q8_0.gguf',
    'f16': 'braindler-f16.gguf',
    'latest': 'braindler-latest.gguf',
  };

  /// Download a model from Ollama
  ///
  /// [variant] - Model variant (q2_k, q3_k_s, q4_k_s, q5_k_m, q8_0, f16, latest)
  /// [destinationPath] - Where to save the model
  /// [onProgress] - Optional progress callback (0.0 to 1.0)
  ///
  /// Returns the path to the downloaded model
  static Future<String> downloadModel({
    String variant = 'q2_k',
    required String destinationPath,
    void Function(double progress)? onProgress,
  }) async {
    if (!braindlerModels.containsKey(variant)) {
      throw ArgumentError('Invalid model variant: $variant. '
          'Available: ${braindlerModels.keys.join(", ")}');
    }

    final fileName = braindlerModels[variant]!;
    final modelUrl = _getModelDownloadUrl(variant);
    final outputFile = path.join(destinationPath, fileName);

    if (kDebugMode) {
      print('[OllamaDownloader] Downloading $variant variant...');
      print('[OllamaDownloader] From: $modelUrl');
      print('[OllamaDownloader] To: $outputFile');
    }

    // Create directory if it doesn't exist
    final dir = Directory(destinationPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    // Check if file already exists
    final file = File(outputFile);
    if (await file.exists()) {
      if (kDebugMode) {
        print('[OllamaDownloader] Model already exists at $outputFile');
      }
      return outputFile;
    }

    try {
      // Download the model using HttpClient
      final httpClient = HttpClient();
      final request = await httpClient.getUrl(Uri.parse(modelUrl));
      final response = await request.close();

      final contentLength = response.contentLength;
      var downloadedBytes = 0;

      final sink = file.openWrite();

      await for (final chunk in response) {
        sink.add(chunk);
        downloadedBytes += chunk.length;

        if (contentLength > 0 && onProgress != null) {
          final progress = downloadedBytes / contentLength;
          onProgress(progress);

          if (kDebugMode && (downloadedBytes ~/ (1024 * 1024)) % 10 == 0) {
            print(
                '[OllamaDownloader] Downloaded: ${(downloadedBytes / (1024 * 1024)).toStringAsFixed(2)} MB');
          }
        }
      }

      await sink.close();
      httpClient.close();

      if (kDebugMode) {
        print('[OllamaDownloader] Download completed: $outputFile');
        final fileSize = await file.length();
        print(
            '[OllamaDownloader] File size: ${(fileSize / (1024 * 1024)).toStringAsFixed(2)} MB');
      }

      return outputFile;
    } catch (e) {
      if (kDebugMode) {
        print('[OllamaDownloader] Download failed: $e');
      }

      // Clean up partial download
      if (await file.exists()) {
        await file.delete();
      }

      rethrow;
    }
  }

  /// Get the download URL for a specific model variant
  static String _getModelDownloadUrl(String variant) {
    // This is a placeholder URL structure
    // In reality, you would need to query Ollama API to get the actual download URL
    // For now, we'll construct a hypothetical URL
    return '$ollamaBaseUrl/api/blobs/sha256-$variant';
  }

  /// Pull model using Ollama CLI (if installed)
  ///
  /// This method assumes Ollama is installed on the system
  static Future<String> pullModelWithOllama({
    String model = '$defaultModel:q2_k',
    required String destinationPath,
  }) async {
    if (kDebugMode) {
      print('[OllamaDownloader] Pulling model using Ollama CLI: $model');
    }

    try {
      // Check if Ollama is installed
      final which = await Process.run('which', ['ollama']);
      if (which.exitCode != 0) {
        throw Exception(
            'Ollama CLI not found. Please install Ollama from https://ollama.com');
      }

      // Pull the model
      if (kDebugMode) {
        print('[OllamaDownloader] Running: ollama pull $model');
      }

      final result = await Process.run('ollama', ['pull', model]);

      if (result.exitCode != 0) {
        throw Exception('Failed to pull model: ${result.stderr}');
      }

      if (kDebugMode) {
        print('[OllamaDownloader] Model pulled successfully');
        print(result.stdout);
      }

      // Get model path from Ollama
      final showResult =
          await Process.run('ollama', ['show', model, '--modelfile']);
      if (showResult.exitCode != 0) {
        throw Exception('Failed to get model info: ${showResult.stderr}');
      }

      // Parse model path (this is platform-specific)
      final modelPath = _parseModelPath(showResult.stdout.toString(), model);

      // Copy to destination if needed
      if (modelPath != null && modelPath != destinationPath) {
        final sourceFile = File(modelPath);
        if (await sourceFile.exists()) {
          final fileName = path.basename(modelPath);
          final destFile = path.join(destinationPath, fileName);
          await sourceFile.copy(destFile);

          if (kDebugMode) {
            print('[OllamaDownloader] Model copied to: $destFile');
          }

          return destFile;
        }
      }

      return modelPath ?? '';
    } catch (e) {
      if (kDebugMode) {
        print('[OllamaDownloader] Error pulling model with Ollama: $e');
      }
      rethrow;
    }
  }

  /// Extract GGUF model path from Ollama's stored models
  static Future<String?> getOllamaModelPath(String model) async {
    try {
      // Ollama stores models in ~/.ollama/models on Unix-like systems
      final home =
          Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
      if (home == null) return null;

      final ollamaDir = path.join(home, '.ollama', 'models');
      final ollamaDirectory = Directory(ollamaDir);

      if (!await ollamaDirectory.exists()) {
        return null;
      }

      // Search for GGUF files
      await for (final entity in ollamaDirectory.list(recursive: true)) {
        if (entity is File && entity.path.toLowerCase().endsWith('.gguf')) {
          if (kDebugMode) {
            print('[OllamaDownloader] Found GGUF model: ${entity.path}');
          }
          return entity.path;
        }
      }

      return null;
    } catch (e) {
      if (kDebugMode) {
        print('[OllamaDownloader] Error finding Ollama model: $e');
      }
      return null;
    }
  }

  static String? _parseModelPath(String output, String model) {
    // Try to extract model path from Ollama output
    // This is a simplified version and might need adjustment based on actual output
    final lines = output.split('\n');
    for (final line in lines) {
      if (line.toLowerCase().contains('from') ||
          line.toLowerCase().contains('model')) {
        // Extract path-like string
        final pathRegex = RegExp(r'([/~][\w\-./]+\.gguf)');
        final match = pathRegex.firstMatch(line);
        if (match != null) {
          return match.group(1);
        }
      }
    }
    return null;
  }

  /// Check if a model file is valid GGUF format
  static Future<bool> isValidGGUFFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return false;

      // Check file size (GGUF files should be reasonably large)
      final size = await file.length();
      if (size < 1024 * 1024) return false; // Less than 1MB is suspicious

      // Check GGUF magic number (first 4 bytes should be "GGUF")
      final bytes = await file.openRead(0, 4).first;
      final magic = String.fromCharCodes(bytes);

      return magic == 'GGUF' || magic == 'gguf';
    } catch (e) {
      if (kDebugMode) {
        print('[OllamaDownloader] Error validating GGUF file: $e');
      }
      return false;
    }
  }

  /// Get information about available Braindler models
  static Map<String, dynamic> getModelInfo(String variant) {
    final sizes = {
      'q2_k': '72MB',
      'q3_k_s': '77MB',
      'q4_k_s': '88MB',
      'q5_k_m': '103MB',
      'q8_0': '140MB',
      'f16': '256MB',
      'latest': '94MB',
    };

    return {
      'variant': variant,
      'fileName': braindlerModels[variant] ?? 'unknown',
      'size': sizes[variant] ?? 'unknown',
      'contextSize': '2K',
      'model': 'nativemind/braindler',
    };
  }

  /// List all available model variants
  static List<String> getAvailableVariants() {
    return braindlerModels.keys.toList();
  }
}
