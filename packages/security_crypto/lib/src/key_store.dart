// Persistence for responder keys and badge.
//
// Split by sensitivity (issue #17 review):
//   * private Ed25519/X25519 seeds  → [SecretStore] (platform secure storage)
//   * badge + non-secret metadata   → JSON files in the app-private directory
//
// The badge holds only public material, so a file is fine for it; the seeds
// are the responder's whole identity and never touch the filesystem. Devices
// provisioned before this split are migrated on first load — see
// [_migrateLegacyPlaintextKeys]. Rotation and recovery behaviour is
// documented in packages/security_crypto/README.md.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'credential.dart';
import 'identity.dart';
import 'secret_store.dart';

class ConsultKeyStore {
  ConsultKeyStore(String baseDir, {SecretStore? secrets})
      : _baseDir = Directory(baseDir),
        _secrets = secrets ?? SecureStorageSecretStore();

  final Directory _baseDir;
  final SecretStore _secrets;

  /// The directory this store persists into (for sibling files).
  String get basePath => _baseDir.path;

  /// Secure-store key holding the JSON seed pair. Not a file path.
  static const String secretsKey = 'rescate.responder.keys.v1';

  static const String _keysFileName = 'rescate_responder_keys.json';
  static const String _credentialFileName = 'rescate_badge.json';

  File _file(String name) {
    if (!_baseDir.existsSync()) {
      _baseDir.createSync(recursive: true);
    }
    return File('${_baseDir.path}${Platform.pathSeparator}$name');
  }

  // ── Responder keys ─────────────────────────────────────────

  /// Reads the seeds from secure storage, migrating a legacy plaintext file
  /// if one is still present. Returns null when this device has no responder
  /// identity.
  ///
  /// Nothing here ever *writes* plaintext. If the platform store is down, a
  /// pre-existing v1 file is still honoured for this session and migration
  /// is retried on the next load — refusing would lock a responder out of
  /// their badge over a transient Keystore failure, while protecting nothing
  /// (anyone who can read that file already has it).
  Future<ResponderKeys?> loadResponderKeys() async {
    try {
      final raw = await _secrets.read(secretsKey);
      if (raw != null) {
        try {
          return ResponderKeys.fromJson(
            jsonDecode(raw) as Map<String, dynamic>,
          );
        } catch (_) {
          return null;
        }
      }
    } on SecretStoreUnavailable catch (e) {
      debugPrint('ConsultKeyStore: secure storage unavailable ($e)');
    }
    return _migrateLegacyPlaintextKeys();
  }

  /// Writes the seeds to secure storage and leaves only non-secret metadata
  /// on disk. Throws [SecretStoreUnavailable] if the platform store cannot
  /// hold the seeds — callers must surface that rather than continue, since
  /// a responder without retrievable keys cannot complete a handshake.
  Future<void> saveResponderKeys(ResponderKeys keys) async {
    await _secrets.write(secretsKey, jsonEncode(keys.toJson()));
    await _file(_keysFileName).writeAsString(jsonEncode(<String, dynamic>{
      'version': 2,
      'type': 'rescate_responder_keys',
      // Deliberately no key material: the seeds live in platform secure
      // storage under ConsultKeyStore.secretsKey.
      'storage': 'secure_store',
      'saved_at': DateTime.now().toUtc().toIso8601String(),
    }));
  }

  /// v1 wrote base64 seeds straight into the JSON file. Move them into
  /// secure storage, then overwrite the file with metadata only so the
  /// plaintext copy stops existing.
  Future<ResponderKeys?> _migrateLegacyPlaintextKeys() async {
    final f = _file(_keysFileName);
    if (!f.existsSync()) return null;
    final ResponderKeys keys;
    try {
      final json = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      if (json['identity_seed'] is! String || json['kx_seed'] is! String) {
        return null; // already migrated (metadata-only) or unreadable
      }
      keys = ResponderKeys.fromJson(json);
    } catch (_) {
      return null;
    }
    try {
      await saveResponderKeys(keys);
      debugPrint('ConsultKeyStore: migrated legacy plaintext seeds to '
          'secure storage');
    } on SecretStoreUnavailable catch (e) {
      // Leave the legacy file intact rather than destroying the only copy
      // of the responder's identity.
      debugPrint('ConsultKeyStore: legacy seed migration deferred ($e)');
    }
    return keys;
  }

  // ── Badge ──────────────────────────────────────────────────

  Future<ResponderCredential?> loadCredential() async {
    final f = _file(_credentialFileName);
    if (!f.existsSync()) return null;
    try {
      return ResponderCredential.decode(await f.readAsString());
    } catch (_) {
      return null;
    }
  }

  Future<void> saveCredential(ResponderCredential credential) async {
    await _file(_credentialFileName).writeAsString(credential.encode());
  }

  /// Drops the badge only. Used when new keys are generated and the stored
  /// badge no longer matches them (it was issued against the old keys).
  Future<void> clearCredential() async {
    final f = _file(_credentialFileName);
    if (f.existsSync()) await f.delete();
  }

  Future<void> clearResponder() async {
    await _secrets.delete(secretsKey);
    for (final name in [_keysFileName, _credentialFileName]) {
      final f = _file(name);
      if (f.existsSync()) await f.delete();
    }
  }
}
