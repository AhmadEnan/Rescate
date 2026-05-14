# 🚀 Быстрый старт: Lazy Loading моделей

## 3 минуты до первой работающей модели!

### Шаг 1: Импорт (5 секунд)

```dart
import 'package:flutter_llama/flutter_llama.dart';
```

### Шаг 2: Загрузка модели (1 минута)

```dart
// Выберите любой из способов:

// 🟢 ПРОСТЕЙШИЙ - Рекомендуемая модель
await FlutterLlama.instance.loadPresetModel(
  preset: PresetModels.braindlerQ4K,  // 88 MB, быстрая
  onProgress: (progress) {
    print('${progress.status}: ${progress.progressPercent}');
  },
);

// 🔵 С ВЫБОРОМ ИСТОЧНИКА
await FlutterLlama.instance.loadModelWithAutoDownload(
  modelId: 'nativemind/braindler',
  source: ModelSource.ollama,  // или ModelSource.huggingFace
  variant: 'q4_k_s',
  onProgress: (p) => print(p),
);

// 🟣 ЧЕРЕЗ UI (самый красивый)
final model = await Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => const ModelPickerScreen(),
  ),
);
// Модель уже загружена!
```

### Шаг 3: Использование (30 секунд)

```dart
// Генерация текста
final result = await FlutterLlama.instance.generate(
  GenerationParams(
    prompt: 'Привет! Расскажи о себе.',
    maxTokens: 256,
    temperature: 0.7,
  ),
);

print(result.text);
```

### Шаг 4: Streaming генерация (1 минута)

```dart
await for (final token in FlutterLlama.instance.generateStream(
  GenerationParams(prompt: 'Привет!'),
)) {
  print(token);  // Печатает токен за токеном
}
```

## 🎯 Полный пример приложения

```dart
import 'package:flutter/material.dart';
import 'package:flutter_llama/flutter_llama.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lazy Loading Demo',
      home: const ChatScreen(),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _llama = FlutterLlama.instance;
  bool _isLoading = true;
  bool _isModelLoaded = false;
  double _progress = 0.0;
  String _status = 'Инициализация...';
  String _response = '';

  @override
  void initState() {
    super.initState();
    _loadModel();
  }

  Future<void> _loadModel() async {
    try {
      final success = await _llama.loadPresetModel(
        preset: PresetModels.braindlerQ4K,
        onProgress: (progress) {
          setState(() {
            _progress = progress.progress;
            _status = progress.status;
          });
        },
      );

      setState(() {
        _isModelLoaded = success;
        _isLoading = false;
        _status = success ? 'Модель готова!' : 'Ошибка загрузки';
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _status = 'Ошибка: $e';
      });
    }
  }

  Future<void> _generate() async {
    if (!_isModelLoaded) return;

    setState(() => _response = '');

    await for (final token in _llama.generateStream(
      GenerationParams(
        prompt: 'Привет! Расскажи о себе.',
        maxTokens: 128,
      ),
    )) {
      setState(() => _response += token);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Flutter Llama')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Статус загрузки
            if (_isLoading) ...[
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 8),
              Text(_status, textAlign: TextAlign.center),
            ] else
              Text(
                _status,
                style: TextStyle(
                  color: _isModelLoaded ? Colors.green : Colors.red,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),

            const SizedBox(height: 24),

            // Кнопка генерации
            ElevatedButton(
              onPressed: _isModelLoaded ? _generate : null,
              child: const Text('Сгенерировать текст'),
            ),

            const SizedBox(height: 24),

            // Результат
            if (_response.isNotEmpty)
              Expanded(
                child: SingleChildScrollView(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(_response),
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
```

## 📦 Доступные модели

### Ollama модели (рекомендуется)

| Модель | Размер | Скорость | Качество | Рекомендуется |
|--------|--------|----------|----------|---------------|
| `PresetModels.braindlerQ2K` | 72 MB | ⚡⚡⚡ | ⭐⭐⭐ | Для слабых устройств |
| `PresetModels.braindlerQ4K` | 88 MB | ⚡⚡ | ⭐⭐⭐⭐ | ✅ **ДА** |
| `PresetModels.braindlerQ5K` | 103 MB | ⚡ | ⭐⭐⭐⭐⭐ | Для мощных устройств |
| `PresetModels.braindlerQ8` | 140 MB | 🐌 | ⭐⭐⭐⭐⭐ | Десктоп |
| `PresetModels.braindlerF16` | 256 MB | 🐌🐌 | ⭐⭐⭐⭐⭐ | Максимум |

