import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import '../models/model_source.dart';

/// Информация о модели в Ollama
class OllamaModelInfo {
  final String name;
  final String? modifiedAt;
  final int? size;
  final String? digest;
  final Map<String, dynamic>? details;
  
  const OllamaModelInfo({
    required this.name,
    this.modifiedAt,
    this.size,
    this.digest,
    this.details,
  });
  
  factory OllamaModelInfo.fromJson(Map<String, dynamic> json) {
    return OllamaModelInfo(
      name: json['name'] as String,
      modifiedAt: json['modified_at'] as String?,
      size: json['size'] as int?,
      digest: json['digest'] as String?,
      details: json['details'] as Map<String, dynamic>?,
    );
  }
  
  String get sizeFormatted {
    if (size == null) return 'N/A';
    final mb = size! / 1024 / 1024;
    if (mb < 1024) {
      return '${mb.toStringAsFixed(1)} MB';
    }
    return '${(mb / 1024).toStringAsFixed(2)} GB';
  }
}

/// Сервис для работы с Ollama
class OllamaDownloader {
  static const String defaultApiUrl = 'http://localhost:11434';
  static const String defaultModel = 'nativemind/braindler';
  
  final String apiUrl;
  
  OllamaDownloader([this.apiUrl = defaultApiUrl]);
  
  /// Проверить доступность Ollama
  Future<bool> isAvailable() async {
    try {
      final response = await http.get(
        Uri.parse('$apiUrl/api/tags'),
      ).timeout(const Duration(seconds: 3));
      
      return response.statusCode == 200;
    } catch (e) {
      if (kDebugMode) {
        print('[OllamaDownloader] Ollama not available: $e');
      }
      return false;
    }
  }
  
  /// Получить список установленных моделей
  Future<List<OllamaModelInfo>> listModels() async {
    try {
      final response = await http.get(Uri.parse('$apiUrl/api/tags'));
      
      if (response.statusCode != 200) {
        throw Exception('Failed to get models: ${response.statusCode}');
      }
      
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final models = json['models'] as List<dynamic>?;
      
      if (models == null) return [];
      
      return models
          .map((m) => OllamaModelInfo.fromJson(m as Map<String, dynamic>))
          .toList();
    } catch (e) {
      if (kDebugMode) {
        print('[OllamaDownloader] Error listing models: $e');
      }
      rethrow;
    }
  }
  
  /// Проверить, установлена ли модель
  Future<bool> isModelInstalled(String modelName) async {
    try {
      final models = await listModels();
      return models.any((m) => m.name == modelName);
    } catch (e) {
      return false;
    }
  }
  
  /// Pull модель через Ollama API
  Future<void> pullModel({
    required String modelName,
    DownloadProgressCallback? onProgress,
  }) async {
    try {
      if (kDebugMode) {
        print('[OllamaDownloader] Pulling model: $modelName');
      }
      
      final request = http.Request(
        'POST',
        Uri.parse('$apiUrl/api/pull'),
      );
      
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode({
        'name': modelName,
        'stream': true,
      });
      
      final streamedResponse = await request.send();
      
      if (streamedResponse.statusCode != 200) {
        throw Exception('Failed to pull model: ${streamedResponse.statusCode}');
      }
      
      var lastProgress = 0.0;
      
      await for (var chunk in streamedResponse.stream.transform(utf8.decoder)) {
        // Каждая строка - это JSON объект
        final lines = chunk.split('\n').where((line) => line.trim().isNotEmpty);
        
        for (var line in lines) {
          try {
            final json = jsonDecode(line) as Map<String, dynamic>;
            final status = json['status'] as String? ?? 'Загрузка...';
            
            // Вычисляем прогресс
            double progress = 0.0;
            int? completed;
            int? total;
            
            if (json.containsKey('completed') && json.containsKey('total')) {
              completed = json['completed'] as int?;
              total = json['total'] as int?;
              
              if (total != null && total > 0 && completed != null) {
                progress = completed / total;
              }
            } else if (status.contains('success')) {
              progress = 1.0;
            }
            
            // Обновляем прогресс только если изменился
            if (progress != lastProgress || progress == 1.0) {
              lastProgress = progress;
              
              onProgress?.call(DownloadProgress(
                progress: progress,
                status: status,
                downloadedBytes: completed,
                totalBytes: total,
              ));
              
              if (kDebugMode && progress > 0) {
                print('[OllamaDownloader] Progress: ${(progress * 100).toStringAsFixed(1)}% - $status');
              }
            }
          } catch (e) {
            if (kDebugMode) {
              print('[OllamaDownloader] Error parsing progress: $e');
            }
          }
        }
      }
      
      if (kDebugMode) {
        print('[OllamaDownloader] Model pulled successfully: $modelName');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[OllamaDownloader] Error pulling model: $e');
      }
      throw ModelDownloadException(modelName, 'Failed to pull from Ollama', e);
    }
  }
  
