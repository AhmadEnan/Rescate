import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import '../models/model_source.dart';
import '../models/preset_model.dart';
import 'ollama_downloader.dart';
import 'huggingface_downloader.dart';

/// Унифицированный менеджер моделей
/// 
/// Управляет загрузкой, хранением и доступом к моделям из различных источников
class ModelManager {
  final String modelId;
  final ModelSource source;
  final String? variant;
  final String? specificFile;
  
  late final OllamaDownloader _ollamaDownloader;
  late final HuggingFaceDownloader _huggingFaceDownloader;
  
  ModelManager({
    required this.modelId,
    required this.source,
    this.variant,
    this.specificFile,
    String? ollamaApiUrl,
  }) {
    _ollamaDownloader = OllamaDownloader(
      ollamaApiUrl ?? OllamaDownloader.defaultApiUrl,
    );
    _huggingFaceDownloader = HuggingFaceDownloader();
  }
  
  /// Создать из предустановленной модели
  factory ModelManager.fromPreset(PresetModel preset) {
    return ModelManager(
      modelId: preset.id,
      source: preset.source,
      variant: preset.variant,
      specificFile: preset.files.isNotEmpty ? preset.files.first : null,
    );
  }
  
  /// Получить полное имя модели
  String get fullModelName {
    if (variant != null) {
      return '$modelId:$variant';
    }
    return modelId;
  }
  
  /// Проверить, доступна ли модель локально
  Future<bool> isModelAvailable() async {
    final modelPath = await getModelPath();
    return modelPath != null;
  }
  
  /// Получить путь к модели (если она уже скачана)
  Future<String?> getModelPath() async {
    try {
      switch (source) {
        case ModelSource.huggingFace:
          return await _getHuggingFaceModelPath();
          
        case ModelSource.ollama:
          return await _getOllamaModelPath();
          
        case ModelSource.local:
          return null; // Для локальных файлов путь задается пользователем
      }
    } catch (e) {
      if (kDebugMode) {
        print('[ModelManager] Error getting model path: $e');
      }
      return null;
    }
  }
  
  /// Гарантировать, что модель загружена (с автоматической загрузкой)
  Future<String> ensureModelLoaded({
    required DownloadProgressCallback onProgress,
    bool autoDownload = true,
  }) async {
    // 1. Проверяем локально
    final localPath = await getModelPath();
    
    if (localPath != null) {
      onProgress(const DownloadProgress(
        progress: 1.0,
        status: 'Модель уже загружена',
      ));
      
      if (kDebugMode) {
        print('[ModelManager] Model already available at: $localPath');
      }
      
      return localPath;
    }
    
    // 2. Если нет и разрешена автозагрузка - скачиваем
    if (autoDownload) {
      return await downloadModel(onProgress: onProgress);
    }
    
    // 3. Иначе выбрасываем исключение
    throw ModelNotFoundException(
      fullModelName,
      'Model not found locally and autoDownload is disabled',
    );
  }
  
  /// Скачать модель
  Future<String> downloadModel({
    required DownloadProgressCallback onProgress,
  }) async {
    try {
      if (kDebugMode) {
        print('[ModelManager] Downloading model: $fullModelName from ${source.displayName}');
      }
      
      switch (source) {
        case ModelSource.huggingFace:
          return await _downloadFromHuggingFace(onProgress);
          
        case ModelSource.ollama:
          return await _downloadFromOllama(onProgress);
          
        case ModelSource.local:
          throw Exception('Cannot download local file - use file picker');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[ModelManager] Download failed: $e');
      }
      
      if (e is ModelDownloadException || e is ModelNotFoundException) {
        rethrow;
      }
      
      throw ModelDownloadException(
        fullModelName,
        'Failed to download model',
        e,
      );
    }
  }
  
  /// Удалить модель
  Future<bool> deleteModel() async {
    try {
      switch (source) {
        case ModelSource.huggingFace:
          return await _huggingFaceDownloader.deleteModel(modelId);
          
        case ModelSource.ollama:
          // Для Ollama удаляем экспортированный GGUF файл
          final modelPath = await _getOllamaModelPath();
          if (modelPath != null) {
            final file = File(modelPath);
            if (await file.exists()) {
              await file.delete();
              return true;
            }
          }
          return false;
          
        case ModelSource.local:
          // Локальные файлы не удаляем
          return false;
      }
    } catch (e) {
      if (kDebugMode) {
        print('[ModelManager] Error deleting model: $e');
      }
      return false;
    }
  }
  
  /// Получить размер модели
  Future<int> getModelSize() async {
    try {
      final modelPath = await getModelPath();
      
      if (modelPath == null) {
        return 0;
      }
      
      final file = File(modelPath);
      
      if (!await file.exists()) {
        return 0;
      }
      
      return await file.length();
    } catch (e) {
      if (kDebugMode) {
        print('[ModelManager] Error getting model size: $e');
      }
      return 0;
    }
  }
  
  /// Проверить статус источника (доступность)
  Future<SourceStatus> checkSourceStatus() async {
    switch (source) {
      case ModelSource.huggingFace:
        // Всегда доступен (если есть интернет)
        return SourceStatus(
          isAvailable: true,
          message: 'HuggingFace Hub доступен',
        );
        
      case ModelSource.ollama:
        final available = await _ollamaDownloader.isAvailable();
        return SourceStatus(
          isAvailable: available,
          message: available
              ? 'Ollama запущен и доступен'
              : 'Ollama не запущен. Установите и запустите Ollama.',
        );
        
      case ModelSource.local:
        return SourceStatus(
          isAvailable: true,
          message: 'Локальные файлы доступны',
        );
    }
  }
  
