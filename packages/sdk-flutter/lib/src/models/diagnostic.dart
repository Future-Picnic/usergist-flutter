/// Bounded production-safe SDK diagnostic.
class SdkDiagnostic {
  const SdkDiagnostic({
    required this.code,
    required this.message,
    required this.occurredAt,
  });

  final String code;
  final String message;
  final DateTime occurredAt;
}
