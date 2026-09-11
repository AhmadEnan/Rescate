// Rescate Medical Authority (RMA) provisioning tool.
//
// Pure Dart CLI — runs on the coordinator's machine, never on phones.
// The RMA private key file this tool creates must be kept safe; whoever
// holds it can mint responder badges.
//
// Usage:
//   dart run packages/security_crypto/tool/credential_provisioner.dart \
//       create-authority --out keys/rma_key.json
//   dart run packages/security_crypto/tool/credential_provisioner.dart \
//       show-authority --authority-key keys/rma_key.json
//   dart run packages/security_crypto/tool/credential_provisioner.dart \
//       issue --request rescate_request.json --authority-key keys/rma_key.json \
//             --name "Dr. Ahmed Hassan" --role doctor --specialty "ER" \
//             --license "SY-ER-1234" [--expires-days 30] --out badge.json
//   dart run packages/security_crypto/tool/credential_provisioner.dart \
//       verify --badge badge.json
//   dart run packages/security_crypto/tool/credential_provisioner.dart \
//       show --badge badge.json
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart' show SimpleKeyPair;
import 'package:security_crypto/security_crypto.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    _usage();
    exitCode = 2;
    return;
  }
  try {
    switch (args[0]) {
      case 'create-authority':
        await _createAuthority(_opts(args));
      case 'show-authority':
        await _showAuthority(_opts(args));
      case 'issue':
        await _issue(_opts(args));
      case 'verify':
        await _verify(_opts(args));
      case 'show':
        _show(_opts(args));
      case _:
        _usage();
        exitCode = 2;
    }
  } on FormatException catch (e) {
    stderr.writeln('Error: ${e.message}');
    exitCode = 1;
  } catch (e) {
    stderr.writeln('Error: $e');
    exitCode = 1;
  }
}

Map<String, String> _opts(List<String> args) {
  final out = <String, String>{};
  for (var i = 1; i < args.length - 1; i += 2) {
    if (!args[i].startsWith('--')) {
      throw FormatException('unexpected argument: ${args[i]}');
    }
    out[args[i].substring(2)] = args[i + 1];
  }
  return out;
}

String _require(Map<String, String> opts, String key) {
  final v = opts[key];
  if (v == null || v.isEmpty) {
    throw FormatException('missing required option --$key');
  }
  return v;
}

Future<SimpleKeyPair> _loadAuthorityKey(String path) async {
  final f = File(path);
  if (!f.existsSync()) {
    throw FormatException('authority key file not found: $path');
  }
  final json = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
  return ConsultAuthority.authorityKeyPairFromSeed(
    base64Decode(json['seed'] as String),
  );
}

Future<void> _createAuthority(Map<String, String> opts) async {
  final outPath = _require(opts, 'out');
  final keyPair = await ConsultAuthority.newAuthorityKeyPair();
  final seed = await keyPair.extractPrivateKeyBytes();
  final pub = (await keyPair.extractPublicKey()).bytes;
  final file = File(outPath);
  await file.parent.create(recursive: true);
  await file.writeAsString(jsonEncode(<String, dynamic>{
    'version': 1,
    'type': 'rescate_authority_key',
    'seed': base64Encode(seed),
    'public_key_hex': bytesToHex(pub),
  }));
  stdout.writeln('Authority key created: $outPath');
  stdout.writeln();
  stdout.writeln('Public key (pin this in the app, packages/security_crypto:');
  stdout.writeln('  lib/src/identity.dart -> ConsultAuthority.defaultPublicKeyHex):');
  stdout.writeln(bytesToHex(pub));
  stdout.writeln();
  stdout.writeln('Keep this file safe and offline — it can mint badges.');
}

Future<void> _showAuthority(Map<String, String> opts) async {
  final keyPair = await _loadAuthorityKey(_require(opts, 'authority-key'));
  final pub = (await keyPair.extractPublicKey()).bytes;
  stdout.writeln('Authority public key: ${bytesToHex(pub)}');
}

Future<void> _issue(Map<String, String> opts) async {
  final requestPath = _require(opts, 'request');
  final authorityPath = _require(opts, 'authority-key');
  final outPath = _require(opts, 'out');

  final request = BadgeRequest.decode(File(requestPath).readAsStringSync());
  final authorityKeyPair = await _loadAuthorityKey(authorityPath);

  final name = opts['name'] ?? request.displayName;
  if (name.isEmpty) {
    throw FormatException('no name: pass --name or set display_name in the request');
  }
  final role = ResponderRole.fromName(opts['role']);
  final expiresDays = int.tryParse(opts['expires-days'] ?? '');

  final credential = await ResponderCredential.issue(
    identityPublicKey: request.identityPublicKey,
    keyExchangePublicKey: request.keyExchangePublicKey,
    authorityKeyPair: authorityKeyPair,
    name: name,
    role: role,
    specialty: opts['specialty'] ?? '',
    licenseRef: opts['license'] ?? '',
    expiresAt: expiresDays == null
        ? null
        : DateTime.now().toUtc().add(Duration(days: expiresDays)),
  );

  final file = File(outPath);
  await file.parent.create(recursive: true);
  await file.writeAsString(credential.encode());
  stdout.writeln('Badge issued: $outPath');
  stdout.writeln('  name: ${credential.name}');
  stdout.writeln('  role: ${credential.role.title}');
  stdout.writeln('  specialty: ${credential.specialty}');
  stdout.writeln(
      '  expires: ${credential.expiresAt?.toIso8601String() ?? 'never'}');
  stdout.writeln('Transfer this file to the responder phone and import it.');
}

Future<void> _verify(Map<String, String> opts) async {
  final badgePath = _require(opts, 'badge');
  final credential = ResponderCredential.decode(
    File(badgePath).readAsStringSync(),
  );
  // Signature-only check (no presented keys — those are verified during the
  // handshake). Uses the pinned default authority key.
  final bodyValid = await ConsultAuthority.verifyAuthoritySignature(
    utf8.encode(credential.canonicalBodyJson()),
    base64Decode(credential.signature),
  );
  stdout.writeln(bodyValid
      ? 'VALID: badge signed by the pinned Rescate authority.'
      : 'INVALID: signature does not match the pinned authority key.');
  if (!bodyValid) exitCode = 1;
}

void _show(Map<String, String> opts) {
  final credential = ResponderCredential.decode(
    File(_require(opts, 'badge')).readAsStringSync(),
  );
  final body = credential.toEnvelopeJson();
  body.forEach((k, v) => stdout.writeln('$k: $v'));
}

void _usage() {
  stdout.writeln('''
Rescate Medical Authority provisioning tool.

Commands:
  create-authority --out keys/rma_key.json
      Generate the authority signing key (once). Prints the public key to
      pin in the app.
  show-authority --authority-key keys/rma_key.json
      Print the authority public key.
  issue --request <request.json> --authority-key keys/rma_key.json
        --name "Dr. Ahmed Hassan" [--role doctor|nurse|emt]
        [--specialty ER] [--license SY-ER-1234] [--expires-days N]
        --out badge.json
      Sign a responder badge request. --expires-days omitted = never.
  verify --badge badge.json
      Check a badge against the pinned authority key.
  show --badge badge.json
      Print badge fields.''');
}
