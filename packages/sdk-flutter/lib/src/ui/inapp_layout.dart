// Presentational body for in-app messages (card, full screen, slide-up).
// InAppPresenter owns routes, timing and outcomes; this file owns layout.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/inapp_message.dart';
import 'surface_controls.dart';
import 'surface_primitives.dart';
import 'surface_tokens.dart';
import 'theme_resolver.dart';

/// Presentation of an in-app message.
enum InAppFormat {
  /// Centred card.
  card,

  /// Full screen.
  full,

  /// Floating card inset above the home indicator.
  slide,
}

/// Lays out one in-app message for its [format]. Long copy, images and CTA
/// labels scroll inside the safe height; nothing is dropped or clipped.
class InAppMessageLayout extends StatelessWidget {
  /// Creates the layout.
  const InAppMessageLayout({
    required this.message,
    required this.format,
    required this.theme,
    required this.onClose,
    required this.onCta,
    super.key,
  });

  /// Message payload.
  final ArmedInAppMessage message;

  /// Presentation.
  final InAppFormat format;

  /// Resolved theme.
  final ResolvedPromptTheme theme;

  /// Close handler.
  final VoidCallback onClose;

  /// CTA handler.
  final void Function(InAppCta cta, int index) onCta;

  @override
  Widget build(BuildContext context) {
    final layout = SurfaceLayout.of(context);
    switch (format) {
      case InAppFormat.full:
        return _full(layout);
      case InAppFormat.slide:
        return _slide(layout);
      case InAppFormat.card:
        return _card(layout);
    }
  }

  Widget get _close => SurfaceClose(
        key: const ValueKey<String>('inapp-close'),
        onPressed: onClose,
        color: theme.text,
      );

