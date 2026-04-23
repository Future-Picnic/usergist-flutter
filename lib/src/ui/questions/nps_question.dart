import 'package:flutter/material.dart';

import '../../models/question.dart';
import '../theme_resolver.dart';

/// Widget rendering an [NpsQuestion] (0..10 scale).
class NpsQuestionView extends StatefulWidget {
  /// Creates the widget.
  const NpsQuestionView({
    required this.question,
    required this.theme,
    required this.onChanged,
    this.initialValue,
    super.key,
  });

  /// Question payload.
  final NpsQuestion question;

  /// Resolved theme.
  final ResolvedPromptTheme theme;

  /// Callback when the value changes.
  final ValueChanged<int?> onChanged;

  /// Optional initial value.
  final int? initialValue;

  @override
  State<NpsQuestionView> createState() => _NpsQuestionViewState();
}

class _NpsQuestionViewState extends State<NpsQuestionView> {
  int? _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initialValue;
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: List<Widget>.generate(11, (i) {
            final selected = _value == i;
            return GestureDetector(
              onTap: () {
                setState(() => _value = i);
                widget.onChanged(i);
              },
              child: Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? theme.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: selected ? theme.primary : theme.border,
                  ),
                ),
                child: Text(
                  '$i',
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
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(
              'Not likely',
              style: TextStyle(
                color: theme.subtext,
                fontSize: 12,
                fontFamily: theme.fontFamily,
              ),
            ),
            Text(
              'Very likely',
              style: TextStyle(
                color: theme.subtext,
                fontSize: 12,
                fontFamily: theme.fontFamily,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Color _contrastOn(Color c) {
    return ThemeData.estimateBrightnessForColor(c) == Brightness.dark
        ? Colors.white
        : Colors.black;
  }
}
