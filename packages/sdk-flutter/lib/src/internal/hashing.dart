import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Returns the first 12 hex chars of a SHA-256 of [input] — used as a
/// stable namespace derived from the write key so multiple SDK instances
/// can coexist on-device without clobbering each other.
String shortHash(String input) {
  final digest = sha256.convert(utf8.encode(input));
  return digest.toString().substring(0, 12);
}
