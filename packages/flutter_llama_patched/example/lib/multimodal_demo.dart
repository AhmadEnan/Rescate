import 'package:flutter/material.dart';
import 'package:flutter_llama/flutter_llama.dart';

/// Демонстрация мультимодальных возможностей
class MultimodalDemo extends StatefulWidget {
  const MultimodalDemo({Key? key}) : super(key: key);

  @override
  State<MultimodalDemo> createState() => _MultimodalDemoState();
}

class _MultimodalDemoState extends State<MultimodalDemo> {
  final FlutterLlamaMultimodal _llama = FlutterLlamaMultimodal.instance;
  String _output = '';
  bool _isLoading = false;

  /// Демонстрация текстовой генерации
  Future<void> _demoTextGeneration() async {
    setState(() {
      _isLoading = true;
      _output = 'Генерирую текст...';
    });

    try {
      final input = MultimodalInput.text('Что такое бхакти-йога?');
      final params = GenerationParams(maxTokens: 200, temperature: 0.7);

      final response = await _llama.generateMultimodal(input, params);

      setState(() {
        _output =
            'Текстовая генерация:\n\n${response.text}\n\n'
            'Токенов: ${response.tokensGenerated}\n'
            'Время: ${response.generationTimeMs}ms\n'
            'Скорость: ${response.tokensPerSecond.toStringAsFixed(2)} токенов/сек';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _output = 'Ошибка: $e';
        _isLoading = false;
      });
    }
  }

  /// Демонстрация анализа изображения
  Future<void> _demoImageAnalysis() async {
    setState(() {
      _isLoading = true;
      _output = 'Анализирую изображение...';
    });

    try {
      // Симуляция анализа изображения
      final input = MultimodalInput.image(
        '/path/to/spiritual_image.jpg',
        text: 'Опиши духовное значение этого изображения',
      );
      final params = GenerationParams(maxTokens: 200, temperature: 0.7);

      final response = await _llama.generateMultimodal(input, params);

      setState(() {
        _output =
            'Анализ изображения:\n\n${response.text}\n\n'
            'Обработанные модальности: ${response.processedModalities.join(', ')}\n'
            'Vision info: ${response.visionInfo ?? 'Нет данных'}';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _output = 'Ошибка анализа изображения: $e';
        _isLoading = false;
      });
    }
  }

  /// Демонстрация обработки аудио
  Future<void> _demoAudioProcessing() async {
    setState(() {
      _isLoading = true;
      _output = 'Обрабатываю аудио...';
    });

    try {
      // Симуляция обработки аудио
      final input = MultimodalInput.audio(
        '/path/to/mantra.mp3',
        text: 'Проанализируй эту мантру',
      );
      final params = GenerationParams(maxTokens: 200, temperature: 0.7);

      final response = await _llama.generateMultimodal(input, params);

      setState(() {
        _output =
            'Обработка аудио:\n\n${response.text}\n\n'
            'Обработанные модальности: ${response.processedModalities.join(', ')}\n'
            'Audio info: ${response.audioInfo ?? 'Нет данных'}';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _output = 'Ошибка обработки аудио: $e';
        _isLoading = false;
      });
    }
  }

  /// Демонстрация смешанного ввода
  Future<void> _demoMixedInput() async {
    setState(() {
      _isLoading = true;
      _output = 'Обрабатываю смешанный ввод...';
    });

    try {
      // Симуляция смешанного ввода
      final input = MultimodalInput.mixed(
        text: 'Проанализируй все модальности',
        imagePath: '/path/to/temple.jpg',
        audioPath: '/path/to/bhajan.mp3',
      );
      final params = GenerationParams(maxTokens: 300, temperature: 0.7);

      final response = await _llama.generateMultimodal(input, params);

      setState(() {
        _output =
            'Смешанный анализ:\n\n${response.text}\n\n'
            'Обработанные модальности: ${response.processedModalities.join(', ')}\n'
            'Мультимодальная информация: ${response.multimodalInfo ?? 'Нет данных'}';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _output = 'Ошибка смешанного ввода: $e';
        _isLoading = false;
      });
    }
  }

  /// Демонстрация потоковой генерации
  Future<void> _demoStreamingGeneration() async {
    setState(() {
      _isLoading = true;
      _output = 'Потоковая генерация...\n';
    });

    try {
      final input = MultimodalInput.text('Расскажи о духовном пути');
      final params = GenerationParams(maxTokens: 200, temperature: 0.7);

      await for (final response in _llama.generateMultimodalStream(
        input,
        params,
      )) {
        setState(() {
          _output += response.text;
        });
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _output = 'Ошибка потоковой генерации: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Мультимодальная демонстрация'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Кнопки демонстрации
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _demoTextGeneration,
                  icon: const Icon(Icons.text_fields),
                  label: const Text('Текст'),
                ),
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _demoImageAnalysis,
                  icon: const Icon(Icons.image),
                  label: const Text('Изображение'),
                ),
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _demoAudioProcessing,
                  icon: const Icon(Icons.audiotrack),
                  label: const Text('Аудио'),
                ),
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _demoMixedInput,
                  icon: const Icon(Icons.merge),
                  label: const Text('Смешанный'),
                ),
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _demoStreamingGeneration,
                  icon: const Icon(Icons.stream),
                  label: const Text('Поток'),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Индикатор загрузки
            if (_isLoading) const LinearProgressIndicator(),

            const SizedBox(height: 16),

            // Вывод
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: SingleChildScrollView(
                    child: Text(
                      _output.isEmpty ? 'Выберите демонстрацию...' : _output,
                      style: const TextStyle(fontSize: 14),
                    ),
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

