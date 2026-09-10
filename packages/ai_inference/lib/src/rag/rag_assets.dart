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
}
