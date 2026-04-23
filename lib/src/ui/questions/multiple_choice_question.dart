import 'package:flutter/material.dart';

import '../../models/question.dart';
import '../theme_resolver.dart';

/// Widget rendering a [MultipleChoiceQuestion]. Returns either a single
/// option id (single-select) or a list of ids (multi-select) to the
/// [onChanged] callback.
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

  /// Callback when the selection changes. Emits a `String` (single) or
  /// a `List<String>` (multi-select) of option ids.
  final ValueChanged<Object?> onChanged;

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
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _toggle(opt.id),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: _selected.contains(opt.id)
                      ? theme.primary.withAlpha(31)
                      : Colors.transparent,
                  border: Border.all(
                    color: _selected.contains(opt.id)
                        ? theme.primary
                        : theme.border,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        opt.label,
                        style: TextStyle(
                          color: theme.text,
                          fontFamily: theme.fontFamily,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (_selected.contains(opt.id))
                      Icon(Icons.check, color: theme.primary, size: 18),
                  ],
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
    if (widget.question.multiSelect) {
      widget.onChanged(_selected.toList(growable: false));
    } else {
      widget.onChanged(_selected.isEmpty ? null : _selected.first);
    }
  }
}
