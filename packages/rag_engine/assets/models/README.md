# Model assets

Place the following files in this directory before running the app:

- `model.onnx`  — quantized MiniLM-L6-v2 ONNX model (~23 MB)
- `tokenizer.json` — tokenizer vocabulary for MiniLM

Run the download script from the package root:

```bash
bash scripts/download_models.sh
```

Or download manually from:
- https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2/tree/main/onnx
