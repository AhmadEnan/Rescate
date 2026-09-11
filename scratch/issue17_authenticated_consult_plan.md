# Issue #17 — Authenticated Nearby Medical Consultation: Solution Plan

> Plan for [AhmadEnan/Rescate#17](https://github.com/AhmadEnan/Rescate/issues/17): "[Doctor] Let patients reach an authenticated nearby medical responder."
> Scope: **one-hop only** (issue #21 depends on this for multi-hop). Written 2026-09-06 against the current codebase state.

---

## 1. Starting point (what exists today)

| Piece | State | Location |
|---|---|---|
| Transport | Google Nearby Connections, `P2P_CLUSTER`, serviceId `com.rescate.bluetooth_messenger`, **auto-accepts every connection**, raw UTF-8 over BYTES payload, no frame format | `packages/bluetooth_mesh/lib/src/nearby_service.dart` |
| Crypto | `MeshCrypto`: Ed25519 identity + ephemeral X25519 + ChaCha20-Poly1305 — **implemented but wired nowhere**; known flaw: decrypt path uses the Ed25519 identity key *as* X25519 (wrong key type, non-functional) | `packages/security_crypto/lib/src/` (single file) |
| Trust | None. Device name only; specialty filter is a frontend placeholder | `apps/rescate_app/lib/features/community/screens/community_screen.dart` |
| Doctor side | Simulated replies, gated by `DemoState.isDemoMode` (hardcoded `false`) | `bt_chat_screen.dart`, `lib/core/providers/demo_state.dart` |
| Patient-data sharing | "Share vitals" formats last 5 `MeasurementStore` readings as **plaintext** chat text | `bt_chat_screen.dart` |
| AI escalation hook | `request_help_nearby` tool sends <100-byte text to all peers, no verification | `lib/features/ai_chat/tools/tool_dispatcher.dart` |
| Prior design work | BitChat-style mesh design (identity/peers/messages schema, E2EE, TTL/queue) — never implemented | `scratch/mesh_chat_design.md` |

## 2. Threat model (one-hop)

Adversary in BLE/Wi-Fi-Direct range. We defend against:

| Threat | Defense |
|---|---|
| **Impersonation** ("a phone that calls itself a doctor") | Offline-issued, signed Responder Credential bound to an Ed25519 identity key; app verifies signature chain + key fingerprints before any patient data flows |
| **Man-in-the-middle** | Transcript-bound handshake: session key derives from ephemeral↔static X25519 *plus* hash of all handshake frames; the static key is certified — swapping keys breaks the transcript MAC |
| **Replay / re-injection** | Monotonic per-direction counters in the AEAD nonce + receiver replay window; old frames fail decryption or the counter check and are dropped |
| **Tampering** | AEAD (ChaCha20-Poly1305) on every frame; AAD covers the frame header |
| **Metadata exposure** | Discovery name carries no PHI; discovery broadcasts only "responder present" flag; case payload is opt-in |
| **Lost / stolen device** | **v1: skipped (product decision 2026-09-06)** — no blocklist, no expiry, no theft handling. Note: the badge→key fingerprint match in §4 stays because it is inherent to badge verification (zero extra code); it means a *copied badge file* is useless, though a stolen unlocked phone is fully trusted |
| **Revocation without network** | **v1: skipped** — accepted that revocation doesn't exist offline without it. Revisit in v2 (local blocklist shipped with app updates, and/or `expires_at`) |

Explicitly **out of scope** (one-hop): multi-hop relay attacks (issue #21), traffic-analysis anonymity, Sybil/flood of connection requests (rate-limited in UI only), radio jamming / availability attacks.

**Prime directive (from acceptance criteria): failure never delays first aid.** Every security failure degrades to a clear status message; the AI chat and CPR flows are never blocked by consult code paths.

## 3. Trust anchor & credential design

No network ⇒ no online CA. Design:

- A **Rescate Medical Authority (RMA)** Ed25519 keypair signs responder credentials. The RMA public key is **pinned in the app** (`assets/keys/rma_public.pem` + fingerprint shown in Settings). Rotation = app update (acceptable for one-hop hackathon scope; document for later).
- **ResponderCredential v1** (canonical JSON, signed):
  ```
  { subject_fp:   SHA256(Ed25519 identity public key),      // 32B hex
    kx_fp:        SHA256(X25519 static public key),          // 32B hex — binding per issue
    name, role: doctor|nurse|emt, specialty, license_ref,
    issued_at }                                               // expires_at: reserved, omitted in v1 (no expiry)
  signature: Ed25519(RMA) over the canonical serialization
  ```
- **Distinct signing vs key-exchange keys** (explicit issue requirement): every responder device holds an Ed25519 identity keypair AND a separate X25519 static keypair; the credential fingerprints both, so the X25519 key is trusted *because* the credential says so — never by key-type conversion (this also retires the known MeshCrypto flaw).
- **Provisioning (offline):** a small CLI/desk tool (new `tools/credential_provisioner` in `security_crypto`, or a Python script under `scripts/`) generates responder keypairs, issues credentials as `.rescatecred` files / QR. Field flow: responder imports the file once in-app; private keys never leave the device.
- **Patient identity:** patients keep an ephemeral Ed25519 key regenerated per app install (per CONTRIBUTING's rotation spirit) but are **not required to be verified** — the trust asymmetry is deliberate: the patient must verify the responder; the responder sees only self-declared patient info.

## 4. Protocol (wire format)

**Framing** — length-prefixed binary frame (replaces raw UTF-8 text on the BYTES payload):

```
Frame = header(8B) + payload
header: magic 'RS' (2B) | version u8=1 | type u8 | flags u8 | reserved u8 | payload_len u16 LE
Types: HELLO(1) CERT_OFFER(2) SESSION_ACCEPT(3) DATA_TEXT(4) DATA_CASE(5)
       STATUS(6) ACK(7) CLOSE(8) REJECT(9)
```

⚠️ **Contract conflict to decide:** CONTRIBUTING mandates packets <100 bytes, but a cert + handshake can't fit. **Recommendation:** keep the <100B rule for *discovery/control* frames; exempt DATA frames on the Nearby transport (the plugin fragments internally); when BLE-native transport arrives (#21), the frame codec already supports fragmenting large payloads into ≤90B chunks via a `flags` bit — so the contract survives where it actually matters.

**Handshake (patient initiates to a discovered responder):**
1. `HELLO` (patient→responder): protocol version, patient ephemeral X25519 pub key, 16B random challenge. (<100B ✓)
2. `CERT_OFFER` (responder→patient): ResponderCredential + both public keys (larger frame, allowed).
3. Patient verifies: RMA signature ✓, `subject_fp`/`kx_fp` match presented keys ✓, not blocklisted ✓ (expiry checked only if the field is present — it never is in v1). Any failure → `REJECT` + drop, UI shows "Unverified device".
4. `SESSION_ACCEPT` (responder→patient): responder ephemeral X25519 pub, echo of challenge.
5. Both derive: `shared = X25519(patient_eph, responder_kx_static) ‖ X25519(patient_eph, responder_eph)` → `HKDF-SHA256(salt = transcript_hash, info = "rescate-consult-v1")` → **two keys** (`c2r`, `r2c`).
6. Every DATA frame: ChaCha20-Poly1305, `nonce = 4B session_id ‖ 8B BE counter`, AAD = frame header. Receiver enforces strictly-increasing counter with a 64-slot reorder window.

**Case payload** (the only message type allowed to contain patient data — `DATA_CASE`):
```
{ symptom_tags: [enum ids], note: ≤500 chars, vitals: [optional MeasurementStore records],
  include_location: bool + lat/lng, created_at }
```
Deterministic escalation policy: red-flag symptom set (from the LLM's `get_biometric`/triage flow or manual pick) → app *suggests* escalation and surfaces nearby **verified** responders; nothing is ever auto-sent. Sending requires the consent preview screen (§5).

## 5. UI / UX flows

- **CommunityScreen**: discovered devices split into **"Verified responders"** (green check + role/specialty from credential) and "Unverified devices" (grey, chat-only). The placeholder specialty dropdown is replaced by the credential's specialty.
- **Patient consult flow**: `BtChatScreen` becomes session-aware — unverified peer ⇒ persistent banner "Unverified device — patient data sharing disabled" and the share-vitals / case-payload buttons are disabled at the *state* layer, not just hidden. Verified peer ⇒ "Request consult" → **case payload preview sheet** (exactly what will be sent, per-field consent toggles for vitals/location) → explicit Send = consent → patient sees **delivered / accepted / declined / replied** status.
- **Responder mode**: Settings toggle "I am a medical responder" → credential import (file picker or QR) → verified badge. Adds **Responder Inbox** screen: incoming `DATA_CASE` requests, accept/decline with reply, secure history. Same app binary, role via credential.
- **Demo isolation**: simulated responders exist only under `DemoState` (unchanged, hardcoded false in prod); demo chats are visually labeled and never use the real session layer.
- **Failure paths**: no verified responder in range ⇒ escalation sheet says so and offers emergency numbers + "continue with AI guidance". Handshake failure ⇒ non-blocking toast; chat remains.

## 6. Implementation phases

**Phase 0 — Spec (½ day):** finalize this doc; get sign-off on the two decisions in §7.

**Phase 1 — `security_crypto` rework (2–3 days):**
- `lib/src/identity.dart`: `KeyMaterial` — Ed25519 identity + separate X25519 static key, serialize/persist.
- `lib/src/credential.dart`: `ResponderCredential` (issue, parse, verify against pinned RMA key + key-fingerprint match; blocklist/expiry checks deferred to v2).
- `lib/src/session.dart`: `ConsultSession` — handshake state machine, HKDF, encrypt/decrypt with counters + replay window.
- Replace `mesh_crypto.dart` (delete the flawed decrypt path).
- Unit tests: round-trip, tamper, replay, wrong key, expired cert, bad signature, fingerprint mismatch. *All run on host — no device needed.*

**Phase 2 — `bluetooth_mesh` transport upgrade (2–3 days):**
- `lib/src/frame.dart`: binary codec (encode/decode/fragment).
- `lib/src/consult_service.dart`: sessions over `NearbyService`, trust gating, connection confirmation (replace auto-accept: accept transport, then close unverified peers before handshake).
- `lib/src/mesh_store.dart`: sqflite peers/sessions/messages (per `scratch/mesh_chat_design.md` schema, minus multi-hop fields).
- `nearby_service.dart`: add raw-bytes send + payload callback (keep text API for demo mode).
- Tests: codec round-trip; service test with mocked transport.

**Phase 3 — App UI (3–4 days):**
- `features/community/services/consult_state.dart` — `ChangeNotifier` singleton (app pattern), bridges ConsultService ↔ UI.
- Rework `community_screen.dart` (trust split, responder toggle), `bt_chat_screen.dart` (session-aware, disable sharing to unverified), new `responder_inbox_screen.dart`, new `widgets/case_payload_sheet.dart` (consent preview), `models/case_payload.dart`.
- Update `test/demo_mode_test.dart` with a trust-gating test: unverified peer can never receive a case payload.

**Phase 4 — AI integration (1 day):**
- `tool_dispatcher.dart` `request_help_nearby`: enumerate *verified* responders only, route through consent sheet; if none in range, return that fact to the LLM so it can say "no responder nearby, here's first aid + emergency numbers".

**Phase 5 — Verification & docs (1–2 days):**
- Two-device manual test matrix: verified↔patient full flow; unverified peer blocked; replayed frame rejected; badge copied to a second phone rejected (fingerprint mismatch); app killed mid-consult; airplane-mode recovery; demo mode still isolated.
- Threat-model checklist review (clinical + security sign-off per acceptance criteria).
- Update `CONTEXT.md`, `README.md`, CONTRIBUTING packet-contract note.

## 7. Decisions to confirm (defaults chosen, cheap to change)

1. **Packet contract:** exempt DATA frames on Nearby; fragment for future BLE. *(Recommended; alternative: hard 100B everywhere → cert must be chunked through many frames, slower handshake.)*
2. **Trust anchor:** pinned RMA key + offline provisioning tool. *(Recommended; alternative for demo day: self-signed "community-witnessed" credentials — other verified responders co-sign — defer to post-hackathon.)*
3. **Responder inbox persistence:** keep consult history local, encrypted-at-rest later (SQLCipher stays a stated future item — don't block this issue on it).
4. **Badge TTL & revocation:** none in v1 — `expires_at` exists in the schema but is omitted and unenforced; no blocklist. Product decision 2026-09-06: skip all anti-theft machinery for now; the only protection is the (free, inherent) badge→key fingerprint binding. Revisit both after field feedback.

## 8. Acceptance-criteria mapping

| Issue criterion | Covered by |
|---|---|
| Unverified peers cannot receive patient data | §5 trust gating (state-layer enforcement) + Phase 3 test |
| Traffic is authenticated ciphertext | §4 session keys bound to certified identity; AEAD everywhere |
| Tampering/replay rejected | AEAD AAD + counters + replay window (Phase 1 tests) |
| Verified responder can receive and reply | §5 responder inbox + accept/decline/reply flow |
| Failure never delays first aid | §2 prime directive — all consult paths async, AI never blocked (Phase 4 fallback) |
| Clinical/security sign-off | Phase 5 checklist |

**Estimated total: ~9–13 working days** with Phase 1 testable on host immediately, and two physical devices needed from Phase 5 (the BLE multi-device testing rule from `scratch/mesh_chat_design.md` applies).
