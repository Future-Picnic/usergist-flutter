import 'dart:async';

import 'package:flutter/material.dart';

import '../internal/logger.dart';
import '../models/prompt.dart';
import '../models/response_info.dart';
import '../models/theme.dart';
import 'prompt_sheet.dart';
import 'modal_coordinator.dart';

/// Lightweight representation of a "show this prompt" request emitted
/// from the SDK core to the UI layer.
class PromptShowRequest {
  /// Creates a request.
  const PromptShowRequest({required this.prompt});

  /// Prompt to show.
  final ClientPrompt prompt;
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
        _routeActive = true;
        final presentation = showModalBottomSheet<PromptSheetResult>(
          context: ctx,
          useRootNavigator: true,
          isScrollControlled: true,
          enableDrag: false,
          backgroundColor: Colors.transparent,
          barrierColor: Colors.black.withAlpha(128),
          builder: (_) => PromptSheet(
            prompt: req.prompt,
            themeOverrides: themeOverrides,
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
            answers: result?.answers ?? const <ResponseAnswer>[],
            latencyMs: latency,
          ),
        );
      });
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
