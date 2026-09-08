"""rag_v2: sentence-level multilingual retrieval for Rescate (issue #14 night build).

Architecture (the "rethink" implemented):
  - 312 page-chunks -> ~7000 sentence units (precomputed in sentences.json)
  - multilingual embeddings (Qwen3-Embedding-0.6B GGUF via llama-server) for
    every sentence: precomputed once -> vectors.npy; queries embedded at runtime
  - hybrid retrieval: dense cosine + lexical BM25 (pure python, no deps) fused
    with Reciprocal Rank Fusion
  - MMR diversity re-rank so top-k covers distinct instruction clusters
  - context builder returns whole sentences (no 180-char window) within a
    token budget, grouped by source chunk order

Target: phone CPU. Costs per query at 7K sentences: 1 embedding (~20ms server)
+ cosine scan (numpy, <5ms) + BM25 scan (~30ms python) => fine on-device.
"""
from __future__ import annotations

import json
import math
import re
import time
import urllib.request
from pathlib import Path

import numpy as np

_REPO = Path(__file__).resolve().parents[2]
SENTENCES = json.loads((_REPO / "eval" / "rag_mirror" / "sentences.json").read_text())
VECTORS_PATH = _REPO / "eval" / "rag_mirror" / "vectors.npy"
EMB_URL_DEFAULT = "http://127.0.0.1:8084"

BILINGUAL = re.compile(r"[\u0600-\u06FF]")

# BM25 over sentence units
_TOKEN = re.compile(r"[\w\u0600-\u06FF]+", re.UNICODE)


def _tok(text: str) -> list[str]:
    return [t.lower() for t in _TOKEN.findall(text)]


