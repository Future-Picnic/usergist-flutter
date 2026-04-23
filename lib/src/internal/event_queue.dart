import 'dart:async';
import 'dart:collection';
import 'dart:io';

import '../models/event.dart';
import 'json.dart';
import 'logger.dart';

/// Bounded, persistent FIFO queue of pending ingest events.
///
/// * Appends are non-blocking.
/// * On overflow, the oldest event is dropped.
/// * State is mirrored to a JSON-lines file which is rewritten on flush.
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
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        final map = safeDecodeMap(trimmed);
        if (map.isEmpty) continue;
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
      for (final e in _buffer) {
        sb.writeln(safeEncode(e.toJson()));
      }
      await _file.writeAsString(sb.toString(), flush: true);
    } on Object catch (err, st) {
      log.e('queue persist failed', err, st);
    }
  }
}
