// lib/rag/parsers/markdown_parser.dart

import 'dart:io';

import 'package:flutter/foundation.dart';

import '../exceptions.dart';
import 'document_parser.dart';
import 'txt_parser.dart';

/// Parser for Markdown files (`.md`, `.markdown`).
///
/// Strips Markdown syntax using regex patterns and returns plain text suitable
/// for embedding. No HTML rendering is performed — only syntax stripping.
///
/// Patterns handled:
/// - ATX headings (`# Title`)
/// - Setext headings (`===`, `---` underlines)
/// - Bold / italic (`**`, `__`, `*`, `_`)
/// - Inline code (`` `code` ``)
/// - Fenced code blocks (` ``` `)
/// - Block quotes (`> `)
/// - Unordered / ordered list markers (`- `, `* `, `1. `)
/// - Inline links `[text](url)` → `text`
/// - Reference links `[text][ref]` → `text`
/// - Images `![alt](url)` → `alt`
/// - Horizontal rules (`---`, `===`, `***`)
class MarkdownParser extends DocumentParser {
  /// Creates a [MarkdownParser].
  const MarkdownParser();

  @override
  Future<String> parse(File file) async {
    if (await file.length() == 0) return '';

    try {
      final raw = decodeTextBytes(await file.readAsBytes());
      return stripMarkdown(raw);
    } on RagParseException {
      rethrow;
    } catch (e) {
      debugPrint('[MarkdownParser] parse error for ${file.path}: $e');
      throw RagParseException(
        'Failed to parse Markdown: ${file.path}',
        cause: e,
      );
    }
  }

  /// Strips Markdown syntax from [input] and returns plain text.
  ///
  /// Exposed as a static helper for tests and in-memory usage.
  static String stripMarkdown(String input) {
    if (input.isEmpty) return '';
    var s = input;

    // Fenced code blocks (``` ... ```) — strip markers, keep content.
    s = s.replaceAll(
      RegExp(r'```[^\n]*\n([\s\S]*?)```', multiLine: true),
      r'$1',
    );

    // ATX headings — strip leading #'s.
    s = s.replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '');

    // Setext heading underlines.
    s = s.replaceAll(RegExp(r'^[=\-]{2,}\s*$', multiLine: true), '');

    // Block quotes.
    s = s.replaceAll(RegExp(r'^>\s?', multiLine: true), '');

    // Images — keep alt text.
    s = s.replaceAll(RegExp(r'!\[([^\]]*)\]\([^)]*\)'), r'$1');

    // Inline links — keep link text.
    s = s.replaceAll(RegExp(r'\[([^\]]+)\]\([^)]*\)'), r'$1');

    // Reference links — keep link text.
    s = s.replaceAll(RegExp(r'\[([^\]]+)\]\[[^\]]*\]'), r'$1');

    // Bold / italic (must process ** before *).
    s = s.replaceAll(RegExp(r'\*\*([^*]+)\*\*'), r'$1');
    s = s.replaceAll(RegExp(r'__([^_]+)__'), r'$1');
    s = s.replaceAll(RegExp(r'\*([^*]+)\*'), r'$1');
    s = s.replaceAll(RegExp(r'_([^_]+)_'), r'$1');

    // Inline code.
    s = s.replaceAll(RegExp(r'`([^`]+)`'), r'$1');

    // Horizontal rules.
    s = s.replaceAll(RegExp(r'^[-*_]{3,}\s*$', multiLine: true), '');

    // Unordered list markers.
    s = s.replaceAll(RegExp(r'^[\*\-\+]\s+', multiLine: true), '');

    // Ordered list markers.
    s = s.replaceAll(RegExp(r'^\d+\.\s+', multiLine: true), '');

    // Collapse excessive blank lines.
    s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    return s.trim();
  }
}
