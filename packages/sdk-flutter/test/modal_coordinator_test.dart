import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:usergist_feedback/src/ui/modal_coordinator.dart';

void main() {
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
