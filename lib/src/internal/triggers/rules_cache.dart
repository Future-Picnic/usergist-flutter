import 'dart:async';
import 'dart:io';

import '../../models/prompt.dart';
import '../json.dart';
import '../logger.dart';

/// Persistent cache of armed triggers. Keyed by event name for fast
/// lookup in the hot-path of `track()`.
class RulesCache {
  /// Creates a rules cache persisting to [file].
  RulesCache({required File file}) : _file = file;

  final File _file;

  List<ArmedTrigger> _triggers = const <ArmedTrigger>[];
  Map<String, List<ArmedTrigger>> _byEvent =
      const <String, List<ArmedTrigger>>{};

  /// Current triggers (read-only snapshot).
  List<ArmedTrigger> get all => _triggers;

  /// Returns all triggers armed for [eventName].
  List<ArmedTrigger> forEvent(String eventName) =>
      _byEvent[eventName] ?? const <ArmedTrigger>[];

  /// Hydrates from disk.
  Future<void> hydrate() async {
    try {
      if (!await _file.exists()) return;
      final raw = await _file.readAsString();
      if (raw.isEmpty) return;
      final list = safeDecodeList(raw);
      final next = <ArmedTrigger>[];
      for (final item in list) {
        if (item is Map<String, Object?>) {
          try {
            next.add(ArmedTrigger.fromJson(item));
          } on Object catch (err) {
            log.w('drop malformed cached trigger: $err');
          }
        }
      }
      _replace(next);
    } on Object catch (err, st) {
      log.e('rules-cache hydrate failed', err, st);
    }
  }

  /// Replaces all triggers and persists.
  Future<void> replace(List<Map<String, Object?>> raw) async {
    final next = <ArmedTrigger>[];
    for (final item in raw) {
      try {
        next.add(ArmedTrigger.fromJson(item));
      } on Object catch (err) {
        log.w('drop malformed trigger: $err');
      }
    }
    _replace(next);
    try {
      await _file.writeAsString(safeEncode(raw), flush: true);
    } on Object catch (err, st) {
      log.e('rules-cache persist failed', err, st);
    }
  }

  /// Clears the cache (both memory and disk).
  Future<void> clear() async {
    _replace(const <ArmedTrigger>[]);
    try {
      if (await _file.exists()) {
        await _file.writeAsString('');
      }
    } on Object catch (err, st) {
      log.e('rules-cache clear failed', err, st);
    }
  }

  void _replace(List<ArmedTrigger> next) {
    _triggers = List<ArmedTrigger>.unmodifiable(next);
    final byEvent = <String, List<ArmedTrigger>>{};
    for (final t in next) {
      byEvent.putIfAbsent(t.eventName, () => <ArmedTrigger>[]).add(t);
    }
    _byEvent = Map<String, List<ArmedTrigger>>.unmodifiable(
      byEvent.map(
        (k, v) => MapEntry<String, List<ArmedTrigger>>(
          k,
          List<ArmedTrigger>.unmodifiable(v),
        ),
      ),
    );
  }
}
