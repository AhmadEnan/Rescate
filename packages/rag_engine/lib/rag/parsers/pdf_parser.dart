// lib/rag/parsers/pdf_parser.dart

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:pdfrx/pdfrx.dart';

import '../exceptions.dart';
import 'document_parser.dart';

/// Parser for PDF files (`.pdf`) using the PDFium-based `pdfrx` package.
///
/// Text is extracted page-by-page via [PdfPage.loadText]. Each page's text is
/// separated by a newline for downstream chunking.
///
/// ### Limitations
/// - Scanned (image-only) PDFs return empty or near-empty strings — pdfrx
///   does not perform OCR.
/// - Password-protected PDFs throw [RagParseException] with the message
///   `"Password-protected document"`.
class PdfParser extends DocumentParser {
  /// Creates a [PdfParser].
  const PdfParser();

  @override
  Future<String> parse(File file) async {
    final stat = await file.stat();
    if (stat.size == 0) return '';

    PdfDocument? doc;
    try {
      doc = await PdfDocument.openFile(file.path);

      if (doc.isEncrypted) {
        throw const RagParseException('Password-protected document');
      }

      final buf = StringBuffer();
      // pdfrx exposes pages as a List<PdfPage> — no pagesCount/getPage().
      for (final page in doc.pages) {
        try {
          final pageText = await page.loadText();
          final text = pageText.fullText.trim();
          if (text.isNotEmpty) {
            buf.write(text);
            buf.write('\n');
          }
        } catch (e) {
          // Skip unreadable pages — continue processing remaining pages.
          debugPrint(
            '[PdfParser] skipping page ${page.pageNumber} of ${file.path}: $e',
          );
        }
        // Note: pdfrx PdfPage has no close() method. Pages are owned by
        // PdfDocument and freed when doc.dispose() is called.
      }

      return buf.toString();
    } on RagParseException {
      rethrow;
    } catch (e) {
      debugPrint('[PdfParser] parse error for ${file.path}: $e');
      throw RagParseException('Failed to parse PDF: ${file.path}', cause: e);
    } finally {
      await doc?.dispose();
    }
  }
}
