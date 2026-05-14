import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

/// Callback для отслеживания прогресса загрузки
typedef ProgressCallback = void Function(double progress, String status);

/// Сервис для скачивания моделей с Hugging Face
class ModelDownloader {
  /// Базовый URL для Hugging Face
  static const String _baseUrl = 'https://huggingface.co';

  /// Скачать модель с Hugging Face
  /// 
  /// [modelId] - идентификатор модели (например, "nativemind/shridhar_8k_multimodal")
  /// [fileName] - имя файла для скачивания (например, "adapter_model.safetensors")
  /// [onProgress] - callback для отслеживания прогресса
  /// 
  /// Возвращает путь к скачанному файлу
  static Future<String> downloadModel({
    required String modelId,
    required String fileName,
    ProgressCallback? onProgress,
  }) async {
    try {
      // Получаем директорию для хранения моделей
      final appDir = await getApplicationDocumentsDirectory();
      final modelsDir = Directory(path.join(appDir.path, 'models'));
      
      // Создаем директорию, если её нет
      if (!await modelsDir.exists()) {
        await modelsDir.create(recursive: true);
      }

      // Создаем поддиректорию для конкретной модели
      final modelDir = Directory(path.join(modelsDir.path, modelId.replaceAll('/', '_')));
      if (!await modelDir.exists()) {
        await modelDir.create(recursive: true);
      }

      final filePath = path.join(modelDir.path, fileName);
      final file = File(filePath);

      // Проверяем, не скачан ли уже файл
      if (await file.exists()) {
        onProgress?.call(1.0, 'Файл уже существует');
        return filePath;
      }

      // Формируем URL для скачивания
      final url = '$_baseUrl/$modelId/resolve/main/$fileName';
      
      onProgress?.call(0.0, 'Подключение к Hugging Face...');
      
      // Создаем запрос
      final request = http.Request('GET', Uri.parse(url));
      final response = await request.send();

      if (response.statusCode != 200) {
        throw Exception('Ошибка загрузки: ${response.statusCode}');
      }

      // Получаем размер файла
      final contentLength = response.contentLength ?? 0;
      var receivedBytes = 0;

      // Открываем файл для записи
      final sink = file.openWrite();

      try {
        await for (var chunk in response.stream) {
          sink.add(chunk);
          receivedBytes += chunk.length;

          // Обновляем прогресс
          if (contentLength > 0) {
            final progress = receivedBytes / contentLength;
            final mb = (receivedBytes / 1024 / 1024).toStringAsFixed(1);
            final totalMb = (contentLength / 1024 / 1024).toStringAsFixed(1);
            onProgress?.call(
              progress,
              'Скачивание: $mb MB / $totalMb MB',
            );
          }
        }
      } finally {
        await sink.close();
      }

      onProgress?.call(1.0, 'Загрузка завершена');
      return filePath;
    } catch (e) {
      onProgress?.call(0.0, 'Ошибка: $e');
      rethrow;
    }
  }

  /// Скачать GGUF модель с Hugging Face
  /// 
  /// Автоматически ищет GGUF файлы в репозитории модели
  static Future<String> downloadGGUFModel({
    required String modelId,
    String? specificFile,
    ProgressCallback? onProgress,
  }) async {
    // Если указан конкретный файл, скачиваем его
    if (specificFile != null) {
      return downloadModel(
        modelId: modelId,
        fileName: specificFile,
        onProgress: onProgress,
      );
    }

    // Иначе ищем GGUF файлы
    try {
      onProgress?.call(0.0, 'Поиск GGUF файлов...');
      
      // Пробуем распространённые имена GGUF файлов
      final commonNames = [
        'model.gguf',
        'ggml-model-q4_0.gguf',
        'ggml-model-q4_1.gguf',
        'ggml-model-q5_0.gguf',
        'ggml-model-q5_1.gguf',
        'ggml-model-q8_0.gguf',
        'ggml-model-f16.gguf',
        '${modelId.split('/').last}.gguf',
      ];

      // Пробуем скачать первый найденный файл
      for (final name in commonNames) {
        try {
          final filePath = await downloadModel(
            modelId: modelId,
            fileName: name,
            onProgress: onProgress,
          );
          return filePath;
        } catch (e) {
          // Продолжаем поиск
          continue;
        }
      }

      throw Exception('GGUF файл не найден для модели $modelId');
    } catch (e) {
      onProgress?.call(0.0, 'Ошибка: $e');
      rethrow;
    }
  }

  /// Получить список скачанных моделей
  static Future<List<String>> getDownloadedModels() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final modelsDir = Directory(path.join(appDir.path, 'models'));

      if (!await modelsDir.exists()) {
        return [];
      }

      final models = <String>[];
      await for (var entity in modelsDir.list()) {
        if (entity is Directory) {
          final modelName = path.basename(entity.path);
          models.add(modelName);
        }
      }

      return models;
    } catch (e) {
      return [];
    }
  }

  /// Получить путь к скачанной модели
  static Future<String?> getModelPath(String modelId, String fileName) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final modelDir = path.join(
        appDir.path,
        'models',
        modelId.replaceAll('/', '_'),
      );
      final filePath = path.join(modelDir, fileName);
      final file = File(filePath);

      if (await file.exists()) {
        return filePath;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Удалить скачанную модель
  static Future<bool> deleteModel(String modelId) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final modelDir = Directory(path.join(
        appDir.path,
        'models',
        modelId.replaceAll('/', '_'),
      ));

      if (await modelDir.exists()) {
        await modelDir.delete(recursive: true);
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Получить размер скачанной модели
  static Future<int> getModelSize(String modelId) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final modelDir = Directory(path.join(
        appDir.path,
        'models',
        modelId.replaceAll('/', '_'),
      ));

      if (!await modelDir.exists()) {
        return 0;
      }

      var totalSize = 0;
      await for (var entity in modelDir.list(recursive: true)) {
        if (entity is File) {
          totalSize += await entity.length();
        }
      }

      return totalSize;
    } catch (e) {
      return 0;
    }
  }
}

// NOTE: PresetModel and PresetModels are now in flutter_llama library
// Import them from 'package:flutter_llama/flutter_llama.dart'

