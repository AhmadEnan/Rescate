import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_llama/flutter_llama.dart';
import '../utils/model_downloader.dart';

/// Экран для тестирования загрузки и работы с моделями
class ModelTestScreen extends StatefulWidget {
  const ModelTestScreen({super.key});

  @override
  State<ModelTestScreen> createState() => _ModelTestScreenState();
}

class _ModelTestScreenState extends State<ModelTestScreen> {
  final FlutterLlama _llama = FlutterLlama.instance;
  final TextEditingController _promptController = TextEditingController();

  String? _selectedModel;
  bool _isDownloading = false;
  bool _isGenerating = false;
  double _downloadProgress = 0.0;
  String _output = '';
  String _statusMessage = 'Выберите модель для начала';

  final List<String> _logs = [];

  @override
  void initState() {
    super.initState();
    _loadAvailableModels();
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _loadAvailableModels() async {
    _addLog('Загрузка списка доступных моделей...');
    final downloaded = await ModelDownloader.getDownloadedModels();
    setState(() {
      _statusMessage = downloaded.isEmpty
          ? 'Нет загруженных моделей. Загрузите модель для начала.'
          : 'Найдено ${downloaded.length} загруженных моделей';
    });
    _addLog('Найдено ${downloaded.length} загруженных моделей');
  }

  void _addLog(String message) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    setState(() {
      _logs.add('[$timestamp] $message');
      if (_logs.length > 50) {
        _logs.removeAt(0);
      }
    });
  }

