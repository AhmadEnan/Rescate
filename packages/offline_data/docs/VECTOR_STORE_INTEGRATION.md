# VectorStore Integration Guide

A reference for Rescate package developers who want to add semantic (vector)
search to their feature area.

---

## When to Use VectorStore

| Use case | VectorStore | SQLite FTS5 | ObjectBox |
|---|---|---|---|
| Semantic similarity search (meaning-based) | ✅ | ❌ | ✅ (HNSW) |
| Keyword / full-text search | ❌ | ✅ | partial |
| Structured queries (filters, joins) | ❌ | ✅ | ✅ |
| Offline, no native build step | ✅ | ✅ | ❌ (codegen) |

Use `VectorStore` when you need to find content by *meaning* rather than exact
keywords — e.g. "find chunks similar to this query" or "find cached responses
that answer the same question".

---

## Core Concepts

### Namespaces
A **namespace** is a logical collection within the single shared SQLite file
(`rescate_vectors.db`). Each feature area gets its own namespace so queries
never bleed into another area's data.

```
rag:report.pdf        ← all chunks from report.pdf (rag_engine)
chat:history          ← chat message embeddings (future ai_inference use)
inference:cache       ← deduplication cache for LLM responses
```

### Entries
A `VectorEntry` holds:
- `id` — unique within its namespace
- `namespace` — logical collection identifier
- `payload` — `Map<String, dynamic>` of JSON metadata (source, page, timestamp …)
- `embedding` — `List<double>` L2-normalised float vector

---

## Quick-Start Example

### 1. Open the store (once per app session)

```dart
import 'package:offline_data/offline_data.dart';

final store = await VectorStore.open(); // uses rescate_vectors.db
```

### 2. Insert entries

```dart
// Single insert
await store.upsert(VectorEntry(
  id: 'msg-001',
  namespace: 'chat:history',
  payload: {'sender': 'alice', 'timestamp': '2026-04-09T23:00:00Z'},
  embedding: myEmbeddingModel.embed('Hello, how are you?'),
));

// Bulk insert (always prefer this — uses one SQL transaction)
await store.upsertBatch(entries);
```

### 3. Search

```dart
final queryVec = myEmbeddingModel.embed('What did Alice say?');
final results = await store.search(
  queryVec,
  topK: 5,
  minScore: 0.5,
  namespace: 'chat:history',
);

for (final r in results) {
  print('${r.score.toStringAsFixed(3)}  ${r.entry.payload}');
}
```

### 4. Delete by namespace (e.g. clear one document)

```dart
await store.deleteNamespace('rag:old_report.pdf');
```

---

## Worked Example — Chat History Semantic Search

```dart
class ChatVectorIndex {
  final VectorStore _store;
  final EmbeddingModel _embedder;
  static const _ns = 'chat:history';

  ChatVectorIndex(this._store, this._embedder);

  Future<void> indexMessage(ChatMessage msg) async {
    final vec = await _embedder.embed(msg.text);
    await _store.upsert(VectorEntry(
      id: msg.id,
      namespace: _ns,
      payload: {'sender': msg.sender, 'text': msg.text},
      embedding: vec,
    ));
  }

  Future<List<ChatMessage>> findSimilar(String query, {int k = 5}) async {
    final vec = await _embedder.embed(query);
    final results = await _store.search(vec, topK: k, namespace: _ns);
    return results
        .map((r) => ChatMessage.fromPayload(r.entry.payload))
        .toList();
  }
}
```

---

## Worked Example — LLM Response Deduplication

```dart
Future<String?> getCachedResponse(String prompt) async {
  final vec = await embedder.embed(prompt);
  final results = await store.search(
    vec,
    topK: 1,
    minScore: 0.97,         // very high threshold = near-identical prompt
    namespace: 'inference:cache',
  );
  if (results.isEmpty) return null;
  return results.first.entry.payload['response'] as String?;
}

Future<void> cacheResponse(String prompt, String response) async {
  final vec = await embedder.embed(prompt);
  await store.upsert(VectorEntry(
    id: sha256(prompt),
    namespace: 'inference:cache',
    payload: {'response': response},
    embedding: vec,
  ));
}
```

---

## Performance Tuning

| Parameter | Default | When to change |
|---|---|---|
| `topK` | 5 | Increase if results feel sparse; decrease for speed |
| `minScore` | 0.0 | Set 0.5–0.7 to filter low-quality matches |
| `VectorStore.open(dbName:)` | `rescate_vectors.db` | Use a different name in tests |
| Linear scan threshold | 10 000 entries | Hardcoded; adjust `_kIvfThreshold` if needed |
| IVF probes | 3 buckets | Increase `_kIvfProbes` for higher recall at > 10k |

> **Important**: Always provide **L2-normalised** (unit-length) vectors.
> The `VectorStore` does NOT normalise automatically — unnormalised vectors
> will produce incorrect similarity scores.

---

## Testing Guide

### Use a temp database in tests

```dart
setUp(() async {
  store = await VectorStore.open(dbName: 'test_${DateTime.now().millisecond}.db');
});

tearDown(() async {
  await store.clear();
  await store.close();
});
```

### Mock VectorStore for pure unit tests

Implement a simple in-memory test double:

```dart
class FakeVectorStore implements VectorStore {
  final _data = <String, VectorEntry>{};

  @override
  Future<void> upsert(VectorEntry entry) async => _data[entry.id] = entry;

  @override
  Future<List<VectorSearchResult>> search(
    List<double> query, {
    int topK = 5,
    double minScore = 0.0,
    String namespace = 'default',
  }) async {
    // Return all entries with a fixed score of 1.0 for testing.
    return _data.values
        .where((e) => e.namespace == namespace)
        .take(topK)
        .map((e) => VectorSearchResult(entry: e, score: 1.0))
        .toList();
  }

  // ... other methods as needed
}
```

---

## FAQ

**Q: Can two packages write to the same namespace?**
A: Technically yes, but avoid it — use distinct namespaces per feature area
to prevent accidental data interference.

**Q: Does VectorStore encrypt data?**
A: No. If you store sensitive text in `payload`, wrap the DB access through
`security_crypto`'s SQLCipher layer (planned for a future sprint).

**Q: What happens when corpus > 10 000 entries?**
A: The IVF index is built automatically on the first search call. This is a
one-time cost (~1–3 s on a Snapdragon 450) and is persisted in SQLite.
Subsequent searches probe only `_kIvfProbes` (3) buckets.

**Q: Can I use VectorStore from a background Isolate?**
A: Not with the shared instance — SQLite connections are not thread-safe
across Flutter Isolates. Open a separate `VectorStore.open()` instance per
Isolate if needed, or use `compute()` for the search operation (which the
`VectorStore` already does internally).
