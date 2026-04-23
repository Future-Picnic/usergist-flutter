import 'question.dart';
import 'segment.dart';
import 'theme.dart';

/// Frequency caps for a prompt. Times are days.
class FrequencyCaps {
  /// Creates frequency caps.
  const FrequencyCaps({this.perPromptDays, this.perUserDays});

  /// Minimum days between shows of the same prompt to the same user.
  final int? perPromptDays;

  /// Minimum days between _any_ prompt shown to the same user.
  final int? perUserDays;

  /// Parses from JSON.
  factory FrequencyCaps.fromJson(Map<String, Object?> json) => FrequencyCaps(
        perPromptDays: (json['perPromptDays'] as num?)?.toInt(),
        perUserDays: (json['perUserDays'] as num?)?.toInt(),
      );
}

/// The subset of a prompt that ships with an armed trigger for rendering.
class ClientPrompt {
  /// Creates a [ClientPrompt].
  const ClientPrompt({
    required this.id,
    required this.questions,
    this.theme,
  });

  /// Stable id of the underlying prompt.
  final String id;

  /// The questions to render, in order.
  final List<Question> questions;

  /// Optional theme override shipped by the dashboard.
  final PromptTheme? theme;

  /// Parses from JSON.
  factory ClientPrompt.fromJson(Map<String, Object?> json) {
    final rawQs = json['questions'];
    final qs = <Question>[];
    if (rawQs is List<Object?>) {
      for (final q in rawQs) {
        if (q is Map<String, Object?>) {
          qs.add(Question.fromJson(q));
        }
      }
    }
    final rawTheme = json['theme'];
    return ClientPrompt(
      id: json['id']! as String,
      questions: List<Question>.unmodifiable(qs),
      theme: rawTheme is Map<String, Object?>
          ? PromptTheme.fromJson(rawTheme)
          : null,
    );
  }
}

/// An "armed" trigger: a prompt that will fire when its [eventName]
/// is tracked and the segment rules evaluate true.
class ArmedTrigger {
  /// Creates an armed trigger.
  const ArmedTrigger({
    required this.promptId,
    required this.eventName,
    required this.frequency,
    required this.prompt,
    this.segmentRules,
  });

  /// The prompt id.
  final String promptId;

  /// The name of the event that fires this trigger.
  final String eventName;

  /// Optional segment predicates — `null` means "no segment constraints".
  final SerializedSegmentRules? segmentRules;

  /// Frequency caps applied to this prompt.
  final FrequencyCaps frequency;

  /// The prompt content to render.
  final ClientPrompt prompt;

  /// Parses from JSON.
  factory ArmedTrigger.fromJson(Map<String, Object?> json) {
    final rawSeg = json['segmentRules'];
    return ArmedTrigger(
      promptId: json['promptId']! as String,
      eventName: json['eventName']! as String,
      segmentRules: rawSeg is Map<String, Object?>
          ? SerializedSegmentRules.fromJson(rawSeg)
          : null,
      frequency: FrequencyCaps.fromJson(
        (json['frequency'] as Map<String, Object?>?) ??
            const <String, Object?>{},
      ),
      prompt: ClientPrompt.fromJson(json['prompt']! as Map<String, Object?>),
    );
  }
}
