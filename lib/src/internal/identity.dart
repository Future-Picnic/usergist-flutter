import 'dart:async';

import 'storage.dart';
import 'uid.dart';

/// Persistent identity store — a 21-character anonymous id that survives restarts
/// plus an optional external id set by [identify].
class IdentityStore {
  /// Creates an identity store backed by [store].
  IdentityStore(this._store);

  final KeyValueStore _store;

  static const String _anonKey = 'identity.anonymousId';
  static const String _extKey = 'identity.externalId';
  static const String _propsKey = 'identity.externalProps';

  String? _anonymousId;
  String? _externalId;

  /// Hydrates the in-memory state from disk. Generates and persists a
  /// new anonymous id if one doesn't exist.
  Future<void> hydrate() async {
    var anon = await _store.readString(_anonKey);
    if (anon == null || anon.isEmpty) {
      anon = newAnonymousId();
      await _store.writeString(_anonKey, anon);
    }
    _anonymousId = anon;
    _externalId = await _store.readString(_extKey);
  }

  /// The anonymous identifier (hydrated on [hydrate]).
  String get anonymousId => _anonymousId ?? '';

  /// The current external identifier (if set).
  String? get externalId => _externalId;

  /// Sets the external identifier (called by [UserGist.identify]).
  Future<void> setExternalId(String? id) async {
    if (id == null) {
      await _store.remove(_extKey);
    } else {
      await _store.writeString(_extKey, id);
    }
    _externalId = id;
  }

  /// Persists the latest external user properties. Stored as a JSON blob.
  Future<void> setExternalProperties(String json) async {
    await _store.writeString(_propsKey, json);
  }

  /// Reads the persisted external-properties blob.
  Future<String?> readExternalProperties() => _store.readString(_propsKey);

  /// Clears external id and properties. Regenerates the anonymous id.
  Future<void> reset() async {
    _externalId = null;
    await _store.remove(_extKey);
    await _store.remove(_propsKey);
    final fresh = newAnonymousId();
    await _store.writeString(_anonKey, fresh);
    _anonymousId = fresh;
  }
}
