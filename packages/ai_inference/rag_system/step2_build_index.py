"""
STEP 2 — Build the search index
=================================
Run this ONCE after step1.
It reads chunks.json and builds a fast search index.
Creates a folder called: search_index/

HOW TO RUN:
    python step2_build_index.py

REQUIREMENTS (install once):
    pip install whoosh
"""

import json
import os
import sys

OUTPUT_INDEX_DIR = "search_index"
CHUNKS_FILE = "chunks.json"


def build_index():
    print("=" * 55)
    print("  RAG SYSTEM — Step 2: Build Search Index")
    print("=" * 55)

    # ── Check whoosh is installed ──
    try:
        from whoosh import index
        from whoosh.fields import Schema, TEXT, ID, STORED
        from whoosh.analysis import StemmingAnalyzer
    except ImportError:
        print("\n✗ 'whoosh' is not installed.")
        print("  Run this command first:")
        print("      pip install whoosh")
        sys.exit(1)

    # ── Check chunks file exists ──
    if not os.path.exists(CHUNKS_FILE):
        print(f"\n✗ '{CHUNKS_FILE}' not found.")
        print("  Run step1 first:  python step1_parse_and_chunk.py")
        sys.exit(1)

    # ── Load chunks ──
    with open(CHUNKS_FILE, "r", encoding="utf-8") as f:
        chunks = json.load(f)

    print(f"\n📦 Loaded {len(chunks)} chunks from {CHUNKS_FILE}")

    # ── Define schema ──
    # TEXT fields are searchable, STORED fields are returned in results
    schema = Schema(
        chunk_id=ID(stored=True),
        source=ID(stored=True),
        content=TEXT(stored=True, analyzer=StemmingAnalyzer()),
    )

    # ── Create or clear index directory ──
    if not os.path.exists(OUTPUT_INDEX_DIR):
        os.makedirs(OUTPUT_INDEX_DIR)
        ix = index.create_in(OUTPUT_INDEX_DIR, schema)
    else:
        # Overwrite existing index
        ix = index.create_in(OUTPUT_INDEX_DIR, schema)

    # ── Write chunks to index ──
    writer = ix.writer()
    for i, chunk in enumerate(chunks):
        writer.add_document(
            chunk_id=chunk["id"],
            source=chunk["source"],
            content=chunk["text"],
        )
        if (i + 1) % 50 == 0:
            print(f"   Indexed {i+1}/{len(chunks)} chunks...", end="\r")

    writer.commit()

    print(f"\n  ✅ Index built with {len(chunks)} chunks")
    print(f"  💾 Saved to folder: {OUTPUT_INDEX_DIR}/")
    print(f"\n{'='*55}")
    print(f"➜ Next step: run  python step3_rag_chat.py")


if __name__ == "__main__":
    build_index()
