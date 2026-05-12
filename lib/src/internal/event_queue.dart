import 'dart:async';
import 'dart:collection';
import 'dart:io';

import '../models/event.dart';
import 'json.dart';
import 'logger.dart';

// PORTED FROM: packages/sdk-react-native/src/internal/queue.ts
//
// Persisted shape on disk:
//   <header line>: {"version":1}\n
//   <event line 1>: {...}\n
//   <event line 2>: {...}\n
//
// Bumped every time the on-disk shape changes; older snapshots are
// discarded rather than risk a deserialise mismatch. Events are
// best-effort, not durable contracts.
//
// Legacy migration: pre-versioning builds wrote bare {...}\n event lines
// with no header. On hydrate, if the first line is missing a "version"
// key, we treat the entire file as legacy events; the next _persist()
// rewrite emits the header.
const int _queueSchemaVersion = 1;
const String _queueHeaderLine = '{"version":$_queueSchemaVersion}';

/// Bounded, persistent FIFO queue of pending ingest events.
///
/// * Appends are non-blocking.
/// * On overflow, the oldest event is dropped.
/// * State is mirrored to a versioned JSON-lines file: a header line
///   `{"version":N}` followed by one [IngestEvent] per line. Rewritten
///   on every change.
class EventQueue {
  /// Creates a queue writing to [file] with [maxSize] elements max.
  EventQueue({required File file, required int maxSize})
      : _file = file,
        _maxSize = maxSize;

  final File _file;
  final int _maxSize;

  final Queue<IngestEvent> _buffer = Queue<IngestEvent>();
  int _dropped = 0;

  /// Number of events currently queued.
  int get length => _buffer.length;

  /// Total number of events dropped due to overflow since process start.
  int get droppedCount => _dropped;

  /// Returns `true` when the queue is empty.
  bool get isEmpty => _buffer.isEmpty;

  /// Hydrates from the backing file (if it exists).
  Future<void> hydrate() async {
    try {
      if (!await _file.exists()) return;
      final contents = await _file.readAsString();
      if (contents.isEmpty) return;
      final lines = contents.split('\n');
      var headerConsumed = false;
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        final map = safeDecodeMap(trimmed);
        if (map.isEmpty) continue;
        if (!headerConsumed) {
          headerConsumed = true;
          // Versioned header line: {"version": N}. Discard the whole
          // queue if N is unknown, skip if it matches; otherwise treat
          // as a legacy event line and fall through to parsing.
          if (map.containsKey('version') && map.length == 1) {
            final version = map['version'];
            if (version is int && version == _queueSchemaVersion) {
              continue;
            }
            log.w('queue hydrate: discarding unknown version $version');
            _buffer.clear();
            await _file.writeAsString('');
            return;
          }
        }
        try {
          _buffer.addLast(IngestEvent.fromJson(map));
        } on Object catch (err) {
          log.w('drop malformed queued event: $err');
        }
      }
      // Trim to capacity if persisted file exceeded it.
      while (_buffer.length > _maxSize) {
        _buffer.removeFirst();
        _dropped++;
      }
    } on Object catch (err, st) {
      log.e('queue hydrate failed', err, st);
    }
  }

  /// Appends [event], dropping the oldest element if at capacity.
  Future<void> append(IngestEvent event) async {
    if (_buffer.length >= _maxSize) {
      _buffer.removeFirst();
      _dropped++;
    }
    _buffer.addLast(event);
    await _persist();
  }

  /// Returns up to [max] events from the head without removing them.
  List<IngestEvent> peek(int max) {
    final count = max < _buffer.length ? max : _buffer.length;
    return List<IngestEvent>.unmodifiable(_buffer.take(count));
  }

  /// Removes the first [count] events (e.g. after a successful batch).
  Future<void> drop(int count) async {
    final n = count < _buffer.length ? count : _buffer.length;
    for (var i = 0; i < n; i++) {
      _buffer.removeFirst();
    }
    await _persist();
  }

  /// Drops everything (e.g. on `reset()`).
  Future<void> clear() async {
    _buffer.clear();
    await _persist();
  }

  Future<void> _persist() async {
    try {
      if (_buffer.isEmpty) {
        if (await _file.exists()) {
          await _file.writeAsString('');
        }
        return;
      }
      final sb = StringBuffer();
      sb.writeln(_queueHeaderLine);
      for (final e in _buffer) {
        sb.writeln(safeEncode(e.toJson()));
      }
      await _file.writeAsString(sb.toString(), flush: true);
    } on Object catch (err, st) {
      log.e('queue persist failed', err, st);
    }
  }
}
