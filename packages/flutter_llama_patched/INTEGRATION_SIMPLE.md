# Flutter Llama - Простая интеграция

## 🚀 Быстрый старт

### 1. Добавить зависимость

`pubspec.yaml`:
```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_llama:
    path: ../flutter_llama  # или git URL
```

### 2. Получить зависимости

```bash
flutter pub get
```

### 3. Готово! ✅

Никаких дополнительных настроек не требуется!

---

## 💡 Использование

### Базовый пример

```dart
import 'package:flutter_llama/flutter_llama.dart';

// Загрузить модель
final llama = FlutterLlama.instance;
final config = LlamaConfig(
  modelPath: '/path/to/model.gguf',
  nThreads: 4,
  contextSize: 2048,
);
await llama.loadModel(config);

// Генерировать текст
final params = GenerationParams(
  prompt: 'Привет!',
  maxTokens: 100,
);
final response = await llama.generate(params);
print(response.text);
```

---

## ✅ Что уже настроено

### iOS
- ✅ Статические библиотеки llama.cpp включены
- ✅ Metal GPU ускорение
- ✅ Accelerate framework оптимизация
- ✅ Работает на device и simulator
- ✅ Никаких внешних зависимостей

### macOS
- ✅ Универсальные библиотеки (ARM64 + x86_64)
- ✅ Metal GPU ускорение
- ✅ Accelerate framework
- ✅ Полностью автономно

### Android
- ✅ JNI интеграция
- ✅ NDK библиотеки
- ✅ Поддержка ARMv7, ARM64, x86_64

---

## 📱 Платформы

| Платформа | Статус | Версия |
|-----------|--------|--------|
| iOS | ✅ Работает | 13.0+ |
| macOS | ✅ Работает | 10.15+ |
| Android | ✅ Работает | API 21+ |

---

## ⚙️ Настройки (опционально)

### iOS Info.plist

Если используете мультимодальность (фото/аудио):

```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>Для обработки изображений</string>
<key>NSCameraUsageDescription</key>
<string>Для создания фото</string>
<key>NSMicrophoneUsageDescription</key>
<string>Для аудио запросов</string>
```

---

## 🎯 Примеры использования

### Простой чат

См. пример в `/example/lib/main.dart`

### Streaming генерация

```dart
await for (final response in llama.generateStream(params)) {
  print(response.text);
}
```

### Мультимодальность

```dart
final multimodal = FlutterLlamaMultimodal.instance;
final response = await multimodal.describeImage(
  '/path/to/image.jpg',
  'Что на этом изображении?',
);
```

---

## 🔧 Troubleshooting

### iOS build fails

```bash
cd ios
pod deintegrate
pod install
cd ..
flutter clean
flutter build ios
```

### macOS build fails

```bash
flutter clean
flutter pub get
flutter build macos
```

### Model не загружается

Убедитесь что:
- Файл .gguf существует
- Путь корректный
- Достаточно RAM

---

## 📖 Полная документация

- `README.md` - основная документация
- `PLUGIN_ARCHITECTURE.md` - архитектура плагина
- `INTEGRATION_SIMPLE.md` - этот файл
- `example/` - полный рабочий пример

---

## 🙌 Готово!

Flutter Llama плагин полностью готов к использованию!

**Приложения не заморачиваются с llama.cpp - все уже внутри плагина!** ✨

---

© 2025 NativeMind

