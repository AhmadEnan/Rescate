enum DiagnosticSeverity { info, warning, error }

class DiagnosticEvent {
  const DiagnosticEvent({
    required this.stage,
    required this.message,
    this.level = DiagnosticSeverity.info,
  });

  final String stage;
  final String message;
  final DiagnosticSeverity level;
}
