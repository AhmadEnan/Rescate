// lib/rag/exceptions.dart

/// Typed exceptions for the RAG pipeline.
///
/// All public methods in [RagPipeline], parsers, and [EmbeddingEngine] catch
/// platform/library exceptions and re-throw as one of these types so callers
/// can handle errors without inspecting opaque [Exception] messages.

/// Thrown when a document cannot be parsed.
///
/// Common causes: corrupt file, unsupported encoding, password-protected PDF.
class RagParseException implements Exception {
  /// Human-readable description of why parsing failed.
  final String message;

  /// The underlying error, if any (e.g. a library-specific exception).
  final Object? cause;

  /// Creates a [RagParseException].
  const RagParseException(this.message, {this.cause});

  @override
  String toString() =>
      'RagParseException: $message${cause != null ? ' (cause: $cause)' : ''}';
}

/// Thrown when an embedding model fails to initialise or run inference.
class RagEmbedException implements Exception {
  /// Human-readable description of the embedding failure.
  final String message;

  /// The underlying error, if any.
  final Object? cause;

  /// Creates a [RagEmbedException].
  const RagEmbedException(this.message, {this.cause});

  @override
  String toString() =>
      'RagEmbedException: $message${cause != null ? ' (cause: $cause)' : ''}';
}

/// Thrown when a [VectorStore] operation fails.
class RagStoreException implements Exception {
  /// Human-readable description of the store failure.
  final String message;

  /// The underlying error, if any.
  final Object? cause;

  /// Creates a [RagStoreException].
  const RagStoreException(this.message, {this.cause});

  @override
  String toString() =>
      'RagStoreException: $message${cause != null ? ' (cause: $cause)' : ''}';
}

/// Thrown when the ONNX / TFLite model file cannot be found.
///
/// Usually means the asset has not been downloaded yet or the asset path in
/// `pubspec.yaml` is incorrectly configured.
class RagModelNotFoundException implements Exception {
  /// The asset path that was not found.
  final String assetPath;

  /// Creates a [RagModelNotFoundException].
  const RagModelNotFoundException(this.assetPath);

  @override
  String toString() =>
      'RagModelNotFoundException: Model not found at "$assetPath". '
      'Run scripts/download_models.sh and add the file to assets/.';
}

/// Thrown by [ParserRegistry] when no parser is registered for a file
/// extension.
class UnsupportedFormatException implements Exception {
  /// The unsupported file extension (e.g. `.xyz`).
  final String extension;

  /// Creates an [UnsupportedFormatException].
  const UnsupportedFormatException(this.extension);

  @override
  String toString() =>
      'UnsupportedFormatException: No parser registered for extension '
      '"$extension". Supported: .pdf, .docx, .txt, .md, .html, .htm';
}
