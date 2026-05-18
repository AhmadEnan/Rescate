// Parses Gemma 4 tool-call emissions and renders tool-responses.
//
// Wire forms:
//   model emits:  <|tool_call>call:NAME{arg1:<|"|>str<|"|>,arg2:42}<tool_call|>
//   we feed back: <|tool_response>response:NAME{key:<|"|>str<|"|>,n:42}<tool_response|>

class ToolCall {
  const ToolCall({
    required this.name,
    required this.args,
    required this.startOffset,
    required this.endOffset,
  });

  final String name;
  final Map<String, Object?> args;

  /// Byte offsets of the full `<|tool_call>...<tool_call|>` substring inside
  /// the source text. Use these to strip the markup from a visible bubble.
  final int startOffset;
  final int endOffset;
}

class ToolCallParser {
  static final RegExp _callRe =
      RegExp(r'<\|tool_call>call:(\w+)\{(.*?)\}<tool_call\|>', dotAll: true);

  static final RegExp _argRe =
      RegExp(r'(\w+):(?:<\|"\|>(.*?)<\|"\|>|([^,}]*))');

  static List<ToolCall> parse(String text) {
    final results = <ToolCall>[];
    for (final m in _callRe.allMatches(text)) {
      final name = m.group(1)!;
      final argsBlob = m.group(2) ?? '';
      final args = <String, Object?>{};
      for (final am in _argRe.allMatches(argsBlob)) {
        final key = am.group(1)!;
        final stringVal = am.group(2);
        final bareVal = am.group(3);
        if (stringVal != null) {
          args[key] = stringVal;
        } else if (bareVal != null) {
          args[key] = _coerce(bareVal.trim());
        }
      }
      results.add(ToolCall(
        name: name,
        args: args,
        startOffset: m.start,
        endOffset: m.end,
      ));
    }
    return results;
  }

  static Object? _coerce(String raw) {
    if (raw.isEmpty) return null;
    final lower = raw.toLowerCase();
    if (lower == 'true') return true;
    if (lower == 'false') return false;
    if (lower == 'null') return null;
    final asInt = int.tryParse(raw);
    if (asInt != null) return asInt;
    final asDouble = double.tryParse(raw);
    if (asDouble != null) return asDouble;
    return raw;
  }

  /// Renders a `<|tool_response>response:NAME{...}<tool_response|>` block.
  /// Strings are wrapped in `<|"|>...<|"|>`; numbers, bools, null bare.
  /// Nested maps/lists are JSON-flattened and treated as strings.
  static String renderResponse(String name, Map<String, Object?> result) {
    final buf = StringBuffer();
    buf.write('<|tool_response>response:$name{');
    final entries = result.entries.toList();
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      buf.write(e.key);
      buf.write(':');
      buf.write(_renderValue(e.value));
      if (i < entries.length - 1) buf.write(',');
    }
    buf.write('}<tool_response|>');
    return buf.toString();
  }

  static String _renderValue(Object? v) {
    if (v == null) return 'null';
    if (v is bool || v is num) return v.toString();
    final s = v.toString().replaceAll('<|"|>', '');
    return '<|"|>$s<|"|>';
  }

  /// Removes every `<|tool_call>...<tool_call|>` (matched or orphan) and any
  /// stray `<|tool_response>...<tool_response|>` from [text] so the user sees
  /// clean prose.
  static String stripMarkup(String text) {
    return text
        .replaceAll(_callRe, '')
        .replaceAll(
          RegExp(r'<\|tool_response>.*?<tool_response\|>', dotAll: true),
          '',
        )
        .replaceAll(RegExp(r'<\|tool_call>.*'), '')
        .replaceAll(RegExp(r'.*?<tool_call\|>'), '');
  }
}
