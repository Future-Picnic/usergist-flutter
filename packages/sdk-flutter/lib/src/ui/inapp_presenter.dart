import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../internal/logger.dart';
import '../models/inapp_message.dart';
import '../models/theme.dart';
import 'inapp_layout.dart';
import 'theme_resolver.dart';
import 'modal_coordinator.dart';

/// Request emitted by the authenticated instruction inbox.
class InAppShowRequest {
  const InAppShowRequest({required this.message, this.isValid});

  final ArmedInAppMessage message;

  final bool Function()? isValid;
}

enum _InAppOutcomeKind { dismissed, autoDismissed, cta }

class _InAppOutcome {
  const _InAppOutcome.dismissed()
      : kind = _InAppOutcomeKind.dismissed,
        cta = null,
        index = null;
  const _InAppOutcome.autoDismissed()
      : kind = _InAppOutcomeKind.autoDismissed,
        cta = null,
        index = null;
  const _InAppOutcome.cta(this.cta, this.index) : kind = _InAppOutcomeKind.cta;

  final _InAppOutcomeKind kind;
  final InAppCta? cta;
  final int? index;
}

/// Presents modal, full-screen, and slide-up messages with native Material
/// routes while keeping lifecycle reporting independent from host analytics.
class InAppPresenter {
  InAppPresenter({
    required this.stream,
    required this.onShown,
    required this.onDismissed,
    required this.onCta,
    required this.coordinator,
    this.themeOverrides,
  });

  final Stream<InAppShowRequest> stream;
  final ValueChanged<String> onShown;
  final void Function(String messageId, String reason) onDismissed;
  final void Function(String messageId, InAppCta cta, int index) onCta;
  final SdkModalCoordinator coordinator;
  PromptTheme? themeOverrides;

  StreamSubscription<InAppShowRequest>? _subscription;
  BuildContext? _context;
  bool _isPresenting = false;
  bool _routeActive = false;
  bool _suppressOutcome = false;
  final List<InAppShowRequest> _pending = <InAppShowRequest>[];

  void attach(BuildContext context) {
    _context = context;
    _subscription ??= stream.listen((request) {
      _pending.add(request);
      unawaited(_drain());
    });
    unawaited(_drain());
  }

  Future<void> detach() async {
    await _subscription?.cancel();
    _subscription = null;
    _context = null;
    _pending.clear();
    _isPresenting = false;
  }

  /// Clears queued messages and closes an active SDK route without reporting
  /// a user dismissal or CTA.
  Future<void> reset() async {
    _pending.clear();
    final context = _context;
    if (!_routeActive || context == null || !context.mounted) return;
    _suppressOutcome = true;
    await Navigator.of(context, rootNavigator: true).maybePop();
  }

  void updateThemeOverrides(PromptTheme? theme) {
    themeOverrides = theme;
  }

