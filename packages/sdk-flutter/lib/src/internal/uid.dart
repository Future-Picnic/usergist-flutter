import 'dart:math';

import 'package:uuid/uuid.dart';

const Uuid _uuid = Uuid();

/// Generates a new v4 UUID.
String newUuid() => _uuid.v4();

const String _anonymousIdAlphabet =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-';

/// Generates the 21-character URL-safe anonymous id used by every SDK.
String newAnonymousId() {
  final random = Random.secure();
  return List<String>.generate(
    21,
    (_) => _anonymousIdAlphabet[random.nextInt(_anonymousIdAlphabet.length)],
    growable: false,
  ).join();
}
