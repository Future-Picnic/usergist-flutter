import 'dart:async';

/// Host readiness and validity of campaign work, independent from analytics.
class PresentationGate {
  bool paused = false;
  int _identity = 0;
  final Map<String, int> _revisions = <String, int>{'feedback': 0, 'survey': 0};
  final Set<void Function()> _listeners = <void Function()>{};
  final List<({void Function() run, bool Function() valid})> _pending = [];

  void setPaused(bool value) {
    paused = value;
    _notify();
  }

  void invalidate([String? purpose]) {
    if (purpose == null) {
      _identity++;
    } else {
      _revisions[purpose] = (_revisions[purpose] ?? 0) + 1;
    }
    _notify();
  }

  bool Function() validator(String purpose) {
    final identity = _identity;
    final revision = _revisions[purpose];
    return () => identity == _identity && revision == _revisions[purpose];
  }

  void dispatch(void Function() run, bool Function() valid) {
    if (!valid()) return;
    if (!paused) { run(); return; }
    if (_pending.length < 100) _pending.add((run: run, valid: valid));
  }

  Future<bool> waitUntilReady(bool Function() valid) {
    if (!valid()) return Future<bool>.value(false);
    if (!paused) return Future<bool>.value(true);
    final completer = Completer<bool>();
    late final void Function() listener;
    listener = () {
      if (valid() && paused) return;
      _listeners.remove(listener);
      completer.complete(valid());
    };
    _listeners.add(listener);
    return completer.future;
  }

  void _notify() {
    _pending.removeWhere((task) => !task.valid());
    for (final listener in List<void Function()>.of(_listeners)) { listener(); }
    while (!paused && _pending.isNotEmpty) {
      final task = _pending.removeAt(0);
      if (task.valid()) task.run();
    }
  }
}
