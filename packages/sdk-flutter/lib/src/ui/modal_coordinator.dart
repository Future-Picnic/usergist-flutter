import 'dart:async';
import '../internal/presentation_gate.dart';

/// Serializes SDK-owned Navigator routes so prompts, surveys, and in-app
/// messages never overlap or disappear while another SDK surface is active.
class SdkModalCoordinator {
  SdkModalCoordinator({PresentationGate? gate}) : gate = gate ?? PresentationGate();
  final PresentationGate gate;
  final List<_ModalTask> _pending = <_ModalTask>[];
  bool _running = false;

  Future<void> schedule(Future<void> Function() action, {bool Function()? isValid}) {
    final completer = Completer<void>();
    _pending.add(_ModalTask(action, completer, isValid ?? () => true));
    unawaited(_drain());
    return completer.future;
  }

  /// Drops work that has not started. Active routes are dismissed by their
  /// owning presenter so unrelated host routes are never popped.
  void clearPending() {
    final dropped = List<_ModalTask>.of(_pending);
    _pending.clear();
    for (final task in dropped) {
      if (!task.completer.isCompleted) task.completer.complete();
    }
  }

  Future<void> _drain() async {
    if (_running || _pending.isEmpty) return;
    _running = true;
    final task = _pending.removeAt(0);
    try {
      while (task.isValid() && gate.paused) {
        await gate.waitUntilReady(task.isValid);
      }
      if (task.isValid()) await task.action();
      task.completer.complete();
    } on Object catch (error, stack) {
      task.completer.completeError(error, stack);
    } finally {
      _running = false;
      unawaited(_drain());
    }
  }
}

class _ModalTask {
  const _ModalTask(this.action, this.completer, this.isValid);

  final bool Function() isValid;

  final Future<void> Function() action;
  final Completer<void> completer;
}