  Future<void> _drain() async {
    final context = _context;
    if (_isPresenting ||
        _pending.isEmpty ||
        context == null ||
        !context.mounted) {
      return;
    }
    final request = _pending.removeAt(0);
    _isPresenting = true;
    try {
      await coordinator.schedule(() async {
        if (!context.mounted) {
          _pending.insert(0, request);
          return;
        }
        _routeActive = true;
        final presentation = _show(context, request.message);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_routeActive) onShown(request.message.messageId);
        });
        final outcome = await presentation;
        _routeActive = false;
        if (_suppressOutcome) {
          _suppressOutcome = false;
          return;
        }
        if (outcome == null || outcome.kind == _InAppOutcomeKind.dismissed) {
          onDismissed(request.message.messageId, 'user');
        } else if (outcome.kind == _InAppOutcomeKind.autoDismissed) {
          onDismissed(request.message.messageId, 'auto');
        } else {
          final cta = outcome.cta!;
          final index = outcome.index!;
          onCta(request.message.messageId, cta, index);
          await _openTarget(cta);
        }
      }, isValid: request.isValid);
    } on Object catch (error, stack) {
      log.e('in-app presentation failed', error, stack);
    } finally {
      _routeActive = false;
      _isPresenting = false;
      unawaited(_drain());
    }
  }

  Future<_InAppOutcome?> _show(
    BuildContext context,
    ArmedInAppMessage message,
  ) {
    if (message.format == 'slideup') {
      return showModalBottomSheet<_InAppOutcome>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        // The floating card sizes itself; Material 3 would cap the route.
        constraints: const BoxConstraints(),
        barrierColor: message.backdropEnabled
            ? const Color(0x73000000)
            : Colors.transparent,
        builder: (routeContext) => _InAppSurface(
          message: message,
          themeOverrides: themeOverrides,
          presentation: _InAppPresentation.slideup,
        ),
      );
    }

    return showGeneralDialog<_InAppOutcome>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: message.format == 'modal_full' || !message.backdropEnabled
          ? Colors.transparent
          : const Color(0x73000000),
      transitionDuration: const Duration(milliseconds: 220),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(opacity: curved, child: child);
      },
      pageBuilder: (routeContext, _, __) => _InAppSurface(
        message: message,
        themeOverrides: themeOverrides,
        presentation: message.format == 'modal_full'
            ? _InAppPresentation.full
            : _InAppPresentation.modal,
      ),
    );
  }

  Future<void> _openTarget(InAppCta cta) async {
    if (cta.action != 'open_url' && cta.action != 'deep_link') return;
    final target = cta.target;
    final uri = target == null ? null : Uri.tryParse(target);
    if (uri == null || !uri.hasScheme) {
      log.w('in-app CTA has an invalid target');
      return;
    }
    if (!await launchUrl(uri)) {
      log.w('unable to open in-app CTA target');
    }
  }
}

enum _InAppPresentation { modal, full, slideup }

class _InAppSurface extends StatefulWidget {
  const _InAppSurface({
    required this.message,
    required this.themeOverrides,
    required this.presentation,
  });

  final ArmedInAppMessage message;
  final PromptTheme? themeOverrides;
  final _InAppPresentation presentation;

  @override
  State<_InAppSurface> createState() => _InAppSurfaceState();
}

class _InAppSurfaceState extends State<_InAppSurface> {
  Timer? _autoDismissTimer;

  @override
  void initState() {
    super.initState();
    final seconds = widget.message.autoDismissSeconds;
    if (widget.presentation == _InAppPresentation.slideup &&
        seconds != null &&
        seconds > 0) {
      _autoDismissTimer = Timer(
        Duration(milliseconds: (seconds * 1000).round()),
        () {
          if (mounted) {
            Navigator.of(context).pop(const _InAppOutcome.autoDismissed());
          }
        },
      );
    }
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final messageTheme = PromptTheme(
      colors: PromptThemeColors(
        primary: _parseHex(widget.message.accentColor),
        background: _parseHex(widget.message.backgroundColor),
      ),
    );
    final theme = ResolvedPromptTheme.of(
      context,
      serverTheme: messageTheme,
      overrides: widget.themeOverrides,
    );
    return InAppMessageLayout(
      message: widget.message,
      theme: theme,
      format: switch (widget.presentation) {
        _InAppPresentation.full => InAppFormat.full,
        _InAppPresentation.slideup => InAppFormat.slide,
        _InAppPresentation.modal => InAppFormat.card,
      },
      onClose: () => Navigator.of(context).pop(
        const _InAppOutcome.dismissed(),
      ),
      onCta: (cta, index) => Navigator.of(context).pop(
        _InAppOutcome.cta(cta, index),
      ),
    );
  }

  Color? _parseHex(String? value) {
    if (value == null) return null;
    final normalized = value.startsWith('#') ? value.substring(1) : value;
    if (normalized.length != 6 && normalized.length != 8) return null;
    final parsed = int.tryParse(normalized, radix: 16);
    if (parsed == null) return null;
    return Color(normalized.length == 6 ? 0xff000000 | parsed : parsed);
  }

}
