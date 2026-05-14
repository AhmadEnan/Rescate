/// Параметры для генерации текста
class GenerationParams {
  /// Температура для сэмплинга (0.0 - 2.0, default: 0.8)
  final double temperature;

  /// Top-P сэмплинг (0.0 - 1.0, default: 0.95)
  final double topP;

  /// Top-K сэмплинг (default: 40)
  final int topK;

  /// Максимальное количество токенов для генерации
  final int maxTokens;

  /// Repeat penalty для предотвращения повторов
  final double repeatPenalty;

  /// Промпт для генерации
  final String prompt;

  /// Stop sequences - строки, при которых генерация останавливается
  final List<String> stopSequences;

  const GenerationParams({
    required this.prompt,
    this.temperature = 0.8,
    this.topP = 0.95,
    this.topK = 40,
    this.maxTokens = 512,
    this.repeatPenalty = 1.1,
    this.stopSequences = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      'prompt': prompt,
      'temperature': temperature,
      'topP': topP,
      'topK': topK,
      'maxTokens': maxTokens,
      'repeatPenalty': repeatPenalty,
      'stopSequences': stopSequences,
    };
  }

  @override
  String toString() {
    return 'GenerationParams(temperature: $temperature, topP: $topP, '
        'topK: $topK, maxTokens: $maxTokens, repeatPenalty: $repeatPenalty, '
        'prompt length: ${prompt.length}, stopSequences: $stopSequences)';
  }
}





