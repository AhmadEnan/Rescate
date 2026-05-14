import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

/// Утилита для загрузки GGUF моделей с Ollama
class ModelDownloader {
  /// Базовый URL для Ollama
  static const String ollamaBaseUrl = 'https://ollama.com/nativemind/braindler';

  /// Прямые ссылки на GGUF модели (необходимо получить актуальные URL)
  static const Map<String, String> modelUrls = {
    'braindler-q2_k':
        'https://huggingface.co/nativemind/braindler/resolve/main/braindler-q2_k.gguf',
    'braindler-q3_k_s':
        'https://huggingface.co/nativemind/braindler/resolve/main/braindler-q3_k_s.gguf',
    'braindler-q4_k_s':
        'https://huggingface.co/nativemind/braindler/resolve/main/braindler-q4_k_s.gguf',
    'braindler-q5_k_m':
        'https://huggingface.co/nativemind/braindler/resolve/main/braindler-q5_k_m.gguf',
    'braindler-q8_0':
        'https://huggingface.co/nativemind/braindler/resolve/main/braindler-q8_0.gguf',
    'braindler-f16':
        'https://huggingface.co/nativemind/braindler/resolve/main/braindler-f16.gguf',
  };

  /// Загрузить модель по имени
  ///
  /// [modelName] - имя модели из [modelUrls]
  /// [onProgress] - callback для отслеживания прогресса (0.0 - 1.0)
  ///
  /// Возвращает путь к загруженному файлу
  static Future<String> downloadModel(
    String modelName, {
    Function(double progress)? onProgress,
  }) async {
    if (!modelUrls.containsKey(modelName)) {
      throw ArgumentError(
        'Unknown model: $modelName. Available models: ${modelUrls.keys.join(", ")}',
      );
    }

    final url = modelUrls[modelName]!;
    final fileName = '$modelName.gguf';

    // Получаем директорию для хранения моделей
    final directory = await _getModelsDirectory();
    final filePath = path.join(directory.path, fileName);
    final file = File(filePath);

    // Проверяем, не загружена ли уже модель
    if (await file.exists()) {
      print('Model already exists: $filePath');
      return filePath;
    }

    print('Downloading model from: $url');
    print('Saving to: $filePath');

    try {
      // Создаем HTTP запрос
      final request = http.Request('GET', Uri.parse(url));
      final response = await http.Client().send(request);

      if (response.statusCode != 200) {
        throw Exception(
          'Failed to download model: HTTP ${response.statusCode}',
        );
      }

      // Получаем общий размер файла
      final contentLength = response.contentLength ?? 0;
      print('File size: ${_formatBytes(contentLength)}');

      // Загружаем файл с отслеживанием прогресса
      final bytes = <int>[];
      int downloaded = 0;
      int lastReportedMB = 0;

      await for (final chunk in response.stream) {
        bytes.addAll(chunk);
        downloaded += chunk.length;

        if (contentLength > 0 && onProgress != null) {
          final progress = downloaded / contentLength;
          onProgress(progress);

          final currentMB = downloaded ~/ (1024 * 1024);
          if (currentMB > lastReportedMB || downloaded == contentLength) {
            lastReportedMB = currentMB;
            print(
              'Downloaded: ${_formatBytes(downloaded)} / ${_formatBytes(contentLength)} (${(progress * 100).toStringAsFixed(1)}%)',
            );
          }
        }
      }

      // Сохраняем файл
      await file.writeAsBytes(bytes);
      print('Model downloaded successfully: $filePath');

      return filePath;
    } catch (e) {
      print('Error downloading model: $e');
      // Удаляем частично загруженный файл
      if (await file.exists()) {
        await file.delete();
      }
      rethrow;
    }
  }

  /// Получить директорию для хранения моделей
  static Future<Directory> _getModelsDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final modelsDir = Directory(path.join(appDir.path, 'llama_models'));

    if (!await modelsDir.exists()) {
      await modelsDir.create(recursive: true);
    }

    return modelsDir;
  }

  /// Получить список загруженных моделей
  static Future<List<String>> getDownloadedModels() async {
    final directory = await _getModelsDirectory();
    final files = await directory.list().toList();

    return files
        .whereType<File>()
        .where((file) => file.path.endsWith('.gguf'))
        .map((file) => path.basename(file.path))
        .toList();
  }

  /// Удалить модель
  static Future<void> deleteModel(String modelName) async {
    final directory = await _getModelsDirectory();
    final fileName = modelName.endsWith('.gguf')
        ? modelName
        : '$modelName.gguf';
    final filePath = path.join(directory.path, fileName);
    final file = File(filePath);

    if (await file.exists()) {
      await file.delete();
      print('Model deleted: $filePath');
    }
  }

  /// Получить путь к модели (если она загружена)
  static Future<String?> getModelPath(String modelName) async {
    final directory = await _getModelsDirectory();
    final fileName = modelName.endsWith('.gguf')
        ? modelName
        : '$modelName.gguf';
    final filePath = path.join(directory.path, fileName);
    final file = File(filePath);

    if (await file.exists()) {
      return filePath;
    }
    return null;
  }

  /// Форматировать размер в байтах
  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024)
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// Получить информацию о доступных моделях
  static Map<String, ModelInfo> getAvailableModels() {
    return {
      'braindler-q2_k': ModelInfo(
        name: 'braindler-q2_k',
        size: 72 * 1024 * 1024, // 72MB
        quantization: 'Q2_K',
        description: 'Наименьший размер, быстрее всего работает',
      ),
      'braindler-q3_k_s': ModelInfo(
        name: 'braindler-q3_k_s',
        size: 77 * 1024 * 1024, // 77MB
        quantization: 'Q3_K_S',
        description: 'Малый размер с хорошим качеством',
      ),
      'braindler-q4_k_s': ModelInfo(
        name: 'braindler-q4_k_s',
        size: 88 * 1024 * 1024, // 88MB
        quantization: 'Q4_K_S',
        description: 'Сбалансированный вариант',
      ),
      'braindler-q5_k_m': ModelInfo(
        name: 'braindler-q5_k_m',
        size: 103 * 1024 * 1024, // 103MB
        quantization: 'Q5_K_M',
        description: 'Высокое качество',
      ),
      'braindler-q8_0': ModelInfo(
        name: 'braindler-q8_0',
        size: 140 * 1024 * 1024, // 140MB
        quantization: 'Q8_0',
        description: 'Очень высокое качество',
      ),
      'braindler-f16': ModelInfo(
        name: 'braindler-f16',
        size: 256 * 1024 * 1024, // 256MB
        quantization: 'F16',
        description: 'Максимальное качество',
      ),
    };
  }
}

/// Информация о модели
class ModelInfo {
  final String name;
  final int size;
  final String quantization;
  final String description;

  ModelInfo({
    required this.name,
    required this.size,
    required this.quantization,
    required this.description,
  });

  String get sizeFormatted => ModelDownloader._formatBytes(size);
}
