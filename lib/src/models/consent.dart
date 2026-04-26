/// User-facing consent flags for the SDK. Transport is blocked entirely
/// until at least one of [Consent.feedback] or [Consent.survey] is `true`.
class Consent {
  /// Creates a [Consent] value. Unset fields mean "unknown".
  const Consent({this.analytics, this.feedback, this.push, this.survey});

  /// Whether analytics events may be transmitted.
  final bool? analytics;

  /// Whether feedback prompts may be shown and responses transmitted.
  final bool? feedback;

  /// Whether the SDK may register a device token and accept pushes.
  final bool? push;

  /// Whether the SDK may deliver surveys and collect survey responses.
  final bool? survey;

  /// Convenience: returns a copy with updated fields.
  Consent copyWith({bool? analytics, bool? feedback, bool? push, bool? survey}) => Consent(
        analytics: analytics ?? this.analytics,
        feedback: feedback ?? this.feedback,
        push: push ?? this.push,
        survey: survey ?? this.survey,
      );

  /// JSON representation matching the control-plane contract.
  Map<String, Object?> toJson() => <String, Object?>{
        if (analytics != null) 'analytics': analytics,
        if (feedback != null) 'feedback': feedback,
        if (push != null) 'push': push,
        if (survey != null) 'survey': survey,
      };

  /// Parses a consent object from JSON. Missing keys become `null`.
  factory Consent.fromJson(Map<String, Object?> json) => Consent(
        analytics: json['analytics'] as bool?,
        feedback: json['feedback'] as bool?,
        push: json['push'] as bool?,
        survey: json['survey'] as bool?,
      );

  /// Whether the transport layer may ship data to the backend.
  bool get allowsTransport => feedback == true || survey == true;

  /// Whether the SDK may register a device token and accept pushes.
  bool get allowsPush => push == true;

  /// Whether the SDK may deliver surveys.
  bool get allowsSurvey => survey == true;
}
