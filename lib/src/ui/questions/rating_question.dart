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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: List<Widget>.generate(widget.question.scale, (i) {
            final v = i + 1;
            final selected = _value == v;
            return GestureDetector(
              onTap: () {
                setState(() => _value = v);
                widget.onChanged(v);
              },
              child: Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? theme.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: selected ? theme.primary : theme.border,
                  ),
                ),
                child: Text(
                  '$v',
                  style: TextStyle(
                    color: selected
                        ? _contrastOn(theme.primary)
                        : theme.text,
                    fontWeight: FontWeight.w600,
                    fontFamily: theme.fontFamily,
                  ),
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

  Color _contrastOn(Color c) {
    return ThemeData.estimateBrightnessForColor(c) == Brightness.dark
        ? Colors.white
        : Colors.black;
  }
}
