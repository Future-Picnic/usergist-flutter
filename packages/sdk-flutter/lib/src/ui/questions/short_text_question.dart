import 'package:flutter/material.dart';

import '../../models/question.dart';
import '../surface_primitives.dart';
import '../theme_resolver.dart';

/// Widget rendering a [ShortTextQuestion].
class ShortTextQuestionView extends StatefulWidget {
  /// Creates the widget.
  const ShortTextQuestionView({
    required this.question,
    required this.theme,
    required this.onChanged,
    this.initialValue = '',
    this.minHeight = 96,
    super.key,
  });

  /// Question payload.
  final ShortTextQuestion question;

  /// Resolved theme.
  final ResolvedPromptTheme theme;

  /// Callback when the text changes.
  final ValueChanged<String> onChanged;

  /// Text restored when the question is shown again.
  final String initialValue;

  /// Minimum field height.
  final double minHeight;

  @override
  State<ShortTextQuestionView> createState() => _ShortTextQuestionViewState();
}

class _ShortTextQuestionViewState extends State<ShortTextQuestionView> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final question = widget.question;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        QuestionHeader(
          title: question.title,
          subtitle: question.subtitle,
          imageUrl: question.imageUrl,
          theme: widget.theme,
        ),
        SurfaceField(
          theme: widget.theme,
          controller: _ctrl,
          onChanged: widget.onChanged,
          hintText: question.placeholder,
          maxLength: question.maxLength,
          multiline: true,
          minHeight: widget.minHeight,
          semanticsLabel: 'Feedback text answer',
        ),
      ],
    );
  }
}
