import 'package:flutter/material.dart';

import '../../models/question.dart';
import '../theme_resolver.dart';

/// Widget rendering a [RatingQuestion].
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

  int? _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initialValue;
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final labels = <String?>[
      widget.question.lowLabel,
      widget.question.highLabel,
    ];
    final display = widget.question.display == RatingDisplayMode.emoji &&
            widget.question.scale != 5
        ? RatingDisplayMode.stars
        : widget.question.display;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: List<Widget>.generate(widget.question.scale, (i) {
            final v = i + 1;
            final selected = _value == v;
            return Semantics(
              button: true,
              selected: selected,
              label: 'Rate $v',
              child: GestureDetector(
                onTap: () {
                  setState(() => _value = v);
                  widget.onChanged(v);
                },
                child: _ratingItem(
                  value: v,
                  selected: selected,
                  display: display,
                  theme: theme,
                ),
              ),
            );
          }),
        ),
        if (labels[0] != null || labels[1] != null) ...<Widget>[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                labels[0] ?? '',
                style: TextStyle(
                  color: theme.subtext,
                  fontSize: 12,
                  fontFamily: theme.fontFamily,
                ),
              ),
              Text(
                labels[1] ?? '',
                style: TextStyle(
                  color: theme.subtext,
                  fontSize: 12,
                  fontFamily: theme.fontFamily,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _ratingItem({
    required int value,
    required bool selected,
    required RatingDisplayMode display,
    required ResolvedPromptTheme theme,
  }) {
    switch (display) {
      case RatingDisplayMode.stars:
        final filled = _value != null && value <= _value!;
        return SizedBox(
          width: 36,
          height: 36,
          child: Center(
            child: Text(
              '★',
              style: TextStyle(
                color: filled ? theme.primary : theme.border,
                fontSize: 28,
                height: 1,
              ),
            ),
          ),
        );
      case RatingDisplayMode.emoji:
        return Opacity(
          opacity: _value == null || selected ? 1 : 0.35,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: Text(
                _emoji[value - 1],
                style: const TextStyle(fontSize: 30, height: 1.2),
              ),
            ),
          ),
        );
      case RatingDisplayMode.numeric:
        return Container(
          constraints: const BoxConstraints(minWidth: 40),
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? theme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: theme.border,
            ),
          ),
          child: Text(
            '$value',
            style: TextStyle(
              color: selected ? theme.background : theme.text,
              fontWeight: FontWeight.w600,
              fontFamily: theme.fontFamily,
            ),
          ),
        );
    }
  }
}
