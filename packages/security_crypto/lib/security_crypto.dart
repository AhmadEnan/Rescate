/// Rescate security & cryptography — authenticated responder consultations.
///
/// Trust model: the Rescate Medical Authority (RMA) signs responder badges
/// ([ResponderCredential]); the badge's public key is pinned in
/// [ConsultAuthority.defaultPublicKeyHex]. Patients verify badges and talk to
/// responders only through [ConsultSession] — authenticated,
/// replay-protected ChaCha20-Poly1305 frames derived from an ephemeral
/// X25519 handshake bound to the certified identity (issue #17).
///
/// Layers:
///  - [ResponderKeys]: per-device Ed25519 identity + X25519 key-exchange keys.
///  - [BadgeRequest] / [ResponderCredential]: the ID badge and its issuance.
///  - [PatientHandshake] / [ResponderHandshake]: transcript-bound handshake.
///  - [ConsultSession]: sealed frames with replay protection.
///  - [ConsultKeyStore]: badge persistence; private seeds go to a
///    [SecretStore] (platform secure storage), never to a file.
library security_crypto;

export 'src/credential.dart';
export 'src/identity.dart';
export 'src/key_store.dart';
export 'src/secret_store.dart';
export 'src/session.dart';
