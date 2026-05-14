import 'package:flutter/material.dart';
import 'package:flutter_llama/flutter_llama.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'screens/model_manager_screen.dart';
import 'screens/model_picker_screen.dart';
import 'services/model_downloader.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Shridhar Multimodal Chat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF10A37F),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          elevation: 0,
          centerTitle: true,
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF10A37F),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF343541),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF343541),
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
        ),
      ),
      themeMode: ThemeMode.dark,
      home: const ChatScreen(),
    );
  }
}

class Message {
  final String text;
  final bool isUser;
  final List<String>? imagePaths;
  final DateTime timestamp;

  Message({
    required this.text,
    required this.isUser,
    this.imagePaths,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final FlutterLlama _llama = FlutterLlama.instance;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Message> _messages = [];
  final List<String> _selectedImages = [];

  bool _isModelLoaded = false;
  bool _isGenerating = false;
  String _modelPath = '';
  String _currentResponse = '';

  @override
  void initState() {
    super.initState();
    _loadModelFromAssets();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _llama.unloadModel();
    super.dispose();
  }

  /// Выбор модели
  Future<void> _pickModel() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['gguf', 'safetensors'],
      );

      if (result != null && result.files.single.path != null) {
        _modelPath = result.files.single.path!;
        await _loadModel();
      }
    } catch (e) {
      _addSystemMessage('Ошибка выбора файла: $e');
    }
  }

  /// Открыть менеджер моделей
  Future<void> _openModelManager() async {
    final modelId = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const ModelManagerScreen()),
    );

    if (modelId != null) {
      // Пользователь выбрал модель из менеджера
      await _loadDownloadedModel(modelId);
    }
  }

  /// Открыть новый пикер моделей с lazy loading
  Future<void> _openModelPicker() async {
    final model = await Navigator.push<PresetModel>(
      context,
      MaterialPageRoute(builder: (context) => const ModelPickerScreen()),
    );

    if (model != null) {
      // Модель уже загружена через ModelPickerScreen
      setState(() {
        _isModelLoaded = true;
        _addSystemMessage(
          'Модель ${model.name} готова к использованию!\n'
          'Источник: ${model.source.displayName}\n'
          'Размер: ${model.size}',
        );
      });
    }
  }

  /// Загрузка скачанной модели
  Future<void> _loadDownloadedModel(String modelId) async {
    try {
      setState(() {
        _addSystemMessage('Поиск модели $modelId...');
      });

      // Получаем путь к модели
      final modelPath = await ModelDownloader.getModelPath(
        modelId,
        'adapter_model.safetensors',
      );

      if (modelPath != null) {
        _modelPath = modelPath;
        await _loadModel();
      } else {
        _addSystemMessage(
          'Модель не найдена. Пожалуйста, скачайте её сначала.',
        );
      }
    } catch (e) {
      _addSystemMessage('Ошибка загрузки модели: $e');
    }
  }

  /// Загрузка модели из assets
  Future<void> _loadModelFromAssets() async {
    try {
      final documentsDir = await getApplicationDocumentsDirectory();
      final modelFile = File(
        '${documentsDir.path}/shridhar_8k_multimodal.gguf',
      );

      // Копируем модель из assets, если её нет
      if (!await modelFile.exists()) {
        setState(() {
          _addSystemMessage('Копирую модель из assets...');
        });

        final byteData = await rootBundle.load(
          'assets/models/braindler-q2_k.gguf',
        );
        await modelFile.writeAsBytes(byteData.buffer.asUint8List());
      }

      _modelPath = modelFile.path;
      await _loadModel();
    } catch (e) {
      _addSystemMessage(
        'Ошибка загрузки модели: $e\nИспользуйте кнопку "Менеджер моделей" для скачивания моделей с Hugging Face.',
      );
    }
  }

  /// Загрузка модели
  Future<void> _loadModel() async {
    try {
      setState(() {
        _addSystemMessage('Загружаю мультимодальную модель Shridhar...');
      });

      final config = LlamaConfig(
        modelPath: _modelPath,
        nThreads: 8,
        nGpuLayers: -1, // Все слои на GPU
        contextSize: 8192, // 8K контекст
        batchSize: 512,
        useGpu: true,
        verbose: false,
      );

      final success = await _llama.loadModel(config);

      if (success) {
        final info = await _llama.getModelInfo();
        setState(() {
          _isModelLoaded = true;
          _addSystemMessage(
            'Модель Shridhar 8K Multimodal загружена успешно!\n'
            'Параметры: ${info?['nParams'] ?? 'N/A'}\n'
            'Слои: ${info?['nLayers'] ?? 'N/A'}\n'
            'Контекст: ${info?['contextSize'] ?? 'N/A'} токенов\n\n'
            'Поддерживаемые языки: 🇷🇺 Русский, 🇪🇸 Испанский, 🇮🇳 Хинди, 🇹🇭 Тайский\n'
            'Категории: ИКАРОС, Джив Джаго, Love Destiny, Медитация, Йога',
          );
        });
      } else {
        _addSystemMessage('Не удалось загрузить модель');
      }
    } catch (e) {
      _addSystemMessage('Ошибка: $e');
    }
  }

  void _addSystemMessage(String text) {
    setState(() {
      _messages.add(Message(text: text, isUser: false));
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Выбор изображений
  Future<void> _pickImages() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true,
      );

      if (result != null) {
        setState(() {
          _selectedImages.addAll(
            result.files
                .map((file) => file.path!)
                .where((path) => path.isNotEmpty),
          );
        });
      }
    } catch (e) {
      _addSystemMessage('Ошибка выбора изображений: $e');
    }
  }

  /// Удаление изображения
  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
    });
  }

  /// Отправка сообщения
  Future<void> _sendMessage() async {
    if (!_isModelLoaded) {
      _addSystemMessage('Пожалуйста, дождитесь загрузки модели');
      return;
    }

    final text = _messageController.text.trim();
    if (text.isEmpty && _selectedImages.isEmpty) {
      return;
    }

    // Добавляем сообщение пользователя
    final userMessage = Message(
      text: text.isEmpty ? '[Изображение]' : text,
      isUser: true,
      imagePaths: _selectedImages.isNotEmpty
          ? List.from(_selectedImages)
          : null,
    );

    setState(() {
      _messages.add(userMessage);
      _messageController.clear();
      _isGenerating = true;
      _currentResponse = '';
    });

    _scrollToBottom();

    // Формируем промпт с учётом мультимодальности
    String prompt = text;
    if (_selectedImages.isNotEmpty) {
      prompt = '[IMAGE] $text';
    }

    try {
      final params = GenerationParams(
        prompt: prompt,
        temperature: 0.7,
        topP: 0.9,
        topK: 40,
        maxTokens: 512,
        repeatPenalty: 1.1,
      );

      // Генерация с потоковым выводом
      final assistantMessage = Message(text: '', isUser: false);
      setState(() {
        _messages.add(assistantMessage);
        _selectedImages.clear();
      });

      await for (final token in _llama.generateStream(params)) {
        setState(() {
          _currentResponse += token;
          _messages[_messages.length - 1] = Message(
            text: _currentResponse,
            isUser: false,
          );
        });

        _scrollToBottom();
      }
    } catch (e) {
      setState(() {
        _messages.add(Message(text: 'Ошибка генерации: $e', isUser: false));
      });
    } finally {
      setState(() {
        _isGenerating = false;
        _currentResponse = '';
      });
    }
  }

  /// Очистка чата
  void _clearChat() {
    setState(() {
      _messages.clear();
      _addSystemMessage('Чат очищен');
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF343541) : Colors.white;
    final userBubbleColor = isDark
        ? const Color(0xFF10A37F)
        : const Color(0xFF10A37F);
    final aiBubbleColor = isDark
        ? const Color(0xFF444654)
        : const Color(0xFFF7F7F8);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFF10A37F),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.auto_awesome,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Shridhar Multimodal',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                Text(
                  '8K Context',
                  style: TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: _openModelPicker,
            tooltip: '🦙 Скачать модель (HF/Ollama)',
          ),
          IconButton(
            icon: const Icon(Icons.cloud_download_outlined),
            onPressed: _openModelManager,
            tooltip: 'Менеджер моделей',
          ),
          if (_isModelLoaded)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _clearChat,
              tooltip: 'Очистить чат',
            ),
          IconButton(
            icon: Icon(_isModelLoaded ? Icons.check_circle : Icons.file_open),
            color: _isModelLoaded ? Colors.green : Colors.grey,
            onPressed: _isModelLoaded ? null : _pickModel,
            tooltip: _isModelLoaded ? 'Модель загружена' : 'Выбрать модель',
          ),
        ],
      ),
      body: Column(
        children: [
          // Список сообщений
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: const Color(0xFF10A37F).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Icon(
                            Icons.auto_awesome,
                            size: 40,
                            color: Color(0xFF10A37F),
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'Shridhar 8K Multimodal',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Мультиязычная духовная модель',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 32),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 48),
                          child: Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            alignment: WrapAlignment.center,
                            children: [
                              _buildFeatureChip('🇷🇺 Русский', isDark),
                              _buildFeatureChip('🇪🇸 Испанский', isDark),
                              _buildFeatureChip('🇮🇳 Хинди', isDark),
                              _buildFeatureChip('🇹🇭 Тайский', isDark),
                              _buildFeatureChip('🧘 Медитация', isDark),
                              _buildFeatureChip('🎵 ИКАРОС', isDark),
                              _buildFeatureChip('🎬 Love Destiny', isDark),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      return _buildMessageBubble(
                        message,
                        userBubbleColor,
                        aiBubbleColor,
                        isDark,
                      );
                    },
                  ),
          ),

          // Предпросмотр выбранных изображений
          if (_selectedImages.isNotEmpty)
            Container(
              height: 100,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: aiBubbleColor,
                border: Border(
                  top: BorderSide(color: Colors.grey.withOpacity(0.2)),
                ),
              ),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _selectedImages.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            File(_selectedImages[index]),
                            width: 80,
                            height: 80,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: GestureDetector(
                            onTap: () => _removeImage(index),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

          // Поле ввода
          Container(
            decoration: BoxDecoration(
              color: bgColor,
              border: Border(
                top: BorderSide(color: Colors.grey.withOpacity(0.2)),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                // Кнопка добавления изображения
                IconButton(
                  icon: const Icon(Icons.add_photo_alternate),
                  onPressed: _isGenerating ? null : _pickImages,
                  color: const Color(0xFF10A37F),
                ),
                const SizedBox(width: 8),

                // Текстовое поле
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: aiBubbleColor,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: TextField(
                      controller: _messageController,
                      maxLines: null,
                      enabled: !_isGenerating && _isModelLoaded,
                      decoration: const InputDecoration(
                        hintText: 'Напишите сообщение...',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Кнопка отправки
                Container(
                  decoration: BoxDecoration(
                    color: _isGenerating
                        ? Colors.grey
                        : const Color(0xFF10A37F),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: Icon(
                      _isGenerating ? Icons.stop : Icons.send,
                      color: Colors.white,
                    ),
                    onPressed: !_isModelLoaded || _isGenerating
                        ? null
                        : _sendMessage,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureChip(String label, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF444654) : const Color(0xFFF7F7F8),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }

  Widget _buildMessageBubble(
    Message message,
    Color userBubbleColor,
    Color aiBubbleColor,
    bool isDark,
  ) {
    final isUser = message.isUser;
    final hasImages =
        message.imagePaths != null && message.imagePaths!.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFF10A37F),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.auto_awesome,
                color: Colors.white,
                size: 16,
              ),
            ),
            const SizedBox(width: 12),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                if (hasImages)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: message.imagePaths!.map((imagePath) {
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(
                            File(imagePath),
                            width: 200,
                            height: 200,
                            fit: BoxFit.cover,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: isUser ? userBubbleColor : aiBubbleColor,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(
                    message.text,
                    style: TextStyle(
                      color: isUser ? Colors.white : null,
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 12),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.grey[600],
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.person, color: Colors.white, size: 16),
            ),
          ],
        ],
      ),
    );
  }
}
