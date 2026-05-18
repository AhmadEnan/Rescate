import 'tool_call.dart';
import 'tool_schema.dart';

/// Executes a parsed tool call. Returns a result map that gets rendered into
/// a `<|tool_response>...<tool_response|>` block and fed back to the model.
typedef ToolExecutor = Future<Map<String, Object?>> Function(ToolCall call);

/// Pairs the tools the model knows about (declarations) with the executor
/// that runs them. The app layer constructs one of these and attaches it to
/// [LlmService] at boot.
class ToolRegistry {
  const ToolRegistry({required this.schemas, required this.executor});

  final List<ToolSchema> schemas;
  final ToolExecutor executor;

  String renderDeclarations() => ToolSchema.renderAll(schemas);
}
