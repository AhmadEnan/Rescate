# Security & Cryptography Module

This package enforces cryptographic standards and protocols for Rescate, including the authenticated nearby consult channel (Issue #17).

- **Identity & Authentication**: Ed25519 digital signatures with SHA-256 public key fingerprint binding.
- **Key Exchange**: X25519 ECDH deriving dual directional keys via HKDF-SHA256 bound to handshake transcripts.
- **Session Cipher**: ChaCha20-Poly1305 AEAD with monotonic counters for tamper protection and replay rejection.
- **Secure Key Storage**: Private seeds stored in platform-backed secure hardware storage.

---

## Key Management & Storage Architecture

### Storage Model
Private key material must **never** be persisted in plaintext files or unencrypted app sandbox files:
- **Private Seeds**: Ed25519 identity seed and X25519 key-exchange seed are stored using `SecretStore` (`SecureStorageSecretStore`), which delegates to `FlutterSecureStorage`:
  - **Android**: Android Keystore backed by `EncryptedSharedPreferences`.
  - **iOS**: iOS Keychain with `KeychainAccessibility.first_unlock_this_device`.
- **Metadata**: On-disk JSON file (`rescate_responder_keys.json`) contains only non-sensitive metadata (schema version, type, storage backend identifier, and creation timestamp). Legacy v1 plaintext files are automatically migrated to platform secure storage upon loading.
- **Badge Credentials**: Authority-signed badge credentials (`rescate_responder_badge.json`) contain public keys, permissions, authority signatures, and validity timestamps. Badges are cryptographic certificates and are re-validated upon each restore.

---

## Key Rotation Workflow

When a responder needs to rotate their keys (e.g. routine rotation, device change, or policy expiry):

1. **New Keypair Generation**:
   - The responder triggers `ConsultState.instance.createBadgeRequest()` (or CLI tool `credential_provisioner.dart`).
   - A fresh Ed25519 identity keypair and X25519 key-exchange keypair are generated.
   - The new private seeds are written to platform secure storage, replacing the prior secrets.
2. **Badge Invalidation & Request**:
   - Any previously held badge credential associated with the old public key fingerprints is cleared (`ConsultKeyStore.clearCredential()`), disabling responder mode until a new badge is issued.
   - A new CSR-like badge request JSON containing the fresh public keys is exported via the system share sheet.
3. **Medical Authority Endorsement**:
   - The Medical Authority signs the badge request using its offline root key (`authority.issueBadge(...)`).
   - The issued badge is imported into the app via `ConsultState.instance.importBadge()`.
   - The signature, public key fingerprints, and expiration are verified before activating responder mode.
4. **Session Invalidation**:
   - Existing peer connections must perform a new transcript-bound handshake; old session keys cannot decrypt future traffic.

---

## Key Loss and Recovery Policy

In an emergency offline-first context:

- **No Remote Key Escrow**: For patient and responder privacy, private keys are strictly local and non-escrowed.
- **Key Loss Behavior**:
  - If a device is wiped, secure storage is cleared, or the device is lost, the responder's identity keys cannot be recovered.
  - The stored badge cannot be used with newly generated keys because badge signatures bind cryptographically to the original public key fingerprints (`identity_key_fingerprint` and `kx_key_fingerprint`).
- **Recovery Procedure**:
  - The responder must re-generate a new identity keypair and badge request on their replacement device.
  - The responder presents their clinical credentials to the Medical Authority to receive a newly signed badge.
  - Patient safety is prioritized: unverified responders fail closed and cannot receive sensitive case payloads or consult requests.

