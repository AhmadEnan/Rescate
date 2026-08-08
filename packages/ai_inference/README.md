# AI & LLM Inference Module

This package is responsible for on-device LLM Execution.
It wraps `llama.cpp` or LiteRT for Int4 Model Quantization and Handles token streaming.

Please refer to the root `CONTRIBUTING.md` before making changes.

## Device benchmarks

Use `fixedLlmBenchmarkCases` from the public package API for repeatable
emergency prompts. Each profiler `llm.turn` trace now records the resolved
backend, GPU layers, loaded Android CPU module (when visible in
`/proc/self/maps`), prompt token count, and native llama.cpp phase counters.
See [`benchmarks/README.md`](../../benchmarks/README.md) for the device run
procedure and artifact names.