  /// Экспортировать модель в GGUF файл через CLI
  Future<String> exportModelToGGUF({
    required String modelName,
    String? outputPath,
  }) async {
    try {
      // Определяем путь для сохранения
      final appDir = await getApplicationDocumentsDirectory();
      final modelsDir = Directory(path.join(appDir.path, 'models', 'ollama'));
      
      if (!await modelsDir.exists()) {
        await modelsDir.create(recursive: true);
      }
      
      final fileName = '${modelName.replaceAll('/', '_').replaceAll(':', '_')}.gguf';
      final finalPath = outputPath ?? path.join(modelsDir.path, fileName);
      
      if (kDebugMode) {
        print('[OllamaDownloader] Exporting model to: $finalPath');
      }
      
      // Проверяем наличие Ollama CLI
      final whichResult = await Process.run('which', ['ollama']);
      if (whichResult.exitCode != 0) {
        throw Exception('Ollama CLI not found. Please install from https://ollama.com');
      }
      
      // Экспортируем модель
      final result = await Process.run('ollama', [
        'export',
        modelName,
        '-o',
        finalPath,
      ]);
      
      if (result.exitCode != 0) {
        throw Exception('Export failed: ${result.stderr}');
      }
      
      if (kDebugMode) {
        print('[OllamaDownloader] Model exported successfully');
        print(result.stdout);
      }
      
      // Проверяем, что файл создан
      final file = File(finalPath);
      if (!await file.exists()) {
        throw Exception('Exported file not found at: $finalPath');
      }
      
      return finalPath;
    } catch (e) {
      if (kDebugMode) {
        print('[OllamaDownloader] Error exporting model: $e');
      }
      throw ModelDownloadException(modelName, 'Failed to export model', e);
    }
  }
  
  /// Получить путь к модели из Ollama хранилища
  Future<String?> getModelPath(String modelName) async {
    try {
      // Ollama хранит модели в ~/.ollama/models
      final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
      if (home == null) return null;
      
      final ollamaDir = path.join(home, '.ollama', 'models', 'blobs');
      final directory = Directory(ollamaDir);
      
      if (!await directory.exists()) {
        return null;
      }
      
      // Получаем информацию о модели через API
      final models = await listModels();
      final model = models.firstWhere(
        (m) => m.name == modelName,
        orElse: () => throw ModelNotFoundException(modelName),
      );
      
      // Извлекаем digest (SHA256 хеш)
      if (model.digest != null) {
        final blobPath = path.join(ollamaDir, model.digest!.replaceFirst('sha256:', 'sha256-'));
        final file = File(blobPath);
        
        if (await file.exists()) {
          if (kDebugMode) {
            print('[OllamaDownloader] Found model at: $blobPath');
          }
          return blobPath;
        }
      }
      
      // Альтернативный поиск GGUF файлов
      await for (final entity in directory.list()) {
        if (entity is File && await _isValidGGUFFile(entity.path)) {
          if (kDebugMode) {
            print('[OllamaDownloader] Found GGUF file: ${entity.path}');
          }
          return entity.path;
        }
      }
      
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('[OllamaDownloader] Error getting model path: $e');
      }
      return null;
    }
  }
  
  /// Полный цикл: pull + export
  Future<String> downloadAndExport({
    required String modelName,
    DownloadProgressCallback? onProgress,
  }) async {
    try {
      // Проверяем доступность Ollama
      if (!await isAvailable()) {
        throw Exception('Ollama is not running. Please start Ollama.');
      }
      
      // Проверяем, установлена ли модель
      final installed = await isModelInstalled(modelName);
      
      if (!installed) {
        // Pull модель
        onProgress?.call(const DownloadProgress(
          progress: 0.0,
          status: 'Загрузка модели через Ollama...',
        ));
        
        await pullModel(
          modelName: modelName,
          onProgress: (progress) {
            // Масштабируем прогресс: 0-80% для pull, 80-100% для export
            final scaledProgress = DownloadProgress(
              progress: progress.progress * 0.8,
              status: progress.status,
              downloadedBytes: progress.downloadedBytes,
              totalBytes: progress.totalBytes,
            );
            onProgress?.call(scaledProgress);
          },
        );
      }
      
      // Экспортируем в GGUF
      onProgress?.call(const DownloadProgress(
        progress: 0.8,
        status: 'Экспорт модели в GGUF...',
      ));
      
      final ggufPath = await exportModelToGGUF(modelName: modelName);
      
      onProgress?.call(const DownloadProgress(
        progress: 1.0,
        status: 'Готово!',
      ));
      
      return ggufPath;
    } catch (e) {
      if (kDebugMode) {
        print('[OllamaDownloader] Error in downloadAndExport: $e');
      }
      rethrow;
    }
  }
  
  /// Проверка валидности GGUF файла
  Future<bool> _isValidGGUFFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return false;
      
      // Проверяем размер (должен быть больше 1MB)
      final size = await file.length();
      if (size < 1024 * 1024) return false;
      
      // Проверяем magic number "GGUF"
      final bytes = await file.openRead(0, 4).first;
      final magic = String.fromCharCodes(bytes);
      
      return magic == 'GGUF' || magic == 'gguf';
    } catch (e) {
      return false;
    }
  }
  
  /// Удалить модель через API
  Future<bool> deleteModel(String modelName) async {
    try {
      final response = await http.delete(
        Uri.parse('$apiUrl/api/delete'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'name': modelName}),
      );
      
      return response.statusCode == 200;
    } catch (e) {
      if (kDebugMode) {
        print('[OllamaDownloader] Error deleting model: $e');
      }
      return false;
    }
  }
  
  /// Получить информацию о доступных вариантах модели
  static Map<String, String> getBraindlerVariants() {
    return {
      'q2_k': '72MB - Самая быстрая',
      'q4_k_s': '88MB - ⭐ Рекомендуется',
      'q5_k_m': '103MB - Выше качество',
      'q8_0': '140MB - Высокое качество',
      'f16': '256MB - Максимальное качество',
    };
  }
}


