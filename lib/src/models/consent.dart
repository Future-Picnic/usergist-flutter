/// User-facing consent flags for the SDK. Transport is blocked entirely
/// until [Consent.feedback] is explicitly `true`.
class Consent {
  /// Creates a [Consent] value. Unset fields mean "unknown".
  const Consent({this.analytics, this.feedback});

  /// Whether analytics events may be transmitted.
  final bool? analytics;

  /// Whether feedback prompts may be shown and responses transmitted.
  final bool? feedback;

  /// Convenience: returns a copy with updated fields.
  Consent copyWith({bool? analytics, bool? feedback}) => Consent(
        analytics: analytics ?? this.analytics,
        feedback: feedback ?? this.feedback,
      );

  /// JSON representation matching the control-plane contract.
  Map<String, Object?> toJson() => <String, Object?>{
        if (analytics != null) 'analytics': analytics,
        if (feedback != null) 'feedback': feedback,
      };

  /// Parses a consent object from JSON. Missing keys become `null`.
  factory Consent.fromJson(Map<String, Object?> json) => Consent(
        analytics: json['analytics'] as bool?,
        feedback: json['feedback'] as bool?,
      );
}
