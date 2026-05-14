import 'package:flutter/material.dart';
import 'package:flutter_llama/flutter_llama.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

/// Пример использования мультимодальной модели Shridhar
class MultimodalExample extends StatefulWidget {
  const MultimodalExample({Key? key}) : super(key: key);

  @override
  State<MultimodalExample> createState() => _MultimodalExampleState();
}

class _MultimodalExampleState extends State<MultimodalExample> {
  final FlutterLlamaMultimodal _llama = FlutterLlamaMultimodal.instance;
  bool _isLoading = false;
  bool _isModelLoaded = false;
  String _output = '';
  String _status = 'Готов к загрузке модели';

  @override
  void initState() {
    super.initState();
    _loadMultimodalModel();
  }

  /// Загрузка мультимодальной модели
  Future<void> _loadMultimodalModel() async {
    setState(() {
      _isLoading = true;
      _status = 'Загружаю мультимодальную модель...';
    });

    try {
      // Получаем путь к assets
      final documentsDir = await getApplicationDocumentsDirectory();
      final modelPath = '${documentsDir.path}/shridhar_multimodal_gguf';

      // Создаем конфигурацию для мультимодальной модели
      final config = MultimodalConfig.full(
        textModelPath: '$modelPath/text_model',
        mmprojPath: '$modelPath/mmproj-shridhar_multimodal.gguf',
        visionEncoder: 'git',
        audioEncoder: 'wav2vec2',
        projectionDim: 768,
        maxImageSize: 224,
        maxAudioDuration: 30,
      );

      final success = await _llama.loadMultimodalModel(config);

      setState(() {
        _isLoading = false;
        _isModelLoaded = success;
        _status = success
            ? 'Модель загружена успешно'
            : 'Ошибка загрузки модели';
      });

      if (success) {
        _showSupportedModalities();
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _status = 'Ошибка: $e';
      });
    }
  }

  /// Показать поддерживаемые модальности
  void _showSupportedModalities() {
    final modalities = _llama.getSupportedModalities();
    setState(() {
      _status = 'Поддерживаемые модальности: ${modalities.join(', ')}';
    });
  }

  /// Генерация текста
  Future<void> _generateText(String prompt) async {
    if (!_isModelLoaded) return;

    setState(() {
      _isLoading = true;
      _status = 'Генерирую текст...';
    });

    try {
      final input = MultimodalInput.text(prompt);
      final params = GenerationParams(
        maxTokens: 256,
        temperature: 0.7,
        topP: 0.9,
      );

      final response = await _llama.generateMultimodal(input, params);

      setState(() {
        _isLoading = false;
        _output = response.text;
        _status =
            'Сгенерировано ${response.tokensGenerated} токенов за ${response.generationTimeMs}ms';
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _status = 'Ошибка генерации: $e';
      });
    }
  }

  /// Анализ изображения
  Future<void> _analyzeImage(String imagePath, String prompt) async {
    if (!_isModelLoaded) return;

    setState(() {
      _isLoading = true;
      _status = 'Анализирую изображение...';
    });

    try {
      final response = await _llama.describeImage(
        imagePath,
        prompt,
        params: GenerationParams(maxTokens: 256, temperature: 0.7),
      );

      setState(() {
        _isLoading = false;
        _output = response.text;
        _status =
            'Изображение проанализировано. Обработаны модальности: ${response.processedModalities.join(', ')}';
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _status = 'Ошибка анализа изображения: $e';
      });
    }
  }

  /// Обработка аудио
  Future<void> _processAudio(String audioPath, String prompt) async {
    if (!_isModelLoaded) return;

    setState(() {
      _isLoading = true;
      _status = 'Обрабатываю аудио...';
    });

    try {
      final response = await _llama.processAudio(
        audioPath,
        prompt,
        params: GenerationParams(maxTokens: 256, temperature: 0.7),
      );

      setState(() {
        _isLoading = false;
        _output = response.text;
        _status =
            'Аудио обработано. Обработаны модальности: ${response.processedModalities.join(', ')}';
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _status = 'Ошибка обработки аудио: $e';
      });
    }
  }

  /// Смешанная обработка
  Future<void> _processMixedInput({
    String? text,
    String? imagePath,
    String? audioPath,
  }) async {
    if (!_isModelLoaded) return;

    setState(() {
      _isLoading = true;
      _status = 'Обрабатываю смешанный ввод...';
    });

    try {
      final response = await _llama.processMixedInput(
        text: text,
        imagePath: imagePath,
        audioPath: audioPath,
        params: GenerationParams(maxTokens: 256, temperature: 0.7),
      );

      setState(() {
        _isLoading = false;
        _output = response.text;
        _status =
            'Смешанный ввод обработан. Обработаны модальности: ${response.processedModalities.join(', ')}';
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _status = 'Ошибка обработки смешанного ввода: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Мультимодальная модель Shridhar'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Статус
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Статус: $_status',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    if (_isLoading) const LinearProgressIndicator(),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Кнопки для тестирования
            if (_isModelLoaded) ...[
              const Text(
                'Тестирование мультимодальности:',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),

              // Текстовые тесты
              ElevatedButton.icon(
                onPressed: () =>
                    _generateText('Расскажи о философии вайшнавизма'),
                icon: const Icon(Icons.text_fields),
                label: const Text('Текстовый тест'),
              ),

              const SizedBox(height: 8),

              // Тест изображения
              ElevatedButton.icon(
                onPressed: () => _analyzeImage(
                  '/path/to/image.jpg',
                  'Опиши это изображение с духовной точки зрения',
                ),
                icon: const Icon(Icons.image),
                label: const Text('Анализ изображения'),
              ),

              const SizedBox(height: 8),

              // Тест аудио
              ElevatedButton.icon(
                onPressed: () => _processAudio(
                  '/path/to/audio.mp3',
                  'Проанализируй эту музыку',
                ),
                icon: const Icon(Icons.audiotrack),
                label: const Text('Обработка аудио'),
              ),

              const SizedBox(height: 8),

              // Смешанный тест
              ElevatedButton.icon(
                onPressed: () => _processMixedInput(
                  text: 'Проанализируй все модальности',
                  imagePath: '/path/to/image.jpg',
                  audioPath: '/path/to/audio.mp3',
                ),
                icon: const Icon(Icons.merge),
                label: const Text('Смешанный ввод'),
              ),
            ],

            const SizedBox(height: 16),

            // Вывод
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Результат:',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Text(
                            _output.isEmpty
                                ? 'Результат появится здесь...'
                                : _output,
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