  // Private методы
  
  Future<String?> _getHuggingFaceModelPath() async {
    if (specificFile != null) {
      return await _huggingFaceDownloader.getModelPath(modelId, specificFile!);
    }
    
    // Ищем любой GGUF или SafeTensors файл
    final appDir = await getApplicationDocumentsDirectory();
    final modelDir = Directory(path.join(
      appDir.path,
      'models',
      'huggingface',
      modelId.replaceAll('/', '_'),
    ));
    
    if (!await modelDir.exists()) {
      return null;
    }
    
    await for (final entity in modelDir.list()) {
      if (entity is File) {
        final fileName = path.basename(entity.path);
        if (fileName.endsWith('.gguf') || fileName.endsWith('.safetensors')) {
          return entity.path;
        }
      }
    }
    
    return null;
  }
  
  Future<String?> _getOllamaModelPath() async {
    // Проверяем экспортированный GGUF файл
    final appDir = await getApplicationDocumentsDirectory();
    final modelsDir = Directory(path.join(appDir.path, 'models', 'ollama'));
    
    if (!await modelsDir.exists()) {
      return null;
    }
    
    final fileName = '${fullModelName.replaceAll('/', '_').replaceAll(':', '_')}.gguf';
    final filePath = path.join(modelsDir.path, fileName);
    final file = File(filePath);
    
    if (await file.exists()) {
      return filePath;
    }
    
    // Альтернативно: попробовать получить путь из Ollama хранилища
    return await _ollamaDownloader.getModelPath(fullModelName);
  }
  
  Future<String> _downloadFromHuggingFace(DownloadProgressCallback onProgress) async {
    if (specificFile != null) {
      return await _huggingFaceDownloader.downloadFile(
        modelId: modelId,
        fileName: specificFile!,
        onProgress: onProgress,
      );
    }
    
    // Автоматически найти и скачать GGUF файл
    return await _huggingFaceDownloader.downloadGGUFModel(
      modelId: modelId,
      onProgress: onProgress,
    );
  }
  
  Future<String> _downloadFromOllama(DownloadProgressCallback onProgress) async {
    // Проверяем доступность Ollama
    final status = await checkSourceStatus();
    
    if (!status.isAvailable) {
      throw ModelDownloadException(
        fullModelName,
        'Ollama не доступен. ${status.message}',
      );
    }
    
    // Pull и экспорт модели
    return await _ollamaDownloader.downloadAndExport(
      modelName: fullModelName,
      onProgress: onProgress,
    );
  }
  
  // Статические методы для общего управления
  
  /// Получить список всех скачанных моделей
  static Future<List<DownloadedModelInfo>> getAllDownloadedModels() async {
    final models = <DownloadedModelInfo>[];
    
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final modelsRootDir = Directory(path.join(appDir.path, 'models'));
      
      if (!await modelsRootDir.exists()) {
        return models;
      }
      
      // Проход по источникам
      for (final sourceDir in ['huggingface', 'ollama']) {
        final dir = Directory(path.join(modelsRootDir.path, sourceDir));
        
        if (!await dir.exists()) {
          continue;
        }
        
        await for (final entity in dir.list()) {
          if (entity is Directory) {
            final modelName = path.basename(entity.path);
            var totalSize = 0;
            var fileCount = 0;
            
            await for (final file in entity.list(recursive: true)) {
              if (file is File) {
                totalSize += await file.length();
                fileCount++;
              }
            }
            
            models.add(DownloadedModelInfo(
              modelId: modelName.replaceAll('_', '/'),
              source: sourceDir == 'huggingface'
                  ? ModelSource.huggingFace
                  : ModelSource.ollama,
              path: entity.path,
              size: totalSize,
              fileCount: fileCount,
            ));
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('[ModelManager] Error listing downloaded models: $e');
      }
    }
    
    return models;
  }
  
  /// Очистить все скачанные модели
  static Future<bool> clearAllModels() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final modelsDir = Directory(path.join(appDir.path, 'models'));
      
      if (await modelsDir.exists()) {
        await modelsDir.delete(recursive: true);
        return true;
      }
      
      return false;
    } catch (e) {
      if (kDebugMode) {
        print('[ModelManager] Error clearing models: $e');
      }
      return false;
    }
  }
}

/// Статус источника модели
class SourceStatus {
  final bool isAvailable;
  final String message;
  
  const SourceStatus({
    required this.isAvailable,
    required this.message,
  });
}

/// Информация о скачанной модели
class DownloadedModelInfo {
  final String modelId;
  final ModelSource source;
  final String path;
  final int size;
  final int fileCount;
  
  const DownloadedModelInfo({
    required this.modelId,
    required this.source,
    required this.path,
    required this.size,
    required this.fileCount,
  });
  
  String get sizeFormatted {
    final mb = size / 1024 / 1024;
    if (mb < 1024) {
      return '${mb.toStringAsFixed(1)} MB';
    }
    return '${(mb / 1024).toStringAsFixed(2)} GB';
  }
  
  @override
  String toString() {
    return 'DownloadedModelInfo($modelId, ${source.displayName}, $sizeFormatted, $fileCount files)';
  }
}


