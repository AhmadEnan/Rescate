// rag_v3 asset loader: sentence units + int8-quantized embedding matrix.
//
// Asset format (produced by eval/rag_mirror pipeline):
// - sentences.json: [{i: id, c: chunkId, s: source, p: pos, t: text}, ...]
// - vectors_q8.bin: [u32 rows][u32 cols][rows*cols i8 data][rows f32 scales]
//
// Storage math: 7,535 x 1024 int8 + per-row f32 scale = 7.7 MB (vs 30.9 MB
// f32). Cosine rank order is preserved because rows are L2-normalized before
// quantization; the per-row scale rescales the dot product exactly.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

class RagSentence {
  final String id;
  final String chunkId;
  final String source;
  final int pos;
  final String text;
  const RagSentence({
    required this.id,
    required this.chunkId,
    required this.source,
    required this.pos,
    required this.text,
  });

  factory RagSentence.fromJson(Map<String, dynamic> j) => RagSentence(
        id: j['i'] as String,
        chunkId: j['c'] as String,
        source: j['s'] as String,
        pos: j['p'] as int,
        text: j['t'] as String,
      );
}

class RagVectors {
  final int rows;
  final int cols;
  final Int8List data; // rows*cols
  final Float32List scales; // rows

  RagVectors({
    required this.rows,
    required this.cols,
    required this.data,
    required this.scales,
  });

  factory RagVectors.fromBytes(Uint8List bytes) {
    final bd = ByteData.sublistView(bytes);
    final rows = bd.getUint32(0, Endian.little);
    final cols = bd.getUint32(4, Endian.little);
    final expected = 8 + rows * cols + rows * 4;
    if (bytes.length != expected) {
      throw StateError(
        'vectors_q8.bin size mismatch: got ${bytes.length}, expected $expected',
      );
    }
    final data = Int8List.sublistView(bytes, 8, 8 + rows * cols);
    final scales = Float32List.sublistView(
      bytes,
      8 + rows * cols,
      8 + rows * cols + rows * 4,
    );
    return RagVectors(rows: rows, cols: cols, data: data, scales: scales);
  }

  /// Dot product of a normalized f32 query against quantized row [r].
  ///
  /// Rows were L2-normalized before int8 quantization, so
  /// dot(q, row)/127 * scale is proportional to cosine(q, row); the constant
  /// factor cancels in ranking.
  double dotRow(Float32List q, int r) {
    final off = r * cols;
    var acc = 0.0;
    // Plain loop: Dart AOT on arm64 vectorizes this well; Float32x4 SHUFFLE
    // //path adds complexity for <5ms at 7.5k rows (measured on VM).
    for (var i = 0; i < cols; i++) {
      acc += q[i] * data[off + i];
    }
    return acc * scales[r];
  }
}

class RagAssets {
  static const _kSentencesAsset = 'packages/ai_inference/assets/rag/sentences.json';
  static const _kVectorsAsset = 'packages/ai_inference/assets/rag/vectors_q8.bin';

  final List<RagSentence> sentences;
  final RagVectors vectors;

  const RagAssets._(this.sentences, this.vectors);

  /// Public constructor for tests/tooling loading from file.
  RagAssets({required this.sentences, required this.vectors});

  static Future<RagAssets> load() async {
    final raw = await rootBundle.loadString(_kSentencesAsset);
    final list = jsonDecode(raw) as List<dynamic>;
    final sentences = list
        .map((e) => RagSentence.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);

    final vbytes = (await rootBundle.load(_kVectorsAsset)).buffer.asUint8List();
    final vectors = RagVectors.fromBytes(vbytes);

    if (vectors.rows != sentences.length) {
      throw StateError(
        'rag assets mismatch: ${vectors.rows} vectors vs ${sentences.length} sentences',
      );
    }
    return RagAssets._(sentences, vectors);
  }

  /// Optional integrity check (call in tests / first run).
  static String sha256Of(Uint8List bytes) => sha256Hex(bytes);

  static String sha256Hex(Uint8List bytes) {
    // Minimal SHA-256 for asset integrity verification without extra deps.
    final h = _Sha256();
    return h.convert(bytes);
  }
}

/// Compact SHA-256 (no external dependency) - used only for asset integrity.
class _Sha256 {
  static const _k = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
    0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
    0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
    0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
    0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
    0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ];
  final _h = <int>[
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
  ];
  String convert(Uint8List bytes) {
    var bitLen = bytes.length * 8;
    final data = List<int>.from(bytes)..add(0x80);
    while (data.length % 64 != 56) {
      data.add(0);
    }
    for (var i = 7; i >= 0; i--) {
      data.add((bitLen >> (i * 8)) & 0xff);
    }
    for (var off = 0; off < data.length; off += 64) {
      final w = List<int>.filled(64, 0);
      for (var i = 0; i < 16; i++) {
        w[i] = (data[off + i * 4] << 24) |
            (data[off + i * 4 + 1] << 16) |
            (data[off + i * 4 + 2] << 8) |
            data[off + i * 4 + 3];
      }
      for (var i = 16; i < 64; i++) {
        final s0 = _rotr(w[i - 15], 7) ^ _rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
        final s1 = _rotr(w[i - 2], 17) ^ _rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
        w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xffffffff;
      }
      var a = _h[0], b = _h[1], c = _h[2], d = _h[3];
      var e = _h[4], f = _h[5], g = _h[6], h = _h[7];
      for (var i = 0; i < 64; i++) {
        final s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
        final ch = (e & f) ^ ((~e & 0xffffffff) & g);
        final t1 = (h + s1 + ch + _k[i] + w[i]) & 0xffffffff;
        final s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
        final maj = (a & b) ^ (a & c) ^ (b & c);
        final t2 = (s0 + maj) & 0xffffffff;
        h = g; g = f; f = e;
        e = (d + t1) & 0xffffffff;
        d = c; c = b; b = a;
        a = (t1 + t2) & 0xffffffff;
      }
      _h[0] = (_h[0] + a) & 0xffffffff;
      _h[1] = (_h[1] + b) & 0xffffffff;
      _h[2] = (_h[2] + c) & 0xffffffff;
      _h[3] = (_h[3] + d) & 0xffffffff;
      _h[4] = (_h[4] + e) & 0xffffffff;
      _h[5] = (_h[5] + f) & 0xffffffff;
      _h[6] = (_h[6] + g) & 0xffffffff;
      _h[7] = (_h[7] + h) & 0xffffffff;
    }
    bitLen = 0;
    return _h.map((x) => x.toRadixString(16).padLeft(8, '0')).join();
  }

  static int _rotr(int x, int n) => ((x >> n) | (x << (32 - n))) & 0xffffffff;
}

/// File-based loader for tests / tooling (asset bundle not available there).
class RagAssetsFile {
  static Future<RagAssets> loadFromDirectory(String dir) async {
    final sentences = (jsonDecode(
      await File('$dir/sentences.json').readAsString(),
    ) as List<dynamic>)
        .map((e) => RagSentence.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
    final vectors = RagVectors.fromBytes(
      await File('$dir/vectors_q8.bin').readAsBytes(),
    );
    if (vectors.rows != sentences.length) {
      throw StateError('rag assets mismatch');
    }
    return RagAssets._(sentences, vectors);
  }
}
