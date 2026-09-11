# Issue #17 — Testing Guide: Making a Verified Doctor

> Companion to `issue17_authenticated_consult_plan.md`. Everything is implemented and covered by
> 23 host tests (10 crypto, 8 mesh protocol, 2 app trust-gating, plus the pre-existing suites).
> This guide walks the *real* flow on devices.

## What was built (summary)

| Layer | What |
|---|---|
| `packages/security_crypto` | `ResponderKeys` (Ed25519 identity + X25519 kx), `ResponderCredential` (the badge), `BadgeRequest`, `PatientHandshake`/`ResponderHandshake`, `ConsultSession` (ChaCha20-Poly1305 + replay protection), `ConsultKeyStore` |
| `packages/security_crypto/tool` | `credential_provisioner.dart` — the coordinator's CLI (`create-authority`, `issue`, `verify`, `show`) |
| `packages/bluetooth_mesh` | `ConsultFrame` binary codec ('RS' magic), `ConsultService` (trust-gated sessions), `NearbyService` now routes `RS`-magic bytes to the consult layer and text to legacy chat |
| App | `ConsultState` hub, responder setup + inbox screens, consent-preview case-payload sheet, trust banner in chat, responder strip on the Consult tab, `request_help_nearby` tool now targets verified responders only |

Trust anchors: the RMA public key is pinned in `packages/security_crypto/lib/src/identity.dart`
(`ConsultAuthority.defaultPublicKeyHex`). The matching private key lives in `keys/rma_key.json`
on the coordinator machine (**gitignored — never commit it**).

---

## Part A — Become a verified doctor (2 phones + 1 PC)

**Phone D = the doctor's phone. Phone P = the patient's phone. PC = coordinator.**

1. **Install the app on both phones** (USB debugging → run/`flutter install`, or `adb install app-debug.apk`).

2. **Doctor: create a badge request (Phone D)**
   - Open the app → **Consult** tab → tap the **"I am a medical responder"** strip.
   - Enter the doctor's full name → **Generate request file**.
   - The request is written to `/sdcard/Download/` when shared storage is
     writable; on phones that deny it (scoped storage), it falls back to the
     app's private directory and the shown path reflects that — either way
     the write succeeds.
   - Send it to the coordinator: tap **Share request file…** (WhatsApp/email/
     any share target — no cable needed), or `adb pull <shown path>`.

3. **Coordinator: sign the badge (PC)**
   ```bash
   dart run packages/security_crypto/tool/credential_provisioner.dart issue \
     --request rescate_badge_request.json \
     --authority-key keys/rma_key.json \
     --name "Dr. Ahmed Hassan" \
     --role doctor \
     --specialty "Emergency Medicine" \
     --license "SY-ER-1234" \
     --out badge_ahmed.json
   ```
   Roles: `doctor` | `nurse` | `emt`. Omit `--expires-days` for a never-expiring badge (v1 default).
   Sanity-check: `... verify --badge badge_ahmed.json` → `VALID`.

4. **Doctor: import the badge (Phone D)**
   - Push the badge to the phone: `adb push badge_ahmed.json /sdcard/Download/`
     (or any file transfer).
   - In the responder screen tap **Choose badge file…** → pick `badge_ahmed.json`.
   - Expected: green snackbar "Verified: Dr. Ahmed Hassan — responder mode enabled",
     the strip turns into a green badge card, **Open consult inbox** appears, and the
     phone's mesh display name gains a `•MD` suffix.
   - **Turn on the radio**: on the Consult tab press **Go Online** so Phone D
     advertises and is discoverable.

## Part B — The patient flow (Phone P)

1. On the Consult tab press **Go Online** (grant the Bluetooth/location permissions).
2. The patient phone **auto-connects to and verifies every device it discovers** in the
   background. Verified responders surface under **"Verified doctors"** — showing the real
   name, role, and specialty from the signed badge, with a green border and shield icon.
   Everything else lands in "Connected — unverified" / "Nearby — unverified".
3. Tap a **Verified doctor** → chat opens with the green banner
   *"Verified Doctor: Dr. Ahmed Hassan — end-to-end encrypted"* (verification already
   happened, so it's instant).
4. The keyboard-send arrow now sends **encrypted** messages; the heart-pulse button opens the
   **consult request sheet** — a consent preview of exactly what will be sent:
   symptom chips, free-text note, recent vitals (per-item toggles), optional location.
   Tap **Send consult request**.

## Part C — The responder flow (Phone D)

1. The consult request appears in the **responder strip** ("1 pending consult request(s)")
   and in **Open consult inbox** — with symptoms, note, vitals, and location.
2. **Accept** (optionally with a message) or **Decline**.
3. Phone P instantly shows *"✅ The responder accepted your consult request."* and any
   reply text as encrypted chat.

## Negative tests (the point of the whole feature)

| Test | Expected |
|---|---|
| Connect two non-responder phones | Orange banner stays "Unverified device — patient data sharing disabled"; heart button shows the lock icon and tapping it warns; plain chat still works (no patient data ever flows) |
| Badge file copied to a random phone, then imported | Import fails: `identity_key_mismatch` (fingerprint binding) |
| Badge edited (any byte of the body) and re-imported | `badge_signature_invalid` |
| Badge signed by a non-authority key | `badge_signature_invalid` (pinned key rejects it) |
| App "B" not in responder mode receives a HELLO | No reply at all — no session can form |
| Patient sends data frames before any handshake | Receiver drops them (`data from unverified peer` test) |
| Tamper with or replay a frame in flight | Session is torn down; nothing is accepted (`tampered`/`replayed` tests) |
| Patient taps help-request in AI chat with no verified responder | The AI is told `no_verified_responder_in_range` and falls back to first-aid guidance |

## Quick host-side verification (no phones)

```bash
flutter test packages/security_crypto
flutter test packages/bluetooth_mesh
flutter test apps/rescate_app
```

To re-run the issuance pipeline without phones, generate a synthetic request with a tiny
Dart script using `ResponderKeys.generate()` + `BadgeRequest(...).encode()` — exactly what
the responder screen writes to Downloads.

## Known v1 limitations (by design, per plan §7)

- Badges never expire; no blocklist (deferred to v2).
- Consult history is in-memory (per app run) — persistence is a follow-up.
- Responder and patient must be on the same local radio hop (multi-hop is issue #21).
- `keys/rma_key.json` on the PC is the single trust root — keep it offline.
