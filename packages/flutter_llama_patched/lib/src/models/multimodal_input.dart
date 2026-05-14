/// Мультимодальный ввод для поддержки текста, изображений и аудио
class MultimodalInput {
  /// Текстовый промпт
  final String? text;

  /// Путь к изображению
  final String? imagePath;

  /// Путь к аудио файлу
  final String? audioPath;

  /// Тип мультимодального ввода
  final MultimodalType type;

  /// Дополнительные параметры для обработки
  final Map<String, dynamic>? metadata;

  const MultimodalInput({
    this.text,
    this.imagePath,
    this.audioPath,
    required this.type,
    this.metadata,
  });

  /// Создать текстовый ввод
  factory MultimodalInput.text(String text, {Map<String, dynamic>? metadata}) {
    return MultimodalInput(
      text: text,
      type: MultimodalType.text,
      metadata: metadata,
    );
  }

  /// Создать ввод с изображением
  factory MultimodalInput.image(
    String imagePath, {
    String? text,
    Map<String, dynamic>? metadata,
  }) {
    return MultimodalInput(
      text: text,
      imagePath: imagePath,
      type: MultimodalType.image,
      metadata: metadata,
    );
  }

  /// Создать ввод с аудио
  factory MultimodalInput.audio(
    String audioPath, {
    String? text,
    Map<String, dynamic>? metadata,
  }) {
    return MultimodalInput(
      text: text,
      audioPath: audioPath,
      type: MultimodalType.audio,
      metadata: metadata,
    );
  }

  /// Создать смешанный ввод (текст + изображение + аудио)
  factory MultimodalInput.mixed({
    String? text,
    String? imagePath,
    String? audioPath,
    Map<String, dynamic>? metadata,
  }) {
    return MultimodalInput(
      text: text,
      imagePath: imagePath,
      audioPath: audioPath,
      type: MultimodalType.mixed,
      metadata: metadata,
    );
  }

  /// Проверить, содержит ли ввод изображение
  bool get hasImage => imagePath != null && imagePath!.isNotEmpty;

  /// Проверить, содержит ли ввод аудио
  bool get hasAudio => audioPath != null && audioPath!.isNotEmpty;

  /// Проверить, содержит ли ввод текст
  bool get hasText => text != null && text!.isNotEmpty;

  /// Получить все пути к файлам
  List<String> get filePaths {
    final paths = <String>[];
    if (imagePath != null) paths.add(imagePath!);
    if (audioPath != null) paths.add(audioPath!);
    return paths;
  }

  Map<String, dynamic> toMap() {
    return {
      'text': text,
      'imagePath': imagePath,
      'audioPath': audioPath,
      'type': type.name,
      'metadata': metadata,
    };
  }

  factory MultimodalInput.fromMap(Map<String, dynamic> map) {
    return MultimodalInput(
      text: map['text'] as String?,
      imagePath: map['imagePath'] as String?,
      audioPath: map['audioPath'] as String?,
      type: MultimodalType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => MultimodalType.text,
      ),
      metadata: map['metadata'] as Map<String, dynamic>?,
    );
  }

  @override
  String toString() {
    return 'MultimodalInput(text: $text, imagePath: $imagePath, audioPath: $audioPath, type: $type)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MultimodalInput &&
        other.text == text &&
        other.imagePath == imagePath &&
        other.audioPath == audioPath &&
        other.type == type;
  }

  @override
  int get hashCode {
    return Object.hash(text, imagePath, audioPath, type);
  }
}

/// Типы мультимодального ввода
enum MultimodalType {
  /// Только текст
  text,

  /// Текст + изображение
  image,

  /// Текст + аудио
  audio,

  /// Смешанный ввод (текст + изображение + аудио)
  mixed,
}
