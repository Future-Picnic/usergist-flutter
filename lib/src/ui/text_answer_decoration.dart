import 'package:flutter/material.dart';

import 'surface_tokens.dart';
import 'theme_resolver.dart';

/// Builds the soft, theme-owned text field used by every SDK surface: a
/// neutral wash of the text colour, no resting outline and a primary focus
/// border. Never inherits the host app's input fill.
InputDecoration textAnswerDecoration({
  required ResolvedPromptTheme theme,
  required String? hintText,
}) {
  OutlineInputBorder outline(Color color) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(theme.fieldRadius),
        borderSide: BorderSide(color: color, width: 1.5),
      );
  return InputDecoration(
    hintText: hintText,
    hintStyle: theme.textStyle(
      color: surfaceWithOpacity(theme.subtext, 0.8),
      lineHeight: 22,
    ),
    counterText: '',
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    filled: true,
    fillColor: theme.fill,
    hoverColor: theme.fill,
    border: outline(Colors.transparent),
    enabledBorder: outline(Colors.transparent),
    disabledBorder: outline(Colors.transparent),
    focusedBorder: outline(theme.primary),
  );
}
