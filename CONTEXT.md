# Rescate Project Context

## Overview
Rescate is an offline-first emergency response application built with Flutter & Dart workspace monorepo structure (`apps/rescate_app` and packages under `packages/`).

## Status & User Guidance
- Added detailed step-by-step instructions for building the Flutter app (`apps/rescate_app`) with dart-defines (`apps/rescate_app/dart_defines.json`) and connecting Android devices wirelessly via ADB pairing / connection.
- Identified local ADB path at `C:\Users\Ahmed\AppData\Local\Android\Sdk\platform-tools`. Provided instructions to add to PATH and quick PowerShell workaround.
- Clarified that `flutter run` / `flutter build` commands must be run from inside `apps/rescate_app` directory where the Android platform files (`android/AndroidManifest.xml`) reside.
- Corrected `-t` flag syntax error (`-t` requires target file path like `lib/main.dart` or can be omitted if in app root).
- Verified wireless ADB device connection (`192.168.1.10:45867`). Provided full `flutter run` command including `RESCATE_PROFILER=true` and `dart_defines.json`.
- **Build Resolution & Fixes Complete**:
  - Fixed Java 25 / Gradle compatibility error by configuring Flutter JDK to OpenJDK 21 (`21.0.4+7`).
  - Upgraded Android Gradle Plugin (AGP) to `8.9.1`, Gradle Wrapper to `8.11.1`, and Kotlin to `2.1.0`.
  - Resolved Flutter 3.44 / Dart 3 `final class IconData` error by migrating `lucide_icons` to `lucide_icons_flutter: ^3.1.15` across app features.
  - Successfully compiled release APK (`apps/rescate_app/build/app/outputs/flutter-apk/app-release.apk` - 154.0MB).
  - Verified `dev_profiler` implementation and ran test suites across `packages/dev_profiler`, `packages/biometric_estimators`, `packages/offline_data`, and `packages/sensor_availability` (all 39 tests passed).
- **Live Deployment & Profiling Results**:
  - Pulled live session profiler data from device (`session_1785996865910_chat_turn.json`) and updated workspace root [profiler_report.json](file:///c:/dev/Rescate/profiler_report.json).
  - **Performance Analysis (superseded — see below)**: initial reading attributed the 590.5s `chat.turn` to Flutter JIT debug overhead, VM service tracing, and thermal throttling.
  - **Corrected root cause (2026-08-06)**: the native llama.cpp timers rule debug overhead out. `prompt_eval_ms` (336,872) + `eval_ms` (251,581) + `sample_ms` (1,728) = **590.2s of the 590.6s** `chat.turn` wall time — i.e. ~0.4s total outside libllama. Dart/JIT/profiler overhead is noise at this scale.
  - **Benchmark Execution & Artifact Collection Complete**:
    - Updated `benchmarks/automate_benchmarks.py` to resolve ADB device serials dynamically (`get_device_serial()`).
    - Verified all 3 required checkpoint artifacts in `benchmarks/README.md` are present and valid:
      - `profiler_report.json` (24 KB, raw profiler export)
      - `benchmarks/benchmark_report.json` (2 KB, `LlmBenchmarkReport` envelope)
      - `benchmarks/device_logcat.txt` (23.5 MB, native device logcat)
    - The real signal is the **prefill:decode ratio**: 703 prompt tokens in 336.9s = **2.09 tok/s**, vs 377 generated tokens in 251.6s = **1.50 tok/s**. Healthy llama.cpp prefill runs 10-100x decode because it batches the whole prompt into one matmul. Near-parity means batching bought nothing — the signature of a Vulkan compute path round-tripping per op rather than executing the batch.
    - Device is **MT6893** (Dimensity 1200 / Mali-G77), a known-poor llama.cpp Vulkan target, and `rung0` was offloading **all 999 layers** to it. Because the model *loads* fine and answers correctly, the crash-driven fallback ladder never triggered — it only reacts to SIGSEGVs, not to a backend that is merely slow.
  - **Fixes applied** (`packages/ai_inference`):
    - `llm_load_strategy.dart`: added `slowVulkanSocMarkers` / `hasSlowVulkanCompute()`; matching SoCs get a CPU-only ladder with the Vulkan rungs stripped entirely.
    - Retuned the CPU rung — it is now the primary path on these devices, not a last resort: `contextSize` 1024 → `safeCtx` (2048, since a ~700-token prompt + 1024 `maxTokens` could not fit in 1024), and `batchSize`/`microBatchSize` 64/32 → 256/128 so prefill actually batches.
    - Added `firstCpuRungIndex()` and switched `llm_service.dart`'s crash-collapse and low-RAM jumps off the hardcoded `safeModeRungIndex` (3), which would index past the end of the now-shorter CPU-only ladder.
    - `device_profile.dart`: split `recommendedBatchThreads` from `recommendedThreads`. Decode stays pinned to big cores (2 here); prefill is compute-bound and now scales across all cores (6). Previously both were 2, leaving 6 cores idle during the most expensive phase.
    - `legacy_rag.dart` / `llm_config.dart`: Gemma 4 thinking mode (`<|think|>`) is now opt-in via `LlmDefaults.enableThinking` (default **false**). Counters showed `chat.flush_thought=36` vs `chat.flush_answer=12` — ~3 hidden reasoning tokens per visible token, all decoded before the user sees any first-aid text.
  - **Verification**: `flutter analyze` clean for the changed files; all tests pass (`ai_inference` 27, `dev_profiler` 9, `biometric_estimators` 17, `offline_data` 13, `sensor_availability` 10).
  - **Verified On-Device Performance Improvements** (`session_1786004510405_chat_turn.json`):
    - **Prefill (Prompt Eval)**: Speed increased from 2.09 tok/s (336.9s for 703 tokens) to **4.58 tok/s** (153.1s for 701 tokens) — **>2.2x faster prefill**.
    - **Generation Phase**: Reduced from 251.6s to **53.9s** — **>4.6x faster generation phase**.
    - **Time-to-First-Token (TTFT)**: Cut from 342.3s (~5.7 min) down to **157.8s (~2.6 min)** — **>2.1x faster TTFT**.
    - **Overall Chat Turn Duration**: Slashed from 590.6s (~9.8 min) down to **207.6s (~3.4 min)** — **>2.8x FASTER OVERALL**.
- **Documentation & Git Commit Consolidation**:
  - Enhanced the "Model Download required" callout in `README.md` using GitHub-flavored Markdown native alerts (`> [!IMPORTANT]`) for visual appeal, theme compatibility, and clear downloading instructions.
  - Staged and created structured, logical commits across monorepo packages (dev_profiler, ai_inference, rescate_app, benchmarks, and docs).
- **GitHub Actions Release CI**:
  - Created `.github/workflows/release.yml` with Java 21, Flutter setup, workspace unit test execution, release APK compilation (`flutter build apk --release`), and automatic publishing to GitHub Releases via `softprops/action-gh-release@v2`.
  - Verified local release build end-to-end (`app-release.apk` - 153.8MB compiled cleanly).
  - Pushed all commits to `origin/main` (`https://github.com/AhmadEnan/Rescate`).


