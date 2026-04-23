import 'package:flutter/material.dart';

import '../models/prompt.dart';
import '../models/question.dart';
import '../models/response_info.dart';
import '../models/theme.dart';
import 'questions/multiple_choice_question.dart';
import 'questions/nps_question.dart';
import 'questions/rating_question.dart';
import 'questions/short_text_question.dart';
import 'theme_resolver.dart';

/// Result emitted by [PromptSheet] back to the presenter.
class PromptSheetResult {
  /// Creates a result.
  const PromptSheetResult({
    required this.dismissed,
    required this.answers,
  });

  /// `true` when the user dismissed instead of submitting.
  final bool dismissed;

  /// Answers provided (may be empty when [dismissed] is `true`).
  final List<ResponseAnswer> answers;
}

/// The bottom-sheet that renders a [ClientPrompt]. Pops the route
/// with a [PromptSheetResult] once finished.
class PromptSheet extends StatefulWidget {
  /// Creates the sheet.
  const PromptSheet({
    required this.prompt,
    required this.themeOverrides,
    super.key,
  });

  /// The prompt to render.
  final ClientPrompt prompt;

  /// Caller-supplied theme overrides (merged over the server theme).
  final PromptTheme? themeOverrides;

  @override
  State<PromptSheet> createState() => _PromptSheetState();
}

class _PromptSheetState extends State<PromptSheet> {
  final Map<String, Object?> _answers = <String, Object?>{};
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final theme = ResolvedPromptTheme.of(
      context,
      serverTheme: widget.prompt.theme,
      overrides: widget.themeOverrides,
    );
    final questions = widget.prompt.questions;
    if (questions.isEmpty) {
      return const SizedBox.shrink();
    }
    final current = questions[_index];
    final isLast = _index == questions.length - 1;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: theme.background,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(theme.radius),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _header(theme),
              const SizedBox(height: 12),
              Text(
                current.title,
                style: TextStyle(
                  color: theme.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  fontFamily: theme.fontFamily,
                ),
              ),
              if (current.subtitle != null) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  current.subtitle!,
                  style: TextStyle(
                    color: theme.subtext,
                    fontSize: 14,
                    fontFamily: theme.fontFamily,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              _questionView(current, theme),
              const SizedBox(height: 20),
              _cta(theme, isLast, current.id),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(ResolvedPromptTheme theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: theme.border,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        GestureDetector(
          onTap: _dismiss,
          child: Icon(Icons.close, color: theme.subtext, size: 20),
        ),
      ],
    );
  }

  Widget _questionView(Question q, ResolvedPromptTheme theme) {
    if (q is RatingQuestion) {
      return RatingQuestionView(
        question: q,
        theme: theme,
        onChanged: (v) => _answers[q.id] = v,
      );
    }
    if (q is NpsQuestion) {
      return NpsQuestionView(
        question: q,
        theme: theme,
        onChanged: (v) => _answers[q.id] = v,
      );
    }
    if (q is MultipleChoiceQuestion) {
      return MultipleChoiceQuestionView(
        question: q,
        theme: theme,
        onChanged: (v) => _answers[q.id] = v,
      );
    }
    if (q is ShortTextQuestion) {
      return ShortTextQuestionView(
        question: q,
        theme: theme,
        onChanged: (v) => _answers[q.id] = v,
      );
    }
    return const SizedBox.shrink();
  }

  Widget _cta(ResolvedPromptTheme theme, bool isLast, String qid) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: theme.primary,
          foregroundColor: _contrastOn(theme.primary),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        onPressed: _answers[qid] == null ? null : _advance,
        child: Text(
          isLast ? 'Submit' : 'Next',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontFamily: theme.fontFamily,
          ),
        ),
      ),
    );
  }

  Color _contrastOn(Color c) {
    return ThemeData.estimateBrightnessForColor(c) == Brightness.dark
        ? Colors.white
        : Colors.black;
  }

  void _advance() {
    final total = widget.prompt.questions.length;
    if (_index < total - 1) {
      setState(() => _index++);
      return;
    }
    final answers = widget.prompt.questions
        .map(
          (q) => ResponseAnswer(
            questionId: q.id,
            value: _answers[q.id],
          ),
        )
        .toList(growable: false);
    Navigator.of(context).pop(
      PromptSheetResult(dismissed: false, answers: answers),
    );
  }

  void _dismiss() {
    Navigator.of(context).pop(
      const PromptSheetResult(
        dismissed: true,
        answers: <ResponseAnswer>[],
      ),
    );
  }
}