  Future<void> _downloadModel(String modelName) async {
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _statusMessage = 'Загрузка $modelName...';
    });

    try {
      _addLog('Начинается загрузка $modelName');

      final modelPath = await ModelDownloader.downloadModel(
        modelName,
        onProgress: (progress) {
          setState(() {
            _downloadProgress = progress;
          });
        },
      );

      _addLog('Модель загружена: $modelPath');

      setState(() {
        _selectedModel = modelPath;
        _statusMessage = 'Модель загружена успешно';
        _isDownloading = false;
      });

      // Автоматически загрузить модель
      await _loadModel();
    } catch (e) {
      _addLog('Ошибка загрузки: $e');
      setState(() {
        _statusMessage = 'Ошибка загрузки: $e';
        _isDownloading = false;
      });
    }
  }

  Future<void> _loadModel() async {
    if (_selectedModel == null) {
      _addLog('Модель не выбрана');
      return;
    }

    try {
      _addLog('Инициализация модели...');
      setState(() {
        _statusMessage = 'Загрузка модели в память...';
      });

      final config = LlamaConfig(
        modelPath: _selectedModel!,
        nThreads: 4,
        contextSize: 2048,
        useGpu: true,
      );

      final success = await _llama.loadModel(config);

      if (success) {
        _addLog('Модель загружена успешно');
        final info = await _llama.getModelInfo();
        _addLog('Информация о модели: $info');

        setState(() {
          _statusMessage = 'Модель готова к генерации';
        });
      } else {
        _addLog('Не удалось загрузить модель');
        setState(() {
          _statusMessage = 'Ошибка загрузки модели';
        });
      }
    } catch (e) {
      _addLog('Ошибка при загрузке модели: $e');
      setState(() {
        _statusMessage = 'Ошибка: $e';
      });
    }
  }

  Future<void> _generate() async {
    if (!_llama.isModelLoaded) {
      _addLog('Модель не загружена');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Сначала загрузите модель')));
      return;
    }

    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) {
      _addLog('Пустой промпт');
      return;
    }

    setState(() {
      _isGenerating = true;
      _output = '';
      _statusMessage = 'Генерация...';
    });

    try {
      _addLog('Начало генерации для промпта: "$prompt"');

      final params = GenerationParams(
        prompt: prompt,
        maxTokens: 100,
        temperature: 0.7,
      );

      final stopwatch = Stopwatch()..start();
      final response = await _llama.generate(params);
      stopwatch.stop();

      _addLog('Генерация завершена за ${stopwatch.elapsedMilliseconds}ms');
      _addLog('Сгенерировано токенов: ${response.tokensGenerated}');
      _addLog('Скорость: ${response.tokensPerSecond.toStringAsFixed(2)} tok/s');

      setState(() {
        _output = response.text;
        _statusMessage =
            'Готово (${response.tokensGenerated} токенов, ${stopwatch.elapsedMilliseconds}ms)';
        _isGenerating = false;
      });
    } catch (e) {
      _addLog('Ошибка генерации: $e');
      setState(() {
        _statusMessage = 'Ошибка: $e';
        _isGenerating = false;
      });
    }
  }

  Future<void> _generateStream() async {
    if (!_llama.isModelLoaded) {
      _addLog('Модель не загружена');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Сначала загрузите модель')));
      return;
    }

    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) {
      _addLog('Пустой промпт');
      return;
    }

    setState(() {
      _isGenerating = true;
      _output = '';
      _statusMessage = 'Streaming генерация...';
    });

    try {
      _addLog('Начало streaming генерации для: "$prompt"');

      final params = GenerationParams(
        prompt: prompt,
        maxTokens: 100,
        temperature: 0.7,
      );

      int tokenCount = 0;
      final stopwatch = Stopwatch()..start();

      await for (final token in _llama.generateStream(params)) {
        tokenCount++;
        setState(() {
          _output += token;
        });
      }

      stopwatch.stop();
      _addLog(
        'Streaming завершен: $tokenCount токенов за ${stopwatch.elapsedMilliseconds}ms',
      );

      setState(() {
        _statusMessage = 'Готово ($tokenCount токенов)';
        _isGenerating = false;
      });
    } catch (e) {
      _addLog('Ошибка streaming: $e (возможно, не реализовано)');
      setState(() {
        _statusMessage = 'Streaming недоступен';
        _isGenerating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Model Testing'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              if (_llama.isModelLoaded) {
                await _llama.unloadModel();
                _addLog('Модель выгружена');
                setState(() {
                  _statusMessage = 'Модель выгружена';
                });
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Status bar
          Container(
            padding: const EdgeInsets.all(12),
            color: Theme.of(context).primaryColor.withOpacity(0.1),
            child: Row(
              children: [
                Icon(
                  _llama.isModelLoaded
                      ? Icons.check_circle
                      : Icons.circle_outlined,
                  color: _llama.isModelLoaded ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _statusMessage,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),

          // Model selection
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Доступные модели:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ModelDownloader.modelUrls.keys.map((modelName) {
                    final info =
                        ModelDownloader.getAvailableModels()[modelName]!;
                    return ElevatedButton(
                      onPressed: _isDownloading
                          ? null
                          : () => _downloadModel(modelName),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(info.quantization),
                          Text(
                            info.sizeFormatted,
                            style: const TextStyle(fontSize: 10),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
                if (_isDownloading) ...[
                  const SizedBox(height: 12),
                  LinearProgressIndicator(value: _downloadProgress),
                  Text('${(_downloadProgress * 100).toStringAsFixed(1)}%'),
                ],
              ],
            ),
          ),

          const Divider(),

          // Generation controls
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _promptController,
                  decoration: const InputDecoration(
                    labelText: 'Prompt',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isGenerating || !_llama.isModelLoaded
                            ? null
                            : _generate,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Generate'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isGenerating || !_llama.isModelLoaded
                            ? null
                            : _generateStream,
                        icon: const Icon(Icons.stream),
                        label: const Text('Stream'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const Divider(),

          // Output
          Expanded(
            child: DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  const TabBar(
                    tabs: [
                      Tab(text: 'Output'),
                      Tab(text: 'Logs'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        // Output tab
                        SingleChildScrollView(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            _output.isEmpty
                                ? 'Результат появится здесь...'
                                : _output,
                          ),
                        ),
                        // Logs tab
                        ListView.builder(
                          padding: const EdgeInsets.all(8),
                          itemCount: _logs.length,
                          itemBuilder: (context, index) {
                            return Text(
                              _logs[index],
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}





