// lib/rag/embedder.dart

import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:mobile_rag_engine/services/embedding_service.dart';

import 'exceptions.dart';

/// Abstract interface for embedding text into a fixed-size float vector.
///
/// Decouples the [RagPipeline] from the concrete embedding backend.
/// The default implementation ([MobileRagEmbedder]) delegates to
/// `mobile_rag_engine`'s [EmbeddingService] which runs ONNX inference on a
/// background Isolate. If the package proves incompatible (e.g. ARMv7 ABI
/// issue), swap the implementation without touching any other code.
abstract class RagEmbedder {
  /// Initialises the embedding model.
  ///
  /// Must be called once before [embed] or [embedBatch].
  Future<void> initialize();

  /// Embeds a single [text] into a unit-norm float vector.
  ///
  /// Empty [text] inputs return a zero vector rather than throwing.
  Future<List<double>> embed(String text);

  /// Embeds a list of [texts] as a batch.
  ///
  /// Returns a list of vectors in the same order as the input.
  Future<List<List<double>>> embedBatch(List<String> texts);

  /// Releases any native resources held by the embedding model.
  Future<void> dispose();
}

// ─────────────────────────────────────────────────────────────────────────────

/// [RagEmbedder] backed by `mobile_rag_engine`'s [EmbeddingService].
///
/// ### Model path
/// [modelPath] must be an absolute filesystem path to the ONNX model file.
/// The model **must** be copied from Flutter assets to the filesystem before
/// calling [initialize]. Recommended pattern:
///
/// ```dart
/// final dir = await getApplicationDocumentsDirectory();
/// final modelPath = '${dir.path}/model.onnx';
/// if (!File(modelPath).existsSync()) {
///   final data = await rootBundle.load('assets/models/model.onnx');
///   await File(modelPath).writeAsBytes(data.buffer.asUint8List());
/// }
/// final embedder = MobileRagEmbedder(modelPath: modelPath);
/// await embedder.initialize();
/// ```
///
/// ### LRU cache
/// Query embeddings are cached in a 64-slot LRU cache to avoid re-running
/// the model for repeated or near-simultaneous queries.
class MobileRagEmbedder implements RagEmbedder {
  /// Absolute filesystem path to the ONNX model binary.
  final String modelPath;

  static const _cacheCapacity = 64;

  /// LRU cache: text → embedding vector.
  final _cache = LinkedHashMap<String, List<double>>();

  bool _initialised = false;

  /// Creates a [MobileRagEmbedder].
  ///
  /// [modelPath] must point to an existing ONNX model file on the filesystem.
  MobileRagEmbedder({required this.modelPath});

  @override
  Future<void> initialize() async {
    if (_initialised) return;
    try {
      await EmbeddingService.init(modelPath: modelPath);
      _initialised = true;
    } catch (e) {
      debugPrint('[MobileRagEmbedder] init error: $e');
      throw RagEmbedException(
        'Failed to initialise embedding model at $modelPath',
        cause: e,
      );
    }
  }

  @override
  Future<List<double>> embed(String text) async {
    _assertInitialised();

    if (text.isEmpty) return List<double>.filled(384, 0.0);

    // Check LRU cache first.
    if (_cache.containsKey(text)) {
      final cached = _cache.remove(text)!;
      _cache[text] = cached; // move to end (most-recently-used)
      return cached;
    }

    try {
      final vec = await EmbeddingService.embed(text);
      _insertCache(text, vec);
      return vec;
    } catch (e) {
      debugPrint('[MobileRagEmbedder] embed error: $e');
      throw RagEmbedException('Embedding failed', cause: e);
    }
  }

  @override
  Future<List<List<double>>> embedBatch(List<String> texts) async {
    _assertInitialised();

    if (texts.isEmpty) return [];

    try {
      return await EmbeddingService.embedBatch(texts);
    } catch (e) {
      debugPrint(
        '[MobileRagEmbedder] embedBatch error, falling back to sequential: $e',
      );
      // Fallback: sequential processing if native batch fails.
      final result = <List<double>>[];
      for (final t in texts) {
        result.add(await embed(t));
      }
      return result;
    }
  }

  @override
  Future<void> dispose() async {
    _cache.clear();
    _initialised = false;
    try {
      await EmbeddingService.disposeAsync();
    } catch (_) {}
  }

  void _assertInitialised() {
    if (!_initialised) {
      throw RagEmbedException(
        'MobileRagEmbedder.initialize() must be called before embed()',
      );
    }
  }

  void _insertCache(String text, List<double> vec) {
    if (_cache.length >= _cacheCapacity) {
      _cache.remove(_cache.keys.first);
    }
    _cache[text] = vec;
  }
}
