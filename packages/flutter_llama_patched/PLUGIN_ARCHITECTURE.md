# Flutter Llama Plugin Architecture

## 📦 Инкапсуляция llama.cpp

Flutter Llama плагин **полностью инкапсулирует llama.cpp** - приложения просто добавляют зависимость и все работает "из коробки".

### Принцип

```
Приложение (isridhar)
  ↓ просто добавляет в pubspec.yaml
flutter_llama (плагин)
  ↓ содержит внутри
llama.cpp (статические библиотеки)
  ✓ Приложение НЕ знает о llama.cpp
```

---

## 🏗️ Структура плагина

### iOS
```
ios/
├── Classes/
│   ├── FlutterLlamaPlugin.swift      # Swift интерфейс
│   └── llama_cpp_bridge.mm            # C++ bridge к llama.cpp
├── ios_libs/                          # ✅ Статические библиотеки (ARM64)
│   ├── libllama.a            (3.1 MB)
│   ├── libggml.a             (34 KB)
│   ├── libggml-base.a        (799 KB)
│   ├── libggml-cpu.a         (800 KB)
│   ├── libggml-metal.a       (712 KB)
│   └── libggml-blas.a        (20 KB)
└── flutter_llama.podspec              # Pod конфигурация
```

### macOS
```
macos/
├── Classes/
│   ├── FlutterLlamaPlugin.swift
│   └── llama_cpp_bridge.mm
├── macos_libs/                        # ✅ Статические библиотеки (ARM64 + x86_64)
│   ├── libllama.a            (6.3 MB)
│   ├── libggml.a             (69 KB)
│   ├── libggml-base.a        (1.5 MB)
│   ├── libggml-cpu.a         (1.5 MB)
│   ├── libggml-metal.a       (1.4 MB)
│   └── libggml-blas.a        (42 KB)
└── flutter_llama.podspec
```

### Android
```
android/
├── src/main/kotlin/
│   └── FlutterLlamaPlugin.kt
├── src/main/cpp/
│   └── llama_cpp_bridge.cpp
└── libs/                              # ✅ Shared libraries (.so)
    ├── arm64-v8a/libllama.so
    ├── armeabi-v7a/libllama.so
    └── x86_64/libllama.so
```

---

## 🔧 Сборка библиотек

### iOS (только один раз)

```bash
cd /Users/anton/llama.cpp

# Собрать для iOS Device (ARM64)
cmake -B build-ios-device \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=OFF \
  -DGGML_METAL=ON \
  -DGGML_ACCELERATE=ON \
  -DGGML_METAL_EMBED_LIBRARY=ON \
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
  -DLLAMA_CURL=OFF \
  -DGGML_BLAS=ON \
  -DLLAMA_BUILD_TESTS=OFF \
  -DLLAMA_BUILD_EXAMPLES=OFF \
  -DLLAMA_BUILD_SERVER=OFF

cmake --build build-ios-device --config Release --target llama -j8

# Скопировать в плагин
cd /Users/anton/proj/ai.nativemind.net/libs/flutter_llama
cp /Users/anton/llama.cpp/build-ios-device/src/libllama.a ios/ios_libs/
cp /Users/anton/llama.cpp/build-ios-device/ggml/src/libggml*.a ios/ios_libs/
```

### macOS (уже готово)

```bash
cd /Users/anton/llama.cpp

cmake -B build \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=OFF \
  -DGGML_METAL=ON \
  -DGGML_ACCELERATE=ON \
  -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON

cmake --build build --config Release --target llama ggml -j8

# Скопировать
cp build/src/libllama.a ../flutter_llama/macos/macos_libs/
cp build/ggml/src/libggml*.a ../flutter_llama/macos/macos_libs/
```

---

## 📱 Использование в приложении

### 1. Добавить зависимость

`pubspec.yaml`:
```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_llama:
    path: ../flutter_llama  # или git/pub.dev
```

### 2. Готово! ✅

```bash
flutter pub get
flutter run
```

**Никаких дополнительных настроек не требуется!**

---

## ✨ Преимущества

### Для разработчиков приложений
- ✅ **Нулевая конфигурация** - просто добавь в pubspec.yaml
- ✅ Не нужно знать о llama.cpp
- ✅ Не нужно собирать нативные библиотеки
- ✅ Работает сразу на iOS, macOS, Android
- ✅ `flutter pub get` и готово!

### Для плагина
- ✅ Полная инкапсуляция зависимостей
- ✅ Статические библиотеки в репозитории
- ✅ Единообразный подход для всех платформ
- ✅ Простое обновление llama.cpp

---

## 🔄 Обновление llama.cpp

Когда выходит новая версия llama.cpp:

```bash
# 1. Обновить исходники
cd /Users/anton/llama.cpp
git pull

# 2. Пересобрать библиотеки (iOS + macOS)
# ... команды выше ...

# 3. Скопировать в плагин
# ... команды выше ...

# 4. Обновить версию плагина
cd /Users/anton/proj/ai.nativemind.net/libs/flutter_llama
# Изменить version в pubspec.yaml и podspec

# 5. Готово!
```

---

## 📊 Размеры

| Платформа | Библиотеки | Размер |
|-----------|------------|--------|
| iOS (device) | 6 файлов .a | ~5.5 MB |
| macOS (universal) | 6 файлов .a | ~11 MB |
| Android (arm64) | libllama.so | ~4 MB |

**Итого в репозитории**: ~20 MB статических библиотек

### Рекомендация: Git LFS

```bash
cd /Users/anton/proj/ai.nativemind.net/libs/flutter_llama
git lfs track "*.a"
git lfs track "*.so"
git add .gitattributes
git add ios/ios_libs/*.a macos/macos_libs/*.a
git commit -m "Add pre-built llama.cpp libraries"
```

---

## 🎯 Итог

### До изменений:
```
❌ Приложение должно знать о llama.cpp
❌ Нужно настраивать podspec вручную
❌ Проблемы с линковкой
❌ Сложная интеграция
```

### После изменений:
```
✅ Приложение просто добавляет flutter_llama
✅ Все работает "из коробки"
✅ Никаких проблем с линковкой
✅ Простая интеграция
✅ iOS сборка работает!
```

---

## 🔍 Проверка

### Команда для теста:
```bash
cd /Users/anton/proj/ai.nativemind.net/libs/isridhar
flutter clean
flutter pub get
flutter build ios --release --no-codesign
```

### Ожидаемый результат:
```
✓ Built build/ios/iphoneos/Runner.app (94.5MB)
```

✅ **РАБОТАЕТ!**

---

**Дата**: 28 октября 2025  
**Статус**: ✅ iOS линковка исправлена  
**Результат**: Приложения могут использовать flutter_llama без знания о llama.cpp

