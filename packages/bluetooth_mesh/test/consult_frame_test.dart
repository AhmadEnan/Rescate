import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:bluetooth_mesh/bluetooth_mesh.dart';

void main() {
  test('frame encode/decode round-trip', () {
    final payload = Uint8List.fromList(List.generate(200, (i) => i % 256));
    final frame = ConsultFrame(ConsultFrameType.data, payload, flags: 0);
    final decoded = ConsultFrame.decode(frame.encode());

    expect(decoded.type, ConsultFrameType.data);
    expect(decoded.flags, 0);
    expect(decoded.payload, payload);
  });

  test('hello handshake frame stays under 100 bytes', () {
    // The hello payload is 32 hex chars + 24 base64 chars + JSON overhead —
    // the CONTRIBUTING <100-byte contract must hold for control frames.
    final payload = Uint8List.fromList(
        List.generate(90, (i) => 0x61 + (i % 26))); // 90 bytes of JSON-ish
    final wire = ConsultFrame(ConsultFrameType.hello, payload).encode();
    expect(wire.length, lessThanOrEqualTo(100));
  });

  test('bad magic is rejected', () {
    final wire = Uint8List.fromList([0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
    expect(() => ConsultFrame.decode(wire),
        throwsA(isA<ConsultFrameException>()));
  });

  test('truncated payload is rejected', () {
    final frame = ConsultFrame(
        ConsultFrameType.data, Uint8List.fromList(List.filled(32, 1)));
    final wire = frame.encode().sublist(0, 12); // cut payload short
    expect(() => ConsultFrame.decode(wire),
        throwsA(isA<ConsultFrameException>()));
  });
}
