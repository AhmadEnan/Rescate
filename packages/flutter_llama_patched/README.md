# flutter_llama

Flutter plugin for running LLM inference with llama.cpp and GGUF models on Android, iOS, and macOS.

## 🎉 Version 1.0.0 - Production Ready with Full GPU Acceleration!

## Features

- 🚀 High-performance LLM inference using llama.cpp
- 📱 Native support for Android, iOS, and macOS
- ⚡ **Full GPU acceleration:**
  - **Metal** for iOS/macOS (3-10x faster)
  - **Vulkan** for Android (4-8x faster)
  - **OpenCL** fallback (2-5x faster)
  - Automatic GPU detection and fallback
- 🔄 Streaming and blocking text generation
- 🎯 Full control over generation parameters
- 📦 GGUF model format (industry standard)
- 🛠 Easy to integrate and production-ready
- ✅ 71 unit tests, fully tested

## Installation

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
  flutter_llama:
    path: ../flutter_llama  # Adjust path as needed
```

Then run:

```bash
flutter pub get
```

## Usage

### 1. Load a Model

We recommend using the [braindler model from Ollama](https://ollama.com/nativemind/braindler) - a compact and efficient model perfect for mobile devices.

```dart
import 'package:flutter_llama/flutter_llama.dart';

final llama = FlutterLlama.instance;

// Using braindler Q4_K_M quantization (88MB - optimal balance)
final config = LlamaConfig(
  modelPath: '/path/to/braindler-q4_k_s.gguf',  // braindler from ollama.com/nativemind/braindler
  nThreads: 4,
  nGpuLayers: 0,  // 0 = CPU only, -1 = all layers on GPU
  contextSize: 2048,
  batchSize: 512,
  useGpu: true,
  verbose: false,
);

final success = await llama.loadModel(config);
if (success) {
  print('Braindler model loaded successfully!');
}
```

### 2. Generate Text (Blocking)

```dart
final params = GenerationParams(
  prompt: 'Hello, how are you?',
  temperature: 0.8,
  topP: 0.95,
  topK: 40,
  maxTokens: 512,
  repeatPenalty: 1.1,
);

try {
  final response = await llama.generate(params);
  print('Generated: ${response.text}');
  print('Tokens: ${response.tokensGenerated}');
  print('Speed: ${response.tokensPerSecond.toStringAsFixed(2)} tok/s');
} catch (e) {
  print('Error: $e');
}
```

### 3. Generate Text (Streaming)

```dart
final params = GenerationParams(
  prompt: 'Tell me a story',
  maxTokens: 1000,
);

