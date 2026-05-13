// lib/rag_engine.dart

/// Rescate RAG Engine package.
///
/// Provides a fully offline Retrieval-Augmented Generation pipeline:
///
/// ```dart
/// import 'package:rag_engine/rag_engine.dart';
///
/// final pipeline = RagPipeline(
///   store: await VectorStore.open(),
///   embedder: MobileRagEmbedder(),
/// );
/// await pipeline.initialize();
///
/// await pipeline.ingest(File('protocol.pdf'));
/// final result = await pipeline.query('What is the triage procedure?');
/// print(result.toLlmPrompt());
/// ```
library rag_engine;

// Exceptions
export 'rag/exceptions.dart';

// Data models
export 'rag/models.dart';

// Document parsers
export 'rag/parsers/document_parser.dart';
export 'rag/parsers/docx_parser.dart';
export 'rag/parsers/html_parser.dart';
export 'rag/parsers/markdown_parser.dart';
export 'rag/parsers/parser_registry.dart';
export 'rag/parsers/pdf_parser.dart';
export 'rag/parsers/txt_parser.dart';

// Embedding
export 'rag/embedder.dart';

// Pipeline orchestrator
export 'rag/pipeline.dart';
