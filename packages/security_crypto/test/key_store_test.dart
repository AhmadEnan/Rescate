// Where the responder's private key material ends up (issue #17 review).
//
// The rule under test: Ed25519/X25519 seeds go to platform secure storage
// and never appear in any file the store writes. Everything here runs on the
// host against [InMemorySecretStore], the same seam ConsultTransport uses in
// bluetooth_mesh.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:security_crypto/security_crypto.dart';

/// Every byte of both seeds, base64 and hex, as they could plausibly be
/// serialized. Any of these appearing in a file is a leak.
List<String> seedNeedles(ResponderKeys keys) {
  final json = keys.toJson();
  final identity = json['identity_seed'] as String;
  final kx = json['kx_seed'] as String;
  return <String>[
    identity,
    kx,
    bytesToHex(base64Decode(identity)),
    bytesToHex(base64Decode(kx)),
  ];
}

Future<String> readAll(Directory dir) async {
  final buffer = StringBuffer();
  for (final entity in dir.listSync(recursive: true)) {
    if (entity is File) {
      buffer.writeln(entity.path);
      buffer.writeln(await entity.readAsString());
    }
  }
  return buffer.toString();
}

void main() {
  late Directory dir;
  late InMemorySecretStore secrets;
  late ConsultKeyStore store;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('rescate_keystore_test');
    secrets = InMemorySecretStore();
    store = ConsultKeyStore(dir.path, secrets: secrets);
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('saved seeds are absent from every file on disk', () async {
    final keys = await ResponderKeys.generate();
    await store.saveResponderKeys(keys);

    final onDisk = await readAll(dir);
    expect(onDisk, isNotEmpty, reason: 'the metadata file should exist');
    for (final needle in seedNeedles(keys)) {
      expect(onDisk.contains(needle), isFalse,
          reason: 'private seed material must never be written to a file');
    }
    // And the metadata file must not even hint at a seed field.
    expect(onDisk, isNot(contains('identity_seed')));
    expect(onDisk, isNot(contains('kx_seed')));
  });

  test('seeds round-trip through the secret store', () async {
    final keys = await ResponderKeys.generate();
    await store.saveResponderKeys(keys);

    expect(secrets.values.keys, contains(ConsultKeyStore.secretsKey));

    final loaded = await store.loadResponderKeys();
    expect(loaded, isNotNull);
    expect(loaded!.sameKeys(keys), isTrue);
  });

  test('a legacy plaintext key file is migrated and then wiped', () async {
    // v1 on-disk format: base64 seeds straight in the JSON.
    final keys = await ResponderKeys.generate();
    final legacy = File('${dir.path}${Platform.pathSeparator}'
        'rescate_responder_keys.json');
    await legacy.writeAsString(jsonEncode(keys.toJson()));

    final loaded = await store.loadResponderKeys();

    expect(loaded, isNotNull, reason: 'the responder must not lose their id');
    expect(loaded!.sameKeys(keys), isTrue);
    expect(secrets.values[ConsultKeyStore.secretsKey], isNotNull);
    for (final needle in seedNeedles(keys)) {
      expect((await readAll(dir)).contains(needle), isFalse,
          reason: 'migration must remove the plaintext copy');
    }
  });

  test('an unavailable secret store yields no keys and writes no plaintext',
      () async {
    final failing = ConsultKeyStore(dir.path, secrets: _BrokenSecretStore());
    final keys = await ResponderKeys.generate();

    await expectLater(
      failing.saveResponderKeys(keys),
      throwsA(isA<SecretStoreUnavailable>()),
    );
    expect(await failing.loadResponderKeys(), isNull);
    for (final needle in seedNeedles(keys)) {
      expect((await readAll(dir)).contains(needle), isFalse);
    }
  });

  test('a legacy file survives a failed migration rather than being lost',
      () async {
    final keys = await ResponderKeys.generate();
    final legacy = File('${dir.path}${Platform.pathSeparator}'
        'rescate_responder_keys.json');
    await legacy.writeAsString(jsonEncode(keys.toJson()));

    final failing = ConsultKeyStore(dir.path, secrets: _BrokenSecretStore());
    final loaded = await failing.loadResponderKeys();

    // Secure storage is broken, so the seeds cannot move — but destroying
    // the only copy would permanently orphan the responder's badge.
    expect(loaded!.sameKeys(keys), isTrue);
    expect(legacy.existsSync(), isTrue);
  });

  test('clearResponder removes both the secret and the files', () async {
    final keys = await ResponderKeys.generate();
    await store.saveResponderKeys(keys);
    await store.clearResponder();

    expect(secrets.values, isEmpty);
    expect(await store.loadResponderKeys(), isNull);
    expect(dir.listSync(), isEmpty);
  });
}

/// Stands in for a device where the Keystore/Keychain is unusable.
class _BrokenSecretStore implements SecretStore {
  @override
  Future<String?> read(String key) async =>
      throw const SecretStoreUnavailable('keystore unavailable');

  @override
  Future<void> write(String key, String value) async =>
      throw const SecretStoreUnavailable('keystore unavailable');

  @override
  Future<void> delete(String key) async {}
}
