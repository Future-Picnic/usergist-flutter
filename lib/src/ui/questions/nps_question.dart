import 'package:flutter/material.dart';

import '../../models/question.dart';
import '../theme_resolver.dart';

/// Widget rendering an [NpsQuestion] (0..10 scale).
class NpsQuestionView extends StatefulWidget {
  /// Creates the widget.
  const NpsQuestionView({
    required this.question,
    required this.theme,
    required this.onScore,
    required this.onFollowUp,
    required this.score,
    required this.followUp,
    super.key,
  });

  /// Question payload.
  final NpsQuestion question;

  /// Resolved theme.
  final ResolvedPromptTheme theme;

  /// Callback when the score changes.
  final ValueChanged<int> onScore;

  /// Callback when the optional follow-up text changes.
  final ValueChanged<String> onFollowUp;

  /// Current score.
  final int? score;

  /// Current follow-up answer.
  final String followUp;

  @override
  State<NpsQuestionView> createState() => _NpsQuestionViewState();
}

class _NpsQuestionViewState extends State<NpsQuestionView> {
  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (var value = 10; value >= 0; value--)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _scoreRow(value, theme),
          ),
        if (widget.score != null &&
            widget.question.followUp?.isNotEmpty == true) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            widget.question.followUp!,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: theme.text,
              fontSize: 14,
              fontFamily: theme.fontFamily,
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            initialValue: widget.followUp,
            onChanged: widget.onFollowUp,
            minLines: 3,
            maxLines: 5,
            decoration: _inputDecoration(theme),
            style: TextStyle(color: theme.text, fontFamily: theme.fontFamily),
          ),
        ],
      ],
    );
  }

  Widget _scoreRow(int value, ResolvedPromptTheme theme) {
    final selected = widget.score == value;
    final endpointLabel = value == 10
        ? widget.question.highLabel ?? 'Extremely likely'
        : value == 0
            ? widget.question.lowLabel ?? 'Not at all likely'
            : null;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Score $value',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onScore(value),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? theme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? theme.primary : theme.border,
            ),
          ),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 24,
                child: Text(
                  '$value',
                  style: TextStyle(
                    color: selected ? theme.background : theme.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    fontFamily: theme.fontFamily,
                  ),
                ),
              ),
              if (endpointLabel != null) ...<Widget>[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    endpointLabel,
                    style: TextStyle(
                      color: selected ? theme.background : theme.subtext,
                      fontSize: 13,
                      fontFamily: theme.fontFamily,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(ResolvedPromptTheme theme) {
    return InputDecoration(
      hintText: 'Tell us more...',
      hintStyle: TextStyle(color: theme.subtext),
      contentPadding: const EdgeInsets.all(12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: theme.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: theme.primary),
      ),
    );
  }
}
