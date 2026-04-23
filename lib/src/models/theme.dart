import 'package:flutter/material.dart';

/// Colors used to theme a rendered prompt.
class PromptThemeColors {
  /// Creates a color palette for the prompt sheet.
  const PromptThemeColors({
    this.primary,
    this.background,
    this.text,
    this.subtext,
    this.border,
  });

  /// Primary accent color used for selected-state and the CTA button.
  final Color? primary;

  /// Sheet background color.
  final Color? background;

  /// Title / body text color.
  final Color? text;

  /// Subtitle / muted text color.
  final Color? subtext;

  /// Color used for option borders and dividers.
  final Color? border;

  /// Parses the subset of the JSON theme payload shipped from the API.
  factory PromptThemeColors.fromJson(Map<String, Object?> json) {
    return PromptThemeColors(
      primary: _parseHex(json['primary'] as String?),
      background: _parseHex(json['background'] as String?),
      text: _parseHex(json['text'] as String?),
      subtext: _parseHex(json['subtext'] as String?),
      border: _parseHex(json['border'] as String?),
    );
  }
}

/// Visual overrides for prompt presentation. Any `null` field falls back
/// to the host app's [Theme]-derived defaults.
class PromptTheme {
  /// Creates a [PromptTheme] value. All fields are optional.
  const PromptTheme({this.colors, this.radius, this.fontFamily});

  /// Color palette overrides.
  final PromptThemeColors? colors;

  /// Corner radius (in logical pixels) for the prompt sheet.
  final double? radius;

  /// Font family name to use for prompt text.
  final String? fontFamily;

  /// Parses the API-shipped theme payload.
  factory PromptTheme.fromJson(Map<String, Object?> json) {
    final colors = json['colors'];
    final radius = json['radius'];
    return PromptTheme(
      colors: colors is Map<String, Object?>
          ? PromptThemeColors.fromJson(colors)
          : null,
      radius: radius is num ? radius.toDouble() : null,
      fontFamily: json['fontFamily'] as String?,
    );
  }

  /// Merges another theme on top of this one. Non-null fields from
  /// [other] take precedence.
  PromptTheme merge(PromptTheme? other) {
    if (other == null) return this;
    return PromptTheme(
      colors: PromptThemeColors(
        primary: other.colors?.primary ?? colors?.primary,
        background: other.colors?.background ?? colors?.background,
        text: other.colors?.text ?? colors?.text,
        subtext: other.colors?.subtext ?? colors?.subtext,
        border: other.colors?.border ?? colors?.border,
      ),
      radius: other.radius ?? radius,
      fontFamily: other.fontFamily ?? fontFamily,
    );
  }
}

Color? _parseHex(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  var s = raw.trim();
  if (s.startsWith('#')) s = s.substring(1);
  if (s.length == 6) s = 'FF$s';
  if (s.length != 8) return null;
  final v = int.tryParse(s, radix: 16);
  if (v == null) return null;
  return Color(v);
}
