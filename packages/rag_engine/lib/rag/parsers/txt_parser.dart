// lib/rag/parsers/txt_parser.dart

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../exceptions.dart';
import 'document_parser.dart';

/// Attempts to decode [bytes] using UTF-8 → latin-1 → Windows CP-1252.
///
/// Exposed as a package-level function so [HtmlParser] and [MarkdownParser]
/// can reuse it without duplicating the encoding cascade.
String decodeTextBytes(Uint8List bytes) {
  // 1. Try UTF-8 (strict).
  try {
    return utf8.decode(bytes);
  } catch (_) {}

  // 2. Fallback to latin-1 (loss-less for all byte values 0x00–0xFF).
  try {
    return latin1.decode(bytes);
  } catch (_) {}

  // 3. CP-1252 approximation — redefines bytes 0x80–0x9F as Unicode extras.
  return _cp1252Decode(bytes);
}

/// Parser for plain-text files (`.txt`).
///
/// Encoding detection order:
/// 1. UTF-8
/// 2. latin-1 / ISO-8859-1
/// 3. Windows CP-1252
///
/// Files larger than 50 MB are read in 4 MB chunks to bound peak RSS.
class TxtParser extends DocumentParser {
  /// Creates a [TxtParser].
  const TxtParser();

  static const _chunkBytes = 4 * 1024 * 1024; // 4 MB

  @override
  Future<String> parse(File file) async {
    try {
      final stat = await file.stat();
      if (stat.size == 0) return '';

      if (stat.size <= _chunkBytes) {
        // Fast path — read whole file.
        return decodeTextBytes(await file.readAsBytes());
      }

      // Streaming path for large files.
      final buf = StringBuffer();
      await for (final chunk in file.openRead().map(Uint8List.fromList)) {
        buf.write(decodeTextBytes(chunk));
      }
      return buf.toString();
    } on RagParseException {
      rethrow;
    } catch (e) {
      debugPrint('[TxtParser] parse error: $e');
      throw RagParseException(
        'Failed to parse text file: ${file.path}',
        cause: e,
      );
    }
  }
}

/// Approximates Windows CP-1252 decoding.
///
/// CP-1252 extends latin-1 by redefining bytes 0x80–0x9F. This handles the
/// most common extras (smart quotes, dashes, etc.) seen in legacy documents.
String _cp1252Decode(Uint8List bytes) {
  const extras = <int, String>{
    0x80: '\u20ac',
    0x82: '\u201a',
    0x83: '\u0192',
    0x84: '\u201e',
    0x85: '\u2026',
    0x86: '\u2020',
    0x87: '\u2021',
    0x88: '\u02c6',
    0x89: '\u2030',
    0x8a: '\u0160',
    0x8b: '\u2039',
    0x8c: '\u0152',
    0x8e: '\u017d',
    0x91: '\u2018',
    0x92: '\u2019',
    0x93: '\u201c',
    0x94: '\u201d',
    0x95: '\u2022',
    0x96: '\u2013',
    0x97: '\u2014',
    0x98: '\u02dc',
    0x99: '\u2122',
    0x9a: '\u0161',
    0x9b: '\u203a',
    0x9c: '\u0153',
    0x9e: '\u017e',
    0x9f: '\u0178',
  };
  final buf = StringBuffer();
  for (final b in bytes) {
    buf.write(extras[b] ?? String.fromCharCode(b));
  }
  return buf.toString();
}
