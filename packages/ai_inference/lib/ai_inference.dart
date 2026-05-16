// packages/ai_inference/lib/ai_inference.dart

/// Rescate AI Inference package.
///
/// Provides fully offline LLM inference via llama.cpp (flutter_llama).
///
/// ### Quick start
/// ```dart
/// import 'package:ai_inference/ai_inference.dart';
///
/// // Load a user-provided GGUF model file once.
/// await LlmService.instance.loadModel('/path/to/model.gguf');
///
/// // Stream tokens into the UI.
/// await for (final token in LlmService.instance.generateStream(userQuery)) {
///   setState(() => buffer += token);
/// }
/// ```
library ai_inference;

export 'src/device_profile.dart';
export 'src/legacy_rag.dart';
export 'src/llm_config.dart';
export 'src/llm_service.dart';
