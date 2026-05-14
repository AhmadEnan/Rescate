/// Конфигурация для мультимодальной модели
class MultimodalConfig {
  /// Путь к основной текстовой модели
  final String textModelPath;

  /// Путь к мультимодальному проектору (mmproj)
  final String? mmprojPath;

  /// Поддержка изображений
  final bool enableVision;

  /// Поддержка аудио
  final bool enableAudio;

  /// Vision энкодер (git, clip, etc.)
  final String visionEncoder;

  /// Audio энкодер (wav2vec2, whisper, etc.)
  final String audioEncoder;

  /// Размер проекции для мультимодальных признаков
  final int projectionDim;

  /// Максимальный размер изображения
  final int maxImageSize;

  /// Максимальная длительность аудио (секунды)
  final int maxAudioDuration;

  /// Использовать ли GPU для мультимодальной обработки
  final bool useGpuForMultimodal;

  /// Дополнительные параметры
  final Map<String, dynamic>? extraParams;

  const MultimodalConfig({
    required this.textModelPath,
    this.mmprojPath,
    this.enableVision = true,
    this.enableAudio = true,
    this.visionEncoder = 'git',
    this.audioEncoder = 'wav2vec2',
    this.projectionDim = 768,
    this.maxImageSize = 224,
    this.maxAudioDuration = 30,
    this.useGpuForMultimodal = true,
    this.extraParams,
  });

  /// Создать конфигурацию только для текста
  factory MultimodalConfig.textOnly(String textModelPath) {
    return MultimodalConfig(
      textModelPath: textModelPath,
      enableVision: false,
      enableAudio: false,
    );
  }

  /// Создать конфигурацию для текста + изображений
  factory MultimodalConfig.textAndImage(
    String textModelPath,
    String mmprojPath,
  ) {
    return MultimodalConfig(
      textModelPath: textModelPath,
      mmprojPath: mmprojPath,
      enableVision: true,
      enableAudio: false,
    );
  }

  /// Создать конфигурацию для текста + аудио
  factory MultimodalConfig.textAndAudio(
    String textModelPath,
    String mmprojPath,
  ) {
    return MultimodalConfig(
      textModelPath: textModelPath,
      mmprojPath: mmprojPath,
      enableVision: false,
      enableAudio: true,
    );
  }

  /// Создать полную мультимодальную конфигурацию
  factory MultimodalConfig.full({
    required String textModelPath,
    required String mmprojPath,
    String visionEncoder = 'git',
    String audioEncoder = 'wav2vec2',
    int projectionDim = 768,
    int maxImageSize = 224,
    int maxAudioDuration = 30,
    bool useGpuForMultimodal = true,
    Map<String, dynamic>? extraParams,
  }) {
    return MultimodalConfig(
      textModelPath: textModelPath,
      mmprojPath: mmprojPath,
      enableVision: true,
      enableAudio: true,
      visionEncoder: visionEncoder,
      audioEncoder: audioEncoder,
      projectionDim: projectionDim,
      maxImageSize: maxImageSize,
      maxAudioDuration: maxAudioDuration,
      useGpuForMultimodal: useGpuForMultimodal,
      extraParams: extraParams,
    );
  }

  /// Проверить, поддерживает ли конфигурация изображения
  bool get supportsImages => enableVision && mmprojPath != null;

  /// Проверить, поддерживает ли конфигурация аудио
  bool get supportsAudio => enableAudio && mmprojPath != null;

  /// Проверить, является ли конфигурация мультимодальной
  bool get isMultimodal => enableVision || enableAudio;

  Map<String, dynamic> toMap() {
    return {
      'textModelPath': textModelPath,
      'mmprojPath': mmprojPath,
      'enableVision': enableVision,
      'enableAudio': enableAudio,
      'visionEncoder': visionEncoder,
      'audioEncoder': audioEncoder,
      'projectionDim': projectionDim,
      'maxImageSize': maxImageSize,
      'maxAudioDuration': maxAudioDuration,
      'useGpuForMultimodal': useGpuForMultimodal,
      'extraParams': extraParams,
    };
  }

  factory MultimodalConfig.fromMap(Map<String, dynamic> map) {
    return MultimodalConfig(
      textModelPath: map['textModelPath'] as String,
      mmprojPath: map['mmprojPath'] as String?,
      enableVision: map['enableVision'] as bool? ?? true,
      enableAudio: map['enableAudio'] as bool? ?? true,
      visionEncoder: map['visionEncoder'] as String? ?? 'git',
      audioEncoder: map['audioEncoder'] as String? ?? 'wav2vec2',
      projectionDim: map['projectionDim'] as int? ?? 768,
      maxImageSize: map['maxImageSize'] as int? ?? 224,
      maxAudioDuration: map['maxAudioDuration'] as int? ?? 30,
      useGpuForMultimodal: map['useGpuForMultimodal'] as bool? ?? true,
      extraParams: map['extraParams'] as Map<String, dynamic>?,
    );
  }

  @override
  String toString() {
    return 'MultimodalConfig(textModelPath: $textModelPath, mmprojPath: $mmprojPath, '
        'enableVision: $enableVision, enableAudio: $enableAudio, '
        'visionEncoder: $visionEncoder, audioEncoder: $audioEncoder)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MultimodalConfig &&
        other.textModelPath == textModelPath &&
        other.mmprojPath == mmprojPath &&
        other.enableVision == enableVision &&
        other.enableAudio == enableAudio &&
        other.visionEncoder == visionEncoder &&
        other.audioEncoder == audioEncoder &&
        other.projectionDim == projectionDim &&
        other.maxImageSize == maxImageSize &&
        other.maxAudioDuration == maxAudioDuration &&
        other.useGpuForMultimodal == useGpuForMultimodal;
  }

  @override
  int get hashCode {
    return Object.hash(
      textModelPath,
      mmprojPath,
      enableVision,
      enableAudio,
      visionEncoder,
      audioEncoder,
      projectionDim,
      maxImageSize,
      maxAudioDuration,
      useGpuForMultimodal,
    );
  }
}
