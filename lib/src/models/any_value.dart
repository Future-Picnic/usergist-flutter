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

/// Narrows a dynamic map into a `Map<String, Object?>` containing only
/// JSON-safe scalar values. Unknown entries are coerced via [toJsonScalar].
Map<String, Object?> sanitizeProperties(Map<String, Object?>? input) {
  if (input == null || input.isEmpty) return const <String, Object?>{};
  final out = <String, Object?>{};
  for (final entry in input.entries) {
    out[entry.key] = toJsonScalar(entry.value);
  }
  return out;
}
