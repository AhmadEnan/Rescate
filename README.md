# Rescate

An offline-first, highly secure, decentralized medical and emergency response application.

## Architecture

This project uses a **Package-Based Monorepo Architecture** to maintain clean boundaries between complex lower-level integrations (LLM, Cryptography) and the Flutter UI.

```text
Rescate/
├── apps/
│   └── rescate_app/             # Main Flutter UI app. Follows Feature-Based UI structure.
├── packages/
│   ├── ai_inference/            # llama.cpp, LiteRT, Int4 Quantization
│   ├── audio_voice/             # Offline VAD, Piper TTS
│   ├── offline_data/            # SQLite FTS5, ObjectBox/WatermelonDB, MBTiles
│   ├── p2p_mesh/                # BLE/Wi-Fi Direct, Micro-payloads
│   └── security_crypto/         # Ed25519, Curve25519, SQLCipher
```

## Getting Started

Because this project is a **Dart Workspace**, you can initialize it across all packages simultaneously. Ensure you have Flutter installed, then run the initialization command directly from the repository root:

### Initialization

```bash
# Fetch dependencies for all packages from the root directory
flutter pub get

# To run the UI app, navigate to its directory:
cd apps/rescate_app
flutter run
```

## Contribution
Please thoroughly read [CONTRIBUTING.md](CONTRIBUTING.md) before pushing code.