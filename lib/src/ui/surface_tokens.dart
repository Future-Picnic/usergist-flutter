import 'dart:math' as math;

import 'package:flutter/painting.dart';

import 'theme_resolver.dart';

/// Readable measure for content. Sheet backgrounds span the full width; the
/// content inside them (and inside full-screen surfaces) stays within this.
const double kSurfaceContentMaxWidth = 560;

/// Tabular figures for counters and scores.
const List<FontFeature> kTabularFigures = <FontFeature>[
  FontFeature.tabularFigures(),
];

/// WCAG contrast ratio between two relative luminances (1–21).
double surfaceContrastRatio(double a, double b) {
  final hi = math.max(a, b);
  final lo = math.min(a, b);
  return (hi + 0.05) / (lo + 0.05);
}

/// Label colour for text on a filled [background]: whichever of black or
/// white has the greater actual WCAG contrast (not a luminance threshold).
Color surfaceReadableOn(Color background) {
  final lum = background.computeLuminance();
  return surfaceContrastRatio(lum, 0) > surfaceContrastRatio(lum, 1)
      ? const Color(0xFF000000)
      : const Color(0xFFFFFFFF);
}

/// Applies [opacity] (0–1) to [color], ignoring its existing alpha.
Color surfaceWithOpacity(Color color, double opacity) =>
    color.withAlpha((opacity.clamp(0, 1) * 255).round());

/// Colours derived from the five campaign colours. Every SDK surface reads
/// these instead of fixed greys or white, so any dashboard theme (light,
/// dark, pastel or saturated) stays legible without extra configuration.
extension SurfaceTokens on ResolvedPromptTheme {
  /// Readable label colour on a primary fill (black or white by contrast).
  Color get onPrimary => surfaceReadableOn(primary);

  /// Quiet primary wash for selected options.
  Color get tint => surfaceWithOpacity(primary, 0.1);

  /// Neutral wash for inputs, Close and disabled actions.
  Color get fill => surfaceWithOpacity(text, 0.06);

  /// Slightly stronger neutral, used for pressed states and tracks.
  Color get fillStrong => surfaceWithOpacity(text, 0.12);

  /// Modal backdrop.
  Color get scrim => const Color(0x73000000);

  /// Icon-button face (Close / Back).
  Color get iconFace => surfaceWithOpacity(text, 0.08);

  /// Disabled label on a neutral fill.
  Color get disabledLabel => surfaceWithOpacity(text, 0.38);

  /// Neutral outline for secondary actions and unselected indicators.
  Color get quietOutline => surfaceWithOpacity(text, 0.16);

  /// Corner radius for choice rows.
  double get choiceRadius => math.min(radius, 16);

  /// Corner radius for text fields and alerts.
  double get fieldRadius => math.min(radius, 14);

  /// Corner radius for score cells and chips.
  double get cellRadius => math.min(radius, 12);

  /// Text style using the theme font.
  TextStyle textStyle({
    required Color color,
    double fontSize = 16,
    FontWeight fontWeight = FontWeight.w400,
    double? lineHeight,
    double? letterSpacing,
    bool tabular = false,
  }) =>
      TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: fontWeight,
        height: lineHeight == null ? null : lineHeight / fontSize,
        letterSpacing: letterSpacing,
        fontFamily: fontFamily,
        fontFeatures: tabular ? kTabularFigures : null,
      );
}
