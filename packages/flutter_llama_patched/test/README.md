# Flutter Llama Tests

Comprehensive test suite for the Flutter Llama plugin, including unit tests, integration tests, and dynamic model loading from Ollama.

## Test Structure

```
test/
├── models/                          # Unit tests for data models
│   ├── llama_config_test.dart
│   ├── generation_params_test.dart
│   └── llama_response_test.dart
├── helpers/                         # Test utilities
│   └── ollama_model_downloader.dart
└── flutter_llama_test.dart          # Main plugin unit tests

example/integration_test/
├── plugin_integration_test.dart     # Basic integration tests
└── ollama_integration_test.dart     # Ollama model integration tests
```

## Prerequisites

### Required Dependencies

Install the following dependencies:

```bash
flutter pub get
cd example && flutter pub get
```

### Ollama Installation (for integration tests)

For dynamic model loading tests, install Ollama:

**macOS:**
```bash
brew install ollama
```

**Linux:**
```bash
curl -fsSL https://ollama.com/install.sh | sh
```

**Windows:**
Download from [https://ollama.com](https://ollama.com)

### Download Test Model

Pull the Braindler model from Ollama:

```bash
# Smallest variant for faster testing (72MB)
ollama pull nativemind/braindler:q2_k

# Other available variants:
# ollama pull nativemind/braindler:q3_k_s  # 77MB
# ollama pull nativemind/braindler:q4_k_s  # 88MB
# ollama pull nativemind/braindler:q5_k_m  # 103MB
# ollama pull nativemind/braindler:q8_0    # 140MB
# ollama pull nativemind/braindler:f16     # 256MB
# ollama pull nativemind/braindler:latest  # 94MB
```

## Running Tests

### Unit Tests

Run all unit tests (no device/emulator required):

```bash
# From project root
flutter test

# Run specific test file
flutter test test/models/llama_config_test.dart

# Run with coverage
flutter test --coverage
```

### Integration Tests

Integration tests require a device or emulator.

#### Basic Integration Tests

```bash
cd example

# Run on connected device
flutter test integration_test/plugin_integration_test.dart

# Run on specific device
flutter test integration_test/plugin_integration_test.dart -d <device-id>
```

#### Ollama Integration Tests

These tests download and load real GGUF models:

```bash
cd example

# Run Ollama integration tests
flutter test integration_test/ollama_integration_test.dart

# Run on Android
flutter test integration_test/ollama_integration_test.dart -d <android-device>

# Run on iOS
flutter test integration_test/ollama_integration_test.dart -d <ios-device>
```

**Note:** These tests may take several minutes on first run as they download models.

### Run All Tests

```bash
# Unit tests
flutter test

# Integration tests (requires device)
cd example
flutter test integration_test/
```

## Test Details

### Unit Tests

#### Model Tests (`test/models/`)

- **llama_config_test.dart**: Tests for LlamaConfig class
  - Default and custom configurations
  - Serialization (toMap)
  - GPU layer configurations
  
- **generation_params_test.dart**: Tests for GenerationParams class
  - Default and custom parameters
  - Temperature, topP, topK variations
  - Stop sequences handling
  
- **llama_response_test.dart**: Tests for LlamaResponse class
  - Response creation and parsing
  - Tokens per second calculation
  - Various generation speeds

#### Plugin Tests (`test/flutter_llama_test.dart`)

- Singleton pattern
- Model loading/unloading
- Text generation with mocks
- State management
- Error handling

### Integration Tests

#### Basic Integration (`example/integration_test/plugin_integration_test.dart`)

- Platform version retrieval
- Basic plugin functionality

#### Ollama Integration (`example/integration_test/ollama_integration_test.dart`)

- **Model Download & Validation**
  - Downloads GGUF models from Ollama
  - Validates GGUF file format
  - Checks file integrity

- **Model Loading**
  - Loads models with various configurations
  - Tests different thread counts
  - Tests different context sizes

- **Text Generation**
  - Single prompt generation
  - Multiple sequential generations
  - Different temperature settings
  - Generation performance metrics

- **Model Management**
  - Model info retrieval
  - Model unloading
  - State transitions

## Test Helpers

### OllamaModelDownloader

Located in `test/helpers/ollama_model_downloader.dart`, provides utilities for:

- Downloading models from Ollama
- Finding locally installed Ollama models
- Validating GGUF file format
- Model information and variants

**Available Models:**
- `q2_k`: 72MB (fastest, lowest quality)
- `q3_k_s`: 77MB
- `q4_k_s`: 88MB (recommended for testing)
- `q5_k_m`: 103MB
- `q8_0`: 140MB
- `f16`: 256MB (highest quality)
- `latest`: 94MB (default)

## Troubleshooting

### Tests Skip or Fail

**Issue:** Integration tests skip automatically
**Solution:** Ensure Ollama is installed and model is pulled:
```bash
ollama pull nativemind/braindler:q2_k
```

### Model Download Fails

**Issue:** Cannot download models
**Solution:** 
1. Check internet connection
2. Ensure sufficient disk space
3. Verify Ollama is running: `ollama list`

### Platform-Specific Issues

**Android:**
- Ensure minimum SDK version: 21
- Check device has sufficient RAM (2GB+)
- Enable developer mode and USB debugging

**iOS:**
- Check deployment target: iOS 12.0+
- Run on physical device for best performance
- Simulators may be slower

### Performance Issues

**Issue:** Tests timeout
**Solution:**
- Use smaller models (q2_k variant)
- Reduce maxTokens in GenerationParams
- Increase test timeout duration
- Run on physical device instead of emulator

### Memory Issues

**Issue:** Out of memory errors
**Solution:**
- Close other apps
- Use smaller model variants
- Reduce contextSize in LlamaConfig
- Unload model when done

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Tests

on: [push, pull_request]

jobs:
  unit-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.x'
      - run: flutter pub get
      - run: flutter test --coverage
      - uses: codecov/codecov-action@v3

  integration-tests:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      - uses: subosito/flutter-action@v2
      - run: flutter pub get
      - run: cd example && flutter pub get
      - run: brew install ollama
      - run: ollama pull nativemind/braindler:q2_k
      - run: cd example && flutter test integration_test/
```

## Test Coverage

Generate and view test coverage:

```bash
# Generate coverage
flutter test --coverage

# View HTML report (requires lcov)
genhtml coverage/lcov.info -o coverage/html
open coverage/html/index.html
```

## Best Practices

1. **Run unit tests frequently** during development
2. **Run integration tests** before commits
3. **Use smallest model variant** (q2_k) for faster testing
4. **Mock platform calls** in unit tests
5. **Clean up resources** in test tearDown
6. **Set appropriate timeouts** for integration tests
7. **Test on both platforms** (Android & iOS)

## Contributing

When adding new features:

1. Write unit tests first (TDD approach)
2. Add integration tests for end-to-end flows
3. Update this README with new test information
4. Ensure all tests pass before submitting PR

## Resources

- [Flutter Testing Documentation](https://docs.flutter.dev/testing)
- [Ollama Documentation](https://github.com/ollama/ollama)
- [Integration Testing Guide](https://docs.flutter.dev/testing/integration-tests)
- [Braindler Models](https://ollama.com/nativemind/braindler)

## License

See LICENSE file in project root.






