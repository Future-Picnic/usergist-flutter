import 'package:flutter/material.dart';

import '../../models/question.dart';
import '../surface_primitives.dart';
import '../theme_resolver.dart';

/// Widget rendering a [MultipleChoiceQuestion]. Reports the list of selected
/// option ids to [onChanged].
class MultipleChoiceQuestionView extends StatefulWidget {
  /// Creates the widget.
  const MultipleChoiceQuestionView({
    required this.question,
    required this.theme,
    required this.onChanged,
    this.initialValue = const <String>[],
    super.key,
  });

  /// Question payload.
  final MultipleChoiceQuestion question;

  /// Resolved theme.
  final ResolvedPromptTheme theme;

  /// Callback when the selection changes.
  final ValueChanged<List<String>> onChanged;

  /// Previously selected option ids.
  final List<String> initialValue;

  @override
  State<MultipleChoiceQuestionView> createState() =>
      _MultipleChoiceQuestionViewState();
}

class _MultipleChoiceQuestionViewState
    extends State<MultipleChoiceQuestionView> {
  late List<String> _selected = List<String>.of(widget.initialValue);

  @override
  Widget build(BuildContext context) {
    final question = widget.question;
    final subtitle = question.subtitle ??
        (question.multiSelect ? 'Choose all that apply' : null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        QuestionHeader(
          title: question.title,
          subtitle: subtitle,
          imageUrl: question.imageUrl,
          theme: widget.theme,
        ),
        for (final (index, opt) in question.options.indexed) ...<Widget>[
          if (index > 0) const SizedBox(height: 8),
          ChoiceRow(
            label: opt.label,
            selected: _selected.contains(opt.id),
            kind: question.multiSelect ? ChoiceKind.checkbox : ChoiceKind.radio,
            onTap: () => _toggle(opt.id),
            theme: widget.theme,
          ),
        ],
      ],
    );
  }

  void _toggle(String id) {
    final List<String> next;
    if (widget.question.multiSelect) {
      next = _selected.contains(id)
          ? _selected.where((v) => v != id).toList(growable: false)
          : <String>[..._selected, id];
    } else {
      next = <String>[id];
    }
    setState(() => _selected = next);
    widget.onChanged(next);
  }
}
