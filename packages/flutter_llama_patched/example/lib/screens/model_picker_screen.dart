import 'package:flutter/material.dart';
import 'package:flutter_llama/flutter_llama.dart';

/// Экран выбора модели с поддержкой разных источников
class ModelPickerScreen extends StatefulWidget {
  const ModelPickerScreen({super.key});

  @override
  State<ModelPickerScreen> createState() => _ModelPickerScreenState();
}

class _ModelPickerScreenState extends State<ModelPickerScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = false;
  String _statusMessage = '';
  double _downloadProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Выбор модели'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.cloud), text: 'HuggingFace'),
            Tab(icon: Icon(Icons.pets), text: 'Ollama'),
            Tab(icon: Icon(Icons.folder), text: 'Локальные'),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_isLoading) ...[
            LinearProgressIndicator(value: _downloadProgress),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                _statusMessage,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildHuggingFaceTab(),
                _buildOllamaTab(),
                _buildLocalTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHuggingFaceTab() {
    final models = PresetModels.bySource(ModelSource.huggingFace);

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: models.length,
      itemBuilder: (context, index) {
        final model = models[index];
        return _buildModelCard(model);
      },
    );
  }

  Widget _buildOllamaTab() {
    final models = PresetModels.bySource(ModelSource.ollama);

    return Column(
      children: [
        _buildOllamaStatusCard(),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: models.length,
            itemBuilder: (context, index) {
              final model = models[index];
              return _buildModelCard(model);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildOllamaStatusCard() {
    return FutureBuilder<bool>(
      future: OllamaDownloader().isAvailable(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Card(
            margin: EdgeInsets.all(16),
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(width: 16),
                  Text('Проверка Ollama...'),
                ],
              ),
            ),
          );
        }

        final isAvailable = snapshot.data!;

        return Card(
          margin: const EdgeInsets.all(16),
          color: isAvailable ? Colors.green.shade50 : Colors.orange.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  isAvailable ? Icons.check_circle : Icons.warning,
                  color: isAvailable ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isAvailable ? 'Ollama запущен' : 'Ollama не найден',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      if (!isAvailable)
                        const Text(
                          'Установите Ollama с https://ollama.com',
                          style: TextStyle(fontSize: 12),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLocalTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_open, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          const Text(
            'Выбор локальных файлов',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Используйте file picker для выбора GGUF файлов',
            style: TextStyle(color: Colors.grey[600]),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              // TODO: Implement file picker
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Функция в разработке'),
                ),
              );
            },
            icon: const Icon(Icons.file_open),
            label: const Text('Выбрать файл'),
          ),
        ],
      ),
    );
  }

  Widget _buildModelCard(PresetModel model) {
    final isRecommended = model.metadata?['recommended'] == true;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      child: InkWell(
        onTap: () => _loadModel(model),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    model.source.icon,
                    style: const TextStyle(fontSize: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                model.name,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (isRecommended) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.green,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text(
                                  'РЕКОМЕНДУЕТСЯ',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          model.id +
                              (model.variant != null ? ':${model.variant}' : ''),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    model.size,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                model.description,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[800],
                ),
              ),
              if (model.languages.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: model.languages.map((lang) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Text(
                        lang,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.blue.shade900,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
              if (model.contextSize != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Контекст: ${model.contextSize} токенов',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _loadModel(PresetModel model) async {
    setState(() {
      _isLoading = true;
      _downloadProgress = 0.0;
      _statusMessage = 'Подготовка...';
    });

    try {
      final success = await FlutterLlama.instance.loadPresetModel(
        preset: model,
        onProgress: (progress) {
          setState(() {
            _downloadProgress = progress.progress;
            _statusMessage = progress.toString();
          });
        },
      );

      if (success && mounted) {
        Navigator.of(context).pop(model);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Модель ${model.name} загружена!'),
            backgroundColor: Colors.green,
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Не удалось загрузить модель'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = '';
          _downloadProgress = 0.0;
        });
      }
    }
  }
}


