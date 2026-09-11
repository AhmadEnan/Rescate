# Rescate — Full Project Context

> **Purpose of this file:** a complete, self-contained briefing on this repository for any AI agent (or new contributor). It is written so you can work in this codebase **without re-reading the whole project**. It was generated 2026-09-06 from a full sweep of every app feature, package, native layer, CI workflow, benchmark artifact, and design doc. Anything not stated here either doesn't exist or is explicitly flagged as a gap.

---

## Table of contents

1. [What Rescate is](#1-what-rescate-is)
2. [Repository layout](#2-repository-layout)
3. [Tech stack & versions](#3-tech-stack--versions)
4. [Architecture & how the pieces fit](#4-architecture--how-the-pieces-fit)
5. [Build, run & CI](#5-build-run--ci)
6. [The Flutter app — features in detail](#6-the-flutter-app--features-in-detail)
7. [Packages — detailed reference](#7-packages--detailed-reference)
8. [AI / LLM subsystem deep dive](#8-ai--llm-subsystem-deep-dive)
9. [Data & RAG](#9-data--rag)
10. [Mesh communication & security](#10-mesh-communication--security)
11. [Biometrics pipeline](#11-biometrics-pipeline)
12. [Native platform layer](#12-native-platform-layer)
13. [Profiling & benchmarks](#13-profiling--benchmarks)
14. [Tests](#14-tests)
15. [Known gaps, dead code & quirks](#15-known-gaps-dead-code--quirks)
16. [Conventions & rules](#16-conventions--rules)
17. [Environment notes](#17-environment-notes)

---

## 1. What Rescate is

**Rescate** is an **offline-first emergency response Android app** (iOS folder exists but is secondary) built for the **Gemma 4 Good Hackathon**. It gives responders/patients, operating with **no network**, five capabilities via a 5-tab UI:

| Tab | Feature | One-liner |
|---|---|---|
| Learn | `educational` | Bilingual (AR/EN) first-aid lessons with CPR metronome + animations |
| Map | `map` | Offline maps (FMTC tiles), GraphHopper safe routing that detours around crowdsourced danger zones |
| AI Chat (default) | `ai_chat` | Fully on-device GGUF LLM (Gemma 4 via llama.cpp) with tool-calling into device sensors |
| Consult | `community` | P2P device-to-device chat over Google Nearby Connections (BLE/Wi-Fi Direct transport) |
| Vitals | `measurements` | Camera/IMU/mic-derived biometric estimates (PPG heart rate, acoustic respiration, etc.) |

Design pillars (from README/CONTRIBUTING): **domain logic lives in packages, not the app**; **mesh packets < 100 bytes**; **offline behavior is the baseline, not a fallback**; native changes require cold rebuilds.

- License: **Apache 2.0**. Git remote: `https://github.com/AhmadEnan/Rescate`.
- README links a `CLAUDE.md` "Repository Guide" — this file is that guide.

---

## 2. Repository layout

Dart **pub workspace** (not melos) — one `flutter pub get` at the root resolves everything.

```
App/                              (repo root = workspace, name: rescate_workspace)
├── pubspec.yaml                  workspace definition; dependency_overrides: record_linux ^1.3.0, archive ^4.0.7
├── analysis_options.yaml         flutter_lints + stricter subset (see §16)
├── CONTEXT.md                    ← this file
├── README.md, CONTRIBUTING.md, LICENSE (Apache 2.0)
├── .github/workflows/release.yml the only workflow (release APK → GitHub Releases)
├── test/workspace_smoke_test.dart trivial placeholder so root `flutter test` has an entrypoint
├── scripts/run.bat|run.ps1|run.sh  launchers: cd apps/rescate_app && flutter run --dart-define-from-file=dart_defines.json
├── apps/rescate_app/             the Flutter app (see §6)
├── packages/                     10 packages, 8 implemented (see §7)
├── rag_system/                   DESKTOP-ONLY Python prototype harness (not shipped in the app) — see §9
├── benchmarks/                   on-device LLM benchmark tooling + result artifacts — see §13
├── scratch/                      design notes & one-off scripts (mesh_chat_design.md = BitChat-style mesh design; rewrite*.py rewrote onboarding_screen.dart; extract_colors.py theming helper)
├── assets/                       marketing/README imagery only (logo, banner, tab screenshots)
└── artifacts/                    rescate_app_final.png (screenshot)
```

Key rule: **packages never depend on the app**; the app depends on packages via relative path deps (`../../packages/*`).

---

## 3. Tech stack & versions

| Component | Value |
|---|---|
| Flutter | stable ~3.41+ (README badge 3.41.6); app `flutter: >=3.19.0` |
| Dart | `^3.11.4` everywhere |
| Workspace | pub workspace, root `pubspec.yaml` name `rescate_workspace` |
| Android | minSdk **26**, target/compile from Flutter, Java 17 in app Gradle, **JDK 21 required to build** (Flutter JDK configured to OpenJDK 21 after a Java 25/Gradle failure) |
| Android toolchain | AGP **8.9.1**, Gradle wrapper **8.11.1**, Kotlin plugin **2.1.0**; `gradle.properties`: `-Xmx8G`, `kotlin.incremental=false`, `android.builtInKotlin=false`, `android.newDsl=false` |
| applicationId | `com.example.rescate_app` (template default, not rebranded) |
| LLM runtime | **llamadart ^0.6.17** (llama.cpp binding) → GGUF models, CPU/Vulkan/OpenCL Android, Metal iOS |
| Primary model | **Gemma 4 E2B it, Q4_K_M GGUF** (~2.62 GB on device as `/storage/emulated/0/Download/model.gguf`); download from `unsloth/gemma-4-E2B-it-GGUF` on Hugging Face — **not bundled** |
| Release APK | ~154 MB |

App dependencies (all in `apps/rescate_app/pubspec.yaml`): `flutter_map ^6.1.0`, `flutter_map_tile_caching ^9.0.1` (FMTC, ObjectBox backend), `latlong2 ^0.9.1`, `geolocator ^14`, `sensors_plus ^6.1.2`, `nearby_connections ^4.3.0`, `shared_preferences ^2.5.5`, `permission_handler ^12.0.1`, `device_info_plus ^11`, `file_picker ^8` (GGUF picking), `google_fonts ^6.2.1`, `flutter_animate ^4.5.2`, `http`, `sqflite` + `sqflite_common_ffi_web` (web target exists under `web/`), `lucide_icons_flutter ^3.1.15` (migrated off `lucide_icons` for Dart 3 compat).

`apps/rescate_app/dart_defines.json` (always pass via `--dart-define-from-file`):
```json
{ "LLAMADART_ANDROID_VULKAN_ALLOW_OP_OFFLOAD": "true",
  "LLAMADART_ANDROID_VULKAN_ALLOW_KQV": "true",
  "LLAMADART_ANDROID_VULKAN_ALLOW_FLASH_ATTN": "true" }
```
App pubspec also packages **all llama.cpp backends** via `hooks.user_defines.llamadart.llamadart_native_backends: [cpu, vulkan, opencl]` (android-arm64); runtime policy picks per device.

---

## 4. Architecture & how the pieces fit

### 4.1 Package dependency graph (path deps)

```
ai_inference ────────┐          offline_data ──> biometric_estimators ──> sensor_availability
audio_voice ─────────┼──> dev_profiler (leaf; every package + app depends on it)
bluetooth_mesh ──────┤          offline_data ──> sensor_availability
biometric_estimators─┘          bluetooth_mesh ──> security_crypto (declared, NOT yet used in code)
```

All 8 implemented packages are path deps of the app. `p2p_mesh` and `rag_engine` are **spec-only** (READMEs + stale `.dart_tool` state, no pubspec/lib, not workspace members) — see §10 and §9.

### 4.2 App-side architecture (intentionally simple)

- **No code-gen state management** (no Provider/Riverpod/Bloc/goRouter/intl). Pattern is:
  - `ChangeNotifier` singletons in packages (`LlmService`, `TtsService`, `SttService`, `SensorAvailabilityService`, `NearbyService`), subscribed manually via `addListener` + `setState`.
  - App state: `lib/core/providers/app_state.dart` — `AppState extends ChangeNotifier` (language, notificationsEnabled; persisted via SharedPreferences) exposed through `AppStateProvider extends InheritedNotifier<AppState>` with `AppStateProvider.of(context)`.
  - `lib/core/providers/demo_state.dart` — `DemoState` singleton; **`isDemoMode` is hardcoded `false`** (mock readings API kept but production-disabled; enforced by `apps/rescate_app/test/demo_mode_test.dart`).
- **Routing:** plain `MaterialApp`. `home:` is `OnboardingScreen` (first launch, persisted in prefs `isFirstLaunch`) else `MainScreen`. Only named routes: `/sensors` → `SensorAvailabilityScreen`, `/biometrics` → `BiometricAvailabilityScreen`. Everything else is imperative `Navigator.push`. Two global keys matter:
  - `rootNavKey` (`GlobalKey<NavigatorState>`, `lib/main.dart:25`) — AI tool executors show dialogs without context.
  - `mainScreenKey` (`GlobalKey<MainScreenState>`, `main_screen.dart`) — lets onboarding/educational switch bottom-nav tabs.
- **Theming:** inline `ThemeData(ColorScheme.fromSeed(Colors.red), useMaterial3: true)` in `main.dart`. Screens style themselves from `lib/core/theme/app_colors.dart` (`AppColors`: background `0xFFE8E1D7`, primaryRed `0xFFA11F2B`). `lib/core/theme/app_theme.dart` (`AppTheme.lightTheme`, Poppins) is **dead code**.
- **Localization:** no intl/arb. Ad-hoc `AppState.isArabic ? '...' : '...'` ternaries everywhere, hardcoded 7-language maps in onboarding (`English, Español, Français, Deutsch, Português, العربية, हिन्दी`), manual `Directionality` wrappers for RTL. Arabic detection via regex for TTS language pick.

### 4.3 App bootstrap sequence (`lib/main.dart`, ~229 lines)

1. `Profiler.markSessionStart()` → `WidgetsFlutterBinding.ensureInitialized()`; web only: `databaseFactoryFfiWeb`.
2. Inside `Profiler.trace('app.bootstrap')`:
   - `DeviceProfile.detect()` (ai_inference, via MethodChannel `dev.rescate/device_profile`) → `LlmDefaults.activeProfile`.
   - `_initOfflineMapCache()`: `FMTCObjectBoxBackend().initialise()` + store `'rescate_offline_map'`.
   - Fire-and-forget `SensorAvailabilityService.instance.detectAll()` (6 s timeout; 26 sensors probed).
   - SharedPreferences; GPU default heuristic: disable Vulkan on budget SoCs (`g52`, `g72`, `helio`, `mt67` in socModel); read pref `ai_chat.use_gpu`.
3. `runApp(_BootstrapApp(...))` — FutureBuilder spinner until `MeasurementStore.open()` resolves.
4. `RescateApp` (WidgetsBindingObserver): attaches `RescateToolDispatcher(navKey: rootNavKey, measurementStore)` to `LlmState.instance` (→ `LlmService.attachToolRegistry`), post-frame `LlmState.instance.tryAutoLoadModel()`, exports Profiler JSON on pause/detach (`Profiler.exportJson(label: 'autosave')`).

---

## 5. Build, run & CI

### 5.1 Commands

```bash
# workspace resolve (run at repo root once)
flutter pub get

# run the app (from repo root, or use scripts/run.bat|ps1|sh)
cd apps/rescate_app
flutter run --dart-define-from-file=dart_defines.json

# release build (~154 MB APK; lands in build/app/outputs/flutter-apk/app-release.apk)
cd apps/rescate_app && flutter build apk --release

# tests: workspace-level from root, or per package
flutter test
```

- Build **must** be run from inside `apps/rescate_app` (platform folders live there). `-t` flag optional; do not pass `-t` without a target path.
- Regenerate platform folders if needed: `flutter create --platforms=android,ios --org dev.rescate .` (inside the app dir).
- Wireless ADB pairing/connect has been used before (`adb pair`/`adb connect <ip:port>`); full run command previously included `RESCATE_PROFILER=true` plus the dart-defines file.
- Native changes (Android, iOS, CMake, FFI, plugin/llamadart edits) require a **full cold rebuild**.

### 5.2 CI (`.github/workflows/release.yml` — the only workflow)

"Build & Release APK": triggers on **push to `main`**, tags `v*`, and `workflow_dispatch`; `contents: write`.
Job `build-and-release` (ubuntu-latest): checkout@v4 → Java 21 temurin → Flutter stable (cached, subosito/flutter-action@v2) → `flutter pub get` at root **and** in `apps/rescate_app` → `flutter test` → `flutter build apk --release` → copy to `build_output/rescate-app-release.apk` → tag = pushed tag or `v1.0.0-build.<run_number>` → GitHub Release via `softprops/action-gh-release@v2` with auto notes. Only secret: built-in `GITHUB_TOKEN`.

### 5.3 Version-compat history (already fixed, don't regress)

- Java 25 broke Gradle → Flutter JDK pinned to OpenJDK `21.0.4+7`.
- Flutter 3.44/Dart 3 `final class IconData` clash → `lucide_icons` migrated to `lucide_icons_flutter ^3.1.15`.
- `javax.annotation` / concurrent-futures: `androidx.concurrent:concurrent-futures:1.2.0` injected into all subprojects (camera_android_camerax workaround).

---

## 6. The Flutter app — features in detail

App: `apps/rescate_app` (name `rescate_app`, version 0.0.1). ~23 Dart files under `lib/`, ~10.9k lines. UI-only by design; all real logic lives in packages.

### 6.1 `features/home` — app shell
- `screens/main_screen.dart` (237): `MainScreen`/`MainScreenState` + global `mainScreenKey`. Custom pill bottom nav with 5 tabs (order above, AI Chat default index 2). Map + AI Chat kept alive via `Offstage`; others animate slide/fade. Nav bar hides when keyboard opens.
- `widgets/top_bar.dart` (317): logo, `_NotificationButton` (OverlayEntry dropdown fed by a **mock** `Stream.periodic(15s)` with bilingual notification text), settings button → `SettingsScreen`.

### 6.2 `features/ai_chat` — on-device LLM chat (the core feature)
- `screens/ai_chat_screen.dart` (1547): `AiChatScreen` (`AutomaticKeepAliveClientMixin`). Sub-widgets: `_ChatToolbar`, `_ModelStatusBanner`, `_EmptyState`, `_StreamingText`, `_ChatBubble`, `_InlineCprButton`, `_ThoughtsDisclosure` (collapsible model reasoning), `_TypingIndicator`, `_BubbleTail` (CustomPainter), `_VitalsPickerSheet`. Uses `TtsService`/`SttService` for mic input and auto read-aloud of finished answers (Arabic detection regex). Injects recent vitals into prompts as `[SYSTEM_VITALS_CONTEXT: ...]` from `MeasurementStore`.
- `state/llm_state.dart` (537): `LlmState` singleton `ChangeNotifier` — the central chat hub. Models: `ChatMessage` (text, `thoughts` from thought channel, isStreaming/isThinking, ttftMs/totalMs, `InlineWidgetType`), `Conversation`. Streams tokens with word-boundary buffering; separates thought vs answer channels; persists to prefs `ai_chat.conversations.v2` / `ai_chat.active_conversation_id`. `tryAutoLoadModel()` has a crash-loop guard via `LlmLoadDiagnostics` (skips auto-load after 5 fallback rungs exhausted).
- `screens/model_setup_screen.dart` (818): `ModelSetupScreen`, `_GgufBrowserScreen` (in-app filesystem browser for user-supplied `.gguf`), `_RecommendedModelsCard`. Requests `MANAGE_EXTERNAL_STORAGE`, persists path to pref `ai_chat.model_path`, shows `LlmLoadDiagnostics` banner + Safe-mode toggle.
- `screens/chat_history_screen.dart` (202): conversation list/select/delete.
- `screens/voice_chat_screen.dart` (319): full-screen animated-orb voice UI — **mic is NOT wired** (shows snackbar "Voice chat is unavailable until native voice input is connected").
- `tools/tool_definitions.dart` (103): three `ToolSchema`s in `kRescateTools` — `get_biometric` (heart_rate/respiration/spo2/temperature/pupillometry), `request_help_nearby`, `show_cpr_tutorial`; plus `shouldUseRescateTools()` keyword gate (EN+AR) so ordinary medical questions skip tool declarations (tested).
- `tools/tool_dispatcher.dart` (298): `RescateToolDispatcher` —
  - `get_biometric`: consent dialog → `CaptureSession()` + `BiometricEstimatorRegistry` capture → `MeasurementStore.insert`, non-blocking `_CaptureProgressSheet`; maps heart_rate→ppgCardiovascular, respiration→acousticRespiration, spo2→pulseOximetry (stub), temperature→coreBodyTemperature (stub), pupillometry→pupillometry.
  - `request_help_nearby`: `NearbyService.sendMessage` to all connected peers (kept <100 bytes).
  - `show_cpr_tutorial`: queues `PendingInlineWidget` drained by `LlmState` → renders inline CPR button deep-linking into `CprLessonScreen`.

### 6.3 `features/map` — offline map (largest file)
- `screens/map_screen.dart` (1610): flutter_map v6; geolocator stream; compass heading from accelerometer+magnetometer. Offline tile download sheet (`_DownloadedMapArea`, `_DownloadOptionData`, progress panel) on FMTC store `rescate_offline_map`. Crowdsourced `_MapReport` danger zones / aid points (`_ReportType {danger, aid}`, `_DangerZone` with radius) persisted in prefs `offline_map_reports`, tap-to-place. Safe routing: `_setSafeRouteTo` → `OfflineRouteService.findRoute` (native GraphHopper + danger-zone detour algorithm, see §12). Reference point `_redCrescentPoint = LatLng(33.513, 36.285)` (Damascus).
- `services/offline_route_service.dart` (142): Dart side of MethodChannel `rescate/offline_routing` (`prepareRoadGraph`, `findRoute`); graceful `MissingPluginException`/`PlatformException` handling.
- `ui/map_screen.dart` (11): **dead placeholder** ("Map Feature Module Placeholder") — the real screen is `screens/map_screen.dart`.

### 6.4 `features/educational` — first-aid lessons
- `screens/educational_screen.dart` (1239): searchable bilingual AR/EN lesson grid; **6 lessons**: CPR Basics, Wound Care, Fractures & Splints, Burn Treatment, Food Poisoning, Choking Response. `CprLessonScreen` is public (deep-linked from AI chat). `_LessonDetailScreen`: PageView steps with a CPR **metronome** (500 ms `Timer` → `SystemSound.click` = 120 BPM during compressions), `_AnimatedHumanGraphic`, `_ImageSequenceAnimation` (PNG frame playback from `assets/learn/cpr/step1..4`), `_PanelBorderPainter`.

### 6.5 `features/community` — mesh consult
- `screens/community_screen.dart` (736): toggle advertising+discovery via `NearbyService`; runtime permissions (bluetooth*, location; `NEARBY_WIFI_DEVICES` gated to SDK ≥33 via device_info_plus); specialty filter dropdown is a **frontend placeholder** (Cardiologist, ER…); device tiles → `BtChatScreen`.
- `screens/bt_chat_screen.dart` (463): 1:1 chat over `NearbyService`; "share vitals" formats last 5 `MeasurementStore` readings into a message; disconnected banner; simulated doctor replies only when `DemoState.isDemoMode` (hardcoded false).

### 6.6 `features/measurements` — vitals
- `screens/measurements_screen.dart` (915): 3 tabs — Sensors (from `SensorAvailabilityService`), Tests (estimators grouped available/potentiallyAvailable/unavailable; `_TestCard` → `BiometricDetailScreen` from biometric_estimators), History (`MeasurementStore.recentAll(limit: 50)`).

### 6.7 `features/onboarding` & `features/settings`
- `screens/onboarding_screen.dart` (859): 3-page PageView (Language Selection, Offline First, Rescate) with `_localizedContent` for 7 languages; finish → `MainScreen(key: mainScreenKey)`.
- `screens/settings_screen.dart` (105): language bottom sheet (7 languages), notifications switch, About dialog — all via `AppStateProvider`; manual RTL `Directionality`.

---

## 7. Packages — detailed reference

### 7.1 `packages/ai_inference` — Module 1: on-device LLM (the heart of the project)
Full deep dive in **§8**. Wraps **llamadart ^0.6.17** (llama.cpp). Public barrel `lib/ai_inference.dart`: `LlmService`, `LlmState/Status/Token/Channel`, `LlmDefaults`, `DeviceProfile`, fallback ladder types, `LlmLoadDiagnostics`, `LegacyRag`, tool-calling types, benchmark cases/reports. Deps: llamadart, path_provider, dev_profiler.

### 7.2 `packages/audio_voice` — Module 2: voice
- **Reality vs docs:** README says "VAD + Piper TTS", but the implementation wraps **OS engines**: `tts_service.dart` wraps `flutter_tts ^4.2.1`; `stt_service.dart` wraps `speech_to_text ^7.3.0`. No Piper/VAD in the Flutter app (Piper lives only in the desktop `rag_system/` harness, §9).
- `TtsService` singleton: `speak(text, isArabic)` / `stop()` / `setEnabled()`; auto language en-US vs system Arabic locale (fallback `ar-EG`); Arabic rate 0.45 vs 0.5; strips `[SYSTEM_VITALS_CONTEXT:…]` tags + markdown before speaking; Android QUEUE_ADD.
- `SttService` singleton: `initialize()` (mic permission + engine availability), `startListening({isArabic, onResult})` dictation with partials, `stopListening()`, `cancel()`; `SttStatus` enum; Arabic locale matched against engine's supported `ar_*` locales.
- Used only by `ai_chat_screen.dart`.

### 7.3 `packages/offline_data` — Module 3: persistence & search
Deps: sqflite, path, path_provider, collection, crypto, uuid (+ path deps biometric_estimators, sensor_availability, dev_profiler). **Implemented today: two stores** (MBTiles/FTS5/ObjectBox-in-package remain README aspirations — FMTC's ObjectBox is used from the app instead):
- `lib/vector_store/vector_store.dart` — `VectorStore`: SQLite `rescate_vectors.db` (WAL), table `vectors(id, namespace, payload JSON, embedding Float32 BLOB)`. Cosine similarity in a background **Isolate**; ≤10k entries batched linear scan; larger → **flat IVF index** (k-means, √N buckets ≤200, 10 iters, probe top-3). API: `open/upsert/upsertBatch/delete/deleteNamespace/clear/count/listNamespaces/search(queryEmbedding, topK, minScore, namespace)`. `VectorEntry` stores L2-normalized Float32 blobs. **Built and tested, but no production caller yet** — it's waiting for the MiniLM/ONNX embedding model (rag_engine spec, §9).
- `lib/measurement_store/measurement_store.dart` — `MeasurementStore implements BiometricMeasurementRepository`: SQLite `measurements.db` storing `BiometricMeasurement.toLLMRecord()` JSON; `insert`, `latestFor`, `historyFor`, `recentAll`, `exportLLMBundle({since})`. Opened at app bootstrap, injected into `RescateToolDispatcher`.

### 7.4 `packages/bluetooth_mesh` — Module 4: nearby mesh
- Wraps `nearby_connections ^4.3.0` (Google Nearby Connections API; transport is whatever that plugin negotiates — BLE/Wi-Fi Direct).
- `lib/src/nearby_service.dart` — `NearbyService` singleton: `startAdvertising()`/`startDiscovery()` with `Strategy.P2P_CLUSTER`, serviceId `com.rescate.bluetooth_messenger`; `requestConnection(endpointId)` with **auto-accept**; `sendMessage()` sends raw UTF-8 over BYTES payload — **no packet format, no multi-hop routing, no store-and-forward, no encryption yet**. Callbacks `onMessageReceived`, `onConnectionChanged`; maps of discovered/connected/pending endpoints; username defaults to device model.
- `lib/src/bt_message.dart` — `BtChatMessage` (text, isSent, timestamp), UI model only.
- Header TODO: wire Ed25519 ephemeral identity from security_crypto (dep declared but unused).

### 7.5 `packages/security_crypto` — Module 5: crypto
- Deps: `cryptography ^2.9.0`, sqflite, path, uuid, dev_profiler. Pure Dart; **no SQLCipher yet**.
- Single public class `MeshCrypto`: `generateIdentityKeyPair()` (Ed25519), `getPublicKeyBytes()`, `encryptDirectMessage(text, senderIdentity, recipientPubBytes)` / `decryptDirectMessage(...)` — ephemeral X25519 + ECDH + **ChaCha20-Poly1305 AEAD**; wire format `[1B ephemeral-pub-len][ephemeral pub][nonce][MAC][ciphertext]`.
- **Known simplification (in comments):** decrypt treats the recipient identity key as X25519 though identity keys are Ed25519. **Nothing in the repo imports this package yet** — E2EE is declared, not connected.

### 7.6 `packages/dev_profiler` — profiling (everything routes through it)
- Debug/profile-only, tree-shaken in release: `kProfilerEnabled = bool.fromEnvironment('RESCATE_PROFILER', defaultValue: !kReleaseMode)`.
- `Profiler` static API, two layers: **Aggregates** (`span`/`spanSync`/`recordSpan` wall-ms + RSS delta, `event`, `count`, `snapshot`, `reset`) and **Traces** (`openTrace`/`trace`/`traceSync` → nullable `TraceHandle` with nested `TraceStep`s, `op(n)` counters, auto-closing children). `exportJson(label)` writes `appDocuments/profiler/session_<ts>[_label].json`. Caps: 5000 events / 200 traces / 200 samples/span. No-ops when disabled.
- Instrumented spans across the repo: `app.bootstrap`, `llm.loadModel`, `llm.turn` (steps: `rag.search`, `rag.buildPrompt`, `llm.decode` + native TTFT/tok-s), `tts.*`, `stt.*`, `mesh.*`, `crypto.*`, `db.vectors.*`, `db.measurements.*`, `sensors.detectAll`, `tool.dispatch.*`.

### 7.7 `packages/sensor_availability` — Module 7 (the only package with its own native code)
Flutter plugin (`dev.rescate.sensor_availability`), Android + iOS. One-shot existence check of **26 hardware sensors** at startup, cached; statuses `available/unavailable/unknown/needsPermission`; existence only — no values, no permissions.
- `SensorAvailabilityService.instance`: `detectAll()` (native probes, 2 s timeout), `get(SensorId)`, `reports`, `biometrics` (via `resolveBiometrics`), `grouped`.
- `SensorId`: 26 values (accelerometer…radar, uwb, hallEffect, fingerprint×3, structuredLightFace, iris, heartRatePpg, pulseOximeter, thermopile, thermistor, strainGauge, memsMicrophone, cmosImageSensor). `BiometricId`: 20 values.
- Native Android (`SensorAvailabilityPlugin.kt`): `SensorManager.getSensorList(TYPE_ALL)`, Camera2 depth capability, UWB system feature + hard-coded Soli-radar heuristic (Pixel 4 / Pixel 10 Pro strings), `BiometricManager.canAuthenticate(BIOMETRIC_STRONG)`, thermal status, mic/camera features, camera list. minSdk 23, no external maven deps.
- Native iOS (`SensorAvailabilityPlugin.swift`): CoreMotion, ARKit sceneDepth/LiDAR, NearbyInteraction (UWB), LocalAuthentication, AVAudioSession/AVFoundation; `listNativeSensors` returns `[]` (no enumeration API on iOS).
- Dart↔native channel: `dev.rescate/sensor_availability` (methods: listNativeSensors, hasSystemFeature, motionAvailability, cameraDepthCapability, uwbRadarAvailability, biometryAvailability, thermalAvailability, microphoneAvailability, cameraList).
- Also ships UI screens: `SensorAvailabilityScreen`, `BiometricAvailabilityScreen` (the `/sensors` and `/biometrics` routes).
- Most-imported package in the repo (29 imports; also used by biometric_estimators for capability gating and offline_data for the ID types).

### 7.8 `packages/biometric_estimators` — Module 8: vitals pipeline
Pure Dart. Deps: `camera ^0.12`, `sensors_plus ^6`, `record 5.1.2`, `fftea ^1.5`, path_provider, uuid (+ dev_profiler, sensor_availability).
- Core interfaces (`lib/src/core/`): `BiometricEstimator` (`id`, `suggestedDuration`, `captureInstruction`, `isSupportedBy(SensorAvailabilityService)`, `capture(CaptureSession)`), `CaptureSession` (broadcast streams: `progress`, `rawSignal` ~20 Hz downsampled waveform, `diagnostics`; 1200-sample replay buffer; cancel token), `BiometricMeasurement` (status ok/lowConfidence/failed/stub, confidence, primary/secondary `ScalarReading`s, quality flags, source sensors, methodology/biomarker/application; **`toLLMRecord()`/`fromLLMRecord()` schema_version 1** — the format fed to the LLM and DB), `BiometricMeasurementRepository`, `CaptureProtocol`, `signal_quality.dart` (confidence from peak prominence / IBI CoV / SNR).
- `BiometricEstimatorRegistry` singleton: 20 `BiometricId`s → **9 real estimators + 11 stubs**. Stubs include `pulseOximetry` and `coreBodyTemperature` (i.e., the AI `get_biometric` tool will return stub-status measurements for those).
- Real estimators (`lib/src/estimators/`): `PpgCardiovascularEstimator` (rear camera + flash fingertip, 30 s, 0.7–4 Hz band → heart_rate bpm + RMSSD ms), `SeismocardiographyEstimator` (phone on chest, accel z, 0.5–40 Hz), `GyrocardiographyEstimator`, `AcousticRespirationEstimator` (mic → respiratory_rate + dominant freq), `ProximityRespirationEstimator`, `FlickerDosimetryEstimator` (front camera → ambient flicker Hz), `GripStrengthEstimator`, `SpirometryEstimator` (barometer PEF proxy), `PupillometryEstimator`.
- DSP (`lib/src/dsp/`): Biquad/BiquadCascade/Butterworth, radix-2 FFT, Welch periodogram, peak detection with prominence, `RingBuffer`.
- Acquisition (`lib/src/acquisition/`): `CameraPpgSource` (mean-red-channel), `ImuSource`, `MicSource`, `AmbientLightSource`.
- Widget: `lib/src/widgets/biometric_detail_screen.dart` (pushed from the Vitals tab and the AI tool flow).

### 7.9 Spec-only packages (do NOT try to import)
- **`packages/p2p_mesh`** — README only: store-and-forward routing (BLE/Wi-Fi Direct), micro-payload serialization (<100 bytes), decentralized threat consensus. Previous intended deps (from stale plugin state): `flutter_blue_plus 9.0.0`, `flutter_mesh_network 0.1.3`, permission_handler, sqflite. See §10 for the design doc.
- **`packages/rag_engine`** — assets/models/README.md only: plan is **MiniLM-L6-v2 quantized ONNX (~23 MB)** + `tokenizer.json` downloaded via `scripts/download_models.sh` (HF sentence-transformers/all-MiniLM-L6-v2/onnx). Previous intended deps: onnxruntime 1.4.1, pdfrx (PDF ingestion). Meanwhile production RAG = `LegacyRag` (§8.5) and `VectorStore` (§7.3) is ready to back semantic search once embeddings land.

---

## 8. AI / LLM subsystem deep dive

### 8.1 Runtime
**llama.cpp via `llamadart ^0.6.17`** — not MediaPipe/LiteRT. Models are **GGUF** (Gemma family; primary: `gemma-4-E2B-it-Q4_K_M.gguf`, ~2.62 GB). Chat format is the **Gemma 4 template**: `<|turn>…<turn|>` turns, `<|channel>thought…<channel|>` reasoning channel, `<|tool_call>…<tool_call|>` function calling, `<|tool>declaration:` declarations, stop sequence `<turn|>`. Tokenization/streaming/KV-prefix reuse (`reusePromptPrefix`) delegated to llamadart (`LlamaEngine.generate` stream).

### 8.2 `LlmService` (`packages/ai_inference/lib/src/llm_service.dart`)
Singleton `ChangeNotifier`; status machine `LlmStatus` (idle/loading/ready/generating/error). `loadModel(modelPath)` walks a **fallback ladder** with a **sticky crash marker** written before every native call so a libllama SIGSEGV doesn't crash-loop the app. GPU-collapse logic skips remaining Vulkan rungs after a GPU crash; free-RAM check jumps to CPU rung. Streaming: `generateStream()` / `generateStreamWithTools()` → `Stream<LlmToken>`; a channel-splitter state machine strips `<|channel>thought…<channel|>` markers (which can split across tokens) and tags chunks `LlmChannel.thought|answer`. Tool loop: parses `<|tool_call>`, dispatches via `ToolRegistry.executor`, appends `<|tool_response>`, regenerates; hard-capped at **2 round-trips / 45 s per tool**. Also `LlmNotReadyException`, `LlmException`.

### 8.3 Fallback ladder (`llm_load_strategy.dart`)
- rung0 Vulkan all-layers/f16 KV → rung1 Vulkan no-mlock/q8_0 → rung2 Vulkan 16 layers → rung3 CPU q8_0 ctx 2048 batch 256/128 (**primary rung on slow-SoC devices**) → rung4 CPU q4_0 ctx 1024. `flashAttention` forced on everywhere.
- `slowVulkanSocMarkers`: MediaTek `mt6893/6889/6877/6853/6785/6769` → **CPU-only ladder** (Vulkan rungs stripped). Rationale: on MT6893 the Vulkan path round-trips per-op instead of batching (prefill≈decode speed ⇒ broken batching); the crash-fallback never triggers because it only reacts to SIGSEGV, not slowness.
- Helpers: `hasSlowVulkanCompute`, `firstCpuRungIndex` (crash-collapse and low-RAM jumps use it instead of the old hardcoded safe-rung index 3), `describeModelParams`.

### 8.4 `DeviceProfile` (`device_profile.dart`) & sampling (`llm_config.dart`)
- `DeviceProfile.detect()` via MethodChannel **`dev.rescate/device_profile`** (implemented in the app's MainActivity.kt): totalRamMb, availRamMb, isLowRamDevice, socModel (Build.SOC_MODEL), abi, bigCoreCount (sysfs `cpuinfo_max_freq`). Derives: decode threads pinned to big cores (≤4), prefill threads = all cores (≤6; split `recommendedBatchThreads` from `recommendedThreads`), ctx 2048/4096, KV q8_0/f16, batch sizes. `DeviceProfile.fallback` for hosts/desktop.
- `LlmDefaults`: temp 1.0, topP 0.95, topK 64, maxTokens 1024, repeatPenalty 1.1, `useGpu` (pref `ai_chat.use_gpu`), **`enableThinking` default false** (Gemma 4 thinking mode `<|think|>` was emitting ~3 hidden reasoning tokens per visible token at ~1.5 tok/s). When thinking is off, LegacyRag pre-fills a canned thought. `buildModelParams()` is dead code on the production path.

### 8.5 `LegacyRag` (`legacy_rag.dart`) — the production RAG
Keyword/BM-ish retrieval over bundled **`assets/chunks.json` (312 chunks, 400-word windows)**, loaded once (counter `rag.chunks.loaded=312`). Arabic normalization + ~250-entry Arabic→English medical term map + English synonym expansions; windowed scoring (360-char windows, action-term boosts for procedural questions, reference-section penalties); LRU cache (32); `rag.search` observed ≤175 ms. `buildPrompt()` renders the Gemma 4 template with EN/AR first-aid system prompts and optional tool declarations.

### 8.6 Tool calling (`lib/src/tools/`)
`ToolCall`, `ToolCallParser` (parse/`stripMarkup`/`renderResponse`), `ToolSchema`/`ToolArg` (Gemma 4 wire format `<|tool>declaration:…`), `ToolRegistry {schemas, executor}`. The app builds the registry (`RescateToolDispatcher`, §6.2) with the keyword gate `shouldUseRescateTools()` deciding whether tools are even declared for a prompt.

### 8.7 Diagnostics
- `GgufFileCheck` preflight (exists/magic/size), `LoadAttempt` sticky JSON `ai_chat/llm_load_attempt.json` (survives SIGSEGV), `LlmLoadDiagnostics` (256 KB-rotated `llm_load.log`, `readFreeRamMb` via the device_profile channel).
- `runtime_diagnostics.dart`: reads `/proc/self/maps` to detect loaded `libggml-cpu-android_armv*.so` variant.
- `kv_cache_store.dart`: dead code (disk KV path deemed unsound and dropped; imports `crypto` which isn't in pubspec).

---

## 9. Data & RAG

- **In-app corpus:** `apps/rescate_app/assets/chunks.json` — 312 chunks `{id: <source>_chunk_N, source, text, word_count: 400}` with `[Page N]` markers. Covers chronic diseases, fractures, breathing/chest, GI/musculoskeletal, poisoning, neurological, mental health/shock, first aid, survival medicine, burns (Parkland formula, white phosphorus), field emergencies.
- **Origin pipeline:** `rag_system/` (desktop-only, **not shipped in the app**):
  - `step1_parse_and_chunk.py`: PDF → chunks.json (pdfplumber→pypdf fallback; keeps ASCII + Arabic `\u0600-\u06FF`; 400-word chunks, 50 overlap).
  - `step2_build_index.py`: Whoosh full-text index (`chunk_id`, `source`, `content` StemmingAnalyzer) into `search_index/`.
  - `rag_akher_TTS_CHUNK_SUBPROCESS.py` (a.k.a. rag_server_fixed.py): **Flask app on :8081** — desktop voice-chat prototype: llama.cpp server on :8080 (`/completion`), `faster_whisper` STT (tiny, int8), **Piper TTS** (`piper/piper.exe`; voices `en_US-lessac-medium.onnx` and `ar_JO-kareem-low.onnx`, 63 MB each; Arabic also via `tts_arabic` + shakkelha), Whoosh retrieval + AR→EN keyword map, strict "answer only from provided context" system prompts (EN+AR), routes `/ask`, `/v`/`/voice`, `/tts`, `/health`; serves `chat_voice_full.html`. Source PDFs live in `rag_system/docs/` (11 guideline PDFs). `step3_rag_chat.py` is referenced but missing. `tts_outputs/` holds test WAVs.
- **Vector search:** `offline_data.VectorStore` (§7.3) is implemented and tested but has **no production caller** until rag_engine's MiniLM/ONNX embeddings are integrated.
- **Measurements:** `MeasurementStore` (§7.3) — the only DB with production traffic; opened at bootstrap, fed by biometric captures, read by chat prompt context, history tab, and share-vitals.

---

## 10. Mesh communication & security

**Current implementation (shipped):** `bluetooth_mesh` over `nearby_connections` — P2P_CLUSTER, auto-accept connections, raw UTF-8 text messages, 1:1 chat only. No multi-hop, no store-and-forward, no packet format, no encryption.

**Designed but not built:** `scratch/mesh_chat_design.md` records a BitChat-style upgrade:
- Chosen lib: **`flutter_mesh_network`** (flood routing, store-and-forward, TTL, BLE/Wi-Fi Direct/MultipeerConnectivity). Rejected: Bridgefy (proprietary/license/API-key), raw P2P libs (too much routing work), native Nearby/Multipeer (no true multi-hop, duplicated native code).
- Data model: SQLite (`sqflite_sqlcipher`) tables `identity` (nodeId, displayName, Ed25519 keypair), `peers`, `messages` (messageId, senderId, nullable recipientId=broadcast, isOutgoing, encryptedPayload, nonce, timestamp, **ttl 6h**, status queued/sent/delivered/failed); `MeshConfig(maxHops: 10)`.
- Security: Ed25519 identity/signatures, X25519 agreement, ChaCha20-Poly1305 AEAD for 1:1; public channel signed but **unencrypted by design**. Matches `security_crypto.MeshCrypto` (§7.5) which already implements the primitive.
- UX/state: `MeshProvider` (ChangeNotifier, matching `AppState` pattern) replacing CommunityScreen; lazy init on user toggle (battery); background lifecycle via WidgetsBindingObserver; permissions already in the manifest.
- Test plan: ≥3 physical devices, release mode, radios off except BT; phases: crypto/DB unit → discovery + queued delivery across restarts → A–B–C multi-hop → permission-denial/radio-off edge cases.

**Contract to respect:** mesh packets must stay **< 100 bytes** (`request_help_nearby` already honors this).

---

## 11. Biometrics pipeline

End-to-end flow when the LLM calls `get_biometric`:
1. Keyword gate decides tool declaration (§8.6).
2. Consent dialog → `CaptureSession()` from the matching estimator (gated by `SensorAvailabilityService` capabilities).
3. Acquisition sources (camera mean-red PPG / IMU / mic / barometer / ambient light) → DSP (Butterworth biquads → FFT/Welch → peak detection) → `BiometricMeasurement` with confidence from signal quality.
4. `MeasurementStore.insert` (LLM-record JSON) → available to future prompts as `[SYSTEM_VITALS_CONTEXT: …]`, to the Vitals History tab, and to share-vitals in mesh chat.
- Real today: **heart_rate (PPG + RMSSD), respiratory_rate (acoustic), pupillometry proxy, plus SCG/GCG/flare/grip/spirometry variants**. Stub status: **SpO₂, core temperature**, and 9 exotic ones (§7.8).
- UI: Vitals tab groups by availability; `BiometricDetailScreen` renders capture instructions/progress/waveform.

---

## 12. Native platform layer

**`apps/rescate_app/android/app/src/main/kotlin/com/example/rescate_app/MainActivity.kt`** (~450 lines, the live one) registers two MethodChannels:
- **`rescate/offline_routing`**:
  - `prepareRoadGraph` — downloads an OSM bbox from the **Overpass API**, builds a **GraphHopper** graph (CH profile "car") into `filesDir/offline_routing/graph-cache`.
  - `findRoute` — routes start→destination with a **danger-zone detour algorithm**: computes perpendicular/radial detour waypoints around unsafe zones (radius +250/500/850 m at 45° bearings), tries candidate multi-waypoint routes until one avoids all zones; haversine/segment math in Kotlin.
- **`dev.rescate/device_profile`** (consumed by ai_inference): `getInfo` (totalRamMb, availRamMb, isLowRamDevice, socModel, abi, bigCoreCount from sysfs), `getFreeRam`. Also sets Aalto StAX system properties for GraphHopper's OSM XML reader.
- There is a second, **unused** MainActivity at `android/.../dev/rescate/rescate_app/MainActivity.kt` (bare FlutterActivity) — the gradle namespace is `com.example.rescate_app`.

**Gradle:** GraphHopper deps `com.graphhopper:graphhopper-core:1.0`, `graphhopper-reader-osm:1.0`, `slf4j-simple:1.7.36`, `javax.xml.stream:stax-api:1.0-2`, `com.fasterxml:aalto-xml:1.3.2`; proguard notes mention `-dontwarn` for GraphHopper JDK AWT/ImageIO. Release build currently **signs with debug keys**.

**AndroidManifest permissions:** INTERNET; legacy + modern Bluetooth (SCAN/ADVERTISE/CONNECT); fine+coarse location; `NEARBY_WIFI_DEVICES` (+ wifi.aware feature, not required); CAMERA (+ feature); RECORD_AUDIO; READ_EXTERNAL_STORAGE (maxSdk 32); **MANAGE_EXTERNAL_STORAGE** (needed for llama.cpp `fopen` of the GGUF); READ_MEDIA_IMAGES/VIDEO/AUDIO; `<queries>` for PROCESS_TEXT and TTS_SERVICE.

**iOS:** Runner exists (AppDelegate/SceneDelegate/Info.plist) with `NSBluetoothAlwaysUsageDescription`, `NSCameraUsageDescription` (fingertip HR), `NSMicrophoneUsageDescription` (respiration). Not deeply modified.

**Own native code in packages:** only `sensor_availability` (§7.7). Everything else heavy (llama.cpp, Nearby) comes from third-party plugins. No FFI/Pigeon/JNI glue of our own.

---

## 13. Profiling & benchmarks

### 13.1 Workflow (`benchmarks/README.md`)
- Fixed prompt set: `benchmarks/fixed_prompts.json` = also exported as `fixedLlmBenchmarkCases` from ai_inference (burn, unconscious_breathing, bleach_ingestion, arabic_burn).
- Build **profile** APK with `--dart-define=RESCATE_PROFILER=true` + dart_defines.json; install; load model; 1 warm-up turn then ≥3 measured runs per case; pull `app_flutter/profiler/session_*_chat_turn.json` via `adb run-as com.example.rescate_app`; dump logcat.
- Convert: `dart run packages/ai_inference/tool/benchmark_report.dart profiler_report.json benchmarks/benchmark_report.json` (`LlmBenchmarkReport`, formatVersion 1: total time, TTFT, backend, GPU layers, native prompt/decode token counts, phase times, tok/s, thread/batch params).
- **Rule: never compare runs differing in model file, build mode, thermal state, or prompt order.**
- `benchmarks/automate_benchmarks.py`: ADB UI driver — dynamic device serial resolution, taps hardcoded screen coordinates (New Chat / field / send), `adb shell input text` for English, `ADB_INPUT_TEXT` broadcast for Arabic, polls for new profiler sessions (5 s interval, 600 s timeout), pulls to root `profiler_report.json` and runs the conversion.

### 13.2 Recorded results (device: MT6893 (Dimensity 1200-class, Mali-G77), 8 cores / 2 big, 7.6 GB RAM; model.gguf 2.62 GB; backend CPU, Vulkan disabled via slowVulkanSoc; rung `rung3/cpu: mlock=false kv=q8_0 ctx=2048 batch=256/128`)
- **Before the perf fixes:** 590.6 s chat turn — prefill 2.09 tok/s, decode 1.50 tok/s, TTFT 342 s. Near-parity prefill/decode proved the Vulkan path was round-tripping per-op (999 layers on a bad Vulkan target; crash-fallback can't see "slow", only SIGSEGV).
- **After the fixes** (CPU-only ladder + batch 256/128 + prefill threads on all cores + thinking off): prefill 4.58 tok/s (>2.2×), generation phase 53.9 s (>4.6×), TTFT 157.8 s (>2.1×), overall turn 207.6 s (>2.8×).
- **Latest artifacts (2026-08-08, profile build):** `benchmark_model_burn_20260808.json` — TTFT 56.8 s, total 133 s, prompt 260 tok @ 5 tok/s, decode 120 tok @ 2 tok/s (best decode). Others: TTFT 26–65 s on warm turns, decode ~1–2 tok/s. First-turn cold prompt eval dominates (~161–169 s); `llm.loadModel` ≈ 8–12 s with RSS +3.2 GB. `profiler_report.json` at root = raw dev_profiler export (spans/events/counters/traces) from the same session family.
- `benchmarks/model_header_16m.bin` is **not a model** — a 50-byte adb error capture kept as an artifact. `device_logcat*.txt` (up to ~23.6 MB) are native load/backend diagnostics.

---

## 14. Tests

| Location | What | Notes |
|---|---|---|
| `apps/rescate_app/test/demo_mode_test.dart` | `DemoState` can't be enabled in production; `shouldUseRescateTools` gating (ordinary medical Qs get no tool declarations; "measure my heart rate"/"open CPR tutorial" do) | The only meaningful app test |
| `apps/rescate_app/test/widget_test.dart` | trivial smoke (pumps Text('Rescate')) | Placeholder |
| `test/workspace_smoke_test.dart` (root) | asserts true | Exists so root `flutter test`/CI has an entrypoint |
| Package suites | ai_inference (27), dev_profiler (9), biometric_estimators (17), offline_data (13), sensor_availability (10) — all passing as of last recorded run (Aug 2026) | Run via workspace `flutter test` |

**Not covered:** map/routing, chat persistence, mesh, measurements UI, security_crypto. Physical-device mesh testing per the design doc has not happened.

---

## 15. Known gaps, dead code & quirks

1. **Dead code (safe to ignore/delete, don't build on it):** `lib/core/theme/app_theme.dart` (`AppTheme.lightTheme` unused); `lib/features/map/ui/map_screen.dart` (placeholder duplicate — real screen is `screens/map_screen.dart`); `LlmDefaults.buildModelParams()`; `ai_inference/lib/src/kv_cache_store.dart` (dropped disk-KV design, imports non-existent dep); second `dev/rescate/.../MainActivity.kt`.
2. **`security_crypto.MeshCrypto` is implemented but wired nowhere**; `bluetooth_mesh` declares the dep but doesn't use it; decrypt path has the Ed25519-as-X25519 simplification. E2EE is a declared goal, not a feature.
3. **`VectorStore` has no production caller** (awaiting rag_engine embeddings). Production RAG is keyword-based `LegacyRag`.
4. **README overstates voice:** claims "VAD + Piper TTS" in the app; reality is flutter_tts/speech_to_text OS engines; Piper exists only in the desktop `rag_system/` harness. `VoiceChatScreen` mic is explicitly not wired (snackbar).
5. **Demo mode is intentionally hard-disabled** (`DemoState.isDemoMode = false`) and test-enforced. Community specialty filter is a frontend placeholder; notifications are a mock stream.
6. **App identity is still Flutter-template:** `com.example.rescate_app`, label `rescate_app`; release APK signed with debug keys; `pubspec.lock` is gitignored (`*.lock` rule).
7. **SpO₂ and temperature estimators are stubs** (registry marks them stub-status) though the AI tool advertises them.
8. **11 of 20 biometric estimators are stubs** (§7.8).
9. **Vulkan GPU inference is disabled by policy** on listed MediaTek SoCs (mt68xx family) and by default on budget SoCs (`g52/g72/helio/mt67`); GPU path remains for capable devices via pref.
10. **Duplicated exploration debt:** two MainActivity packages; rag_engine/p2p_mesh stale `.dart_tool` state; `rag_system/step3_rag_chat.py` referenced but missing.
11. **Windows quirks baked into config:** `kotlin.incremental=false` and build-dir redirection in Gradle config (cross-drive fix); `gradle.properties` heap 8 GB.
12. `model_header_16m.bin` in benchmarks is junk (adb error capture), not a model.

---

## 16. Conventions & rules

From CONTRIBUTING.md and observed practice:
- **Modular architecture:** domain logic never in the UI app; packages cannot depend on the app; minimize inter-package deps (path deps only within workspace).
- **Mesh packets < 100 bytes** (product contract with BLE/Wi-Fi Direct).
- **Emergency data local-first** — offline is the baseline, not fallback.
- **Security targets:** Ed25519 ephemeral identities with ~12h rotation; SQLite wrapped in SQLCipher (neither landed yet).
- **Feature-based UI:** `lib/features/<feature>/{screens,widgets,state,services,tools}` is the de-facto layout (CONTRIBUTING says `{ui,bloc,models}` but code uses screens/state/tools).
- **Linting:** `flutter_lints` + extra errors (`avoid_print`, `cancel_subscriptions`, `close_sinks`, `valid_regexps`), style rules (const-preferred, final locals, sorted pub deps), `missing_required_param`/`missing_return` as errors, `todo` as warning, generated files excluded. `public_member_api_docs` off.
- **Git flow:** `main` = production, `develop` = integration (not currently used — work lands on `main`), branches `feature/[module]-[desc]` / `bugfix/...`; atomic commits with prefixes (history uses conventional commits like `feat(rescate_app):`, `ci:`, `docs:`, `benchmarks:`).
- **PR checklist:** `flutter analyze` clean; package tests pass; no UI state leakage into packages; benchmark comparisons never cross model/build/thermal/prompt-order boundaries.
- **C/C++ (FFI for llama.cpp/audio):** CMakeLists must build ARM64 Android + iOS; safe pointer parsing.

---

## 17. Environment notes

- Dev machine: Windows (win32), Git Bash shell. Repo commonly edited from `apps/rescate_app` for Flutter commands.
- ADB previously at `C:\Users\<user>\AppData\Local\Android\Sdk\platform-tools` (add to PATH); wireless ADB (`adb pair/connect <ip:port>`) has been used for on-device runs.
- Test device used for benchmarks: MediaTek MT6893 (Dimensity 1200-class), 8 cores/2 big, ~7.6 GB RAM, model at `/storage/emulated/0/Download/model.gguf`.
- Model download (required before AI chat works): [`gemma-4-E2B-it-Q4_K_M.gguf`](https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF?show_file_info=gemma-4-E2B-it-Q4_K_M.gguf) → put on device storage → pick it in the in-app Model Setup screen (persists to pref `ai_chat.model_path`).
- Profiler JSONs auto-export on app pause to `appDocuments/profiler/` (dev/profile builds); pull with `adb run-as com.example.rescate_app`.

---

*End of context. If something you need isn't here, check `scratch/mesh_chat_design.md` (mesh design), `benchmarks/README.md` (benchmark protocol), `CONTRIBUTING.md` (rules), or the package READMEs under `packages/*/README.md`.*
