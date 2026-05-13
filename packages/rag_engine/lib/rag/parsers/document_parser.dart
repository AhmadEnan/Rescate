// lib/rag/parsers/document_parser.dart

import 'dart:io';

import '../exceptions.dart';

/// Abstract base class for all document parsers.
///
/// Each concrete parser knows how to extract plain text from one specific file
/// format. Use [ParserRegistry] to resolve the correct parser from a file
/// extension rather than instantiating parsers directly.
///
/// ### Contract
/// - **Empty files**: return an empty string — do **not** throw.
/// - **Corrupt / malformed files**: throw [RagParseException].
/// - **Password-protected PDFs**: throw [RagParseException] with the
///   message `"Password-protected document"`.
/// - **Files > 50 MB**: implementations should stream content in chunks and
///   concatenate, rather than loading the entire file into RAM.
/// - **Non-UTF-8 encoding**: attempt latin-1 fallback, then CP-1252.
abstract class DocumentParser {
  /// Creates a [DocumentParser].
  const DocumentParser();

  /// Parses [file] and returns its extracted plain text.
  ///
  /// The returned string may be empty if the file contains no extractable
  /// text. Never returns `null`.
  ///
  /// Throws [RagParseException] if the file is corrupt, unreadable, or
  /// otherwise unparseable.
  Future<String> parse(File file);
}
