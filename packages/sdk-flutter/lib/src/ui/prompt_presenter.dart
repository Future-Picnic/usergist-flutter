import 'dart:async';

import 'package:flutter/material.dart';

import '../internal/logger.dart';
import '../models/prompt.dart';
import '../models/response_info.dart';
import '../models/theme.dart';
import 'prompt_sheet.dart';
import 'modal_coordinator.dart';
import 'theme_resolver.dart';

/// Lightweight representation of a "show this prompt" request emitted
/// from the SDK core to the UI layer.
class PromptShowRequest {
  /// Creates a request.
  const PromptShowRequest({required this.prompt, this.isValid});

  /// Prompt to show.
  final ClientPrompt prompt;

  final bool Function()? isValid;
}

/// Callback signature used by [PromptPresenter] to report the
/// user's response/dismissal back to the SDK core.
typedef OnPromptResponded = void Function(PromptResponseInfo info);

/// Owns the Navigator context and is responsible for actually
/// showing a prompt when a [PromptShowRequest] arrives on a stream.
class PromptPresenter {
  /// Creates a presenter.
  PromptPresenter({
    required this.stream,
    required this.onResponded,
    required this.onShown,
    required this.onPresentationFailed,
    required this.coordinator,
    this.themeOverrides,
  });

  /// Stream of show-requests.
  final Stream<PromptShowRequest> stream;

  /// Called when the user responds / dismisses.
  final OnPromptResponded onResponded;

  /// Called when a prompt successfully renders.
  final ValueChanged<String> onShown;
  final ValueChanged<String> onPresentationFailed;
  final SdkModalCoordinator coordinator;

  /// Current theme overrides (updated via [updateThemeOverrides]).
  PromptTheme? themeOverrides;

  StreamSubscription<PromptShowRequest>? _sub;
  BuildContext? _context;
  bool _isPresenting = false;
  bool _routeActive = false;
  bool _suppressOutcome = false;
  final List<PromptShowRequest> _pending = <PromptShowRequest>[];
  String? _lastPromptId;
  ResolvedPromptTheme? _lastTheme;
  OverlayEntry? _savedNotice;
  Timer? _savedNoticeTimer;

  void _clearSavedNotice() {
    _savedNoticeTimer?.cancel();
    _savedNoticeTimer = null;
    _savedNotice?.remove();
    _savedNotice = null;
  }

  /// Acknowledges durable local storage, without claiming server delivery.
  void showSavedNotice(String promptId) {
    final context = _context;
    final theme = _lastTheme;
    if (context == null || !context.mounted || theme == null ||
        _lastPromptId != promptId) return;
    final overlay = Navigator.maybeOf(context, rootNavigator: true)?.overlay ??
        Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    _clearSavedNotice();
    final entry = OverlayEntry(builder: (_) => Positioned(
      left: 16, right: 16, bottom: 16,
      child: IgnorePointer(child: SafeArea(top: false, child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Semantics(liveRegion: true, child: Material(
            color: theme.background,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(theme.radius),
              side: BorderSide(color: theme.border),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Text('Feedback saved. We’ll send it automatically.',
                style: TextStyle(color: theme.text, fontFamily: theme.fontFamily,
                  fontSize: 14), textAlign: TextAlign.center),
            ),
          )),
        ),
      ))),
    ));
    _savedNotice = entry;
    overlay.insert(entry);
    _savedNoticeTimer = Timer(const Duration(seconds: 4), _clearSavedNotice);
  }

  /// Attaches the presenter to a Navigator-owning context.
  void attach(BuildContext context) {
    _context = context;
    _sub ??= stream.listen((request) {
      _pending.add(request);
      unawaited(_drain());
    });
    unawaited(_drain());
  }

  /// Detaches the presenter (stops listening / drops the context).
  Future<void> detach() async {
    _clearSavedNotice();
    _lastPromptId = null;
    await _sub?.cancel();
    _sub = null;
    _context = null;
    for (final request in _pending) {
      onPresentationFailed(request.prompt.id);
    }
    _pending.clear();
    _isPresenting = false;
  }

  /// Clears queued prompts and closes an active SDK prompt without producing
  /// a synthetic user dismissal.
  Future<void> reset() async {
    _clearSavedNotice();
    _lastPromptId = null;
    _pending.clear();
    final context = _context;
    if (!_routeActive || context == null || !context.mounted) return;
    _suppressOutcome = true;
    await Navigator.of(context, rootNavigator: true).maybePop();
  }

  /// Replaces the stored theme overrides.
  void updateThemeOverrides(PromptTheme? theme) {
    themeOverrides = theme;
  }

  Future<void> _drain() async {
    final ctx = _context;
    if (_isPresenting || _pending.isEmpty || ctx == null || !ctx.mounted) {
      return;
    }
    final req = _pending.removeAt(0);
    _isPresenting = true;
    try {
      await coordinator.schedule(() async {
        if (!ctx.mounted) {
          _pending.insert(0, req);
          return;
        }
        final startedAt = DateTime.now();
        _lastPromptId = req.prompt.id;
        _lastTheme = ResolvedPromptTheme.of(ctx,
          serverTheme: req.prompt.theme, overrides: themeOverrides);
        var partialAnswers = const <ResponseAnswer>[];
        _routeActive = true;
        final presentation = showModalBottomSheet<PromptSheetResult>(
          context: ctx,
          useRootNavigator: true,
          isScrollControlled: true,
          enableDrag: false,
          backgroundColor: Colors.transparent,
          elevation: 0,
          // The sheet background spans the full screen width in every
          // orientation; Material 3 would otherwise cap it at 640.
          constraints: const BoxConstraints(),
          barrierColor: const Color(0x73000000),
          builder: (_) => PromptSheet(
            prompt: req.prompt,
            themeOverrides: themeOverrides,
            onAnswersChanged: (answers) => partialAnswers = answers,
          ),
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_routeActive) onShown(req.prompt.id);
        });
        final PromptSheetResult? result = await presentation;
        _routeActive = false;
        if (_suppressOutcome) {
          _suppressOutcome = false;
          return;
        }
        final latency = DateTime.now().difference(startedAt).inMilliseconds;
        final dismissed = result == null || result.dismissed;
        onResponded(
          PromptResponseInfo(
            promptId: req.prompt.id,
            dismissed: dismissed,
            answers: result?.answers ?? partialAnswers,
            latencyMs: latency,
          ),
        );
      }, isValid: req.isValid);
    } on Object catch (err, st) {
      onPresentationFailed(req.prompt.id);
      log.e('prompt presentation failed', err, st);
    } finally {
      _routeActive = false;
      _isPresenting = false;
      unawaited(_drain());
    }
  }
}