### HuggingFace модели

| Модель | Размер | Особенности |
|--------|--------|-------------|
| `PresetModels.shridharMultimodal` | 50 MB | Мультиязычная (RU/ES/HI/TH), 8K контекст |

## ⚙️ Требования

### Для Ollama моделей

1. Установите Ollama:
```bash
# macOS/Linux
brew install ollama

# Windows
# Скачайте с https://ollama.com
```

2. Запустите Ollama:
```bash
ollama serve
```

### Для HuggingFace моделей

Просто наличие интернета! 🌐

## 💡 Советы

### Выбор модели

**Для мобильных:**
```dart
PresetModels.braindlerQ2K  // или Q4K
```

**Для десктопа:**
```dart
PresetModels.braindlerQ5K  // или Q8
```

**Для многоязычности:**
```dart
PresetModels.shridharMultimodal
```

### Оптимизация

```dart
// Используйте все GPU слои
LlamaConfig(
  nGpuLayers: -1,  // Все слои на GPU
  useGpu: true,
  nThreads: 8,     // Больше потоков
)
```

### Кэширование

Модели автоматически кэшируются! Второй запуск мгновенный.

```dart
// Первый раз - скачивание
await _llama.loadPresetModel(...);  // ~30 секунд

// Второй раз - мгновенно
await _llama.loadPresetModel(...);  // < 1 секунды
```

## 🐛 Решение проблем

### "Модель не найдена"

```dart
// Проверьте статус источника
final manager = ModelManager.fromPreset(PresetModels.braindlerQ4K);
final status = await manager.checkSourceStatus();

if (!status.isAvailable) {
  print('Проблема: ${status.message}');
  // Для Ollama: убедитесь что ollama serve запущен
  // Для HuggingFace: проверьте интернет
}
```

### "Ollama не найден"

```bash
# Проверьте что Ollama запущен
ollama list

# Если нет - запустите
ollama serve
```

### "Медленная генерация"

```dart
// 1. Используйте меньшую модель (Q2K)
PresetModels.braindlerQ2K

// 2. Включите GPU
LlamaConfig(nGpuLayers: -1, useGpu: true)

// 3. Уменьшите контекст
LlamaConfig(contextSize: 1024)  // вместо 2048
```

## 📚 Дополнительно

- 📖 **Полная документация**: `LAZY_LOADING.md`
- 🔧 **Технические детали**: `CHANGES_LAZY_LOADING.md`
- 🎨 **UI компоненты**: `example/lib/screens/model_picker_screen.dart`

## ❓ FAQ

**Q: Нужен ли интернет?**  
A: Только для первой загрузки. Потом модель в кэше.

**Q: Сколько места нужно?**  
A: От 72 MB (Q2K) до 256 MB (F16). Средняя модель ~100 MB.

**Q: Работает офлайн?**  
A: Да! После загрузки всё работает без интернета.

**Q: Можно несколько моделей?**  
A: Да, каждая кэшируется отдельно.

**Q: Как удалить модель?**  
A: 
```dart
final manager = ModelManager.fromPreset(model);
await manager.deleteModel();
```

**Q: Как посмотреть размер?**  
A:
```dart
final size = await manager.getModelSize();
print('${(size/1024/1024).toStringAsFixed(1)} MB');
```

## 🎉 Готово!

Вы освоили lazy loading в Flutter Llama!

**Следующие шаги:**
1. Попробуйте разные модели
2. Настройте параметры генерации
3. Создайте свой UI
4. Интегрируйте в приложение

**Нужна помощь?**
- Читайте `LAZY_LOADING.md` для деталей
- Смотрите `example/lib/main.dart` для примеров
- Проверьте `example/lib/screens/model_picker_screen.dart` для UI

---

**Удачи с Flutter Llama! 🦙✨**


