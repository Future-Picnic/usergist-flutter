/// Supported question types for feedback prompts in v1.
enum QuestionType {
  /// 1..5 or 1..10 rating scale.
  rating,

  /// Net Promoter Score: 0..10 with an optional follow-up.
  nps,

  /// Single- or multi-select choice from a list of options.
  multipleChoice,

  /// Free-form short text input.
  shortText;

  /// Wire value used on the API.
  String get wire => switch (this) {
        QuestionType.rating => 'rating',
        QuestionType.nps => 'nps',
        QuestionType.multipleChoice => 'multiple_choice',
        QuestionType.shortText => 'short_text',
      };

  /// Reverse lookup. Unknown values throw [FormatException].
  static QuestionType fromWire(String value) {
    switch (value) {
      case 'rating':
        return QuestionType.rating;
      case 'nps':
        return QuestionType.nps;
      case 'multiple_choice':
        return QuestionType.multipleChoice;
      case 'short_text':
        return QuestionType.shortText;
    }
    throw FormatException('Unknown question type: $value');
  }
}

/// Base interface for all question variants.
sealed class Question {
  /// Creates a base [Question]. Concrete variants extend this class.
  const Question({
    required this.id,
    required this.title,
    this.subtitle,
  });

  /// Stable id assigned by the server.
  final String id;

  /// Primary question text shown to the user.
  final String title;

  /// Optional secondary / subtitle text.
  final String? subtitle;

  /// Concrete type discriminator.
  QuestionType get type;

  /// Parses a question polymorphically by its `type` field.
  factory Question.fromJson(Map<String, Object?> json) {
    final type = QuestionType.fromWire(json['type']! as String);
    return switch (type) {
      QuestionType.rating => RatingQuestion._fromJson(json),
      QuestionType.nps => NpsQuestion._fromJson(json),
      QuestionType.multipleChoice => MultipleChoiceQuestion._fromJson(json),
      QuestionType.shortText => ShortTextQuestion._fromJson(json),
    };
  }
}

/// A rating-scale question (1..5 or 1..10).
class RatingQuestion extends Question {
  /// Creates a [RatingQuestion].
  const RatingQuestion({
    required super.id,
    required super.title,
    required this.scale,
    super.subtitle,
    this.lowLabel,
    this.highLabel,
  });

  /// The scale — either 5 or 10.
  final int scale;

  /// Optional anchor label for the low end.
  final String? lowLabel;

  /// Optional anchor label for the high end.
  final String? highLabel;

  @override
  QuestionType get type => QuestionType.rating;

  factory RatingQuestion._fromJson(Map<String, Object?> json) {
    final scale = (json['scale'] as num?)?.toInt() ?? 5;
    return RatingQuestion(
      id: json['id']! as String,
      title: json['title']! as String,
      subtitle: json['subtitle'] as String?,
      scale: scale == 10 ? 10 : 5,
      lowLabel: json['lowLabel'] as String?,
      highLabel: json['highLabel'] as String?,
    );
  }
}

/// An NPS question (0..10 with an optional follow-up prompt).
class NpsQuestion extends Question {
  /// Creates an [NpsQuestion].
  const NpsQuestion({
    required super.id,
    required super.title,
    super.subtitle,
    this.followUp,
  });

  /// Optional free-text follow-up prompt.
  final String? followUp;

  @override
  QuestionType get type => QuestionType.nps;

  factory NpsQuestion._fromJson(Map<String, Object?> json) {
    return NpsQuestion(
      id: json['id']! as String,
      title: json['title']! as String,
      subtitle: json['subtitle'] as String?,
      followUp: json['followUp'] as String?,
    );
  }
}

/// A single option in a [MultipleChoiceQuestion].
class MultipleChoiceOption {
  /// Creates an option.
  const MultipleChoiceOption({required this.id, required this.label});

  /// Stable id of the option.
  final String id;

  /// Label shown to the user.
  final String label;

  /// Parses an option from JSON.
  factory MultipleChoiceOption.fromJson(Map<String, Object?> json) =>
      MultipleChoiceOption(
        id: json['id']! as String,
        label: json['label']! as String,
      );
}

/// A multiple-choice question (single- or multi-select).
class MultipleChoiceQuestion extends Question {
  /// Creates a [MultipleChoiceQuestion].
  const MultipleChoiceQuestion({
    required super.id,
    required super.title,
    required this.options,
    super.subtitle,
    this.multiSelect = false,
  });

  /// The list of options. Must be non-empty.
  final List<MultipleChoiceOption> options;

  /// If `true`, the UI allows multi-selection.
  final bool multiSelect;

  @override
  QuestionType get type => QuestionType.multipleChoice;

  factory MultipleChoiceQuestion._fromJson(Map<String, Object?> json) {
    final rawOpts = json['options'];
    final opts = <MultipleChoiceOption>[];
    if (rawOpts is List<Object?>) {
      for (final r in rawOpts) {
        if (r is Map<String, Object?>) {
          opts.add(MultipleChoiceOption.fromJson(r));
        }
      }
    }
    return MultipleChoiceQuestion(
      id: json['id']! as String,
      title: json['title']! as String,
      subtitle: json['subtitle'] as String?,
      options: List<MultipleChoiceOption>.unmodifiable(opts),
      multiSelect: json['multiSelect'] as bool? ?? false,
    );
  }
}

/// A short-free-text question.
class ShortTextQuestion extends Question {
  /// Creates a [ShortTextQuestion].
  const ShortTextQuestion({
    required super.id,
    required super.title,
    super.subtitle,
    this.placeholder,
    this.maxLength,
  });

  /// Placeholder text inside the input.
  final String? placeholder;

  /// Hard cap on the number of characters accepted.
  final int? maxLength;

  @override
  QuestionType get type => QuestionType.shortText;

  factory ShortTextQuestion._fromJson(Map<String, Object?> json) {
    return ShortTextQuestion(
      id: json['id']! as String,
      title: json['title']! as String,
      subtitle: json['subtitle'] as String?,
      placeholder: json['placeholder'] as String?,
      maxLength: (json['maxLength'] as num?)?.toInt(),
    );
  }
}
