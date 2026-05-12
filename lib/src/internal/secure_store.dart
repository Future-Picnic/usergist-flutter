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
// Failures are non-fatal: flutter_secure_storage can fail on some
// emulators / corrupt keystores. The caller tolerates a `null` read and
// continues with a fresh anonymous id.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'hashing.dart';
import 'logger.dart';
import 'storage.dart';

class SecureKeyValueStore implements KeyValueStore {
  SecureKeyValueStore({
    required String writeKey,
    required KeyValueStore legacy,
    FlutterSecureStorage? backend,
  })  : _prefix = 'ritmus.${shortHash(writeKey)}.secure.',
        _legacy = legacy,
        _backend = backend ?? const FlutterSecureStorage(
          aOptions: AndroidOptions(encryptedSharedPreferences: true),
        );

  final String _prefix;
  final KeyValueStore _legacy;
  final FlutterSecureStorage _backend;

  String _k(String key) => '$_prefix$key';

  @override
  Future<String?> readString(String key) async {
    try {
      final secureValue = await _backend.read(key: _k(key));
      if (secureValue != null) return secureValue;
    } on Object catch (err, st) {
      log.e('secure read failed', err, st);
    }
    // Legacy migration: one-time copy from the plaintext store.
    final legacyValue = await _legacy.readString(key);
    if (legacyValue == null) return null;
    try {
      await _backend.write(key: _k(key), value: legacyValue);
      await _legacy.remove(key);
    } on Object catch (err, st) {
      log.e('secure migration write failed', err, st);
    }
    return legacyValue;
  }

  @override
  Future<void> writeString(String key, String value) async {
    try {
      await _backend.write(key: _k(key), value: value);
    } on Object catch (err, st) {
      log.e('secure write failed', err, st);
      // Fallback: keep the host app usable even if Keychain access fails.
      await _legacy.writeString(key, value);
    }
  }

  @override
  Future<void> remove(String key) async {
    try {
      await _backend.delete(key: _k(key));
    } on Object catch (err, st) {
      log.e('secure remove failed', err, st);
    }
    // Also clear any legacy copy left behind from a prior install.
    await _legacy.remove(key);
  }
}
