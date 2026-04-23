import 'package:uuid/uuid.dart';

const Uuid _uuid = Uuid();

/// Generates a new v4 UUID.
String newUuid() => _uuid.v4();
