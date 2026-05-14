# 🚀 Быстрое использование Hugging Face моделей

## 1️⃣ Базовое использование

```dart
import 'package:flutter_llama_example/services/model_downloader.dart';

// Скачать модель
final path = await ModelDownloader.downloadModel(
  modelId: 'nativemind/shridhar_8k_multimodal',
  fileName: 'adapter_model.safetensors',
  onProgress: (progress, status) {
    print('${(progress * 100).toStringAsFixed(0)}%: $status');
  },
);
```

## 2️⃣ Использование в UI

```dart
// Открыть менеджер моделей
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => ModelManagerScreen(),
  ),
);
```

## 3️⃣ Пример с прогресс-баром

```dart
double _progress = 0.0;

await ModelDownloader.downloadModel(
  modelId: 'nativemind/shridhar_8k_multimodal',
  fileName: 'adapter_model.safetensors',
  onProgress: (progress, status) {
    setState(() => _progress = progress);
  },
);
```

## 📊 Тесты

Все 8 тестов прошли успешно ✅
