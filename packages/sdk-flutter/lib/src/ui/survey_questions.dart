// Survey question bodies, built on the shared surface primitives so surveys
// and feedback share one visual language. Each body renders its own title
// block; the survey screen owns navigation, saving and completion.
import 'package:flutter/material.dart';

import '../models/question.dart';
import '../models/survey.dart';
import 'questions/nps_question.dart';
import 'surface_controls.dart';
import 'surface_primitives.dart';
import 'surface_tokens.dart';
import 'survey_rating_input.dart';
import 'theme_resolver.dart';

const List<String> _defaultLikert = <String>[
  'Strongly disagree',
  'Disagree',
  'Neutral',
  'Agree',
  'Strongly agree',
];

/// Renders the body for one survey question.
class SurveyQuestionBody extends StatelessWidget {
  /// Creates the body.
  const SurveyQuestionBody({
    required this.question,
    required this.answer,
    required this.theme,
    required this.onAnswer,
    required this.onAnswerAndAdvance,
    required this.onRating,
    required this.onPickDate,
    this.textController,
    this.ranking,
    this.onRankingChanged,
    super.key,
  });

  /// Question payload.
  final SurveyQuestion question;

  /// Current answer.
  final Object? answer;

  /// Resolved theme.
  final ResolvedPromptTheme theme;

  /// Stores an answer.
  final ValueChanged<Object?> onAnswer;

  /// Stores an answer and moves on (tap-to-select types).
  final ValueChanged<Object> onAnswerAndAdvance;

  /// Stores a rating and moves on after a short delay.
  final ValueChanged<int> onRating;

  /// Opens the platform date picker.
  final VoidCallback onPickDate;

  /// Controller for text questions.
  final TextEditingController? textController;

  /// Current ranking order.
  final List<SurveyChoice>? ranking;

  /// Called with the new ranking order.
  final ValueChanged<List<SurveyChoice>>? onRankingChanged;

  QuestionHeader _header({String? subtitle}) => QuestionHeader(
        title: question.title,
        subtitle: subtitle ?? question.subtitle,
        imageUrl: question.imageUrl,
        theme: theme,
      );

