import 'multimodal_input.dart' show MultimodalType;

/// Мультимодальный ответ от модели
class MultimodalResponse {
  /// Сгенерированный текст
  final String text;

  /// Метаданные о генерации
  final Map<String, dynamic> metadata;

  /// Время генерации в миллисекундах
  final int generationTimeMs;

  /// Количество токенов
  final int tokensGenerated;

  /// Тип мультимодального ввода
  final MultimodalType inputType;

  /// Обработанные модальности
  final List<String> processedModalities;

  /// Дополнительная информация о мультимодальной обработке
  final Map<String, dynamic>? multimodalInfo;

  const MultimodalResponse({
    required this.text,
    required this.metadata,
    required this.generationTimeMs,
    required this.tokensGenerated,
    required this.inputType,
    required this.processedModalities,
    this.multimodalInfo,
  });

  /// Создать ответ только для текста
  factory MultimodalResponse.textOnly({
    required String text,
    required int generationTimeMs,
    required int tokensGenerated,
    Map<String, dynamic>? metadata,
  }) {
    return MultimodalResponse(
      text: text,
      metadata: metadata ?? {},
      generationTimeMs: generationTimeMs,
      tokensGenerated: tokensGenerated,
      inputType: MultimodalType.text,
      processedModalities: ['text'],
    );
  }

  /// Создать ответ с изображением
  factory MultimodalResponse.withImage({
    required String text,
    required int generationTimeMs,
    required int tokensGenerated,
    required List<String> processedModalities,
    Map<String, dynamic>? metadata,
    Map<String, dynamic>? multimodalInfo,
  }) {
    return MultimodalResponse(
      text: text,
      metadata: metadata ?? {},
      generationTimeMs: generationTimeMs,
      tokensGenerated: tokensGenerated,
      inputType: MultimodalType.image,
      processedModalities: processedModalities,
      multimodalInfo: multimodalInfo,
    );
  }

  /// Создать ответ с аудио
  factory MultimodalResponse.withAudio({
    required String text,
    required int generationTimeMs,
    required int tokensGenerated,
    required List<String> processedModalities,
    Map<String, dynamic>? metadata,
    Map<String, dynamic>? multimodalInfo,
  }) {
    return MultimodalResponse(
      text: text,
      metadata: metadata ?? {},
      generationTimeMs: generationTimeMs,
      tokensGenerated: tokensGenerated,
      inputType: MultimodalType.audio,
      processedModalities: processedModalities,
      multimodalInfo: multimodalInfo,
    );
  }

  /// Создать смешанный мультимодальный ответ
  factory MultimodalResponse.mixed({
    required String text,
    required int generationTimeMs,
    required int tokensGenerated,
    required List<String> processedModalities,
    Map<String, dynamic>? metadata,
    Map<String, dynamic>? multimodalInfo,
  }) {
    return MultimodalResponse(
      text: text,
      metadata: metadata ?? {},
      generationTimeMs: generationTimeMs,
      tokensGenerated: tokensGenerated,
      inputType: MultimodalType.mixed,
      processedModalities: processedModalities,
      multimodalInfo: multimodalInfo,
    );
  }

  /// Проверить, содержит ли ответ обработку изображений
  bool get hasImageProcessing => processedModalities.contains('image');

  /// Проверить, содержит ли ответ обработку аудио
  bool get hasAudioProcessing => processedModalities.contains('audio');

  /// Проверить, является ли ответ мультимодальным
  bool get isMultimodal =>
      processedModalities.length > 1 ||
      processedModalities.any((m) => m != 'text');

  /// Получить скорость генерации (токены в секунду)
  double get tokensPerSecond {
    if (generationTimeMs == 0) return 0.0;
    return (tokensGenerated * 1000.0) / generationTimeMs;
  }

  /// Получить информацию о vision обработке
  Map<String, dynamic>? get visionInfo {
    return multimodalInfo?['vision'];
  }

  /// Получить информацию о audio обработке
  Map<String, dynamic>? get audioInfo {
    return multimodalInfo?['audio'];
  }

  Map<String, dynamic> toMap() {
    return {
      'text': text,
      'metadata': metadata,
      'generationTimeMs': generationTimeMs,
      'tokensGenerated': tokensGenerated,
      'inputType': inputType.name,
      'processedModalities': processedModalities,
      'multimodalInfo': multimodalInfo,
    };
  }

  factory MultimodalResponse.fromMap(Map<String, dynamic> map) {
    return MultimodalResponse(
      text: map['text'] as String,
      metadata: Map<String, dynamic>.from(map['metadata'] as Map? ?? {}),
      generationTimeMs: map['generationTimeMs'] as int,
      tokensGenerated: map['tokensGenerated'] as int,
      inputType: MultimodalType.values.firstWhere(
        (e) => e.name == map['inputType'],
        orElse: () => MultimodalType.text,
      ),
      processedModalities: List<String>.from(
        map['processedModalities'] as List? ?? [],
      ),
      multimodalInfo: map['multimodalInfo'] as Map<String, dynamic>?,
    );
  }

  @override
  String toString() {
    return 'MultimodalResponse(text: $text, inputType: $inputType, '
        'processedModalities: $processedModalities, '
        'tokensGenerated: $tokensGenerated, generationTimeMs: $generationTimeMs)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MultimodalResponse &&
        other.text == text &&
        other.inputType == inputType &&
        other.tokensGenerated == tokensGenerated &&
        other.generationTimeMs == generationTimeMs;
  }

  @override
  int get hashCode {
    return Object.hash(text, inputType, tokensGenerated, generationTimeMs);
  }
}

