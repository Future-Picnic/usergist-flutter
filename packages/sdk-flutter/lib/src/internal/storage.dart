import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'hashing.dart';
import 'logger.dart';

/// Abstraction over persistent small-state storage.
abstract class KeyValueStore {
  /// Reads a string value by [key].
  Future<String?> readString(String key);

  /// Writes a string value at [key].
  Future<void> writeString(String key, String value);

  /// Removes a value.
  Future<void> remove(String key);
}

/// Shared-preferences backed implementation. All keys are namespaced
/// by a short hash of the SDK write key so multiple workspaces can
/// coexist on the same device without clobbering each other.
class SharedPrefsStore implements KeyValueStore {
  /// Creates a store namespaced to [writeKey].
  SharedPrefsStore({required String writeKey})
      : _prefix = 'usergist.${shortHash(writeKey)}.';

  final String _prefix;
  SharedPreferences? _prefs;

  Future<SharedPreferences> _instance() async {
    final cached = _prefs;
    if (cached != null) return cached;
    final p = await SharedPreferences.getInstance();
    _prefs = p;
    return p;
  }

  String _k(String key) => '$_prefix$key';

  @override
  Future<String?> readString(String key) async {
    try {
      final p = await _instance();
      return p.getString(_k(key));
    } on Object catch (err, st) {
      log.e('prefs read failed', err, st);
      return null;
    }
  }

  @override
  Future<void> writeString(String key, String value) async {
    await writeStringStrict(key, value);
  }

  /// Persists [value] and reports whether the write reached the backing
  /// preferences store. Durable inbox cursors must not be acknowledged when
  /// this returns false.
  Future<bool> writeStringStrict(String key, String value) async {
    try {
      final p = await _instance();
      return await p.setString(_k(key), value);
    } on Object catch (err, st) {
      log.e('prefs write failed', err, st);
      return false;
    }
  }

  @override
  Future<void> remove(String key) async {
    try {
      final p = await _instance();
      await p.remove(_k(key));
    } on Object catch (err, st) {
      log.e('prefs remove failed', err, st);
    }
  }
}

/// Returns the per-writeKey application-support directory used for
/// heavier persistent artifacts (event queue, cached triggers).
Future<Directory> usergistSupportDir(String writeKey) async {
  final base = await getApplicationSupportDirectory();
  final dir = Directory('${base.path}/usergist/${shortHash(writeKey)}');
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir;
}
