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
  int _version = 0;
  DateTime _updatedAt = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  /// Current consent value.
  Consent get value => _consent;

  /// Alias for [value] — matches the naming used by the public UserGist surface.
  Consent get current => _consent;

  /// Monotonic consent revision sent to the API.
  int get version => _version;

  /// Effective timestamp for the current revision.
  DateTime get updatedAt => _updatedAt;

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
    final purposes = map['purposes'];
    if (purposes is Map<String, Object?>) {
      _consent = Consent.fromJson(purposes);
      _version = map['version'] as int? ?? 0;
      _updatedAt =
          DateTime.tryParse(map['updatedAt'] as String? ?? '')?.toUtc() ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    } else {
      // Legacy snapshots stored the purpose object directly.
      _consent = Consent.fromJson(map);
    }
  }

  /// Updates consent and persists it.
  Future<void> set(Consent next) async {
    _consent = _consent.copyWith(
      analytics: next.analytics,
      feedback: next.feedback,
      push: next.push,
      survey: next.survey,
    );
    _version += 1;
    _updatedAt = DateTime.now().toUtc();
    await _store.writeString(
      _key,
      safeEncode(<String, Object?>{
        'purposes': _consent.toJson(),
        'version': _version,
        'updatedAt': _updatedAt.toIso8601String(),
      }),
    );
  }

  /// Clears consent.
  Future<void> clear() async {
    _consent = const Consent();
    _version += 1;
    _updatedAt = DateTime.now().toUtc();
    await _store.remove(_key);
  }
}
