import 'dart:convert';

import 'storage.dart';

/// Persists locally rendered campaign/event pairs until their matching server
/// instruction is consumed, preventing a relaunch from replaying the surface.
class LocalInstructionDedupe {
  LocalInstructionDedupe(SharedPrefsStore store)
      : this.withPersistence(
          read: store.readString,
          writeStrict: store.writeStringStrict,
          remove: store.remove,
        );

  /// Test-only/custom persistence constructor.
  LocalInstructionDedupe.withPersistence({
    required Future<String?> Function(String key) read,
    required Future<bool> Function(String key, String value) writeStrict,
    required Future<void> Function(String key) remove,
  })  : _read = read,
        _writeStrict = writeStrict,
        _remove = remove;

  static const String _storageKey = 'instructions.localDedupe';
  static const int _maxKeys = 200;

  final Future<String?> Function(String key) _read;
  final Future<bool> Function(String key, String value) _writeStrict;
  final Future<void> Function(String key) _remove;
  final Set<String> _keys = <String>{};
  Future<void> _serial = Future<void>.value();

  int get length => _keys.length;
  bool contains(String key) => _keys.contains(key);

  Future<void> hydrate() async {
    final raw = await _read(_storageKey);
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List<Object?>) return;
      _keys.clear();
      for (final value in decoded.whereType<String>().toList().reversed) {
        if (value.isEmpty || _keys.length >= _maxKeys) continue;
        _keys.add(value);
      }
      final latestFirst = _keys.toList(growable: false);
      _keys
        ..clear()
        ..addAll(latestFirst.reversed);
    } on Object {
      _keys.clear();
    }
  }

  void remember(String key) {
    _keys
      ..remove(key)
      ..add(key);
    while (_keys.length > _maxKeys) {
      _keys.remove(_keys.first);
    }
    _schedulePersist();
  }

  bool consume(String key) {
    if (!_keys.remove(key)) return false;
    _schedulePersist();
    return true;
  }

  Future<void> clear() {
    _keys.clear();
    _serial = _serial.then((_) => _remove(_storageKey));
    return _serial;
  }

  /// Waits for queued persistence. Used by deterministic tests and reset.
  Future<void> flush() => _serial;

  void _schedulePersist() {
    final snapshot = jsonEncode(_keys.toList(growable: false));
    _serial = _serial.then((_) async {
      await _writeStrict(_storageKey, snapshot);
    });
  }
}
