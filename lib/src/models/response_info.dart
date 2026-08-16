/// A single answered question inside a prompt response.
class ResponseAnswer {
  /// Creates an answer.
  const ResponseAnswer({required this.questionId, required this.value});

  /// The question id this answer refers to.
  final String questionId;

  /// The answer value. See [AnswerValue] for the valid shapes.
  final Object? value;

  /// JSON representation.
  Map<String, Object?> toJson() => <String, Object?>{
        'questionId': questionId,
        'value': value,
      };
}

/// Public stream event emitted when the user responds (or dismisses)
/// a prompt. See [UserGist.onResponse].
class PromptResponseInfo {
  /// Creates a response-info record.
  const PromptResponseInfo({
    required this.promptId,
    required this.dismissed,
    required this.answers,
    required this.latencyMs,
  });

  /// Prompt that was responded to.
  final String promptId;

  /// `true` if the user dismissed the prompt without answering.
  final bool dismissed;

  /// The answers provided (may be empty when dismissed).
  final List<ResponseAnswer> answers;

  /// Elapsed milliseconds between show and response submission.
  final int latencyMs;
}

/// Sentinel helper around the allowed answer value types.
abstract class AnswerValue {
  AnswerValue._();

  /// Validates that [value] is one of the supported wire types:
  /// number, string, list-of-strings, or null.
  static bool isValid(Object? value) {
    if (value == null) return true;
    if (value is num || value is String) return true;
    if (value is List<String>) return true;
    return false;
  }
}
