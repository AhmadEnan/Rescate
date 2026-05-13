// lib/rag/parsers/docx_parser.dart

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:docx_to_text/docx_to_text.dart';
import 'package:flutter/foundation.dart';

import '../exceptions.dart';
import 'document_parser.dart';

/// Parser for Microsoft Word documents (`.docx`).
///
/// Primary path: uses `docx_to_text` for fast paragraph extraction.
///
/// Fallback path: if `docx_to_text` fails (e.g. DOCX variant it doesn't
/// support), falls back to manually unzipping the DOCX container, reading
/// `word/document.xml`, and stripping all XML tags—guaranteeing we always
/// extract whatever text is present.
class DocxParser extends DocumentParser {
  /// Creates a [DocxParser].
  const DocxParser();

  @override
  Future<String> parse(File file) async {
    if (await file.length() == 0) return '';

    // ── Primary path ──────────────────────────────────────────────────────
    try {
      final bytes = await file.readAsBytes();
      final text = docxToText(bytes);
      if (text.trim().isNotEmpty) return text;
      // Fall through to XML fallback if result is empty (some DOCX variants).
    } catch (e) {
      debugPrint('[DocxParser] docx_to_text failed, trying XML fallback: $e');
    }

    // ── XML fallback ──────────────────────────────────────────────────────
    try {
      return await _extractViaXml(file);
    } on RagParseException {
      rethrow;
    } catch (e) {
      debugPrint('[DocxParser] XML fallback failed: $e');
      throw RagParseException('Failed to parse DOCX: ${file.path}', cause: e);
    }
  }

  /// Unzips the DOCX, reads `word/document.xml`, strips XML tags.
  static Future<String> _extractViaXml(File file) async {
    final bytes = await file.readAsBytes();
    late Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (e) {
      throw RagParseException(
        'DOCX has corrupt ZIP container: ${file.path}',
        cause: e,
      );
    }

    final docXml = archive.files.firstWhere(
      (f) => f.name == 'word/document.xml',
      orElse: () => throw RagParseException(
        'word/document.xml not found in DOCX: ${file.path}',
      ),
    );

    final xmlContent = utf8.decode(docXml.content as List<int>);

    // Extract <w:t> text elements (paragraph text in OOXML).
    final texts = RegExp(r'<w:t[^>]*>([^<]*)<\/w:t>')
        .allMatches(xmlContent)
        .map((m) => m.group(1) ?? '')
        .where((t) => t.isNotEmpty);

    return texts.join(' ').trim();
  }
}
