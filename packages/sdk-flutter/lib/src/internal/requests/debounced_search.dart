// PORTED FROM: packages/sdk-react-native/src/internal/requests.ts
//                (createDebouncedSearch — 300ms typeahead helper)
//
// Coalesces rapid query() calls so only the latest survives the debounce
// window. A monotonically increasing sequence number drops in-flight
// requests whose result returns after a newer query was issued — typeahead
// never flickers a stale result.

import 'dart:async';

typedef DebouncedListener<TResult> = void Function(String q, TResult r);

class DebouncedSearch<TResult> {
  DebouncedSearch({
    required Future<TResult> Function(String q) fn,
    Duration delay = const Duration(milliseconds: 300),
  })  : _fn = fn,
        _delay = delay;

  final Future<TResult> Function(String q) _fn;
  final Duration _delay;

  Timer? _timer;
  int _lastSeq = 0;
  final Map<int, DebouncedListener<TResult>> _listeners =
      <int, DebouncedListener<TResult>>{};
  int _listenerSeq = 0;

  void query(String q) {
    _timer?.cancel();
    _lastSeq++;
    final seq = _lastSeq;
    _timer = Timer(_delay, () {
      _fn(q).then((TResult r) {
        // Drop stale results: another query has fired since.
        if (seq != _lastSeq) return;
        final snapshot = _listeners.values.toList(growable: false);
        for (final cb in snapshot) {
          cb(q, r);
        }
      }).catchError((_) {
        // Swallow — RN reference renders nothing on error and lets the
        // user "post anyway".
      });
    });
  }

  /// Subscribe to debounced results. Returns an unsubscribe closure.
  void Function() subscribe(DebouncedListener<TResult> cb) {
    final token = ++_listenerSeq;
    _listeners[token] = cb;
    return () {
      _listeners.remove(token);
    };
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    _lastSeq++;
  }
}
