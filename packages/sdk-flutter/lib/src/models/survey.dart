import 'theme.dart';
import 'segment.dart';

/// Frequency rules attached to a locally-evaluable survey campaign.
class SurveyFrequencyCap {
  const SurveyFrequencyCap({
    this.perCampaignDays,
    this.perPillarDays,
    this.perGlobalDays,
    this.maxPerUser,
  });

  final int? perCampaignDays;
  final int? perPillarDays;
  final int? perGlobalDays;
  final int? maxPerUser;

  factory SurveyFrequencyCap.fromJson(Map<String, Object?> json) =>
      SurveyFrequencyCap(
        perCampaignDays: (json['perCampaignDays'] as num?)?.toInt(),
        perPillarDays: (json['perPillarDays'] as num?)?.toInt(),
        perGlobalDays: (json['perGlobalDays'] as num?)?.toInt(),
        maxPerUser: (json['maxPerUser'] as num?)?.toInt(),
      );
}

/// Full survey payload cached for synchronous client-side event matching.
class ArmedSurvey {
  const ArmedSurvey({
    required this.campaignId,
    required this.eventName,
    required this.frequencyCap,
    required this.survey,
    this.segmentRules,
    this.clientSideEligible,
    this.cooldownSeconds,
  });

  final String campaignId;
  final String eventName;
  final SerializedSegmentRules? segmentRules;
  final bool? clientSideEligible;
  final int? cooldownSeconds;
  final SurveyFrequencyCap frequencyCap;
  final SurveyCampaignWithFlow survey;

  factory ArmedSurvey.fromJson(Map<String, Object?> json) {
    final segment = json['segmentRules'];
    final frequency = json['frequencyCap'];
    final campaign = json['survey'];
    if (campaign is! Map<String, Object?>) {
      throw const FormatException('armed survey payload is missing');
    }
    return ArmedSurvey(
      campaignId: json['campaignId'] as String? ?? '',
      eventName: json['eventName'] as String? ?? '',
      segmentRules: segment is Map<String, Object?>
          ? SerializedSegmentRules.fromJson(segment)
          : null,
      clientSideEligible: json['clientSideEligible'] as bool?,
      cooldownSeconds: (json['cooldownSeconds'] as num?)?.toInt(),
      frequencyCap: frequency is Map<String, Object?>
          ? SurveyFrequencyCap.fromJson(frequency)
          : const SurveyFrequencyCap(),
      survey: SurveyCampaignWithFlow.fromJson(campaign),
    );
  }
}

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

/// A selectable option used by choice and ranking questions.
class SurveyChoice {
  const SurveyChoice({required this.id, required this.label});

  final String id;
  final String label;

  factory SurveyChoice.fromJson(Map<String, Object?> json) => SurveyChoice(
        id: json['id'] as String? ?? '',
        label: json['label'] as String? ?? '',
      );
}

/// One question in the server-authored survey graph.
class SurveyQuestion {
  const SurveyQuestion({
    required this.id,
    required this.type,
    required this.title,
    required this.required,
    required this.options,
    required this.items,
    this.subtitle,
    this.imageUrl,
    this.allowOther = false,
    this.minSelections,
    this.maxSelections,
    this.scale,
    this.style,
    this.lowLabel,
    this.highLabel,
    this.labels = const <String>[],
    this.placeholder,
    this.maxLength,
    this.minDate,
    this.maxDate,
    this.body,
  });

  final String id;
  final String type;
  final String title;
  final String? subtitle;
  final bool required;
  final String? imageUrl;
  final List<SurveyChoice> options;
  final List<SurveyChoice> items;
  final bool allowOther;
  final int? minSelections;
  final int? maxSelections;
  final int? scale;
  final String? style;
  final String? lowLabel;
  final String? highLabel;
  final List<String> labels;
  final String? placeholder;
  final int? maxLength;
  final String? minDate;
  final String? maxDate;
  final String? body;

