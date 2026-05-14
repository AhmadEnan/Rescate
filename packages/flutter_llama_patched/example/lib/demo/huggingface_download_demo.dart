import 'package:flutter/material.dart';
import '../services/model_downloader.dart';

/// Демонстрация скачивания модели с Hugging Face
/// 
/// Этот виджет показывает, как:
/// 1. Скачать модель Shridhar 8K Multimodal с Hugging Face
/// 2. Отслеживать прогресс загрузки
/// 3. Использовать скачанную модель
class HuggingFaceDownloadDemo extends StatefulWidget {
  const HuggingFaceDownloadDemo({super.key});

  @override
  State<HuggingFaceDownloadDemo> createState() =>
      _HuggingFaceDownloadDemoState();
}

class _HuggingFaceDownloadDemoState extends State<HuggingFaceDownloadDemo> {
  double _downloadProgress = 0.0;
  String _downloadStatus = 'Готов к загрузке';
  bool _isDownloading = false;
  String? _downloadedModelPath;
  List<String> _logs = [];

  void _addLog(String message) {
    setState(() {
      _logs.add('[${DateTime.now().toString().substring(11, 19)}] $message');
    });
  }

  /// Демонстрация загрузки модели Shridhar 8K Multimodal
  Future<void> _demonstrateDownload() async {
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _logs.clear();
    });

    _addLog('=== Демонстрация загрузки модели Shridhar 8K Multimodal ===');
    _addLog('Модель: ${PresetModels.shridharMultimodal.id}');
    _addLog('Описание: ${PresetModels.shridharMultimodal.description}');
    _addLog('Языки: ${PresetModels.shridharMultimodal.languages.join(', ')}');
    _addLog('');

    try {
      // Скачиваем все файлы модели
      for (var i = 0; i < PresetModels.shridharMultimodal.ggufFiles.length; i++) {
        final fileName = PresetModels.shridharMultimodal.ggufFiles[i];
        
        _addLog('Скачивание файла ${i + 1}/${PresetModels.shridharMultimodal.ggufFiles.length}: $fileName');
        
        final filePath = await ModelDownloader.downloadModel(
          modelId: PresetModels.shridharMultimodal.id,
          fileName: fileName,
          onProgress: (progress, status) {
            setState(() {
              _downloadProgress = progress;
              _downloadStatus = status;
            });
          },
        );

        _addLog('✓ Файл сохранён: $filePath');
        
        if (i == 0) {
          _downloadedModelPath = filePath;
        }
      }

      _addLog('');
      _addLog('=== Загрузка завершена успешно! ===');
      _addLog('Модель готова к использованию');

      // Проверяем размер скачанной модели
      final modelSize = await ModelDownloader.getModelSize(
        PresetModels.shridharMultimodal.id,
      );
      final sizeMb = (modelSize / 1024 / 1024).toStringAsFixed(2);
      _addLog('Размер модели: $sizeMb MB');

      setState(() {
        _isDownloading = false;
        _downloadProgress = 1.0;
        _downloadStatus = 'Загрузка завершена';
      });

      // Показываем диалог с результатом
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 12),
                Text('Успех!'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Модель Shridhar 8K Multimodal успешно загружена!'),
                const SizedBox(height: 16),
                Text(
                  'Размер: $sizeMb MB',
                  style: TextStyle(color: Colors.grey[600]),
                ),
                const SizedBox(height: 8),
                Text(
                  'Путь: $_downloadedModelPath',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      _addLog('');
      _addLog('=== ОШИБКА ===');
      _addLog('Ошибка загрузки: $e');

      setState(() {
        _isDownloading = false;
        _downloadProgress = 0.0;
        _downloadStatus = 'Ошибка: $e';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hugging Face Download Demo'),
        backgroundColor: const Color(0xFF10A37F),
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Информация о модели
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                                PresetModels.shridharMultimodal.name,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                PresetModels.shridharMultimodal.id,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(PresetModels.shridharMultimodal.description),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: PresetModels.shridharMultimodal.languages
                          .map((lang) => Chip(
                                label: Text(lang, style: const TextStyle(fontSize: 12)),
                                backgroundColor: Colors.grey[200],
                              ))
                          .toList(),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Кнопка загрузки
            ElevatedButton.icon(
              onPressed: _isDownloading ? null : _demonstrateDownload,
              icon: const Icon(Icons.download),
              label: const Text('Скачать модель с Hugging Face'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10A37F),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),

            const SizedBox(height: 24),

            // Прогресс
            if (_isDownloading || _downloadProgress > 0) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Прогресс загрузки',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '${(_downloadProgress * 100).toStringAsFixed(0)}%',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: _downloadProgress,
                        backgroundColor: Colors.grey[300],
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFF10A37F),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _downloadStatus,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Логи
            const Text(
              'Логи загрузки:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Card(
                child: _logs.isEmpty
                    ? const Center(
                        child: Text('Нажмите кнопку выше для начала загрузки'),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _logs.length,
                        itemBuilder: (context, index) {
                          final log = _logs[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              log,
                              style: const TextStyle(
                                fontSize: 12,
                                fontFamily: 'monospace',
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


