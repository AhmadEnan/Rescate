// lib/rag/parsers/html_parser.dart

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;

import '../exceptions.dart';
import 'document_parser.dart';
import 'txt_parser.dart';

/// Parser for HTML files (`.html`, `.htm`).
///
/// Uses the `html` package to parse the DOM and then walks all text nodes,
/// discarding `<script>`, `<style>`, and comment nodes.
///
/// Malformed / unclosed tags are handled gracefully by the lenient parser.
class HtmlParser extends DocumentParser {
  /// Creates an [HtmlParser].
  const HtmlParser();

  @override
  Future<String> parse(File file) async {
    if (await file.length() == 0) return '';

    try {
      final raw = decodeTextBytes(await file.readAsBytes());
      return parseHtmlString(raw);
    } on RagParseException {
      rethrow;
    } catch (e) {
      debugPrint('[HtmlParser] parse error for ${file.path}: $e');
      throw RagParseException('Failed to parse HTML: ${file.path}', cause: e);
    }
  }

  /// Strips all HTML tags from [htmlString] and returns plain text.
  ///
  /// Exposed as a static helper so [DocxParser] and tests can call it on raw
  /// HTML strings without creating a [File].
  static String parseHtmlString(String htmlString) {
    if (htmlString.isEmpty) return '';
    try {
      final document = html_parser.parse(htmlString);

      // Remove script and style elements.
      for (final el in document.querySelectorAll('script, style')) {
        el.remove();
      }

      final text = document.body?.text ?? document.documentElement?.text ?? '';
      // Collapse whitespace.
      return text.replaceAll(RegExp(r'\s+'), ' ').trim();
    } catch (_) {
      // Even if parsing fails (extremely malformed), fall back to regex strip.
      return htmlString.replaceAll(RegExp(r'<[^>]*>'), ' ').trim();
    }
  }
}
