"""
STEP 1 — Parse PDFs and split into chunks
==========================================
Run this ONCE to prepare your documents.
It will create a file called: chunks.json

HOW TO RUN:
    python step1_parse_and_chunk.py

REQUIREMENTS (install once):
    pip install pypdf pdfplumber
"""

import json
import os
import re

# ── CONFIG ──────────────────────────────────────────────────────────────
CHUNK_SIZE = 400        # words per chunk (keep small for faster search)
CHUNK_OVERLAP = 50      # words overlap between chunks (keeps context)
PDF_FOLDER = "docs"     # folder where you put your PDF files
OUTPUT_FILE = "chunks.json"
# ────────────────────────────────────────────────────────────────────────


def clean_text(text: str) -> str:
    """Remove extra whitespace and weird characters from PDF text."""
    text = re.sub(r'\s+', ' ', text)          # collapse whitespace
    text = re.sub(r'[^\x00-\x7F\u0600-\u06FF\s]', '', text)  # keep ASCII + Arabic
    return text.strip()


def extract_text_from_pdf(pdf_path: str) -> str:
    """Extract all text from a PDF file."""
    try:
        import pdfplumber
        full_text = ""
        with pdfplumber.open(pdf_path) as pdf:
            for i, page in enumerate(pdf.pages):
                text = page.extract_text()
                if text:
                    full_text += f"\n[Page {i+1}]\n{text}"
        return clean_text(full_text)
    except Exception as e:
        print(f"  ⚠ pdfplumber failed ({e}), trying pypdf...")
        try:
            from pypdf import PdfReader
            reader = PdfReader(pdf_path)
            full_text = ""
            for i, page in enumerate(reader.pages):
                text = page.extract_text()
                if text:
                    full_text += f"\n[Page {i+1}]\n{text}"
            return clean_text(full_text)
        except Exception as e2:
            print(f"  ✗ Failed to read {pdf_path}: {e2}")
            return ""


def split_into_chunks(text: str, source_name: str, chunk_size: int, overlap: int) -> list:
    """Split text into overlapping word chunks."""
    words = text.split()
    chunks = []
    start = 0
    chunk_id = 0

    while start < len(words):
        end = min(start + chunk_size, len(words))
        chunk_words = words[start:end]
        chunk_text = " ".join(chunk_words)

        chunks.append({
            "id": f"{source_name}_chunk_{chunk_id}",
            "source": source_name,
            "text": chunk_text,
            "word_count": len(chunk_words),
        })

        chunk_id += 1
        start += chunk_size - overlap  # move forward with overlap

    return chunks


def main():
    print("=" * 55)
    print("  RAG SYSTEM — Step 1: Parse & Chunk PDFs")
    print("=" * 55)

    # Check docs folder exists
    if not os.path.exists(PDF_FOLDER):
        os.makedirs(PDF_FOLDER)
        print(f"\n📁 Created folder: '{PDF_FOLDER}/'")
        print(f"   ➜ Put your PDF files inside '{PDF_FOLDER}/' then run this script again.")
        return

    # Find all PDFs
    pdf_files = [f for f in os.listdir(PDF_FOLDER) if f.lower().endswith(".pdf")]

    if not pdf_files:
        print(f"\n⚠  No PDF files found in '{PDF_FOLDER}/'")
        print(f"   ➜ Put your PDF files inside '{PDF_FOLDER}/' then run this script again.")
        return

    print(f"\n📄 Found {len(pdf_files)} PDF file(s):")
    for f in pdf_files:
        print(f"   • {f}")

    # Process each PDF
    all_chunks = []
    for pdf_file in pdf_files:
        pdf_path = os.path.join(PDF_FOLDER, pdf_file)
        source_name = os.path.splitext(pdf_file)[0]  # filename without .pdf

        print(f"\n⏳ Processing: {pdf_file}")
        text = extract_text_from_pdf(pdf_path)

        if not text:
            print(f"   ✗ Could not extract text. Skipping.")
            continue

        word_count = len(text.split())
        print(f"   ✓ Extracted {word_count:,} words")

        chunks = split_into_chunks(text, source_name, CHUNK_SIZE, CHUNK_OVERLAP)
        print(f"   ✓ Created {len(chunks)} chunks")
        all_chunks.extend(chunks)

    if not all_chunks:
        print("\n✗ No chunks created. Check your PDFs.")
        return

    # Save chunks to JSON
    with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
        json.dump(all_chunks, f, ensure_ascii=False, indent=2)

    print(f"\n{'='*55}")
    print(f"  ✅ Done! Created {len(all_chunks)} total chunks")
    print(f"  💾 Saved to: {OUTPUT_FILE}")
    print(f"{'='*55}")
    print(f"\n➜ Next step: run  python step2_build_index.py")


if __name__ == "__main__":
    main()