  factory SurveyQuestion.fromJson(Map<String, Object?> json) => SurveyQuestion(
        id: json['id'] as String? ?? '',
        type: json['type'] as String? ?? 'info_screen',
        title: json['title'] as String? ?? '',
        subtitle: json['subtitle'] as String?,
        required: json['required'] as bool? ?? false,
        imageUrl: json['imageUrl'] as String?,
        options: _choiceList(json['options']),
        items: _choiceList(json['items']),
        allowOther: json['allowOther'] as bool? ?? false,
        minSelections: (json['minSelections'] as num?)?.toInt(),
        maxSelections: (json['maxSelections'] as num?)?.toInt(),
        scale: (json['scale'] as num?)?.toInt(),
        style: json['style'] as String?,
        lowLabel: json['lowLabel'] as String?,
        highLabel: json['highLabel'] as String?,
        labels: _stringList(json['labels']),
        placeholder: json['placeholder'] as String?,
        maxLength: (json['maxLength'] as num?)?.toInt(),
        minDate: json['minDate'] as String?,
        maxDate: json['maxDate'] as String?,
        body: json['body'] as String?,
      );
}

class SurveyBranchCondition {
  const SurveyBranchCondition({required this.op, this.value});

  final String op;
  final Object? value;

  factory SurveyBranchCondition.fromJson(Map<String, Object?> json) =>
      SurveyBranchCondition(
        op: json['op'] as String? ?? 'eq',
        value: json['value'],
      );
}

class SurveyBranch {
  const SurveyBranch({
    required this.fromQuestionId,
    required this.condition,
    required this.toQuestionId,
  });

  final String fromQuestionId;
  final SurveyBranchCondition condition;
  final String toQuestionId;

  factory SurveyBranch.fromJson(Map<String, Object?> json) => SurveyBranch(
        fromQuestionId: json['fromQuestionId'] as String? ?? '',
        condition: SurveyBranchCondition.fromJson(
          json['condition'] as Map<String, Object?>? ??
              const <String, Object?>{},
        ),
        toQuestionId: json['toQuestionId'] as String? ?? '__end__',
      );
}

class SurveyEndCta {
  const SurveyEndCta({required this.kind, required this.label, this.target});

  final String kind;
  final String label;
  final String? target;

  factory SurveyEndCta.fromJson(Map<String, Object?> json) => SurveyEndCta(
        kind: json['kind'] as String? ?? 'close',
        label: json['label'] as String? ?? 'Close',
        target: json['target'] as String?,
      );
}

class SurveyEndScreen {
  const SurveyEndScreen({required this.headline, this.body, this.cta});

  final String headline;
  final String? body;
  final SurveyEndCta? cta;

  factory SurveyEndScreen.fromJson(Map<String, Object?> json) {
    final cta = json['cta'];
    return SurveyEndScreen(
      headline: json['headline'] as String? ?? 'Thanks for your feedback',
      body: json['body'] as String?,
      cta: cta is Map<String, Object?> ? SurveyEndCta.fromJson(cta) : null,
    );
  }
}

/// Branching survey flow delivered by `/v1/sdk/surveys/:id`.
class SurveyFlow {
  const SurveyFlow({
    required this.startQuestionId,
    required this.questions,
    required this.branches,
    required this.progressStyle,
    required this.backNavigation,
    this.endScreen,
  });

  final String startQuestionId;
  final List<SurveyQuestion> questions;
  final List<SurveyBranch> branches;
  final String progressStyle;
  final bool backNavigation;
  final SurveyEndScreen? endScreen;

  factory SurveyFlow.fromJson(Map<String, Object?> json) {
    final questions = json['questions'];
    final branches = json['branches'];
    final endScreen = json['endScreen'];
    return SurveyFlow(
      startQuestionId: json['startQuestionId'] as String? ?? '',
      questions: questions is List<Object?>
          ? questions
              .whereType<Map<String, Object?>>()
              .map(SurveyQuestion.fromJson)
              .toList(growable: false)
          : const <SurveyQuestion>[],
      branches: branches is List<Object?>
          ? branches
              .whereType<Map<String, Object?>>()
              .map(SurveyBranch.fromJson)
              .toList(growable: false)
          : const <SurveyBranch>[],
      progressStyle: json['progressStyle'] as String? ?? 'bar',
      backNavigation: json['backNavigation'] as bool? ?? true,
      endScreen: endScreen is Map<String, Object?>
          ? SurveyEndScreen.fromJson(endScreen)
          : null,
    );
  }

