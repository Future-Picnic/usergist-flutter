// Shared chrome for every UserGist surface: one Close, one Back, one primary
// action and one header layout. All colours derive from the campaign theme.
//
// Layout rule used by feedback, surveys, messages and requests:
//   - Close is always the leading control in the header.
//   - Portrait: the primary action sits in a footer below the content.
//   - Landscape: the primary action moves to the trailing side of the header,
//     so the content (and the keyboard) keep the full remaining height.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'surface_tokens.dart';
import 'theme_resolver.dart';

/// Live window geometry and safe-area edges, including rotation.
class SurfaceLayout {
  const SurfaceLayout._({
    required this.size,
    required this.safe,
    required this.keyboard,
  });

  /// Reads the current layout from [context].
  factory SurfaceLayout.of(BuildContext context) {
    final media = MediaQuery.of(context);
    // Modal routes strip the top padding from MediaQuery; the window's own
    // view padding still reports the status bar and cutout.
    final view = View.maybeOf(context);
    final windowSafe = view == null
        ? media.viewPadding
        : MediaQueryData.fromView(view).viewPadding;
    return SurfaceLayout._(
      size: media.size,
      safe: EdgeInsets.fromLTRB(
        math.max(media.viewPadding.left, windowSafe.left),
        math.max(media.viewPadding.top, windowSafe.top),
        math.max(media.viewPadding.right, windowSafe.right),
        math.max(media.viewPadding.bottom, windowSafe.bottom),
      ),
      keyboard: media.viewInsets.bottom,
    );
  }

  /// Window size.
  final Size size;

  /// Raw safe-area insets (status bar, cutout, home indicator).
  final EdgeInsets safe;

  /// Software keyboard height (0 when hidden).
  final double keyboard;

  /// Wider than tall.
  bool get landscape => size.width > size.height;
}

/// Glyphs drawn for icon buttons: a thin cross or a chevron.
enum SurfaceGlyph {
  /// Close cross.
  close,

  /// Back chevron (points to the leading edge).
  back,

  /// Upward chevron.
  up,

  /// Downward chevron.
  down,
}

/// Paints a [SurfaceGlyph] centred in its box with a thin stroke.
class SurfaceGlyphPainter extends CustomPainter {
  /// Creates the painter.
  const SurfaceGlyphPainter(this.glyph, this.color, {this.stroke = 1.75});

  /// Glyph to draw.
  final SurfaceGlyph glyph;

  /// Stroke colour.
  final Color color;

  /// Stroke width.
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final c = size.center(Offset.zero);
    switch (glyph) {
      case SurfaceGlyph.close:
        const h = 4.6; // 13pt strokes rotated ±45°.
        canvas
          ..drawLine(c.translate(-h, -h), c.translate(h, h), paint)
          ..drawLine(c.translate(h, -h), c.translate(-h, h), paint);
      case SurfaceGlyph.back:
        final path = Path()
          ..moveTo(c.dx + 2.5, c.dy - 5.5)
          ..lineTo(c.dx - 3, c.dy)
          ..lineTo(c.dx + 2.5, c.dy + 5.5);
        canvas.drawPath(path, paint);
      case SurfaceGlyph.up:
        final path = Path()
          ..moveTo(c.dx - 5, c.dy + 2.5)
          ..lineTo(c.dx, c.dy - 2.5)
          ..lineTo(c.dx + 5, c.dy + 2.5);
        canvas.drawPath(path, paint);
      case SurfaceGlyph.down:
        final path = Path()
          ..moveTo(c.dx - 5, c.dy - 2.5)
          ..lineTo(c.dx, c.dy + 2.5)
          ..lineTo(c.dx + 5, c.dy - 2.5);
        canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(SurfaceGlyphPainter old) =>
      old.glyph != glyph || old.color != color || old.stroke != stroke;
}

class _IconButton extends StatelessWidget {
  const _IconButton({
    required this.onPressed,
    required this.glyph,
    required this.color,
    required this.label,
    this.regular = false,
  });

