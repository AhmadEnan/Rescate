# Repository Guide

**Read [CONTEXT.md](CONTEXT.md) first — it is the complete, self-contained project context** (architecture, every feature and package, native layers, LLM subsystem, build/CI commands, benchmarks, known gaps, and conventions). It is written so you can work in this codebase without re-reading the whole repository.

Quick orientation:

- **What this is:** Rescate — an offline-first emergency response app (Gemma 4 Good Hackathon). Flutter app in `apps/rescate_app`, domain logic in `packages/*` (pub workspace).
- **Run it:** `flutter pub get` at root, then from `apps/rescate_app`: `flutter run --dart-define-from-file=dart_defines.json`. Requires JDK 21.
- **Core rule:** keep domain logic in packages; the app is UI-only. Mesh packets stay under 100 bytes. Offline is the baseline.
- **AI chat needs a model:** download `gemma-4-E2B-it-Q4_K_M.gguf` (link in README) and select it in the in-app Model Setup screen.

See also: [CONTRIBUTING.md](CONTRIBUTING.md), [benchmarks/README.md](benchmarks/README.md), [scratch/mesh_chat_design.md](scratch/mesh_chat_design.md).
