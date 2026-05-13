# 🏥 Medical RAG System — Setup Guide
### Offline AI assistant for medical guidelines (burns, childbirth, etc.)

---

## What This Does

```
User asks a question
       ↓
System searches your PDFs for relevant paragraphs
       ↓
Sends question + paragraphs to your local llama.cpp model
       ↓
Model answers based ONLY on your documents
```

---

## Files in This Folder

```
rag_system/
├── step1_parse_and_chunk.py   ← Run ONCE: reads PDFs, splits into chunks
├── step2_build_index.py       ← Run ONCE: builds searchable index
├── step3_rag_chat.py          ← Run EVERY TIME: the chat interface
├── docs/                      ← PUT YOUR PDF FILES HERE
└── README.md                  ← This file
```

---

## FULL SETUP — Do This Once

### 1. Install Python packages

Open a terminal / command prompt and run:

```bash
pip install pypdf pdfplumber whoosh
```

If you're on Windows and pip doesn't work, try:
```bash
python -m pip install pypdf pdfplumber whoosh
```

---

### 2. Put your PDFs in the `docs/` folder

```
docs/
├── burn_classification_guideline.pdf
├── childbirth_complications.pdf
└── (any other medical PDFs)
```

---

### 3. Run Step 1 — Parse PDFs

```bash
python step1_parse_and_chunk.py
```

You should see something like:
```
📄 Found 2 PDF file(s):
   • burn_classification_guideline.pdf
   • childbirth_complications.pdf

⏳ Processing: burn_classification_guideline.pdf
   ✓ Extracted 8,432 words
   ✓ Created 24 chunks

✅ Done! Created 48 total chunks
💾 Saved to: chunks.json
```

---

### 4. Run Step 2 — Build Index

```bash
python step2_build_index.py
```

You should see:
```
✅ Index built with 48 chunks
💾 Saved to folder: search_index/
```

---

### 5. Start your llama.cpp server

> ⚠️ You need to do this BEFORE running the chat. Open a **separate** terminal window.

Go to your llama.cpp folder (D:\llama.cpp based on your screenshot) and run:

```bash
# Windows — basic CPU mode:
llama-server.exe -m YOUR_MODEL_FILE.gguf --port 8080

# Windows — with GPU (faster!):
llama-server.exe -m YOUR_MODEL_FILE.gguf --port 8080 -ngl 35

# Example with a real model name:
llama-server.exe -m mistral-7b-instruct-v0.2.Q4_K_M.gguf --port 8080 -ngl 35
```

**What `-ngl 35` means:** Load 35 layers to the GPU → much faster.
You have `ggml-cuda.dll` so your GPU IS supported. Use it!

The server is ready when you see:
```
llama server listening at http://127.0.0.1:8080
```

---

### 6. Run the Chat

Open a new terminal (keep the server running in the other one!) and run:

```bash
python step3_rag_chat.py
```

You'll see:
```
🏥 Medical RAG Assistant — Offline
Based on WHO / MSF / Clinical Guidelines
═══════════════════════════════════════
Type your question in English or Arabic.
Type 'quit' to exit.
Type 'chunks' to see what was retrieved last.
═══════════════════════════════════════

✅ Index loaded. Ready!

❓ Your question:
```

---

## Example Questions to Try

```
How do I treat a second degree burn?
What are the signs of a full thickness burn?
How much fluid does a burn patient need?
What is the Parkland formula?
How do I treat white phosphorus burns?
```

---

## Troubleshooting

| Problem | Solution |
|---|---|
| `pip install` fails | Make sure Python is installed: `python --version` |
| `Cannot connect to llama.cpp server` | Make sure you started the server first (Step 5) |
| Model is very slow | Add `-ngl 35` to your server command to use GPU |
| No chunks found | Make sure PDFs are in the `docs/` folder and you ran steps 1 & 2 |
| Wrong/bad answers | Try lowering temperature in step3 config to `0.05` |

---

## Making It Faster (Speed Tips)

### Use GPU layers
```bash
llama-server.exe -m model.gguf --port 8080 -ngl 35
```
`-ngl` = number of GPU layers. Try 35 first. If you have enough VRAM, try higher.

### Use a smaller/quantized model
Better quantizations for speed vs. quality:
- `Q4_K_M` — best balance (recommended)
- `Q3_K_M` — faster, slightly less accurate
- `Q2_K` — fastest, lower quality

### Limit context
In `step3_rag_chat.py`, reduce `TOP_K_CHUNKS` from 3 to 2.
Fewer chunks = shorter prompt = faster response.

---

## Adding More Documents Later

Just add new PDFs to the `docs/` folder and re-run:
```bash
python step1_parse_and_chunk.py
python step2_build_index.py
```
Then restart the chat. That's it!

---

## How to Find Your Model File

In your llama.cpp folder (D:\llama.cpp), look for a file ending in `.gguf`
That's your model. Use its full name in the server command.

If you don't see any `.gguf` file in that folder, check subfolders or 
wherever you downloaded the model.
