import 'dart:convert';

/// Safely encodes a JSON object. Returns an empty object on failure.
String safeEncode(Object? value) {
  try {
    return json.encode(value);
  } on Object {
    return '{}';
  }
}

/// Safely decodes a JSON string. Returns `null` on failure.
Object? safeDecode(String raw) {
  try {
    return json.decode(raw);
  } on Object {
    return null;
  }
}

/// Safely decodes a JSON string as a map. Returns an empty map on failure.
Map<String, Object?> safeDecodeMap(String raw) {
  final v = safeDecode(raw);
  if (v is Map<String, Object?>) return v;
  if (v is Map<Object?, Object?>) {
    return v.map((k, val) => MapEntry(k.toString(), val));
  }
  return <String, Object?>{};
}

/// Safely decodes a JSON string as a list. Returns an empty list on failure.
List<Object?> safeDecodeList(String raw) {
  final v = safeDecode(raw);
  if (v is List<Object?>) return v;
  return const <Object?>[];
}