try {
  await for (final token in llama.generateStream(params)) {
    print(token); // Print each token as it's generated
  }
} catch (e) {
  print('Error: $e');
}
```

### 4. Get Model Info

```dart
final info = await llama.getModelInfo();
if (info != null) {
  print('Model path: ${info['modelPath']}');
  print('Parameters: ${info['nParams']}');
  print('Layers: ${info['nLayers']}');
  print('Context size: ${info['contextSize']}');
}
```

### 5. Unload Model

```dart
await llama.unloadModel();
print('Model unloaded');
```

## Configuration Options

### LlamaConfig

- `modelPath` (String, required): Path to the GGUF model file
- `nThreads` (int, default: 4): Number of CPU threads to use
- `nGpuLayers` (int, default: 0): Number of layers to offload to GPU (0 = CPU only, -1 = all)
- `contextSize` (int, default: 2048): Context size in tokens
- `batchSize` (int, default: 512): Batch size for processing
- `useGpu` (bool, default: true): Enable GPU acceleration
- `verbose` (bool, default: false): Enable verbose logging

### GenerationParams

- `prompt` (String, required): The prompt for text generation
- `temperature` (double, default: 0.8): Sampling temperature (0.0 - 2.0)
- `topP` (double, default: 0.95): Top-P sampling (0.0 - 1.0)
- `topK` (int, default: 40): Top-K sampling
- `maxTokens` (int, default: 512): Maximum tokens to generate
- `repeatPenalty` (double, default: 1.1): Penalty for repeating tokens
- `stopSequences` (List<String>, default: []): Sequences that stop generation

## Example App

See the `example` directory for a complete example application.

## Performance Tips

### 🚀 GPU Acceleration (NEW in v1.0.0!)

**GPU acceleration is now fully enabled and automatic!**

1. **iOS/macOS (Metal)**: 
   ```dart
   nGpuLayers: -1,  // -1 = all layers on Metal GPU
   useGpu: true,    // Metal automatically detected
   ```
   - **Performance:** 3-10x faster than CPU
   - **Devices:** iPhone 8+, iPad Pro, MacBook Pro
   - **Expected:** ~45-50 tok/s on iPhone 14 Pro

2. **Android (Vulkan/OpenCL)**:
   ```dart
   nGpuLayers: -1,  // -1 = all layers on GPU
   useGpu: true,    // Vulkan auto-detected, fallback to OpenCL
   ```
   - **Performance:** 4-8x faster than CPU (Vulkan), 2-5x (OpenCL)
   - **Devices:** Android 7.0+ with Vulkan support
   - **Expected:** ~18-25 tok/s on flagship devices
   - **Fallback:** Automatically uses OpenCL if Vulkan unavailable

3. **Threading** (CPU fallback): Adjust `nThreads` based on device:
   - Mobile devices: 4-6 threads
   - High-end devices: 6-8 threads

4. **Model Size**: Use braindler quantized models for better performance:
   - braindler:q2_k (72MB): Smallest, fastest, good quality
   - braindler:q4_k_s (88MB): ⭐ **Recommended** - Optimal balance
   - braindler:q5_k_m (103MB): Higher quality, larger size
   - braindler:q8_0 (140MB): Best quality, largest size
   
   Get from: https://ollama.com/nativemind/braindler

4. **Context Size**: Reduce if memory is limited:
   - Small devices: 1024-2048
   - Medium devices: 2048-4096
   - High-end devices: 4096-8192

## Requirements

### iOS

- iOS 13.0 or later
- Xcode 14.0 or later
- Metal support for GPU acceleration

### Android

- Android API level 24 (Android 7.0) or later
- NDK r25 or later
- Vulkan support for GPU acceleration (optional)

## Building

The plugin includes native C++ code for llama.cpp integration. 

### iOS

The iOS framework will be built automatically when you build your Flutter app.

### Android

The Android native library will be built automatically using CMake/NDK.

## GGUF Models

This plugin supports GGUF model format. We recommend using the **braindler** model:

### Recommended: Braindler Model

Get the braindler model from [Ollama](https://ollama.com/nativemind/braindler):

**Available quantizations:**
- `braindler:q2_k` - 72MB - Fastest, good quality
- `braindler:q3_k_s` - 77MB - Better quality
- `braindler:q4_k_s` - 88MB - ⭐ **Recommended** - Optimal balance
- `braindler:q5_k_m` - 103MB - Higher quality
- `braindler:q8_0` - 140MB - Best quality
- `braindler:f16` - 256MB - Maximum quality

**How to get braindler models:**

1. Install Ollama: https://ollama.com
2. Pull the model: `ollama pull nativemind/braindler:q4_k_s`
3. Export to GGUF: `ollama export nativemind/braindler:q4_k_s -o braindler-q4_k_s.gguf`
4. Copy the GGUF file to your app's assets or documents directory

### Other model sources:
- [TheBloke on Hugging Face](https://huggingface.co/TheBloke)
- [Hugging Face GGUF models](https://huggingface.co/models?search=gguf)

## Limitations

- Model file must be accessible on device storage
- Large models require significant RAM
- Generation speed depends on device capabilities
- Some older devices may not support GPU acceleration

## License

This plugin is released under the NativeMindNONC License. See LICENSE file for details.

llama.cpp is released under the MIT License.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Acknowledgments

- [llama.cpp](https://github.com/ggerganov/llama.cpp) by Georgi Gerganov
- The Flutter team for the excellent framework
- [Braindler model](https://ollama.com/nativemind/braindler) from Ollama - recommended model for mobile devices
