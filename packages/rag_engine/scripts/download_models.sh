#!/usr/bin/env bash
# scripts/download_models.sh
#
# Downloads the quantized MiniLM-L6-v2 ONNX model and tokenizer.
# Run from the packages/rag_engine directory:
#
#   bash scripts/download_models.sh
#
# Requirements: curl, internet access (one-time setup only).

set -euo pipefail

ASSETS_DIR="$(dirname "$0")/../assets/models"
mkdir -p "$ASSETS_DIR"

MODEL_URL="https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2/resolve/main/onnx/model_qint8_arm64.onnx"
TOKENIZER_URL="https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2/resolve/main/tokenizer.json"

echo "Downloading model (~23 MB)..."
curl -L --progress-bar -o "$ASSETS_DIR/model.onnx" "$MODEL_URL"

echo "Downloading tokenizer..."
curl -L --progress-bar -o "$ASSETS_DIR/tokenizer.json" "$TOKENIZER_URL"

echo "Done. Files saved to $ASSETS_DIR:"
ls -lh "$ASSETS_DIR"
