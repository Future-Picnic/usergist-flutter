import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:usergist_feedback/src/ui/modal_coordinator.dart';
import 'package:usergist_feedback/src/internal/presentation_gate.dart';

void main() {
  test('pauses routes, cancels stale identity work, and resumes fresh work once', () async {
    final gate = PresentationGate()..setPaused(true);
    final coordinator = SdkModalCoordinator(gate: gate);
    final shown = <String>[];
    final first = coordinator.schedule(() async { shown.add('old'); }, isValid: gate.validator('feedback'));
    gate.invalidate();
    final second = coordinator.schedule(() async { shown.add('new'); }, isValid: gate.validator('feedback'));
    expect(shown, isEmpty);
    gate.setPaused(false);
    gate.setPaused(false);
    await Future.wait([first, second]);
    expect(shown, ['new']);
  });

  test('revocation drops buffered delivery and does not revive it after regrant', () {
    final gate = PresentationGate()..setPaused(true);
    final shown = <String>[];
    gate.dispatch(() { shown.add('feedback'); }, gate.validator('feedback'));
    gate.dispatch(() { shown.add('survey'); }, gate.validator('survey'));
    gate.invalidate('feedback');
    gate.setPaused(false);
    expect(shown, ['survey']);
  });

  test('pause after scheduling still holds the next route', () async {
    final gate = PresentationGate();
    final coordinator = SdkModalCoordinator(gate: gate);
    final active = Completer<void>();
    final shown = <String>[];
    final first = coordinator.schedule(() => active.future);
    final second = coordinator.schedule(() async { shown.add('second'); });
    gate.setPaused(true);
    active.complete();
    await first;
    expect(shown, isEmpty);
    gate.setPaused(false);
    await second;
    expect(shown, ['second']);
  });

  test('clearPending drops queued routes without interrupting the active one',
      () async {
    final coordinator = SdkModalCoordinator();
    final active = Completer<void>();
    var queuedStarted = false;

    final first = coordinator.schedule(() => active.future);
    final second = coordinator.schedule(() async {
      queuedStarted = true;
    });
    coordinator.clearPending();
    active.complete();

    await Future.wait<void>(<Future<void>>[first, second]);
    expect(queuedStarted, isFalse);
  });
}
