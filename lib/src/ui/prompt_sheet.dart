import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/prompt.dart';
import '../models/question.dart';
import '../models/response_info.dart';
import '../models/theme.dart';
import 'questions/multiple_choice_question.dart';
import 'questions/nps_question.dart';
import 'questions/rating_question.dart';
import 'questions/short_text_question.dart';
import 'surface_controls.dart';
import 'surface_tokens.dart';
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

/// The bottom sheet that renders a [ClientPrompt]. Pops the route with a
/// [PromptSheetResult] once finished.
///
/// The sheet background always spans the full screen width with the theme's
/// top radius. Landscape keeps Close and Next/Submit in the same header row,
/// aligned with the question. Portrait retains the full-width footer action.
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
    final layout = SurfaceLayout.of(context);
    final landscape = layout.landscape;
    final keyboardOpen = layout.keyboard > 0;
    final maxHeight = math.max(
      0.0,
      layout.size.height -
          layout.safe.top -
          (landscape ? 12 : 16) -
          layout.keyboard,
    );
    final needsNext = _needsExplicitNext(current);
    final isLast = _index >= questions.length - 1;
    final next = SurfaceNext(
      key: const ValueKey<String>('feedback-next'),
      onPressed: _advance,
      theme: theme,
      label: isLast ? 'Submit' : 'Next',
      disabled: _nextRequiresAnswer(current) &&
          !_answerHasValue(_answers[current.id]),
      compact: landscape,
      expand: !landscape,
    );
    final bottomInset = keyboardOpen
        ? 12.0
        : math.max(layout.safe.bottom, landscape ? 12.0 : 16.0);
    return Padding(
      padding: EdgeInsets.only(bottom: layout.keyboard),
      child: Container(
        width: double.infinity,
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: BoxDecoration(
          color: theme.background,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(theme.radius),
          ),
        ),
        padding: EdgeInsets.fromLTRB(
          layout.safe.left + 12,
          8,
          layout.safe.right + 12,
          bottomInset,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: landscape
                      ? kSurfaceContentMaxWidth
                      : double.infinity,
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: landscape ? 12 : 0),
                  child: SurfaceHeader(
                    balancedSides: landscape,
                    leading: SurfaceClose(
                      key: const ValueKey<String>('feedback-close'),
                      onPressed: _dismiss,
                      color: theme.text,
                      regular: landscape,
                    ),
                    center: questions.length > 1
                        ? Text(
                            '${_index + 1} of ${questions.length}',
                            style: theme.textStyle(
                              color: theme.subtext,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              tabular: true,
                            ),
                          )
                        : null,
                    trailing: landscape && needsNext ? next : null,
                      ),
                ),
              ),
            ),
            Flexible(
              child: Align(
                alignment: Alignment.topCenter,
                heightFactor: 1,
                child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(maxWidth: kSurfaceContentMaxWidth),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Flexible(
                        child: SingleChildScrollView(
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                          child: _questionSwitcher(current, theme),
                        ),
                      ),
                      if (!landscape && needsNext)
                        Padding(
                          key: const ValueKey<String>('feedback-footer'),
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                          child: next,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _questionSwitcher(Question current, ResolvedPromptTheme theme) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return AnimatedSwitcher(
      duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 240),
      switchInCurve: Curves.easeOutCubic,
      layoutBuilder: (currentChild, previous) => Stack(
        alignment: Alignment.topCenter,
        children: <Widget>[
          ...previous,
          if (currentChild != null) currentChild,
        ],
      ),
      transitionBuilder: (child, animation) {
        final offset = Tween<Offset>(
          begin: const Offset(0.08, 0),
          end: Offset.zero,
        ).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: offset, child: child),
        );
      },
      child: KeyedSubtree(
        key: ValueKey<String>(current.id),
        child: _questionView(current, theme),
      ),
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
      final saved = _answers[q.id];
      return MultipleChoiceQuestionView(
        question: q,
        theme: theme,
        initialValue: saved is List<String> ? saved : const <String>[],
        onChanged: (v) => _setAnswer(q, v),
      );
    }
    if (q is ShortTextQuestion) {
      return ShortTextQuestionView(
        question: q,
        theme: theme,
        initialValue: _answers[q.id] as String? ?? '',
        onChanged: (v) => _setAnswer(q, v),
      );
    }
    // Unknown/newer question type: render nothing rather than failing.
    return const SizedBox.shrink();
  }

  bool _hasNpsFollowUp(Question q) =>
      q is NpsQuestion && q.followUp?.isNotEmpty == true;

  /// Tap selections advance immediately unless the question has more input.
  bool _shouldAutoAdvance(Question q) {
    if (q is RatingQuestion) return true;
    if (q is NpsQuestion) return !_hasNpsFollowUp(q);
    return q is MultipleChoiceQuestion && !q.multiSelect;
  }

  /// Questions that need a deliberate Next/Submit after answering.
  bool _needsExplicitNext(Question q) =>
      q is ShortTextQuestion ||
      _hasNpsFollowUp(q) ||
      (q is MultipleChoiceQuestion && q.multiSelect);

  /// Explicit Next is gated when its question first requires an answer.
  bool _nextRequiresAnswer(Question q) =>
      q is ShortTextQuestion || _hasNpsFollowUp(q);

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
}
