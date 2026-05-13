"""
Test script — run this to debug the search
    py test_search.py
"""
import json
import os

# First show what's in chunks.json
print("=== Checking chunks.json ===")
with open("chunks.json", "r", encoding="utf-8") as f:
    chunks = json.load(f)

print(f"Total chunks: {len(chunks)}")
print(f"\nFirst chunk preview:")
print(chunks[0]["text"][:300])
print("\n" + "="*50)

# Now test search directly
print("\n=== Testing Search ===")
from whoosh import index
from whoosh.qparser import MultifieldParser, OrGroup
from whoosh import scoring
from whoosh.query import Every

ix = index.open_dir("search_index")

with ix.searcher(weighting=scoring.BM25F()) as searcher:
    # Test 1: get ALL chunks (no filter)
    print("\nTest 1 — All chunks in index:")
    results = searcher.search(Every(), limit=5)
    print(f"Found {len(results)} results")
    for r in results:
        print(f"  - {r['chunk_id']}: {r['content'][:100]}...")

    # Test 2: simple keyword
    print("\nTest 2 — Search for 'burn':")
    parser = MultifieldParser(["content"], ix.schema, group=OrGroup)
    query = parser.parse("burn")
    results = searcher.search(query, limit=3)
    print(f"Found {len(results)} results")
    for r in results:
        print(f"  - score {r.score:.2f}: {r['content'][:100]}...")

    # Test 3: the actual question
    print("\nTest 3 — Search for 'second degree burn treatment':")
    query = parser.parse("second degree burn treatment")
    results = searcher.search(query, limit=3)
    print(f"Found {len(results)} results")
    for r in results:
        print(f"  - score {r.score:.2f}: {r['content'][:100]}...")

print("\n=== Done ===")