  final VoidCallback onPressed;
  final SurfaceGlyph glyph;
  final Color color;
  final String label;
  final bool regular;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      container: true,
      excludeSemantics: true,
      onTap: onPressed,
      child: SizedBox(
        width: 48,
        height: 48,
        child: Material(
          type: MaterialType.transparency,
          child: InkResponse(
            onTap: onPressed,
            radius: 22,
            child: Center(
              child: Container(
                width: regular ? 44 : 32,
                height: regular ? 44 : 32,
                decoration: BoxDecoration(
                  color: surfaceWithOpacity(color, 0.08),
                  shape: BoxShape.circle,
                ),
                child: CustomPaint(
                  painter: SurfaceGlyphPainter(
                    glyph,
                    color,
                    stroke: regular ? 2 : 1.75,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The single Close control. [color] is the theme text colour; the face is a
/// quiet wash of that colour so it reads on any background.
class SurfaceClose extends StatelessWidget {
  /// Creates Close.
  const SurfaceClose({
    required this.onPressed,
    required this.color,
    this.label = 'Close',
    this.regular = false,
    super.key,
  });

  /// Tap handler.
  final VoidCallback onPressed;

  /// Glyph colour (theme text).
  final Color color;

  /// Accessibility label.
  final String label;

  /// Matches the compact landscape primary action's visible height.
  final bool regular;

  @override
  Widget build(BuildContext context) => _IconButton(
        onPressed: onPressed,
        glyph: SurfaceGlyph.close,
        color: color,
        label: label,
        regular: regular,
      );
}

/// Back uses the same face as Close, with a drawn chevron.
class SurfaceBack extends StatelessWidget {
  /// Creates Back.
  const SurfaceBack({
    required this.onPressed,
    required this.color,
    this.label = 'Back',
    this.regular = false,
    super.key,
  });

  /// Tap handler.
  final VoidCallback onPressed;

  /// Glyph colour (theme text).
  final Color color;

  /// Accessibility label.
  final String label;

  /// Matches the compact landscape primary action's visible height.
  final bool regular;

  @override
  Widget build(BuildContext context) => _IconButton(
        onPressed: onPressed,
        glyph: SurfaceGlyph.back,
        color: color,
        label: label,
        regular: regular,
      );
}

/// Solid primary action. Disabled uses a neutral fill rather than a faded
/// brand colour; labels wrap instead of truncating.
class SurfaceNext extends StatelessWidget {
  /// Creates the primary action.
  const SurfaceNext({
    required this.onPressed,
    required this.theme,
    this.label = 'Next',
    this.disabled = false,
    this.loading = false,
    this.compact = false,
    this.expand = false,
    super.key,
  });

  /// Tap handler.
  final VoidCallback onPressed;

  /// Resolved theme.
  final ResolvedPromptTheme theme;

  /// Visible label (also the accessibility label).
  final String label;

  /// Whether the action is unavailable.
  final bool disabled;

  /// Shows a spinner and blocks taps.
  final bool loading;

  /// Header-sized variant.
  final bool compact;

  /// Fill the available width (portrait footers).
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final inactive = disabled && !loading;
    final enabled = !disabled && !loading;
    final background = inactive ? theme.fill : theme.primary;
    final foreground = inactive ? theme.disabledLabel : theme.onPrimary;
    final radius = compact ? 22.0 : 25.0;
    final child = loading
        ? SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: theme.onPrimary,
            ),
          )
        : Text(
            label,
            textAlign: TextAlign.center,
            style: theme.textStyle(
              color: foreground,
              fontSize: compact ? 15 : 16,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
            ),
          );
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      container: true,
      excludeSemantics: true,
      onTap: enabled ? onPressed : null,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: compact ? 44 : 50,
          minWidth: expand ? double.infinity : (compact ? 88 : 0),
        ),
        child: Material(
          color: background,
          borderRadius: BorderRadius.circular(radius),
          child: InkWell(
            onTap: enabled ? onPressed : null,
            borderRadius: BorderRadius.circular(radius),
            highlightColor: surfaceWithOpacity(theme.onPrimary, 0.14),
            splashColor: surfaceWithOpacity(theme.onPrimary, 0.1),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 18 : 24,
                vertical: compact ? 10 : 12,
              ),
              child: Center(widthFactor: 1, heightFactor: 1, child: child),
            ),
          ),
        ),
      ),
    );
  }
}

/// Quiet secondary action. Uses the text colour with a neutral outline: a
/// primary-coloured label is unreadable when the brand colour is light
/// (yellow, mint) on a light background.
class SurfaceSecondary extends StatelessWidget {
  /// Creates the secondary action.
  const SurfaceSecondary({
    required this.onPressed,
    required this.theme,
    required this.label,
    this.compact = false,
    this.expand = false,
    super.key,
  });

  /// Tap handler.
  final VoidCallback onPressed;

  /// Resolved theme.
  final ResolvedPromptTheme theme;

  /// Visible label.
  final String label;

  /// Header-sized variant.
  final bool compact;

  /// Fill the available width.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final radius = compact ? 22.0 : 25.0;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(color: theme.quietOutline, width: 1.5),
    );
    return Semantics(
      button: true,
      label: label,
      container: true,
      excludeSemantics: true,
      onTap: onPressed,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: compact ? 44 : 50,
          minWidth: expand ? double.infinity : (compact ? 88 : 0),
        ),
        child: Material(
          type: MaterialType.transparency,
          shape: shape,
          child: InkWell(
            onTap: onPressed,
            customBorder: shape,
            highlightColor: theme.fill,
            splashColor: theme.fill,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 18 : 24,
                vertical: compact ? 10 : 12,
              ),
              child: Center(
                widthFactor: 1,
                heightFactor: 1,
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: theme.textStyle(
                    color: theme.text,
                    fontSize: compact ? 15 : 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Three-slot header. Leading and trailing slots size to their content; the
/// centre takes the remaining width (progress, title or step count).
class SurfaceHeader extends StatelessWidget {
  /// Creates the header.
  const SurfaceHeader({
    this.leading,
    this.center,
    this.trailing,
    this.balancedSides = false,
    super.key,
  });

  /// Leading slot (Close, Back).
  final Widget? leading;

  /// Centre slot.
  final Widget? center;

  /// Trailing slot (landscape primary action).
  final Widget? trailing;

  /// Reserves matching space for landscape Close + Back and the action.
  final bool balancedSides;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Row(
        children: <Widget>[
          ConstrainedBox(
            constraints: BoxConstraints(minWidth: balancedSides ? 104 : 48),
            child: leading ?? const SizedBox.shrink(),
          ),
          const SizedBox(width: 8),
          Expanded(child: Center(child: center ?? const SizedBox.shrink())),
          const SizedBox(width: 8),
          ConstrainedBox(
            // Long header action labels wrap within this width instead of
            // squeezing the title.
            constraints: BoxConstraints(
              minWidth: balancedSides ? 104 : 48,
              maxWidth: 320,
            ),
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              widthFactor: 1,
              child: trailing ?? const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Centres [child] within the readable measure.
class SurfaceMeasure extends StatelessWidget {
  /// Creates the measure.
  const SurfaceMeasure({required this.child, super.key});

  /// Content.
  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(maxWidth: kSurfaceContentMaxWidth),
          child: child,
        ),
      );
}
