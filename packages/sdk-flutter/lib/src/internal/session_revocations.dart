import 'dart:convert';
import 'secure_store.dart';
import 'transport/api_client.dart';
import 'uid.dart';

/// Logout records outlive user queues and are retried with their original
/// credential and installation, never the current account's credential.
class SessionRevocations {
  SessionRevocations(this.store, this.api);
  final SecureKeyValueStore store;
  final ApiClient api;
  static const key = 'session.revocations';
  Future<void> _serial = Future<void>.value();
  Future<void>? _draining;
  Future<List<Map<String, Object?>>> _read() async {
    final raw = await store.readString(key);
    return raw == null
        ? <Map<String, Object?>>[]
        : (jsonDecode(raw) as List<Object?>)
            .map((v) => Map<String, Object?>.from(v! as Map))
            .toList();
  }

  Future<void> _mutate(
      List<Map<String, Object?>> Function(List<Map<String, Object?>>)
          transform) {
    final task = _serial.then((_) async {
      final next = transform(await _read());
      if (!await store.writeStringStrict(key, jsonEncode(next)))
        throw StateError('Unable to persist logout cleanup');
    });
    _serial = task.catchError((Object _) {});
    return task;
  }

  Future<void> remember(String? token, String anonymousId) async {
    if (token == null) return;
    await _mutate((entries) => entries.any((entry) =>
            entry['token'] == token && entry['anonymousId'] == anonymousId)
        ? entries
        : <Map<String, Object?>>[
            ...entries,
            <String, Object?>{
              'id': newUuid(),
              'token': token,
              'anonymousId': anonymousId
            }
          ]);
  }

  Future<bool> isPending() async {
    await _serial;
    return (await _read()).isNotEmpty;
  }

  Future<void> drain() => _draining ??= _drain().whenComplete(() {
        _draining = null;
      });
  Future<void> _drain() async {
    await _serial;
    for (final entry in await _read()) {
      final result = await api.postJson('/v1/sdk/session/revoke',
          <String, Object?>{'anonymousId': entry['anonymousId']},
          requiresSubject: false,
          subjectTokenOverride: entry['token']! as String);
      if (!result.success && result.status != 401) return;
      await _mutate((entries) =>
          entries.where((item) => item['id'] != entry['id']).toList());
    }
  }
}
