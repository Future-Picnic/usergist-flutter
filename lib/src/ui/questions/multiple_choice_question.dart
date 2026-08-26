import 'package:flutter/material.dart';

import '../../models/question.dart';
import '../theme_resolver.dart';

/// Widget rendering a [MultipleChoiceQuestion]. Returns either a single
/// list of selected option ids to the [onChanged] callback.
class MultipleChoiceQuestionView extends StatefulWidget {
  /// Creates the widget.
  const MultipleChoiceQuestionView({
    required this.question,
    required this.theme,
    required this.onChanged,
    super.key,
  });

  /// Question payload.
  final MultipleChoiceQuestion question;

  /// Resolved theme.
  final ResolvedPromptTheme theme;

  /// Callback when the selection changes.
  final ValueChanged<List<String>> onChanged;

  @override
  State<MultipleChoiceQuestionView> createState() =>
      _MultipleChoiceQuestionViewState();
}

class _MultipleChoiceQuestionViewState
    extends State<MultipleChoiceQuestionView> {
  final Set<String> _selected = <String>{};

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final opt in widget.question.options)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Semantics(
              button: true,
              selected: _selected.contains(opt.id),
              label: opt.label,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _toggle(opt.id),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 48),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _selected.contains(opt.id)
                        ? theme.primary
                        : Colors.transparent,
                    border: Border.all(
                      color: _selected.contains(opt.id)
                          ? theme.primary
                          : theme.border,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.centerLeft,
                  child: Text(
                    opt.label,
                    style: TextStyle(
                      color: _selected.contains(opt.id)
                          ? theme.background
                          : theme.text,
                      fontFamily: theme.fontFamily,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _toggle(String id) {
    setState(() {
      if (widget.question.multiSelect) {
        if (_selected.contains(id)) {
          _selected.remove(id);
        } else {
          _selected.add(id);
        }
      } else {
        _selected
          ..clear()
          ..add(id);
      }
    });
    widget.onChanged(_selected.toList(growable: false));
  }
}
