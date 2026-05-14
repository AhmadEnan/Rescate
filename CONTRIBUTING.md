# Contributing to Rescate

Welcome to the Rescate development team! This guide explains our architecture, our Git workflow, and how to operate within a complex, multi-developer environment.

## 1. Modular Architecture Overview 🏗️

The project is split into isolated domains. **Never** mix domain logic directly into the UI app. 

### Core Packages (`/packages/*`)
* **AI & LLM (`ai_inference`)**: Contains bindings for `llama.cpp` / LiteRT. 
* **Audio (`audio_voice`)**: VAD, Piper TTS integrations. 
* **Data (`offline_data`)**: SQLite FTS5, ObjectBox. 
* **Mesh (`p2p_mesh`)**: BLE / Wi-Fi Direct. Packets must stay under 100 bytes!
* **Security (`security_crypto`)**: Handlers for Ed25519, E2EE, and SQLCipher.

*Rule: Packages CANNOT depend on the main app. Packages should minimize dependencies on each other to prevent cyclical imports.*

### Main App UI (`/apps/rescate_app`)
The UI is broken down into a **Feature-Based Architecture**. Look under `lib/features/`:
* e.g., `lib/features/map`, `lib/features/chat`, `lib/features/sos`. 
* Each feature folder should contain its own `ui/`, `bloc/`(or state), and `models/`. 
* *Yes, the UI is explicitly separated into multiple files and feature directories to prevent UI merge conflicts.*

## 2. Setting Up Your Environment 🛠️

1. **Flutter SDK**: Ensure you are using Flutter 3.19+.
2. **Native Toolchains**: Because of `llama.cpp` and `Piper`, ensure you have CMake and the NDK installed for Android, and Xcode for iOS.
3. **Fetching Dependencies**:
   Because we use Dart Workspaces, you can fetch all dependencies across all packages from the root directory:
   ```bash
   flutter pub get
   ```

## 3. Branching Strategy & Git Flow 🌿

We follow a strict Branch-and-Merge workflow.

* **Main Branch**: `main` is production-ready.
* **Development Branch**: `develop` is the active integration state.
* **Feature Branches**: `feature/[module-name]-[short-desc]`. 
  * *Example:* `feature/ai-int4-quantization`
* **Bugfix Branches**: `bugfix/[module-name]-[short-desc]`.

**Commit Messages**: Keep them atomic. 
* [AI] Added async token streaming.
* [UI] Split MapScreen into MapWidget and MarkerLayer.

## 4. Pull Request Checklist ✅

Before you open a PR against `develop`, ensure:
1. **Linting Passes**: Run `flutter analyze` at the repo root.
2. **Tests Pass**: All unit tests in your specific `/packages/your_package` pass (`flutter test`).
3. **No UI State Leakage**: State management should be local to the `feature/` folder in the app, or provided globally via core.
4. **Security Check**: Did you touch keys or data? Ensure Ed25519 identities remain ephemeral (12h rotation) and SQFlite is wrapped in SQLCipher.

## 5. C/C++ Binding Guidelines
If you are tweaking `llama.cpp` or Audio engines:
* Modify the C/C++ code inside `packages/[name]/src`.
* Ensure `CMakeLists.txt` builds cleanly for both ARM64 Android and iOS.
* Expose via FFI cleanly in Dart, parsing pointers safely.

Thank you for contributing to saving lives!
