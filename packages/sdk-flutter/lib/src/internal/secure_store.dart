// PORTED FROM (concept): packages/sdk-react-native/src/internal/storage.ts
//
// Wraps `flutter_secure_storage` behind the existing [KeyValueStore]
// interface. Used for the identity and consent stores so secrets never
// touch plaintext `shared_preferences`.
//
// On read, falls back to a legacy [KeyValueStore] (typically a
// [SharedPrefsStore]) for one-time migration: if the key is found in the
// legacy store, copy it into the secure store and delete the legacy
// entry. Subsequent reads stay in the secure store.
//
// Failures are non-fatal. Credential-bearing values fail closed instead of
// falling back to plaintext shared preferences; non-secret compatibility
// state can still use the legacy store when secure storage is unavailable.

import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'hashing.dart';
import 'logger.dart';
import 'storage.dart';

class SecureKeyValueStore implements KeyValueStore {
  SecureKeyValueStore({
    required String writeKey,
    required KeyValueStore legacy,
    FlutterSecureStorage? backend,
  })  : _prefix = 'usergist.${shortHash(writeKey)}.secure.',
        _legacy = legacy,
        _backend = backend ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final String _prefix;
  final KeyValueStore _legacy;
  final FlutterSecureStorage _backend;
  Future<void> _serial = Future<void>.value();
  Future<T> _ordered<T>(Future<T> Function() operation) {
    final task = _serial.then((_) => operation());
    _serial = task.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return task;
  }

  String _k(String key) => '$_prefix$key';

  @override
  Future<String?> readString(String key) => _ordered(() => _readString(key));

  Future<String?> _readString(String key) async {
    try {
      final secureValue = await _backend.read(key: _k(key));
      if (secureValue != null) {
        await _legacy.remove(key);
        return secureValue;
      }
    } on Object catch (err, st) {
      log.e('secure read failed', err, st);
    }
    // Legacy migration: one-time copy from the plaintext store.
    final legacyValue = await _legacy.readString(key);
    if (legacyValue == null) return null;
    try {
      await _backend.write(key: _k(key), value: legacyValue);
      await _legacy.remove(key);
      return legacyValue;
    } on Object catch (err, st) {
      log.e('secure migration write failed', err, st);
      if (_requiresSecureStorage(key)) {
        await _legacy.remove(key);
        return null;
      }
    }
    return legacyValue;
  }

  @override
  Future<void> writeString(String key, String value) async {
    if (!await writeStringStrict(key, value))
      throw StateError("Unable to persist SDK state");
  }

  /// Persists state and reports whether the appropriate backing store accepted
  /// it. Credential keys never fall back to plaintext storage.
  Future<bool> writeStringStrict(String key, String value) =>
      _ordered(() => _writeStringStrict(key, value));

  Future<bool> _writeStringStrict(String key, String value) async {
    try {
      await _backend.write(key: _k(key), value: value);
      return true;
    } on Object catch (err, st) {
      log.e('secure write failed', err, st);
      if (_requiresSecureStorage(key)) {
        await _legacy.remove(key);
        return false;
      }
      final legacy = _legacy;
      if (legacy is SharedPrefsStore) {
        return legacy.writeStringStrict(key, value);
      }
      await _legacy.writeString(key, value);
      return true;
    }
  }

  bool _requiresSecureStorage(String key) =>
      key.startsWith('identity.') ||
      key == 'session.subjectToken' ||
      key == 'mutations.queue' ||
      key == 'session.revocations' ||
      key == 'push.registration';

  @override
  Future<void> remove(String key) => _ordered(() => _remove(key));

  Future<void> _remove(String key) async {
    try {
      await _backend.delete(key: _k(key));
    } on Object catch (err, st) {
      log.e('secure remove failed', err, st);
      rethrow;
    }
    // Also clear any legacy copy left behind from a prior install.
    await _legacy.remove(key);
  }
}
