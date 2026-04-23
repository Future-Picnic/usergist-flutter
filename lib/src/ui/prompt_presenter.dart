import 'dart:async';

import 'package:flutter/material.dart';

import '../internal/logger.dart';
import '../models/prompt.dart';
import '../models/response_info.dart';
import '../models/theme.dart';
import 'prompt_sheet.dart';

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
    this.themeOverrides,
  });

  /// Stream of show-requests.
  final Stream<PromptShowRequest> stream;

  /// Called when the user responds / dismisses.
  final OnPromptResponded onResponded;

  /// Called when a prompt successfully renders.
  final ValueChanged<String> onShown;

  /// Current theme overrides (updated via [updateThemeOverrides]).
  PromptTheme? themeOverrides;

  StreamSubscription<PromptShowRequest>? _sub;
  BuildContext? _context;
  bool _isPresenting = false;

  /// Attaches the presenter to a Navigator-owning context.
  void attach(BuildContext context) {
    _context = context;
    _sub ??= stream.listen(_handle);
  }

  /// Detaches the presenter (stops listening / drops the context).
  Future<void> detach() async {
    await _sub?.cancel();
    _sub = null;
    _context = null;
    _isPresenting = false;
  }

  /// Replaces the stored theme overrides.
  void updateThemeOverrides(PromptTheme? theme) {
    themeOverrides = theme;
  }

  Future<void> _handle(PromptShowRequest req) async {
    if (_isPresenting) {
      log.d('skip prompt ${req.prompt.id}: another already presenting');
      return;
    }
    final ctx = _context;
    if (ctx == null || !ctx.mounted) {
      log.w('no navigator context — cannot present prompt ${req.prompt.id}');
      return;
    }
    _isPresenting = true;
    final startedAt = DateTime.now();
    try {
      onShown(req.prompt.id);
      final PromptSheetResult? result =
          await showModalBottomSheet<PromptSheetResult>(
        context: ctx,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black.withAlpha(128),
        builder: (_) => PromptSheet(
          prompt: req.prompt,
          themeOverrides: themeOverrides,
        ),
      );
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
    } on Object catch (err, st) {
      log.e('prompt presentation failed', err, st);
    } finally {
      _isPresenting = false;
    }
  }
}
