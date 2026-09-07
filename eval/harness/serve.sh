#!/bin/bash
# Usage: serve.sh <gguf-path> [port] [ctx]
GGUF="$1"; PORT="${2:-8080}"; CTX="${3:-4096}"
BIN="$HOME/Development/llama.cpp-src/build/bin/llama-server"
exec "$BIN" -m "$GGUF" --port "$PORT" -c "$CTX" -t 2 --mlock -ngl 0 2>&1
