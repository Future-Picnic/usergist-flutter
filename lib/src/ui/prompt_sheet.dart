import 'dart:async';

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
    this.onAnswersChanged,
    super.key,
  });

  /// The prompt to render.
  final ClientPrompt prompt;

  /// Caller-supplied global theme (merged under the per-prompt server theme).
  final PromptTheme? themeOverrides;

  /// Retains partial answers when the enclosing route is dismissed externally.
  final ValueChanged<List<ResponseAnswer>>? onAnswersChanged;

  @override
  State<PromptSheet> createState() => _PromptSheetState();
}

class _PromptSheetState extends State<PromptSheet> {
  final Map<String, Object?> _answers = <String, Object?>{};
  int _index = 0;
  Timer? _advanceTimer;
  bool _closing = false;

  @override
  void dispose() {
    _advanceTimer?.cancel();
    super.dispose();
  }

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
    final media = MediaQuery.of(context);
    final maxHeight = media.size.height - media.viewPadding.top - 16;
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(minHeight: 280, maxHeight: maxHeight),
        decoration: BoxDecoration(
          color: theme.background,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(theme.radius),
          ),
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            (media.viewPadding.bottom > 30 ? media.viewPadding.bottom : 30) +
                16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _header(theme),
              const SizedBox(height: 24),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 240),
                switchInCurve: Curves.easeOutCubic,
                transitionBuilder: (child, animation) {
                  final offset = Tween<Offset>(
                    begin: const Offset(0.1, 0),
                    end: Offset.zero,
                  ).animate(animation);
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(position: offset, child: child),
                  );
                },
                child: KeyedSubtree(
                  key: ValueKey<String>(current.id),
                  child: _questionBlock(current, theme),
                ),
              ),
              if (_needsFooterNext(current)) ...<Widget>[
                const SizedBox(height: 20),
                _nextButton(
                  theme,
                  enabled: current is! NpsQuestion ||
                      _answerHasValue(_answers[current.id]),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(ResolvedPromptTheme theme) {
    return SizedBox(
      height: 32,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: <Widget>[
          Positioned(
            top: 6,
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            child: Semantics(
              button: true,
              label: 'Close',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _dismiss,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(15),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(Icons.close, color: theme.text, size: 18),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _questionBlock(Question q, ResolvedPromptTheme theme) {
    final centered = q is RatingQuestion || q is NpsQuestion;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (q.imageUrl case final imageUrl?) ...<Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(theme.radius),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        Text(
          q.title,
          textAlign: centered ? TextAlign.center : TextAlign.start,
          style: TextStyle(
            color: theme.text,
            // Flutter's Android glyph metrics render the same nominal size
            // smaller than the React Native reference.
            fontSize: 20,
            fontWeight: FontWeight.w700,
            fontFamily: theme.fontFamily,
          ),
        ),
        if (q.subtitle case final subtitle?
            when subtitle.isNotEmpty) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: centered ? TextAlign.center : TextAlign.start,
            style: TextStyle(
              color: theme.subtext,
              fontSize: 14,
              fontFamily: theme.fontFamily,
            ),
          ),
        ],
        SizedBox(
          height: _spacingBeforeControl(
            q,
            q.subtitle?.isNotEmpty ?? false,
          ),
        ),
        _questionView(q, theme),
        if (q is ShortTextQuestion) ...<Widget>[
          const SizedBox(height: 20),
          _nextButton(theme, enabled: _answerHasValue(_answers[q.id])),
        ],
      ],
    );
  }

  Widget _questionView(Question q, ResolvedPromptTheme theme) {
    if (q is RatingQuestion) {
      return RatingQuestionView(
        question: q,
        theme: theme,
        initialValue: _answers[q.id] as int?,
        onChanged: (v) => _setAnswer(q, v),
      );
    }
    if (q is NpsQuestion) {
      return NpsQuestionView(
        question: q,
        theme: theme,
        score: _answers[q.id] as int?,
        followUp: _answers['${q.id}__followUp'] as String? ?? '',
        onScore: (v) => _setAnswer(q, v),
        onFollowUp: (v) => _setAnswerValue('${q.id}__followUp', v),
      );
    }
    if (q is MultipleChoiceQuestion) {
      return MultipleChoiceQuestionView(
        question: q,
        theme: theme,
        onChanged: (v) => _setAnswer(q, v),
      );
    }
    if (q is ShortTextQuestion) {
      return ShortTextQuestionView(
        question: q,
        theme: theme,
        onChanged: (v) => _setAnswer(q, v),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _nextButton(
    ResolvedPromptTheme theme, {
    required bool enabled,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: theme.primary,
          disabledBackgroundColor: theme.primary.withAlpha(102),
          foregroundColor: Colors.white,
          disabledForegroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: const StadiumBorder(),
          elevation: 0,
        ),
        onPressed: enabled ? _advance : null,
        child: Text(
          'Next',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            fontFamily: theme.fontFamily,
          ),
        ),
      ),
    );
  }

  bool _shouldAutoAdvance(Question q) {
    if (q is RatingQuestion) return true;
    if (q is NpsQuestion) return q.followUp?.isNotEmpty != true;
    return q is MultipleChoiceQuestion && !q.multiSelect;
  }

  bool _needsFooterNext(Question q) =>
      (q is MultipleChoiceQuestion && q.multiSelect) ||
      (q is NpsQuestion && q.followUp?.isNotEmpty == true);

  bool _answerHasValue(Object? value) {
    if (value == null) return false;
    if (value is String) return value.trim().isNotEmpty;
    if (value is List<Object?>) return value.isNotEmpty;
    return true;
  }

  void _setAnswer(Question question, Object? value) {
    _setAnswerValue(question.id, value);
    if (!_shouldAutoAdvance(question)) return;
    _advanceTimer?.cancel();
    _advanceTimer = Timer(const Duration(milliseconds: 220), () {
      if (!mounted || _closing) return;
      final questions = widget.prompt.questions;
      if (_index >= questions.length || questions[_index].id != question.id) {
        return;
      }
      _advance();
    });
  }

  void _setAnswerValue(String id, Object? value) {
    if (!mounted) return;
    setState(() => _answers[id] = value);
    widget.onAnswersChanged?.call(_answerSnapshot());
  }

  List<ResponseAnswer> _answerSnapshot() => _answers.entries
      .map((entry) => ResponseAnswer(questionId: entry.key, value: entry.value))
      .toList(growable: false);

  void _advance() {
    if (_closing) return;
    _advanceTimer?.cancel();
    _advanceTimer = null;
    final total = widget.prompt.questions.length;
    if (_index < total - 1) {
      setState(() => _index++);
      return;
    }
    _closing = true;
    final answers = _answerSnapshot();
    Navigator.of(context).pop(
      PromptSheetResult(dismissed: false, answers: answers),
    );
  }

  void _dismiss() {
    if (_closing) return;
    _closing = true;
    _advanceTimer?.cancel();
    final answers = _answerSnapshot();
    Navigator.of(context).pop(
      PromptSheetResult(
        dismissed: true,
        answers: answers,
      ),
    );
  }

  double _spacingBeforeControl(Question question, bool hasSubtitle) {
    if (question is RatingQuestion) return hasSubtitle ? 24 : 12;
    if (question is NpsQuestion) return hasSubtitle ? 24 : 16;
    if (question is MultipleChoiceQuestion) return hasSubtitle ? 16 : 12;
    return hasSubtitle ? 12 : 4;
  }
}
