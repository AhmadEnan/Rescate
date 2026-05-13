// lib/rag/parsers/parser_registry.dart

import 'dart:io';

import '../exceptions.dart';
import 'document_parser.dart';
import 'docx_parser.dart';
import 'html_parser.dart';
import 'markdown_parser.dart';
import 'pdf_parser.dart';
import 'txt_parser.dart';

/// Registry that maps file extensions to [DocumentParser] implementations.
///
/// Extensions are matched **case-insensitively** (`.PDF` == `.pdf`).
///
/// ### Supported formats
/// | Extension       | Parser           |
/// |-----------------|------------------|
/// | `.pdf`          | [PdfParser]      |
/// | `.docx`         | [DocxParser]     |
/// | `.txt`          | [TxtParser]      |
/// | `.md`, `.markdown` | [MarkdownParser] |
/// | `.html`, `.htm` | [HtmlParser]     |
///
/// ### Extending
/// Call [register] to add support for additional formats:
/// ```dart
/// ParserRegistry.instance.register('.epub', MyEpubParser());
/// ```
class ParserRegistry {
  ParserRegistry._();

  /// The singleton registry instance.
  static final instance = ParserRegistry._()
    .._register('.pdf', const PdfParser())
    .._register('.docx', const DocxParser())
    .._register('.txt', const TxtParser())
    .._register('.md', const MarkdownParser())
    .._register('.markdown', const MarkdownParser())
    .._register('.html', const HtmlParser())
    .._register('.htm', const HtmlParser());

  final _parsers = <String, DocumentParser>{};

  void _register(String ext, DocumentParser parser) {
    _parsers[ext.toLowerCase()] = parser;
  }

  /// Registers a custom [parser] for the given file [extension].
  ///
  /// [extension] must include the leading dot (e.g. `'.epub'`). Calling this
  /// with an already-registered extension replaces the existing parser.
  void register(String extension, DocumentParser parser) {
    _register(extension, parser);
  }

  /// Returns the [DocumentParser] for [file]'s extension.
  ///
  /// Throws [UnsupportedFormatException] if no parser is registered for the
  /// extension.
  DocumentParser parserFor(File file) {
    final ext = _extensionOf(file).toLowerCase();
    final parser = _parsers[ext];
    if (parser == null) {
      throw UnsupportedFormatException(ext.isEmpty ? '(no extension)' : ext);
    }
    return parser;
  }

  /// Returns the [DocumentParser] registered for [extension].
  ///
  /// [extension] is matched case-insensitively.
  ///
  /// Throws [UnsupportedFormatException] if not found.
  DocumentParser parserForExtension(String extension) {
    final ext = extension.toLowerCase();
    final parser = _parsers[ext];
    if (parser == null) throw UnsupportedFormatException(ext);
    return parser;
  }

  static String _extensionOf(File file) {
    final name = file.path.split('/').last.split('\\').last;
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot);
  }
}
