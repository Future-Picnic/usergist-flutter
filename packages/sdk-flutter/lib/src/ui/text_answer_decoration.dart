import 'package:flutter/material.dart';

import 'theme_resolver.dart';

/// Builds the transparent-looking, theme-owned text-answer field used by the
/// React Native renderer.
InputDecoration textAnswerDecoration({
  required ResolvedPromptTheme theme,
  required String? hintText,
}) {
  final outline = OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: theme.border),
  );
  return InputDecoration(
    hintText: hintText,
    hintStyle: TextStyle(
      color: theme.subtext,
      fontFamily: theme.fontFamily,
    ),
    counterText: '',
    contentPadding: const EdgeInsets.all(12),
    filled: true,
    fillColor: theme.background,
    border: outline,
    enabledBorder: outline,
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: theme.primary),
    ),
  );
}
