import 'package:flutter/material.dart';

import '../models/theme.dart';

/// Resolves a [ResolvedPromptTheme] for the current [BuildContext] by
/// layering (in order):
///   1. the host app's [Theme];
///   2. the SDK caller's global [UserGist.setThemeOverrides] payload;
///   3. the server-shipped per-prompt theme.
class ResolvedPromptTheme {
  /// Creates a resolved theme.
  const ResolvedPromptTheme({
    required this.primary,
    required this.background,
    required this.text,
    required this.subtext,
    required this.border,
    required this.radius,
    this.fontFamily,
  });

  /// Primary accent color.
  final Color primary;

  /// Sheet background color.
  final Color background;

  /// Title / body text color.
  final Color text;

  /// Subtitle / muted text color.
  final Color subtext;

  /// Border color.
  final Color border;

  /// Corner radius.
  final double radius;

  /// Font family name.
  final String? fontFamily;

  /// Resolves a theme from Flutter [context] + optional overlays.
  static ResolvedPromptTheme of(
    BuildContext context, {
    PromptTheme? serverTheme,
    PromptTheme? overrides,
  }) {
    final flutterTheme = Theme.of(context);
    final colorScheme = flutterTheme.colorScheme;
    final base = PromptTheme(
      colors: PromptThemeColors(
        primary: colorScheme.primary,
        background: colorScheme.surface,
        text: colorScheme.onSurface,
        subtext: colorScheme.onSurfaceVariant,
        border: colorScheme.outlineVariant,
      ),
      radius: 20,
      fontFamily:
          flutterTheme.textTheme.bodyMedium?.fontFamily ?? 'Plus Jakarta Sans',
    );
    final merged = base.merge(overrides).merge(serverTheme);
    return ResolvedPromptTheme(
      primary: merged.colors?.primary ?? colorScheme.primary,
      background: merged.colors?.background ?? colorScheme.surface,
      text: merged.colors?.text ?? colorScheme.onSurface,
      subtext: merged.colors?.subtext ?? colorScheme.onSurfaceVariant,
      border: merged.colors?.border ?? colorScheme.outlineVariant,
      radius: merged.radius ?? 20,
      fontFamily: merged.fontFamily,
    );
  }
}
