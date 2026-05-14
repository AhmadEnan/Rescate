# flutter_llama 🦙

Flutter плагин для запуска LLM инференса с llama.cpp и GGUF моделями на Android и iOS.

## 🌟 Особенности

- 🚀 Высокопроизводительный LLM инференс с llama.cpp
- 📱 Нативная поддержка Android и iOS
- ⚡ GPU ускорение (Metal на iOS, Vulkan/OpenCL на Android)
- 🔄 Потоковая и блокирующая генерация текста
- 🎯 Полный контроль над параметрами генерации
- 📦 Поддержка формата GGUF моделей
- 🛠 Простая интеграция и использование

## 🎯 Рекомендуемая модель

Мы рекомендуем использовать модель [**braindler** от Ollama](https://ollama.com/nativemind/braindler) - компактную и эффективную модель, идеально подходящую для мобильных устройств.

**Доступные квантизации:**
- `braindler:q2_k` (72MB) - Самая быстрая, хорошее качество
- `braindler:q4_k_s` (88MB) - ⭐ **Рекомендуется** - Оптимальный баланс
- `braindler:q5_k_m` (103MB) - Выше качество
- `braindler:q8_0` (140MB) - Лучшее качество
- `braindler:f16` (256MB) - Максимальное качество

## 📦 Установка

Добавьте в `pubspec.yaml`:

```yaml
dependencies:
  flutter_llama:
    path: ../flutter_llama
```

Затем:

```bash
flutter pub get
```

## 🚀 Быстрый старт

### 1. Получите модель braindler

```bash
# Установите Ollama с https://ollama.com
# Затем загрузите модель
ollama pull nativemind/braindler:q4_k_s

# Экспортируйте в GGUF
ollama export nativemind/braindler:q4_k_s -o braindler-q4_k_s.gguf
```

### 2. Используйте в Flutter приложении

```dart
import 'package:flutter_llama/flutter_llama.dart';

// Получить instance
final llama = FlutterLlama.instance;

// Загрузить модель braindler
final config = LlamaConfig(
  modelPath: '/path/to/braindler-q4_k_s.gguf',
  nThreads: 4,
  nGpuLayers: -1,  // Все слои на GPU
  contextSize: 2048,
);

final success = await llama.loadModel(config);

// Генерация текста
if (success) {
  final params = GenerationParams(
    prompt: 'Привет! Как дела?',
    temperature: 0.8,
    maxTokens: 512,
  );
  
  final response = await llama.generate(params);
  print(response.text);
  print('${response.tokensPerSecond.toStringAsFixed(2)} tok/s');
}

// Выгрузить модель
await llama.unloadModel();
```

### 3. Потоковая генерация

```dart
await for (final token in llama.generateStream(params)) {
  print(token); // Каждый токен в реальном времени
}
```

## 📚 Документация

- **[README.md](README.md)** - Полная документация на английском
- **[QUICK_START.md](QUICK_START.md)** - Быстрый старт
- **[BRAINDLER_SETUP.md](BRAINDLER_SETUP.md)** - Подробная настройка модели braindler
- **[INTEGRATION_GUIDE.md](INTEGRATION_GUIDE.md)** - Руководство по интеграции
- **[example/](example/)** - Пример приложения

## 🎛️ Конфигурация

### Для мобильных устройств (рекомендуется)

```dart
final config = LlamaConfig(
  modelPath: '/path/to/braindler-q4_k_s.gguf',  // 88MB
  nThreads: 4,
  nGpuLayers: -1,  // Все слои на GPU
  contextSize: 2048,
  useGpu: true,
);
```

### Для слабых устройств

```dart
final config = LlamaConfig(
  modelPath: '/path/to/braindler-q2_k.gguf',  // 72MB
  nThreads: 2,
  nGpuLayers: 0,  // Только CPU
  contextSize: 1024,
  useGpu: false,
);
```

### Для мощных устройств

```dart
final config = LlamaConfig(
  modelPath: '/path/to/braindler-q8_0.gguf',  // 140MB
  nThreads: 6,
  nGpuLayers: -1,
  contextSize: 4096,
  useGpu: true,
);
```

## 💡 Примеры использования

### Духовный ассистент (mahamantra)

```dart
Future<String?> askSpiritualQuestion(String question) async {
  final llama = FlutterLlama.instance;
  
  final prompt = '''
Ты - духовный наставник в традиции вайшнавизма.

Вопрос: $question

Ответ:''';
  
  final params = GenerationParams(
    prompt: prompt,
    temperature: 0.8,
    maxTokens: 512,
  );
  
  final response = await llama.generate(params);
  return response.text;
}
```

### Мозгач-108 чат (flutter_мозgач)

```dart
Future<String> mozgachChat(String message) async {
  final llama = FlutterLlama.instance;
  
  final prompt = '''
Ты МОЗГАЧ-108 - квантово-запутанная система из 108 моделей.

Пользователь: $message
МОЗГАЧ-108:''';
  
  final params = GenerationParams(
    prompt: prompt,
    temperature: 0.8,
    maxTokens: 512,
  );
  
  final response = await llama.generate(params);
  return response.text;
}
```

## 📊 Производительность

Примерные результаты на разных устройствах с braindler q4_k_s:

| Устройство | Скорость | Память |
|------------|----------|---------|
| iPhone 13 Pro | ~25 tok/s | ~200MB |
| iPhone 11 | ~15 tok/s | ~180MB |
| Pixel 7 Pro | ~20 tok/s | ~220MB |
| Samsung S21 | ~18 tok/s | ~210MB |

## 🔧 Требования

### iOS
- iOS 13.0 или выше
- Xcode 14.0 или выше
- Metal поддержка для GPU

### Android
- Android API 24+ (Android 7.0+)
- NDK r25 или выше
- Vulkan поддержка для GPU (опционально)

## 🐛 Устранение проблем

**Модель не загружается:**
```dart
final file = File(modelPath);
if (!file.existsSync()) {
  print('Файл не найден: $modelPath');
}
```

**Медленная генерация:**
- Используйте braindler:q2_k (72MB)
- Увеличьте nGpuLayers до -1
- Уменьшите contextSize

**Нехватка памяти:**
- Используйте q2_k версию (72MB)
- Уменьшите contextSize до 1024
- Установите nGpuLayers: 0

## 🔗 Полезные ссылки

- **Модель Braindler**: https://ollama.com/nativemind/braindler
- **Ollama**: https://ollama.com
- **llama.cpp**: https://github.com/ggerganov/llama.cpp
- **Примеры**: [example/](example/)

## 📄 Лицензия

NativeMindNONC License (Non-Commercial) - см. файл LICENSE

⚠️ **Важно:** Этот пакет лицензирован для некоммерческого использования.
Для коммерческого использования свяжитесь с: licensing@nativemind.net

## 🙏 Благодарности

- [llama.cpp](https://github.com/ggerganov/llama.cpp) от Georgi Gerganov
- Команда Flutter за отличный фреймворк
- [Модель Braindler](https://ollama.com/nativemind/braindler) от Ollama

---

**Версия:** 0.1.0  
**Обновлено:** 21 октября 2025

