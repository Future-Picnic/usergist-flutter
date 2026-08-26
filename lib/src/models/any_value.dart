/// Internal helpers for safe scalar-value conversions used across models.
///
/// The SDK permits `Map<String, Object?>` for property bags on the public
/// surface; internally we narrow to primitive scalars (string/num/bool/null)
/// before serialization to keep the wire format predictable.
library;

/// Converts any value into a JSON-safe scalar (string/num/bool/null) or
/// drops it. Lists and maps are preserved as long as they are nested
/// structures of scalars.
Object? toJsonScalar(Object? value) {
  if (value == null) return null;
  if (value is String || value is num || value is bool) return value;
  if (value is DateTime) return value.toUtc().toIso8601String();
  if (value is List<Object?>) {
    return value.map(toJsonScalar).toList(growable: false);
  }
  if (value is Map<Object?, Object?>) {
    final out = <String, Object?>{};
    for (final entry in value.entries) {
      final k = entry.key;
      if (k is String) {
        out[k] = toJsonScalar(entry.value);
      }
    }
    return out;
  }
  return value.toString();
}

/// Mirrors the React Native event-property contract: at most 100 non-PII
/// keys, scalar values only, bounded keys/strings, and finite numbers.
Map<String, Object?> sanitizeProperties(Map<String, Object?>? input) {
  if (input == null || input.isEmpty) return const <String, Object?>{};
  final out = <String, Object?>{};
  final piiKey =
      RegExp(r'(?:^|[._])(email|phone|ssn|tax_id)$', caseSensitive: false);
  for (final entry in input.entries.take(100)) {
    final key = entry.key;
    if (key.isEmpty || key.length > 120 || piiKey.hasMatch(key)) continue;
    final value = entry.value;
    if (value == null || value is bool) {
      out[key] = value;
    } else if (value is String) {
      out[key] = value.length <= 10000 ? value : value.substring(0, 10000);
    } else if (value is num && value.isFinite) {
      out[key] = value;
    }
  }
  return out;
}
