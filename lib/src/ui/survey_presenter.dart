import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../internal/logger.dart';
import '../models/survey.dart';
import '../models/theme.dart';
import 'modal_coordinator.dart';
import 'surface_controls.dart';
import 'surface_primitives.dart';
import 'surface_tokens.dart';
import 'survey_questions.dart';
import 'theme_resolver.dart';

part 'survey_screen.dart';

class SurveyShowRequest {
  const SurveyShowRequest({
    this.isValid,
    required this.survey,
    required this.attempt,
    required this.source,
  });

  final SurveyCampaignWithFlow survey;
  final SurveyAttemptSession attempt;
  final String source;

  final bool Function()? isValid;
}

/// Owns the host Navigator context and serializes native survey routes.
class SurveyPresenter {
  SurveyPresenter({
    required this.stream,
    required this.onSaveProgress,
    required this.onCompleteAttempt,
    required this.onAbandonAttempt,
    required this.onShown,
    required this.onPresentationFailed,
    required this.onComplete,
    required this.onAbandon,
    required this.coordinator,
    this.themeOverrides,
  });

  final Stream<SurveyShowRequest> stream;
  final Future<void> Function(
    String attemptId,
    String? currentQuestionId,
    Map<String, Object?> answers,
  ) onSaveProgress;
  final Future<bool> Function(
    String attemptId,
    Map<String, Object?> answers,
  ) onCompleteAttempt;
  final Future<bool> Function(String attemptId) onAbandonAttempt;
  final ValueChanged<String> onShown;
  final ValueChanged<String> onPresentationFailed;
  final void Function(String surveyId, String attemptId) onComplete;
  final void Function(String surveyId, String attemptId) onAbandon;
  final SdkModalCoordinator coordinator;
  PromptTheme? themeOverrides;

  StreamSubscription<SurveyShowRequest>? _subscription;
  BuildContext? _context;
  final List<SurveyShowRequest> _pending = <SurveyShowRequest>[];
  bool _isPresenting = false;
  bool _routeActive = false;

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
    for (final request in _pending) {
      onPresentationFailed(request.survey.id);
    }
    _pending.clear();
    _isPresenting = false;
  }

  /// Clears queued surveys and closes the active SDK survey route without
  /// emitting an abandon lifecycle event.
  Future<void> reset() async {
    _pending.clear();
    final context = _context;
    if (!_routeActive || context == null || !context.mounted) return;
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
    _isPresenting = true;
    final request = _pending.removeAt(0);
    try {
      await coordinator.schedule(() async {
        if (!context.mounted) {
          _pending.insert(0, request);
          return;
        }
        _routeActive = true;
        await Navigator.of(context, rootNavigator: true).push<void>(
          MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => _SurveyScreen(
              request: request,
              themeOverrides: themeOverrides,
              onSaveProgress: onSaveProgress,
              onCompleteAttempt: onCompleteAttempt,
              onAbandonAttempt: onAbandonAttempt,
              onShown: onShown,
              onComplete: onComplete,
              onAbandon: onAbandon,
            ),
          ),
        );
        _routeActive = false;
      }, isValid: request.isValid);
    } on Object catch (error, stack) {
      onPresentationFailed(request.survey.id);
      log.e('survey presentation failed', error, stack);
    } finally {
      _routeActive = false;
      _isPresenting = false;
      unawaited(_drain());
    }
  }
}
