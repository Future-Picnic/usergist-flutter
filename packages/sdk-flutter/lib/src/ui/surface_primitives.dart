// Content primitives shared by feedback, survey, message and request
// surfaces: title block, selectable choice row and text field. Theme colours
// only — no fixed greys.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'surface_tokens.dart';
import 'text_answer_decoration.dart';
import 'theme_resolver.dart';

/// Optional 16:9 question photo with the theme radius.
class SurfaceImage extends StatelessWidget {
  /// Creates the image header.
  const SurfaceImage({
    required this.url,
    required this.theme,
    this.aspectRatio = 16 / 9,
    this.height,
    super.key,
  });

  /// Image URL.
  final String url;

  /// Resolved theme.
  final ResolvedPromptTheme theme;

  /// Aspect ratio when [height] is null.
  final double aspectRatio;

  /// Fixed height (messages); overrides [aspectRatio].
  final double? height;

  @override
  Widget build(BuildContext context) {
    final image = Image.network(
      url,
      fit: BoxFit.cover,
      width: double.infinity,
      height: height,
      excludeFromSemantics: true,
      errorBuilder: (_, __, ___) => ColoredBox(color: theme.fill),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(math.max(8, theme.radius - 6)),
      child: ColoredBox(
        color: theme.fill,
        child: height == null
            ? AspectRatio(aspectRatio: aspectRatio, child: image)
            : SizedBox(height: height, child: image),
      ),
    );
  }
}

/// Title, optional subtitle and optional image above a question control.
class QuestionHeader extends StatelessWidget {
  /// Creates the header block.
  const QuestionHeader({
    required this.title,
    required this.theme,
    this.subtitle,
    this.imageUrl,
    this.center = false,
    super.key,
  });

  /// Question title.
  final String title;

  /// Optional subtitle.
  final String? subtitle;

  /// Optional image URL.
  final String? imageUrl;

  /// Resolved theme.
  final ResolvedPromptTheme theme;

  /// Centre the text (rating, wide NPS).
  final bool center;

  @override
  Widget build(BuildContext context) {
    final align = center ? TextAlign.center : TextAlign.start;
    final sub = subtitle;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (imageUrl case final url?) ...<Widget>[
            SurfaceImage(url: url, theme: theme),
            const SizedBox(height: 16),
          ],
          Semantics(
            header: true,
            child: Text(
              title,
              textAlign: align,
              style: theme.textStyle(
                color: theme.text,
                fontSize: 20,
                lineHeight: 26,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
          ),
          if (sub != null && sub.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              sub,
              textAlign: align,
              style: theme.textStyle(
                color: theme.subtext,
                fontSize: 15,
                lineHeight: 21,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Indicator style of a [ChoiceRow].
enum ChoiceKind {
  /// Single selection.
  radio,

  /// Multiple selection.
  checkbox,
}

/// Selectable row. Selection is shown with a tinted fill, a primary border
/// and a radio/checkbox indicator — never a solid flood of the brand colour,
/// which hides the label on light primaries and shouts on dark ones.
class ChoiceRow extends StatelessWidget {
  /// Creates the row.
  const ChoiceRow({
    required this.label,
    required this.selected,
    required this.kind,
    required this.onTap,
    required this.theme,
    this.detail,
    super.key,
  });

  /// Option label.
  final String label;

  /// Optional secondary line.
  final String? detail;

  /// Whether this option is chosen.
  final bool selected;

  /// Indicator style.
  final ChoiceKind kind;

  /// Tap handler.
  final VoidCallback onTap;

  /// Resolved theme.
  final ResolvedPromptTheme theme;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(theme.choiceRadius);
    final extra = detail;
    return Semantics(
      button: kind == ChoiceKind.radio,
      inMutuallyExclusiveGroup: kind == ChoiceKind.radio,
      checked: selected,
      selected: selected,
      label: label,
      container: true,
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: selected ? theme.tint : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: selected ? theme.primary : theme.border,
            width: 1.5,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          highlightColor: theme.fill,
          splashColor: theme.fill,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          label,
                          style: theme.textStyle(
                            color: theme.text,
                            lineHeight: 21,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (extra != null && extra.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 2),
                          Text(
                            extra,
                            style: theme.textStyle(
                              color: theme.subtext,
                              fontSize: 13,
                              lineHeight: 18,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  _Indicator(kind: kind, selected: selected, theme: theme),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Indicator extends StatelessWidget {
  const _Indicator({
    required this.kind,
    required this.selected,
    required this.theme,
  });

  final ChoiceKind kind;
  final bool selected;
  final ResolvedPromptTheme theme;

  @override
  Widget build(BuildContext context) {
    final accent = theme.primary;
    final border = selected ? accent : surfaceWithOpacity(theme.text, 0.25);
    if (kind == ChoiceKind.radio) {
      return Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: border, width: 1.75),
        ),
        alignment: Alignment.center,
        child: selected
            ? Container(
                width: 10,
                height: 10,
                decoration:
                    BoxDecoration(color: accent, shape: BoxShape.circle),
              )
            : null,
      );
    }
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: selected ? accent : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: border, width: 1.75),
      ),
      child: selected
          ? CustomPaint(painter: _TickPainter(theme.onPrimary))
          : null,
    );
  }
}

class _TickPainter extends CustomPainter {
  const _TickPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(c.dx - 4, c.dy)
      ..lineTo(c.dx - 1.2, c.dy + 2.8)
      ..lineTo(c.dx + 4.2, c.dy - 2.6);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_TickPainter old) => old.color != color;
}

/// Text field with a visible focus state and optional character count.
class SurfaceField extends StatefulWidget {
  /// Creates the field.
  const SurfaceField({
    required this.theme,
    required this.controller,
    this.onChanged,
    this.hintText,
    this.maxLength,
    this.multiline = false,
    this.minHeight,
    this.autofocus = false,
    this.semanticsLabel,
    this.keyboardType,
    this.textInputAction,
    this.fieldKey,
    super.key,
  });

  /// Resolved theme.
  final ResolvedPromptTheme theme;

  /// Text controller owned by the caller.
  final TextEditingController controller;

  /// Change handler.
  final ValueChanged<String>? onChanged;

  /// Placeholder.
  final String? hintText;

  /// Maximum characters; shows a counter when set.
  final int? maxLength;

  /// Multi-line field.
  final bool multiline;

  /// Minimum height for multi-line fields.
  final double? minHeight;

  /// Focus when first shown.
  final bool autofocus;

  /// Accessibility label.
  final String? semanticsLabel;

  /// Keyboard type.
  final TextInputType? keyboardType;

  /// Keyboard action.
  final TextInputAction? textInputAction;

  /// Key applied to the inner [TextField].
  final Key? fieldKey;

  @override
  State<SurfaceField> createState() => _SurfaceFieldState();
}

class _SurfaceFieldState extends State<SurfaceField>
    with WidgetsBindingObserver {
  final FocusNode _focus = FocusNode();
  final GlobalKey _blockKey = GlobalKey();
  bool _revealScheduled = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onText);
    _focus.addListener(_reveal);
    WidgetsBinding.instance.addObserver(this);
  }

  // The keyboard opening or changing height reports new window metrics.
  @override
  void didChangeMetrics() => _reveal();

  /// Keeps the whole focused field — first line through counter — inside
  /// the enclosing scroll view above the keyboard. Flutter's default only
  /// guarantees the caret, which can leave a multi-line field's first line
  /// or the counter hidden in short landscape viewports.
  void _reveal() {
    if (!_focus.hasFocus || _revealScheduled) return;
    _revealScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _revealScheduled = false;
      final target = _blockKey.currentContext;
      if (!mounted || !_focus.hasFocus || target == null) return;
      if (Scrollable.maybeOf(target) == null) return;
      // Start first so the top line is never above the viewport, then end so
      // the counter clears the keyboard. When the field is taller than the
      // viewport the second pass is limited by the first line staying put.
      await Scrollable.ensureVisible(
        target,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      );
      if (!mounted || !target.mounted) return;
      final box = target.findRenderObject();
      final viewport = Scrollable.maybeOf(target)?.context.findRenderObject();
      if (box is RenderBox &&
          viewport is RenderBox &&
          box.size.height > viewport.size.height) {
        return;
      }
      await Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    });
  }

