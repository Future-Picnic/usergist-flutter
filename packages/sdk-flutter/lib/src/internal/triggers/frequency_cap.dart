import 'dart:async';

import '../../models/prompt.dart';
import '../json.dart';
import '../logger.dart';
import '../storage.dart';

/// Tracks when prompts were last shown to the current user so we can
/// enforce [FrequencyCaps] locally before firing.
///
/// Stored as a small JSON map in [KeyValueStore]:
/// ```
/// {
///   "lastGlobal": "<iso>",
///   "perPrompt": { "<promptId>": "<iso>" }
/// }
/// ```
class FrequencyCapStore {
  /// Creates the store.
  FrequencyCapStore(this._store);

  final KeyValueStore _store;

  static const String _key = 'freqCaps.state';

  DateTime? _lastGlobal;
  Map<String, DateTime> _perPrompt = <String, DateTime>{};

  /// Hydrates from disk.
  Future<void> hydrate() async {
    final raw = await _store.readString(_key);
    if (raw == null || raw.isEmpty) return;
    final map = safeDecodeMap(raw);
    final lg = map['lastGlobal'];
    if (lg is String) _lastGlobal = DateTime.tryParse(lg);
    final pp = map['perPrompt'];
    if (pp is Map<String, Object?>) {
      final parsed = <String, DateTime>{};
      for (final entry in pp.entries) {
        final v = entry.value;
        if (v is String) {
          final d = DateTime.tryParse(v);
          if (d != null) parsed[entry.key] = d;
        }
      }
      _perPrompt = parsed;
    }
  }

  /// Records that [promptId] was shown at [when] (defaults to now).
  Future<void> record(String promptId, {DateTime? when}) async {
    final at = when ?? DateTime.now().toUtc();
    _lastGlobal = at;
    _perPrompt = <String, DateTime>{..._perPrompt, promptId: at};
    await _persist();
  }

  /// Returns `true` if [promptId] may be shown now under [caps].
  bool allow(String promptId, FrequencyCaps caps, {DateTime? now}) {
    final t = now ?? DateTime.now().toUtc();
    final perUser = caps.perUserDays;
    if (perUser != null && perUser > 0) {
      final lg = _lastGlobal;
      if (lg != null && t.difference(lg).inDays < perUser) {
        return false;
      }
    }
    final perPrompt = caps.perPromptDays;
    if (perPrompt != null && perPrompt > 0) {
      final last = _perPrompt[promptId];
      if (last != null && t.difference(last).inDays < perPrompt) {
        return false;
      }
    }
    return true;
  }

  /// Clears all recorded shows.
  Future<void> clear() async {
    _lastGlobal = null;
    _perPrompt = <String, DateTime>{};
    await _store.remove(_key);
  }

  Future<void> _persist() async {
    try {
      final out = <String, Object?>{
        if (_lastGlobal != null) 'lastGlobal': _lastGlobal!.toIso8601String(),
        'perPrompt': _perPrompt.map<String, Object?>(
          (k, v) => MapEntry<String, Object?>(k, v.toIso8601String()),
        ),
      };
      await _store.writeString(_key, safeEncode(out));
    } on Object catch (err, st) {
      log.e('freq-cap persist failed', err, st);
    }
  }
}
