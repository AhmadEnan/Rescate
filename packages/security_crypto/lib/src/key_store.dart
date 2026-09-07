// File-backed persistence for responder keys and badge. The app supplies a
// directory (app-support dir on device, temp dir in tests).
import 'dart:convert';
import 'dart:io';

import 'credential.dart';
import 'identity.dart';

class ConsultKeyStore {
  ConsultKeyStore(String baseDir) : _baseDir = Directory(baseDir);

  final Directory _baseDir;

  /// The directory this store persists into (for sibling files).
  String get basePath => _baseDir.path;

  static const String _keysFileName = 'rescate_responder_keys.json';
  static const String _credentialFileName = 'rescate_badge.json';

  File _file(String name) {
    if (!_baseDir.existsSync()) {
      _baseDir.createSync(recursive: true);
    }
    return File('${_baseDir.path}${Platform.pathSeparator}$name');
  }

  Future<ResponderKeys?> loadResponderKeys() async {
    final f = _file(_keysFileName);
    if (!f.existsSync()) return null;
    try {
      return ResponderKeys.fromJson(
        jsonDecode(await f.readAsString()) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> saveResponderKeys(ResponderKeys keys) async {
    await _file(_keysFileName).writeAsString(jsonEncode(keys.toJson()));
  }

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

  Future<void> clearResponder() async {
    for (final name in [_keysFileName, _credentialFileName]) {
      final f = _file(name);
      if (f.existsSync()) await f.delete();
    }
  }
}
