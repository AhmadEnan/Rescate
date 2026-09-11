// Binary frame codec for the consult channel. Every application message on
// the Nearby BYTES transport is wrapped in this frame so the receiving side
// can route it before any JSON parsing. Control frames (hello/cert/accept)
// stay under 100 bytes; data frames may exceed that on the Nearby transport
// (the plugin fragments internally) — see the plan doc, §4.
import 'dart:convert';
import 'dart:typed_data';

class ConsultFrameException implements Exception {
  const ConsultFrameException(this.message);
  final String message;

  @override
  String toString() => 'ConsultFrameException: $message';
}

/// Frame types. 1-3 carry the handshake JSON, 4 carries a sealed session
/// payload, 5 politely ends the consult.
enum ConsultFrameType {
  hello(1),
  cert(2),
  accept(3),
  data(4),
  close(5);

  final int value;
  const ConsultFrameType(this.value);

  static ConsultFrameType fromValue(int v) => ConsultFrameType.values
      .firstWhere((t) => t.value == v, orElse: () => ConsultFrameType.close);
}

class ConsultFrame {
  ConsultFrame._(this.type, this.flags, this.payload);

  static const int magic0 = 0x52; // 'R'
  static const int magic1 = 0x53; // 'S'
  static const int version = 1;
  static const int headerLength = 8;

  final ConsultFrameType type;
  final int flags; // bit 0: fragmented (reserved for issue #21 BLE transport)
  final Uint8List payload;

  factory ConsultFrame(ConsultFrameType type, List<int> payload,
          {int flags = 0}) =>
      ConsultFrame._(type, flags, Uint8List.fromList(payload));

  bool get isFragmented => (flags & 0x1) != 0;

  Uint8List encode() {
    if (payload.length > 0xFFFF) {
      throw const ConsultFrameException('payload exceeds 65535 bytes');
    }
    final out = Uint8List(headerLength + payload.length);
    out[0] = magic0;
    out[1] = magic1;
    out[2] = version;
    out[3] = type.value;
    out[4] = flags;
    out[5] = 0; // reserved
    out[6] = payload.length & 0xFF;
    out[7] = (payload.length >> 8) & 0xFF;
    out.setAll(headerLength, payload);
    return out;
  }

  static ConsultFrame decode(Uint8List wire) {
    if (wire.length < headerLength) {
      throw const ConsultFrameException('frame shorter than header');
    }
    if (wire[0] != magic0 || wire[1] != magic1) {
      throw const ConsultFrameException('bad magic');
    }
    if (wire[2] != version) {
      throw ConsultFrameException('unsupported version ${wire[2]}');
    }
    final len = wire[6] | (wire[7] << 8);
    if (wire.length < headerLength + len) {
      throw const ConsultFrameException('truncated payload');
    }
    return ConsultFrame._(
      ConsultFrameType.fromValue(wire[3]),
      wire[4],
      Uint8List.sublistView(wire, headerLength, headerLength + len),
    );
  }

  /// Decodes the payload of handshake frames as UTF-8 JSON.
  Map<String, dynamic> decodeJsonPayload() =>
      jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
}
