import 'package:flutter/material.dart';
import '../services/model_downloader.dart';

/// Экран управления моделями
class ModelManagerScreen extends StatefulWidget {
  const ModelManagerScreen({super.key});

  @override
  State<ModelManagerScreen> createState() => _ModelManagerScreenState();
}

class _ModelManagerScreenState extends State<ModelManagerScreen> {
  final Map<String, double> _downloadProgress = {};
  final Map<String, String> _downloadStatus = {};
  List<String> _downloadedModels = [];

  @override
  void initState() {
    super.initState();
    _loadDownloadedModels();
  }

  Future<void> _loadDownloadedModels() async {
    final models = await ModelDownloader.getDownloadedModels();
    setState(() {
      _downloadedModels = models;
    });
  }

  Future<void> _downloadModel(PresetModel model) async {
    try {
      setState(() {
        _downloadProgress[model.id] = 0.0;
        _downloadStatus[model.id] = 'Начало загрузки...';
      });

      // Скачиваем все файлы модели
      for (final fileName in model.ggufFiles) {
        await ModelDownloader.downloadModel(
          modelId: model.id,
          fileName: fileName,
          onProgress: (progress, status) {
            setState(() {
              _downloadProgress[model.id] = progress;
              _downloadStatus[model.id] = status;
            });
          },
        );
      }

      setState(() {
        _downloadProgress[model.id] = 1.0;
        _downloadStatus[model.id] = 'Загрузка завершена';
      });

      await _loadDownloadedModels();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Модель ${model.name} успешно загружена'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _downloadProgress[model.id] = 0.0;
        _downloadStatus[model.id] = 'Ошибка: $e';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteModel(String modelId) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить модель?'),
        content: const Text('Вы уверены, что хотите удалить эту модель?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (result == true) {
      await ModelDownloader.deleteModel(modelId);
      await _loadDownloadedModels();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Модель удалена'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Управление моделями'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDownloadedModels,
            tooltip: 'Обновить список',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Заголовок
          Text(
            'Доступные модели',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Скачайте модели с Hugging Face для локального использования',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[600],
                ),
          ),
          const SizedBox(height: 24),

          // Список моделей
          ...PresetModels.all.map((model) {
            final isDownloaded = _downloadedModels.contains(
              model.id.replaceAll('/', '_'),
            );
            final progress = _downloadProgress[model.id] ?? 0.0;
            final status = _downloadStatus[model.id];
            final isDownloading = status != null && progress < 1.0;

            return Card(
              margin: const EdgeInsets.only(bottom: 16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Заголовок модели
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: const Color(0xFF10A37F).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.auto_awesome,
                            color: Color(0xFF10A37F),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                model.name,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                model.id,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Colors.grey[600],
                                    ),
                              ),
                            ],
                          ),
                        ),
                        if (isDownloaded)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.check_circle,
                                  size: 16,
                                  color: Colors.green,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'Скачано',
                                  style: TextStyle(
                                    color: Colors.green,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Описание
                    Text(
                      model.description,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),

                    const SizedBox(height: 12),

                    // Языки
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: model.languages.map((lang) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF444654)
                                : const Color(0xFFF7F7F8),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.grey.withOpacity(0.2),
                            ),
                          ),
                          child: Text(
                            lang,
                            style: const TextStyle(fontSize: 12),
                          ),
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 12),

                    // Размер
                    Row(
                      children: [
                        Icon(
                          Icons.storage,
                          size: 16,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Размер: ${model.size}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),

                    // Прогресс загрузки
                    if (isDownloading) ...[
                      const SizedBox(height: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                status,
                                style: const TextStyle(fontSize: 12),
                              ),
                              Text(
                                '${(progress * 100).toStringAsFixed(0)}%',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: progress,
                            backgroundColor: Colors.grey[300],
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              Color(0xFF10A37F),
                            ),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 16),

                    // Кнопки действий
                    Row(
                      children: [
                        if (!isDownloaded && !isDownloading)
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => _downloadModel(model),
                              icon: const Icon(Icons.download),
                              label: const Text('Скачать'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF10A37F),
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                        if (isDownloaded) ...[
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () =>
                                  _deleteModel(model.id.replaceAll('/', '_')),
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Удалить'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.pop(context, model.id);
                              },
                              icon: const Icon(Icons.play_arrow),
                              label: const Text('Использовать'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF10A37F),
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}


