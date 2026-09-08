// Exploratory test to debug Dart MMR selection order vs Python.
// Prints both so we can align. (Diagnostic; keep temporarily.)
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_inference/src/rag/rag_assets.dart';
import 'package:ai_inference/src/rag/rag_v3.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('debug mmr order', () {
    final dir = 'test/rag_fixtures';
    final sentences = (jsonDecode(
            File('$dir/fixture_sentences.json').readAsStringSync())
        as List<dynamic>)
        .map((e) => RagSentence.fromJson(e as Map<String, dynamic>))
        .toList();
    final vectors = RagVectors.fromBytes(
        File('$dir/fixture_vectors_q8.bin').readAsBytesSync());
    final assets = RagAssets(sentences: sentences, vectors: vectors);
    final rag = RagV3(assets);
    final exp =
        jsonDecode(File('$dir/fixture_expected.json').readAsStringSync())
            as Map<String, dynamic>;
    final e = exp['queries'][0] as Map<String, dynamic>;
    final lv = e['query_vec'] as List<dynamic>;
    final qv = Float32List(lv.length);
    for (var i = 0; i < lv.length; i++) {
      qv[i] = (lv[i] as num).toDouble();
    }
    final ranked = rag.rank(qv, topK: 8);
    // ignore: avoid_print
    print('DART top8: ${ranked.map((h) => h.sentence.id.split('_chunk').last).toList()}');
    // ignore: avoid_print
    print('PY   top8: ${(e['expected_ids'] as List).map((x) => (x as String).split('_chunk').last).toList()}');
    expect(true, isTrue);
  });
}
