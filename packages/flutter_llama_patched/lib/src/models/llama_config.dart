/// Конфигурация для инициализации модели llama.cpp
class LlamaConfig {
  /// Путь к файлу модели GGUF
  final String modelPath;

  /// Количество потоков для инференса (по умолчанию: 4)
  final int nThreads;

  /// Количество слоев для GPU (0 = только CPU, -1 = все слои)
  final int nGpuLayers;

  /// Размер контекста в токенах
  final int contextSize;

  /// Размер батча для обработки
  final int batchSize;

  /// Использовать ли Metal (iOS) или GPU акселерацию (Android)
  final bool useGpu;

  /// Verbose логирование
  final bool verbose;

  const LlamaConfig({
    required this.modelPath,
    this.nThreads = 4,
    this.nGpuLayers = 0,
    this.contextSize = 2048,
    this.batchSize = 512,
    this.useGpu = true,
    this.verbose = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'modelPath': modelPath,
      'nThreads': nThreads,
      'nGpuLayers': nGpuLayers,
      'contextSize': contextSize,
      'batchSize': batchSize,
      'useGpu': useGpu,
      'verbose': verbose,
    };
  }

  /// Создать копию конфигурации с изменениями
  LlamaConfig copyWith({
    String? modelPath,
    int? nThreads,
    int? nGpuLayers,
    int? contextSize,
    int? batchSize,
    bool? useGpu,
    bool? verbose,
  }) {
    return LlamaConfig(
      modelPath: modelPath ?? this.modelPath,
      nThreads: nThreads ?? this.nThreads,
      nGpuLayers: nGpuLayers ?? this.nGpuLayers,
      contextSize: contextSize ?? this.contextSize,
      batchSize: batchSize ?? this.batchSize,
      useGpu: useGpu ?? this.useGpu,
      verbose: verbose ?? this.verbose,
    );
  }

  @override
  String toString() {
    return 'LlamaConfig(modelPath: $modelPath, nThreads: $nThreads, '
        'nGpuLayers: $nGpuLayers, contextSize: $contextSize, '
        'batchSize: $batchSize, useGpu: $useGpu, verbose: $verbose)';
  }
}