  ShapeBorder get _cardShape => RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(theme.radius),
        side: BorderSide(
          color: surfaceWithOpacity(theme.text, 0.08),
          width: 0.5,
        ),
      );

  Widget _text() {
    final full = format == InAppFormat.full;
    final slide = format == InAppFormat.slide;
    final body = message.body;
    return Padding(
      padding: slide
          ? const EdgeInsets.only(top: 10, right: 8)
          : EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Semantics(
            header: true,
            child: Text(
              message.title,
              style: theme.textStyle(
                color: theme.text,
                fontSize: full ? 26 : 19,
                lineHeight: full ? 32 : 25,
                fontWeight: FontWeight.w700,
                letterSpacing: full ? -0.4 : -0.2,
              ),
            ),
          ),
          if (body != null && body.isNotEmpty) ...<Widget>[
            SizedBox(height: slide ? 4 : 8),
            Text(
              body,
              style: theme.textStyle(
                color: theme.subtext,
                fontSize: full ? 17 : 15,
                lineHeight: full ? 26 : 22,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget? _image(bool landscape) {
    final url = message.imageUrl;
    if (url == null || url.isEmpty) return null;
    final double height = switch (format) {
      InAppFormat.slide => 120,
      _ when landscape => 128,
      InAppFormat.full => 240,
      InAppFormat.card => 168,
    };
    return SurfaceImage(url: url, theme: theme, height: height);
  }

  /// Stacked in portrait so long labels never truncate; side by side in
  /// landscape and slide-up where height is scarce. The first CTA is the
  /// primary action and sits trailing when side by side.
  Widget? _ctas(bool landscape) {
    if (message.ctas.isEmpty) return null;
    final compact = format == InAppFormat.slide;
    final stacked = !landscape && !compact;
    Widget button(int index, InAppCta cta) => index == 0
        ? SurfaceNext(
            key: ValueKey<String>('inapp-cta-$index'),
            onPressed: () => onCta(cta, index),
            theme: theme,
            label: cta.label,
            compact: compact,
            expand: true,
          )
        : SurfaceSecondary(
            key: ValueKey<String>('inapp-cta-$index'),
            onPressed: () => onCta(cta, index),
            theme: theme,
            label: cta.label,
            compact: compact,
            expand: true,
          );
    final buttons = <Widget>[
      for (final (i, cta) in message.ctas.indexed) button(i, cta),
    ];
    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final (i, b) in buttons.indexed) ...<Widget>[
            if (i > 0) const SizedBox(height: 10),
            b,
          ],
        ],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final (i, b) in buttons.reversed.indexed) ...<Widget>[
            if (i > 0) const SizedBox(width: 10),
            Expanded(child: b),
          ],
        ],
      ),
    );
  }

  /// Pinned actions keep their natural height up to 40% of the screen and
  /// only scroll beyond it, so long labels or large text are never clipped
  /// and never take all the height from the message body.
  Widget? _footer(SurfaceLayout layout, EdgeInsets padding) {
    final ctas = _ctas(layout.landscape);
    if (ctas == null) return null;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: math.max(120, (layout.size.height * 0.4).roundToDouble()),
      ),
      child: SingleChildScrollView(padding: padding, child: ctas),
    );
  }

  Widget _card(SurfaceLayout layout) {
    final landscape = layout.landscape;
    final image = _image(landscape);
    final footer = _footer(layout, const EdgeInsets.fromLTRB(22, 16, 22, 22));
    return Padding(
      padding: EdgeInsets.fromLTRB(
        layout.safe.left + 16,
        layout.safe.top + 8,
        layout.safe.right + 16,
        math.max(layout.safe.bottom, 12),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: landscape ? kSurfaceContentMaxWidth : 400,
          ),
          child: Material(
            color: theme.background,
            clipBehavior: Clip.antiAlias,
            shape: _cardShape,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: _close,
                  ),
                ),
                Flexible(
                  child: ConstrainedBox(
                    // Body keeps a readable slice; the footer scrolls first.
                    constraints: const BoxConstraints(minHeight: 96),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          if (image != null) ...<Widget>[
                            image,
                            const SizedBox(height: 18),
                          ],
                          _text(),
                        ],
                      ),
                    ),
                  ),
                ),
                if (footer != null) footer,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _full(SurfaceLayout layout) {
    final landscape = layout.landscape;
    final image = _image(landscape);
    final footer = _footer(layout, const EdgeInsets.fromLTRB(24, 8, 24, 0));
    return Material(
      color: theme.background,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          layout.safe.left,
          layout.safe.top + 8,
          layout.safe.right,
          math.max(layout.safe.bottom, 12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: _close,
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: math.max(0, constraints.maxHeight - 32),
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: kSurfaceContentMaxWidth,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            if (image != null) ...<Widget>[
                              image,
                              const SizedBox(height: 24),
                            ],
                            _text(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (footer != null) SurfaceMeasure(child: footer),
          ],
        ),
      ),
    );
  }

  Widget _slide(SurfaceLayout layout) {
    final image = _image(layout.landscape);
    final footer = _footer(layout, const EdgeInsets.only(top: 2));
    final bottom = math.max(layout.safe.bottom, 12.0) + 4;
    // Floats as a card above the home indicator, centred and capped to a
    // readable width in landscape so it never meets the cutout.
    return Padding(
      padding: EdgeInsets.fromLTRB(
        layout.safe.left + 12,
        0,
        layout.safe.right + 12,
        bottom,
      ),
      child: Align(
        alignment: Alignment.bottomCenter,
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth:
                layout.landscape ? kSurfaceContentMaxWidth : double.infinity,
            maxHeight: math.max(
              160,
              layout.size.height - layout.safe.top - bottom - 24,
            ),
          ),
          child: Material(
              color: theme.background,
              clipBehavior: Clip.antiAlias,
              shape: _cardShape,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Flexible(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          _close,
                          const SizedBox(width: 4),
                          Expanded(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: <Widget>[
                                  _text(),
                                  if (image != null) ...<Widget>[
                                    const SizedBox(height: 10),
                                    image,
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (footer != null) ...<Widget>[
                      const SizedBox(height: 10),
                      footer,
                    ],
                  ],
                ),
              ),
            ),
        ),
      ),
    );
  }
}
