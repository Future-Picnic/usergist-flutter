import 'package:flutter/material.dart';

import '../../models/question.dart';
import '../theme_resolver.dart';

/// Widget rendering a [ShortTextQuestion].
class ShortTextQuestionView extends StatefulWidget {
  /// Creates the widget.
  const ShortTextQuestionView({
    required this.question,
    required this.theme,
    required this.onChanged,
    super.key,
  });

  /// Question payload.
  final ShortTextQuestion question;

  /// Resolved theme.
  final ResolvedPromptTheme theme;

  /// Callback when the text changes.
  final ValueChanged<String> onChanged;

  @override
  State<ShortTextQuestionView> createState() => _ShortTextQuestionViewState();
}

class _ShortTextQuestionViewState extends State<ShortTextQuestionView> {
  final TextEditingController _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return TextField(
      controller: _ctrl,
      onChanged: widget.onChanged,
      maxLength: widget.question.maxLength,
      maxLines: 6,
      minLines: 4,
      style: TextStyle(
        color: theme.text,
        fontFamily: theme.fontFamily,
      ),
      decoration: InputDecoration(
        hintText: widget.question.placeholder,
        hintStyle: TextStyle(color: theme.subtext),
        counterText: '',
        contentPadding: const EdgeInsets.all(12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: theme.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: theme.primary),
        ),
      ),
    );
  }
}