  Widget _list(List<Widget> rows) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final (i, row) in rows.indexed) ...<Widget>[
            if (i > 0) const SizedBox(height: 8),
            row,
          ],
        ],
      );

  @override
  Widget build(BuildContext context) {
    switch (question.type) {
      case 'single_choice':
        return _column(<Widget>[
          _header(),
          _list(<Widget>[
            for (final option in question.options)
              ChoiceRow(
                label: option.label,
                selected: answer == option.id,
                kind: ChoiceKind.radio,
                onTap: () => onAnswerAndAdvance(option.id),
                theme: theme,
              ),
          ]),
        ]);
      case 'multi_choice':
        return _multiChoice();
      case 'rating':
        return SurveyRatingInput(
          key: ValueKey<String>('survey-rating-${question.id}'),
          question: question,
          theme: theme,
          initialValue: answer as int?,
          onChanged: (value) {
            if (value != null) onRating(value);
          },
        );
      case 'nps':
        return NpsQuestionView(
          key: ValueKey<String>('survey-nps-${question.id}'),
          question: NpsQuestion(
            id: question.id,
            title: question.title,
            subtitle: question.subtitle,
            imageUrl: question.imageUrl,
            lowLabel: question.lowLabel,
            highLabel: question.highLabel,
          ),
          theme: theme,
          score: answer as int?,
          followUp: '',
          onScore: onAnswerAndAdvance,
          // Survey follow-ups are their own questions (via branching).
          onFollowUp: (_) {},
        );
      case 'likert':
        final labels =
            question.labels.isEmpty ? _defaultLikert : question.labels;
        return _column(<Widget>[
          _header(),
          // Vertical: five long labels never fit a phone row.
          _list(<Widget>[
            for (final (i, label) in labels.indexed)
              ChoiceRow(
                label: label,
                selected: answer == i + 1,
                kind: ChoiceKind.radio,
                onTap: () => onAnswerAndAdvance(i + 1),
                theme: theme,
              ),
          ]),
        ]);
      case 'short_text':
      case 'long_text':
        final controller = textController;
        return _column(<Widget>[
          _header(),
          if (controller != null)
            SurfaceField(
              key: ValueKey<String>('survey-text-${question.id}'),
              theme: theme,
              controller: controller,
              onChanged: onAnswer,
              hintText: question.placeholder,
              maxLength: question.maxLength,
              multiline: true,
              minHeight: question.type == 'long_text' ? 132 : 96,
              semanticsLabel: question.title,
            ),
        ]);
      case 'ranking':
        return _ranking();
      case 'single_date':
        return _column(<Widget>[_header(), _dateField()]);
      case 'info_screen':
        return _column(<Widget>[
          QuestionHeader(
            title: question.title,
            imageUrl: question.imageUrl,
            theme: theme,
          ),
          if (question.body case final body? when body.isNotEmpty)
            Text(
              body,
              style: theme.textStyle(color: theme.subtext, lineHeight: 24),
            ),
        ]);
      default:
        return _column(<Widget>[
          _header(),
          Text(
            'This question needs a newer version of the app. '
            'Continue to skip it.',
            style: theme.textStyle(color: theme.subtext, lineHeight: 24),
          ),
        ]);
    }
  }

  Widget _column(List<Widget> children) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      );

  Widget _multiChoice() {
    final selected =
        (answer as List<Object?>?)?.whereType<String>().toList() ??
            const <String>[];
    final max = question.maxSelections;
    final hint = question.subtitle ??
        (max != null ? 'Choose up to $max' : 'Choose all that apply');
    return _column(<Widget>[
      _header(subtitle: hint),
      _list(<Widget>[
        for (final option in question.options)
          ChoiceRow(
            label: option.label,
            selected: selected.contains(option.id),
            kind: ChoiceKind.checkbox,
            onTap: () {
              final checked = selected.contains(option.id);
              if (!checked && max != null && selected.length >= max) return;
              onAnswer(
                checked
                    ? selected.where((id) => id != option.id).toList()
                    : <String>[...selected, option.id],
              );
            },
            theme: theme,
          ),
      ]),
    ]);
  }

  Widget _ranking() {
    final order = ranking ?? question.items;
    void move(int index, int delta) {
      final target = index + delta;
      if (target < 0 || target >= order.length) return;
      final next = <SurveyChoice>[...order];
      final item = next.removeAt(index);
      next.insert(target, item);
      onRankingChanged?.call(next);
    }

    return _column(<Widget>[
      _header(subtitle: question.subtitle ?? 'Most important first'),
      _list(<Widget>[
        for (final (i, item) in order.indexed)
          _RankRow(
            key: ValueKey<String>(item.id),
            position: i + 1,
            label: item.label,
            canMoveUp: i > 0,
            canMoveDown: i < order.length - 1,
            onUp: () => move(i, -1),
            onDown: () => move(i, 1),
            theme: theme,
          ),
      ]),
    ]);
  }

  Widget _dateField() {
    final value = answer as String?;
    final radius = BorderRadius.circular(theme.fieldRadius);
    return Semantics(
      button: true,
      label: value == null ? 'Choose a date' : 'Date, $value. Change',
      container: true,
      excludeSemantics: true,
      onTap: onPickDate,
      child: Material(
        color: theme.fill,
        borderRadius: radius,
        child: InkWell(
          onTap: onPickDate,
          borderRadius: radius,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 50),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      value ?? 'Choose a date',
                      style: theme.textStyle(
                        color: value == null
                            ? surfaceWithOpacity(theme.subtext, 0.8)
                            : theme.text,
                        lineHeight: 22,
                        tabular: value != null,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CustomPaint(
                      painter: SurfaceGlyphPainter(
                        SurfaceGlyph.down,
                        theme.subtext,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Ranking row with move buttons — accessible without drag gestures.
class _RankRow extends StatelessWidget {
  const _RankRow({
    required this.position,
    required this.label,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onUp,
    required this.onDown,
    required this.theme,
    super.key,
  });

  final int position;
  final String label;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final ResolvedPromptTheme theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.only(left: 12, right: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(theme.choiceRadius),
        border: Border.all(color: theme.border, width: 1.5),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(color: theme.tint, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text(
              '$position',
              style: theme.textStyle(
                color: theme.primary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                tabular: true,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                label,
                style: theme.textStyle(
                  color: theme.text,
                  lineHeight: 21,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          _move(SurfaceGlyph.up, canMoveUp, onUp, 'Move $label up'),
          _move(SurfaceGlyph.down, canMoveDown, onDown, 'Move $label down'),
        ],
      ),
    );
  }

  Widget _move(
    SurfaceGlyph glyph,
    bool enabled,
    VoidCallback onTap,
    String label,
  ) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      container: true,
      excludeSemantics: true,
      onTap: enabled ? onTap : null,
      child: InkResponse(
        onTap: enabled ? onTap : null,
        radius: 22,
        child: SizedBox(
          width: 44,
          height: 48,
          child: CustomPaint(
            painter: SurfaceGlyphPainter(
              glyph,
              enabled ? theme.text : surfaceWithOpacity(theme.text, 0.2),
            ),
          ),
        ),
      ),
    );
  }
}
