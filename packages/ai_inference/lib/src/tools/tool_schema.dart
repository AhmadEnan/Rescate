// Gemma 4 tool-declaration rendering.
//
// Emits the exact wire format documented at
// https://ai.google.dev/gemma/docs/capabilities/text/function-calling-gemma4
//
//   <|tool>declaration:NAME{description:<|"|>...<|"|>,
//     parameters:{type:<|"|>OBJECT<|"|>,
//       properties:{ARG:{type:<|"|>STRING<|"|>,description:<|"|>...<|"|>}},
//       required:[<|"|>ARG<|"|>]}}<tool|>

enum ToolArgType { string, number, boolean }

extension ToolArgTypeWire on ToolArgType {
  String get wire {
    switch (this) {
      case ToolArgType.string:
        return 'STRING';
      case ToolArgType.number:
        return 'NUMBER';
      case ToolArgType.boolean:
        return 'BOOLEAN';
    }
  }
}

class ToolArg {
  const ToolArg({
    required this.name,
    required this.type,
    required this.description,
    this.required = true,
    this.enumValues,
  });

  final String name;
  final ToolArgType type;
  final String description;
  final bool required;
  final List<String>? enumValues;

  String _renderedDescription() {
    final values = enumValues;
    if (values == null || values.isEmpty) return description;
    return '$description (one of: ${values.join('|')})';
  }

  String renderProperty() {
    final desc = _renderedDescription();
    return '$name:{type:<|"|>${type.wire}<|"|>,description:<|"|>$desc<|"|>}';
  }
}

class ToolSchema {
  const ToolSchema({
    required this.name,
    required this.description,
    required this.args,
  });

  final String name;
  final String description;
  final List<ToolArg> args;

  String renderGemma4Declaration() {
    final buf = StringBuffer();
    buf.write('<|tool>declaration:$name{');
    buf.write('description:<|"|>$description<|"|>,');
    buf.write('parameters:{type:<|"|>OBJECT<|"|>');
    if (args.isNotEmpty) {
      buf.write(',properties:{');
      buf.write(args.map((a) => a.renderProperty()).join(','));
      buf.write('}');
      final req = args.where((a) => a.required).map((a) => a.name).toList();
      if (req.isNotEmpty) {
        buf.write(',required:[');
        buf.write(req.map((n) => '<|"|>$n<|"|>').join(','));
        buf.write(']');
      }
    }
    buf.write('}}<tool|>');
    return buf.toString();
  }

  static String renderAll(List<ToolSchema> tools) {
    return tools.map((t) => t.renderGemma4Declaration()).join('\n');
  }
}