class RagV2:
    def __init__(self, emb_url: str = EMB_URL_DEFAULT, k1: float = 1.4, b: float = 0.72,
                 rrf_k: int = 60, dense_w: float = 0.62, bm25_w: float = 0.38,
                 mmr_lambda: float = 0.72):
        self.emb_url = emb_url.rstrip("/")
        self.k1, self.b, self.rrf_k = k1, b, rrf_k
        self.dense_w, self.bm25_w, self.mmr_lambda = dense_w, bm25_w, mmr_lambda

        self.texts = [s["text"] for s in SENTENCES]
        self.toks = [_tok(t) for t in self.texts]
        self.doc_len = np.array([len(t) for t in self.toks], dtype=np.float32)
        self.avgdl = float(self.doc_len.mean())
        self.n = len(self.texts)
        # document frequencies
        df: dict[str, int] = {}
        for toks in self.toks:
            for w in set(toks):
                df[w] = df.get(w, 0) + 1
        self.idf = {w: math.log(1 + (self.n - c + 0.5) / (c + 0.5)) for w, c in df.items()}
        # term counts per doc (sparse)
        self.tcs = []
        for toks in self.toks:
            tc: dict[str, int] = {}
            for w in toks:
                tc[w] = tc.get(w, 0) + 1
            self.tcs.append(tc)

        self.vecs = np.load(VECTORS_PATH) if VECTORS_PATH.exists() else None
        norms = np.linalg.norm(self.vecs, axis=1, keepdims=True) if self.vecs is not None else None
        self.vecs_n = (self.vecs / np.maximum(norms, 1e-9)) if self.vecs is not None else None

    # ---- embeddings ---------------------------------------------------------

    def _embed(self, texts: list[str]) -> np.ndarray:
        req = urllib.request.Request(
            f"{self.emb_url}/v1/embeddings",
            data=json.dumps({"input": texts}).encode(),
            headers={"Content-Type": "application/json"},
        )
        with urllib.request.urlopen(req, timeout=600) as r:
            body = json.loads(r.read())
        data = sorted(body["data"], key=lambda d: d["index"])
        return np.array([d["embedding"] for d in data], dtype=np.float32)

    def build_vectors(self, batch: int = 64, resume: bool = True) -> None:
        import os
        ckpt = VECTORS_PATH.with_suffix(".ckpt.npy")
        done = []
        if resume and ckpt.exists():
            done = [np.asarray(x, dtype=np.float32) for x in np.load(ckpt, allow_pickle=True)]
            print(f"resuming from {len(done)} batches", flush=True)
        start = len(done) * batch
        vecs = done
        for i in range(start, len(self.texts), batch):
            for attempt in range(5):
                try:
                    vecs.append(self._embed(self.texts[i : i + batch]))
                    break
                except Exception as e:
                    print(f"batch {i} attempt {attempt + 1} failed: {e}", flush=True)
                    time.sleep(3 * (attempt + 1))
                    if attempt == 4:
                        raise
            np.save(ckpt, np.array(vecs, dtype=object), allow_pickle=True)
            if (i // batch) % 20 == 0:
                print(f"embedded {i + batch}/{len(self.texts)}", flush=True)
        v = np.vstack([np.asarray(x, dtype=np.float32) for x in vecs])
        v /= np.maximum(np.linalg.norm(v, axis=1, keepdims=True), 1e-9)
        np.save(VECTORS_PATH, v)
        ckpt.unlink(missing_ok=True)
        self.vecs, self.vecs_n = v, v
        print(f"saved {VECTORS_PATH} {v.shape}")

    # ---- lexical ------------------------------------------------------------

    def _bm25(self, query: str, top: int = 60) -> list[tuple[int, float]]:
        q = [w for w in _tok(query) if w in self.idf]
        if not q:
            return []
        scores = np.zeros(self.n, dtype=np.float32)
        qset = set(q)
        for i, tc in enumerate(self.tcs):
            if not (qset & tc.keys()):
                continue
            s = 0.0
            dl = self.doc_len[i]
            for w in qset:
                f = tc.get(w)
                if not f:
                    continue
                s += self.idf[w] * (f * (self.k1 + 1)) / (f + self.k1 * (1 - self.b + self.b * dl / self.avgdl))
            scores[i] = s
        idx = np.argsort(scores)[::-1][:top]
        return [(int(i), float(scores[i])) for i in idx if scores[i] > 0]

    # ---- retrieval ----------------------------------------------------------

    def retrieve(self, query: str, top_k: int = 8, dense: bool = True, lexical: bool = True,
                 neighbors: int = 0) -> list[dict]:
        dense_hits: list[tuple[int, float]] = []
        if dense and self.vecs_n is not None:
            qv = self._embed([query])[0]
            qv = qv / max(float(np.linalg.norm(qv)), 1e-9)
            sims = self.vecs_n @ qv
            idx = np.argsort(sims)[::-1][:60]
            dense_hits = [(int(i), float(sims[i])) for i in idx if sims[i] > 0.25]
        lex_hits = self._bm25(query) if lexical else []

        # RRF fusion
        rrf: dict[int, float] = {}
        for rank, (i, _s) in enumerate(dense_hits):
            rrf[i] = rrf.get(i, 0) + self.dense_w / (self.rrf_k + rank + 1)
        for rank, (i, _s) in enumerate(lex_hits):
            rrf[i] = rrf.get(i, 0) + self.bm25_w / (self.rrf_k + rank + 1)
        if not rrf:
            return []

        # MMR diversity re-rank over the fused candidates
        cand = sorted(rrf, key=lambda i: rrf[i], reverse=True)[:40]
        if self.vecs_n is None:
            selected = cand[:top_k]
        else:
            selected: list[int] = []
            while cand and len(selected) < top_k:
                best, best_score = None, -1e9
                for i in cand[:20]:
                    div = max(float(self.vecs_n[i] @ self.vecs_n[j]) for j in selected) if selected else 0.0
                    score = self.mmr_lambda * rrf[i] / rrf[cand[0]] - (1 - self.mmr_lambda) * div
                    if score > best_score:
                        best, best_score = i, score
                selected.append(best)
                cand.remove(best)

        # Neighbor expansion: multi-phase instructions (e.g. "after the seizure
        # ends", compression-cycle details) typically live in the sentences
        # adjacent to a strong hit. Merge them into the hit (flagged).
        if neighbors > 0:
            expanded: list[dict] = []
            seen_units: set[int] = set()
            for i in selected:
                s = SENTENCES[i]
                merged = s["text"]
                merged_ids = [s["id"]]
                for d in range(1, neighbors + 1):
                    for j in (i - d, i + d):
                        if 0 <= j < len(SENTENCES) and j not in seen_units \
                                and SENTENCES[j]["chunk_id"] == s["chunk_id"]:
                            seen_units.add(j)
                            merged = f"{merged} {SENTENCES[j]['text']}"
                            merged_ids.append(SENTENCES[j]["id"])
                expanded.append({
                    "unit_id": s["id"], "chunk_id": s["chunk_id"], "source": s["source"],
                    "text": merged, "rrf": round(rrf[i], 5), "neighbor_ids": merged_ids,
                })
                seen_units.add(i)
            return expanded

        out = []
        for i in selected:
            s = SENTENCES[i]
            out.append({
                "unit_id": s["id"],
                "chunk_id": s["chunk_id"],
                "source": s["source"],
                "text": s["text"],
                "rrf": round(rrf[i], 5),
            })
        return out

    def build_context(self, query: str, top_k: int = 8, max_tokens: int = 1100,
                      neighbors: int = 1) -> dict:
        """Whole-sentence context, grouped, within a token budget."""
        hits = self.retrieve(query, top_k=top_k, neighbors=neighbors)
        lines, used, sources = [], 0, []
        for h in hits:
            t = h["text"]
            cost = len(t) / 3.7 + 12
            if used + cost > max_tokens:
                continue
            lines.append(f"- {t} [{len(lines) + 1}]")
            used += cost
            if h["source"] not in sources:
                sources.append(h["source"])
        return {
            "hits": hits,
            "sources": sources,
            "context": "\n".join(lines) if lines else "NO_RELEVANT_CONTEXT",
            "tokens_est": int(used),
        }


def is_arabic(text: str) -> bool:
    return len(BILINGUAL.findall(text)) > len(re.findall(r"[A-Za-z]", text))
