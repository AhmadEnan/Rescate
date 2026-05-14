/// Ответ от модели llama
class LlamaResponse {
  /// Сгенерированный текст
  final String text;

  /// Количество сгенерированных токенов
  final int tokensGenerated;

  /// Время генерации в миллисекундах
  final int generationTimeMs;

  /// Скорость генерации (токенов в секунду)
  double get tokensPerSecond =>
      generationTimeMs > 0 ? (tokensGenerated * 1000.0) / generationTimeMs : 0.0;

  const LlamaResponse({
    required this.text,
    this.tokensGenerated = 0,
    this.generationTimeMs = 0,
  });

  factory LlamaResponse.fromMap(Map<String, dynamic> map) {
    return LlamaResponse(
      text: map['text'] as String? ?? '',
      tokensGenerated: map['tokensGenerated'] as int? ?? 0,
      generationTimeMs: map['generationTimeMs'] as int? ?? 0,
    );
  }

  @override
  String toString() {
    return 'LlamaResponse(text: ${text.length} chars, tokens: $tokensGenerated, '
        'time: ${generationTimeMs}ms, speed: ${tokensPerSecond.toStringAsFixed(2)} tok/s)';
  }
}





