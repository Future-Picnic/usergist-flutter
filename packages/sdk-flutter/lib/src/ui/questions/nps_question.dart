import 'package:flutter/material.dart';

import '../../models/question.dart';
import '../surface_primitives.dart';
import '../surface_tokens.dart';
import '../theme_resolver.dart';

/// Content width at which the 0–10 row replaces the vertical list. Measured
/// on the question's own layout width (not the window), so a narrow column
/// inside a wide screen keeps the vertical list.
const double kNpsWideBreakpoint = 524;

/// Widget rendering an [NpsQuestion] (0..10 scale).
///
/// - Wide layouts (landscape, tablets): the familiar 0–10 row with endpoint
///   labels underneath; every numeral, including 10, is centred in its cell.
/// - Narrow portrait: a compact vertical list, 10 at the top, so no number is
///   squeezed below a usable touch target.
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
  late final TextEditingController _followUp =
      TextEditingController(text: widget.followUp);

  @override
  void dispose() {
    _followUp.dispose();
    super.dispose();
  }

  String get _low => widget.question.lowLabel ?? 'Not at all likely';
  String get _high => widget.question.highLabel ?? 'Extremely likely';

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => _build(
          constraints.hasBoundedWidth &&
              constraints.maxWidth >= kNpsWideBreakpoint,
        ),
      );

  Widget _build(bool wide) {
    final theme = widget.theme;
    final question = widget.question;
    final followUpTitle = question.followUp;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        QuestionHeader(
          title: question.title,
          subtitle: question.subtitle,
          imageUrl: question.imageUrl,
          theme: theme,
          center: wide,
        ),
        if (wide) ..._wideRow(theme) else ..._tallList(theme),
        if (widget.score != null &&
            followUpTitle != null &&
            followUpTitle.isNotEmpty) ...<Widget>[
          const SizedBox(height: 24),
          Text(
            followUpTitle,
            style: theme.textStyle(
              color: theme.text,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          SurfaceField(
            theme: theme,
            controller: _followUp,
            onChanged: widget.onFollowUp,
            hintText: 'Tell us more',
            multiline: true,
            minHeight: 80,
            semanticsLabel: followUpTitle,
          ),
        ],
      ],
    );
  }

  List<Widget> _wideRow(ResolvedPromptTheme theme) => <Widget>[
        Row(
          children: <Widget>[
            for (var n = 0; n <= 10; n++) ...<Widget>[
              if (n > 0) const SizedBox(width: 6),
              Expanded(child: _cell(n, theme, wide: true)),
            ],
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Expanded(child: _endLabel(_low, TextAlign.start, theme)),
            const SizedBox(width: 16),
            Expanded(child: _endLabel(_high, TextAlign.end, theme)),
          ],
        ),
      ];

  List<Widget> _tallList(ResolvedPromptTheme theme) => <Widget>[
        for (var n = 10; n >= 0; n--) ...<Widget>[
          if (n < 10) const SizedBox(height: 6),
          _cell(n, theme, wide: false),
        ],
      ];

  Widget _endLabel(String text, TextAlign align, ResolvedPromptTheme theme) =>
      Text(
        text,
        textAlign: align,
        style: theme.textStyle(color: theme.subtext, fontSize: 13),
      );

  Widget _cell(int n, ResolvedPromptTheme theme, {required bool wide}) {
    final selected = widget.score == n;
    final endpoint = wide
        ? null
        : n == 10
            ? _high
            : n == 0
                ? _low
                : null;
    final radius = BorderRadius.circular(theme.cellRadius);
    final number = Text(
      '$n',
      textAlign: TextAlign.center,
      style: theme.textStyle(
        color: selected ? theme.onPrimary : theme.text,
        fontWeight: FontWeight.w700,
        tabular: true,
      ),
    );
    final content = wide
        ? SizedBox(height: 48, child: Center(child: number))
        : ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: <Widget>[
                  // A fixed number column keeps endpoint labels aligned.
                  SizedBox(
                    width: 22,
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: number,
                    ),
                  ),
                  if (endpoint != null) ...<Widget>[
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        endpoint,
                        style: theme.textStyle(
                          color: selected ? theme.onPrimary : theme.subtext,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
    final suffix = n == 10
        ? ', $_high'
        : n == 0
            ? ', $_low'
            : '';
    return Semantics(
      button: true,
      inMutuallyExclusiveGroup: true,
      selected: selected,
      label: 'Score $n$suffix',
      container: true,
      excludeSemantics: true,
      onTap: () => widget.onScore(n),
      child: Material(
        color: selected ? theme.primary : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: selected ? theme.primary : theme.border,
            width: 1.5,
          ),
        ),
        child: InkWell(
          onTap: () => widget.onScore(n),
          borderRadius: radius,
          highlightColor: theme.fill,
          splashColor: theme.fill,
          child: content,
        ),
      ),
    );
  }
}