  String? nextQuestionId(String currentId, Map<String, Object?> answers) {
    final answer = answers[currentId];
    for (final branch in branches.where(
      (branch) => branch.fromQuestionId == currentId,
    )) {
      if (_matches(branch.condition, answer)) {
        return branch.toQuestionId == '__end__' ? null : branch.toQuestionId;
      }
    }
    final index = questions.indexWhere((question) => question.id == currentId);
    if (index < 0 || index >= questions.length - 1) return null;
    return questions[index + 1].id;
  }

  bool _matches(SurveyBranchCondition condition, Object? answer) {
    final expected = condition.value;
    return switch (condition.op) {
      'eq' => answer == expected,
      'neq' => answer != expected,
      'lt' => _number(answer) < _number(expected),
      'lte' => _number(answer) <= _number(expected),
      'gt' => _number(answer) > _number(expected),
      'gte' => _number(answer) >= _number(expected),
      'includes' => answer is List<Object?> && answer.contains(expected),
      'not_includes' => answer is! List<Object?> || !answer.contains(expected),
      'answered' => _isAnswered(answer),
      'unanswered' => !_isAnswered(answer),
      _ => false,
    };
  }

  double _number(Object? value) => value is num ? value.toDouble() : double.nan;
}

/// Campaign data and flow required by the native survey renderer.
class SurveyCampaignWithFlow {
  const SurveyCampaignWithFlow({
    required this.id,
    required this.name,
    required this.flow,
    this.theme,
    this.endScreen,
  });

  final String id;
  final String name;
  final SurveyFlow flow;
  final PromptTheme? theme;
  final SurveyEndScreen? endScreen;

  factory SurveyCampaignWithFlow.fromJson(Map<String, Object?> json) {
    final flow = json['flow'];
    final endScreen = json['endScreen'];
    if (flow is! Map<String, Object?>) {
      throw const FormatException('survey flow is missing');
    }
    return SurveyCampaignWithFlow(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      flow: SurveyFlow.fromJson(flow),
      theme: json['theme'] is Map<String, Object?>
          ? PromptTheme.fromJson(json['theme']! as Map<String, Object?>)
          : null,
      endScreen: endScreen is Map<String, Object?>
          ? SurveyEndScreen.fromJson(endScreen)
          : null,
    );
  }
}

/// Create/resume response returned before a survey can be presented.
class SurveyAttemptSession {
  const SurveyAttemptSession({
    required this.attemptId,
    required this.startQuestionId,
    required this.progressSnapshot,
    required this.currentQuestionId,
    required this.resumed,
  });

  final String attemptId;
  final String startQuestionId;
  final Map<String, Object?> progressSnapshot;
  final String? currentQuestionId;
  final bool resumed;

  factory SurveyAttemptSession.fromJson(Map<String, Object?> json) =>
      SurveyAttemptSession(
        attemptId: json['attemptId'] as String? ?? '',
        startQuestionId: json['startQuestionId'] as String? ?? '',
        progressSnapshot: json['progressSnapshot'] is Map<String, Object?>
            ? Map<String, Object?>.from(
                json['progressSnapshot']! as Map<String, Object?>,
              )
            : <String, Object?>{},
        currentQuestionId: json['currentQuestionId'] as String?,
        resumed: json['resumed'] as bool? ?? false,
      );
}

/// Lifecycle callbacks for the native survey surface.
class SurveyHandlers {
  const SurveyHandlers({
    this.onInvite,
    this.onShow,
    this.onComplete,
    this.onAbandon,
  });

  final void Function(SurveySummary summary)? onInvite;
  final void Function(String surveyId)? onShow;
  final void Function(String surveyId, String attemptId)? onComplete;
  final void Function(String surveyId, String attemptId)? onAbandon;
}

List<SurveyChoice> _choiceList(Object? value) => value is List<Object?>
    ? value
        .whereType<Map<String, Object?>>()
        .map(SurveyChoice.fromJson)
        .toList(growable: false)
    : const <SurveyChoice>[];

List<String> _stringList(Object? value) => value is List<Object?>
    ? value.whereType<String>().toList(growable: false)
    : const <String>[];

bool _isAnswered(Object? value) {
  if (value == null) return false;
  if (value is String) return value.isNotEmpty;
  if (value is Iterable<Object?>) return value.isNotEmpty;
  return true;
}
