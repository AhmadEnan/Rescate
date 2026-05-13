// test/parsers_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rag_engine/rag_engine.dart';

// ─── Helpers ─────────────────────────────────────────────────────────────────

/// Writes [content] to a temp file with [ext] and returns it.
File _tmpFile(String content, String ext, {Encoding encoding = utf8}) {
  final f = File(
    '${Directory.systemTemp.path}/rag_test_${DateTime.now().microsecondsSinceEpoch}$ext',
  );
  f.writeAsBytesSync(encoding.encode(content));
  return f;
}

/// Writes raw [bytes] to a temp file with [ext].
File _tmpBytes(List<int> bytes, String ext) {
  final f = File(
    '${Directory.systemTemp.path}/rag_test_${DateTime.now().microsecondsSinceEpoch}$ext',
  );
  f.writeAsBytesSync(bytes);
  return f;
}

/// Creates a minimal valid DOCX byte sequence for testing.
List<int> _minimalDocx(String paragraphText) {
  final xmlContent =
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:wpc="http://schemas.microsoft.com/office/word/2010/wordprocessingCanvas"
    xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p><w:r><w:t>$paragraphText</w:t></w:r></w:p>
  </w:body>
</w:document>''';

  final archive = Archive();
  final xmlBytes = utf8.encode(xmlContent);
  archive.addFile(ArchiveFile('word/document.xml', xmlBytes.length, xmlBytes));
  // Add minimal [Content_Types].xml so the ZIP is valid.
  const ctBytes = '''<?xml version="1.0"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml"
    ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>''';
  final ctEncoded = utf8.encode(ctBytes);
  archive.addFile(
    ArchiveFile('[Content_Types].xml', ctEncoded.length, ctEncoded),
  );

  return ZipEncoder().encode(archive)!;
}

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  // Clean up temp files after each test.
  final _tempFiles = <File>[];
  tearDown(() {
    for (final f in _tempFiles) {
      try {
        f.deleteSync();
      } catch (_) {}
    }
    _tempFiles.clear();
  });

  File tmpFile(String content, String ext, {Encoding encoding = utf8}) {
    final f = _tmpFile(content, ext, encoding: encoding);
    _tempFiles.add(f);
    return f;
  }

  File tmpBytes(List<int> bytes, String ext) {
    final f = _tmpBytes(bytes, ext);
    _tempFiles.add(f);
    return f;
  }

  // ── TxtParser ─────────────────────────────────────────────────────────────

  group('TxtParser', () {
    const parser = TxtParser();

    test('C1: valid ASCII file → correct string returned', () async {
      final f = tmpFile('Hello, World!', '.txt');
      expect(await parser.parse(f), equals('Hello, World!'));
    });

    test('C2: valid UTF-8 with Arabic chars → correct string', () async {
      const arabic = 'مرحباً بالعالم';
      final f = tmpFile(arabic, '.txt');
      expect(await parser.parse(f), contains('مرحبا'));
    });

    test('C3: latin-1 encoded file → decoded without exception', () async {
      // café in latin-1: c-a-f-é(0xe9)
      final bytes = [0x63, 0x61, 0x66, 0xe9];
      final f = tmpBytes(bytes, '.txt');
      final result = await parser.parse(f);
      expect(result, isNotEmpty);
      expect(() => result, returnsNormally);
    });

    test('C4: empty file → returns empty string', () async {
      final f = tmpBytes([], '.txt');
      expect(await parser.parse(f), equals(''));
    });
  });

  // ── HtmlParser ──────────────────────────────────────────────────────────

  group('HtmlParser', () {
    test('C5: simple HTML → plain text without tags', () async {
      const html = '<p>Hello <b>World</b></p>';
      expect(HtmlParser.parseHtmlString(html), equals('Hello World'));
    });

    test('C6: malformed HTML (unclosed tags) → does not throw', () async {
      const malformed = '<p>Unclosed <b>bold';
      expect(() => HtmlParser.parseHtmlString(malformed), returnsNormally);
    });

    test('C7: empty string → returns empty string', () async {
      expect(HtmlParser.parseHtmlString(''), equals(''));
    });
  });

  // ── MarkdownParser ────────────────────────────────────────────────────────

  group('MarkdownParser', () {
    test('C8: markdown syntax is stripped', () async {
      const md = '# Title\n**bold** and _italic_';
      final result = MarkdownParser.stripMarkdown(md);
      expect(result, contains('Title'));
      expect(result, contains('bold'));
      expect(result, contains('italic'));
      expect(result, isNot(contains('#')));
      expect(result, isNot(contains('**')));
      expect(result, isNot(contains('_')));
    });
  });

  // ── DocxParser ────────────────────────────────────────────────────────────

  group('DocxParser', () {
    const parser = DocxParser();

    test('C9: minimal valid DOCX → extracts paragraph text', () async {
      final bytes = _minimalDocx('Emergency protocol text.');
      final f = tmpBytes(bytes, '.docx');
      final result = await parser.parse(f);
      expect(result, contains('Emergency protocol text'));
    });

    test('C10: corrupted ZIP bytes → throws RagParseException', () async {
      final f = tmpBytes([0x00, 0x01, 0x02, 0x03, 0xFF], '.docx');
      expect(() => parser.parse(f), throwsA(isA<RagParseException>()));
    });
  });

  // ── ParserRegistry ────────────────────────────────────────────────────────

  group('ParserRegistry', () {
    test('C11: uppercase extension .PDF → returns PdfParser', () async {
      final parser = ParserRegistry.instance.parserForExtension('.PDF');
      expect(parser, isA<PdfParser>());
    });

    test('C12: unknown extension → throws UnsupportedFormatException', () {
      expect(
        () => ParserRegistry.instance.parserForExtension('.unknown'),
        throwsA(isA<UnsupportedFormatException>()),
      );
    });
  });
}