  @override
  void didUpdateWidget(SurfaceField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onText);
      widget.controller.addListener(_onText);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_onText);
    _focus.dispose();
    super.dispose();
  }

  void _onText() {
    if (mounted && widget.maxLength != null) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final max = widget.maxLength;
    final length = widget.controller.text.length;
    final near = max != null && length >= max * 0.9;
    final minLines = widget.multiline
        ? math.max(1, (((widget.minHeight ?? 112) - 28) / 22).ceil())
        : 1;
    final field = TextField(
      key: widget.fieldKey,
      controller: widget.controller,
      focusNode: _focus,
      onChanged: widget.onChanged,
      maxLength: max,
      minLines: minLines,
      maxLines: widget.multiline ? math.max(minLines + 2, 6) : 1,
      autofocus: widget.autofocus,
      keyboardType: widget.keyboardType ??
          (widget.multiline ? TextInputType.multiline : null),
      textInputAction: widget.textInputAction,
      cursorColor: theme.primary,
      style: theme.textStyle(color: theme.text, lineHeight: 22),
      decoration: textAnswerDecoration(theme: theme, hintText: widget.hintText),
    );
    return Column(
      key: _blockKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (widget.semanticsLabel case final label?)
          Semantics(label: label, textField: true, child: field)
        else
          field,
        if (max != null) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            '$length/$max',
            textAlign: TextAlign.end,
            style: theme.textStyle(
              color: near ? theme.text : theme.subtext,
              fontSize: 12,
              tabular: true,
            ),
          ),
        ],
      ],
    );
  }
}

/// Inline, theme-coloured notice with an optional action (errors, retry).
class SurfaceNotice extends StatelessWidget {
  /// Creates the notice.
  const SurfaceNotice({
    required this.message,
    required this.theme,
    this.action,
    super.key,
  });

  /// Message text.
  final String message;

  /// Resolved theme.
  final ResolvedPromptTheme theme;

  /// Optional action (for example "Try again").
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final trailing = action;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.fill,
          borderRadius: BorderRadius.circular(theme.fieldRadius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              message,
              style: theme.textStyle(
                color: theme.text,
                fontSize: 15,
                lineHeight: 21,
              ),
            ),
            if (trailing != null) ...<Widget>[
              const SizedBox(height: 12),
              trailing,
            ],
          ],
        ),
      ),
    );
  }
}
