import 'package:flutter/material.dart';

import '../../models/question.dart';
import '../surface_primitives.dart';
import '../surface_tokens.dart';
import '../theme_resolver.dart';

/// Widget rendering a [RatingQuestion]. Honours `question.display`:
///   - stars   → row of star glyphs (default)
///   - numeric → row of score chips
///   - emoji   → 5 faces (only valid when scale = 5; falls back to stars)
///
/// The row is centred so the dashboard preview and the device match.
class RatingQuestionView extends StatefulWidget {
  /// Creates the widget.
  const RatingQuestionView({
    required this.question,
    required this.theme,
    required this.onChanged,
    this.initialValue,
    super.key,
  });

  /// The question to render.
  final RatingQuestion question;

  /// Resolved theme.
  final ResolvedPromptTheme theme;

  /// Called whenever the selected value changes.
  final ValueChanged<int?> onChanged;

  /// Optional initial value.
  final int? initialValue;

  @override
  State<RatingQuestionView> createState() => _RatingQuestionViewState();
}

class _RatingQuestionViewState extends State<RatingQuestionView> {
  static const _emoji = <String>['😡', '😕', '😐', '🙂', '😍'];

  late int? _value = widget.initialValue;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final question = widget.question;
    final display =
        question.display == RatingDisplayMode.emoji && question.scale != 5
            ? RatingDisplayMode.stars
            : question.display;
    final low = question.lowLabel;
    final high = question.highLabel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        QuestionHeader(
          title: question.title,
          subtitle: question.subtitle,
          imageUrl: question.imageUrl,
          theme: theme,
          center: true,
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: List<Widget>.generate(question.scale, (i) {
            final v = i + 1;
            final selected = _value == v;
            void pick() {
              setState(() => _value = v);
              widget.onChanged(v);
            }

            return Semantics(
              button: true,
              inMutuallyExclusiveGroup: true,
              selected: selected,
              label: 'Rate $v',
              container: true,
              excludeSemantics: true,
              onTap: pick,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: pick,
                child: _ratingItem(v, selected, display, theme),
              ),
            );
          }),
        ),
        if (low != null || high != null) ...<Widget>[
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(child: _endLabel(low ?? '', TextAlign.start)),
              const SizedBox(width: 16),
              Expanded(child: _endLabel(high ?? '', TextAlign.end)),
            ],
          ),
        ],
      ],
    );
  }

  Widget _endLabel(String text, TextAlign align) => Text(
        text,
        textAlign: align,
        style: widget.theme.textStyle(
          color: widget.theme.subtext,
          fontSize: 13,
        ),
      );

  Widget _ratingItem(
    int value,
    bool selected,
    RatingDisplayMode display,
    ResolvedPromptTheme theme,
  ) {
    switch (display) {
      case RatingDisplayMode.stars:
        final filled = _value != null && value <= _value!;
        return SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: Text(
              '★',
              style: TextStyle(
                color: filled ? theme.primary : theme.quietOutline,
                // Flutter's star glyph renders smaller than iOS at the same
                // nominal size; 36 matches the RN 34pt reference optically.
                fontSize: 36,
                height: 1,
              ),
            ),
          ),
        );
      case RatingDisplayMode.emoji:
        return AnimatedOpacity(
          duration: const Duration(milliseconds: 120),
          opacity: _value == null || selected ? 1 : 0.4,
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: selected ? theme.tint : Colors.transparent,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              _emoji[value - 1],
              style: const TextStyle(fontSize: 30, height: 1.2),
            ),
          ),
        );
      case RatingDisplayMode.numeric:
        return Container(
          constraints: const BoxConstraints(minWidth: 48),
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? theme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(theme.cellRadius),
            border: Border.all(
              color: selected ? theme.primary : theme.border,
              width: 1.5,
            ),
          ),
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: theme.textStyle(
              color: selected ? theme.onPrimary : theme.text,
              fontWeight: FontWeight.w700,
              tabular: true,
            ),
          ),
        );
    }
  }
}
