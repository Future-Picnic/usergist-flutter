import 'dart:async';

import '../models/consent.dart';
import 'json.dart';
import 'storage.dart';

/// Persistent consent store. Transport in [Transport] / [UserGist] is
/// gated on [isFeedbackGranted] returning `true`.
class ConsentStore {
  /// Creates a consent store.
  ConsentStore(this._store);

  final KeyValueStore _store;
  static const String _key = 'consent.state';

  Consent _consent = const Consent();

  /// Current consent value.
  Consent get value => _consent;

  /// Alias for [value] — matches the naming used by the public UserGist surface.
  Consent get current => _consent;

  /// `true` if the caller has explicitly granted survey consent.
  bool get isSurveyGranted => _consent.survey == true;

  /// `true` if the caller has explicitly granted feedback consent.
  bool get isFeedbackGranted => _consent.feedback == true;

  /// `true` if the caller has explicitly granted analytics consent.
  bool get isAnalyticsGranted => _consent.analytics == true;

  /// `true` if the caller has explicitly granted push-notifications consent.
  bool get isPushGranted => _consent.push == true;

  /// Hydrates from disk.
  Future<void> hydrate() async {
    final raw = await _store.readString(_key);
    if (raw == null || raw.isEmpty) return;
    final map = safeDecodeMap(raw);
    _consent = Consent.fromJson(map);
  }

  /// Updates consent and persists it.
  Future<void> set(Consent next) async {
    _consent = next;
    await _store.writeString(_key, safeEncode(next.toJson()));
  }

  /// Clears consent.
  Future<void> clear() async {
    _consent = const Consent();
    await _store.remove(_key);
  }
}
