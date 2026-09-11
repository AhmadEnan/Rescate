// Where responder private key material lives (issue #17).
//
// Private seeds must never sit in a plaintext file, so [ConsultKeyStore]
// keeps them behind this abstraction instead of writing them to JSON. The
// device implementation is [SecureStorageSecretStore] (Android Keystore /
// iOS Keychain); tests use [InMemorySecretStore] so the whole key-store
// layer stays testable on the host without platform channels. Same seam as
// ConsultTransport in bluetooth_mesh.
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A small key→string secret store backed by platform key material.
abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Thrown when the platform secure store is unavailable. Callers must treat
/// this as "no responder identity" rather than falling back to plaintext —
/// silently degrading is exactly what issue #17's review rejected.
class SecretStoreUnavailable implements Exception {
  const SecretStoreUnavailable(this.cause);
  final Object cause;

  @override
  String toString() => 'SecretStoreUnavailable($cause)';
}

/// Android Keystore / iOS Keychain-backed store used on device.
class SecureStorageSecretStore implements SecretStore {
  SecureStorageSecretStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              // encryptedSharedPreferences routes Android through
              // EncryptedSharedPreferences (AES via the Keystore) instead of
              // the legacy plaintext-capable path.
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (e) {
      throw SecretStoreUnavailable(e);
    }
  }

  @override
  Future<void> write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (e) {
      throw SecretStoreUnavailable(e);
    }
  }

  @override
  Future<void> delete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (e) {
      // Deleting is best-effort — a missing entry is already the goal.
      debugPrint('SecretStore delete failed for $key: $e');
    }
  }
}

/// Host-test implementation. Never used on device.
@visibleForTesting
class InMemorySecretStore implements SecretStore {
  final Map<String, String> _values = <String, String>{};

  /// Exposed so tests can assert exactly what was persisted.
  Map<String, String> get values => Map.unmodifiable(_values);

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);
}
