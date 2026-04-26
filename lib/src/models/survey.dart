/// Summary of a survey currently available to the user.
class SurveySummary {
  const SurveySummary({
    required this.id,
    required this.name,
    required this.mode,
    required this.source,
    this.resumableAttemptId,
  });

  final String id;
  final String name;
  final String mode;
  final String source;
  final String? resumableAttemptId;

  factory SurveySummary.fromJson(Map<String, Object?> json) => SurveySummary(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        mode: json['mode'] as String? ?? 'on_demand',
        source: json['source'] as String? ?? 'on_demand',
        resumableAttemptId: json['resumableAttemptId'] as String?,
      );
}

/// Lifecycle callbacks for the survey surface (host-app rendered in v1).
class SurveyHandlers {
  const SurveyHandlers({
    this.onShow,
    this.onComplete,
    this.onAbandon,
  });

  final void Function(String surveyId)? onShow;
  final void Function(String surveyId, String attemptId)? onComplete;
  final void Function(String surveyId, String attemptId)? onAbandon;
}
