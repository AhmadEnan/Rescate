/// Источник модели
enum ModelSource {
  /// HuggingFace Hub
  huggingFace,
  
  /// Ollama (локальная установка или API)
  ollama,
  
  /// Локальный файл
  local,
}

/// Расширение для получения человеко-читаемых названий
extension ModelSourceExtension on ModelSource {
  String get displayName {
    switch (this) {
      case ModelSource.huggingFace:
        return 'HuggingFace';
      case ModelSource.ollama:
        return 'Ollama';
      case ModelSource.local:
        return 'Локальный файл';
    }
  }
  
  String get description {
    switch (this) {
      case ModelSource.huggingFace:
        return 'Скачать с HuggingFace Hub';
      case ModelSource.ollama:
        return 'Использовать Ollama (локально)';
      case ModelSource.local:
        return 'Выбрать файл на устройстве';
    }
  }
  
  String get icon {
    switch (this) {
      case ModelSource.huggingFace:
        return '🤗';
      case ModelSource.ollama:
        return '🦙';
      case ModelSource.local:
        return '📁';
    }
  }
}

/// Исключение при отсутствии модели
class ModelNotFoundException implements Exception {
  final String modelId;
  final String? message;
  
  ModelNotFoundException(this.modelId, [this.message]);
  
  @override
  String toString() {
    return 'ModelNotFoundException: Модель "$modelId" не найдена. ${message ?? ""}';
  }
}

/// Исключение при ошибке загрузки модели
class ModelDownloadException implements Exception {
  final String modelId;
  final String message;
  final dynamic originalError;
  
  ModelDownloadException(this.modelId, this.message, [this.originalError]);
  
  @override
  String toString() {
    return 'ModelDownloadException: Ошибка загрузки "$modelId": $message';
  }
}

/// Информация о прогрессе загрузки
class DownloadProgress {
  final double progress; // 0.0 - 1.0
  final String status;
  final int? downloadedBytes;
  final int? totalBytes;
  
  const DownloadProgress({
    required this.progress,
    required this.status,
    this.downloadedBytes,
    this.totalBytes,
  });
  
  String get progressPercent => '${(progress * 100).toStringAsFixed(1)}%';
  
  String get downloadedMB => downloadedBytes != null 
      ? '${(downloadedBytes! / 1024 / 1024).toStringAsFixed(1)} MB'
      : 'N/A';
  
  String get totalMB => totalBytes != null
      ? '${(totalBytes! / 1024 / 1024).toStringAsFixed(1)} MB'
      : 'N/A';
  
  @override
  String toString() {
    if (downloadedBytes != null && totalBytes != null) {
      return '$status: $downloadedMB / $totalMB ($progressPercent)';
    }
    return '$status: $progressPercent';
  }
}

/// Callback для отслеживания прогресса загрузки
typedef DownloadProgressCallback = void Function(DownloadProgress progress);


