import 'dart:convert';

import 'secure_store.dart';
import 'uid.dart';

enum MutationKind { identify, feedbackResponse, surveyComplete, surveyAbandon }

enum MutationPurpose { essential, feedback, survey }

class PendingMutation {
  const PendingMutation({
    required this.id,
    required this.kind,
    required this.purpose,
    required this.payload,
    required this.createdAt,
    this.dedupeKey,
  });

  final String id;
  final MutationKind kind;
  final MutationPurpose purpose;
  final Map<String, Object?> payload;
  final String createdAt;
  final String? dedupeKey;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'kind': kind.name,
        'purpose': purpose.name,
        'payload': payload,
        'createdAt': createdAt,
        if (dedupeKey != null) 'dedupeKey': dedupeKey,
      };

  factory PendingMutation.fromJson(Map<String, Object?> json) =>
      PendingMutation(
        id: json['id']! as String,
        kind: MutationKind.values.byName(json['kind']! as String),
        purpose: MutationPurpose.values.byName(json['purpose']! as String),
        payload: json['payload']! as Map<String, Object?>,
        createdAt: json['createdAt']! as String,
        dedupeKey: json['dedupeKey'] as String?,
      );
}

/// Encrypted, versioned FIFO for state-changing requests that must survive
/// process death. Essential identity work is always placed ahead of
/// consent-gated feedback/survey work.
class MutationQueue {
  MutationQueue(SecureKeyValueStore store)
      : _read = store.readString,
        _writeStrict = store.writeStringStrict;

  /// Test-only/custom persistence constructor.
  MutationQueue.withPersistence({
    required Future<String?> Function(String key) read,
    required Future<bool> Function(String key, String value) writeStrict,
  })  : _read = read,
        _writeStrict = writeStrict;

  static const String _key = 'mutations.queue';
  final Future<String?> Function(String key) _read;
  final Future<bool> Function(String key, String value) _writeStrict;
  List<PendingMutation> _items = <PendingMutation>[];
  Future<void> _serial = Future<void>.value();

  int get length => _items.length;
  PendingMutation? get first => _items.isEmpty ? null : _items.first;
  bool contains(String id) => _items.any((item) => item.id == id);

  Future<void> hydrate() async {
    final raw = await _read(_key);
    if (raw == null) return;
    try {
      final root = jsonDecode(raw);
      if (root is! Map<String, Object?> || root['version'] != 1) return;
      final values = root['items'];
      if (values is! List<Object?>) return;
      _items = values
          .whereType<Map<String, Object?>>()
          .map(PendingMutation.fromJson)
          .toList(growable: true);
    } on Object {
      _items = <PendingMutation>[];
    }
  }

  Future<String> enqueue(
    MutationKind kind,
    MutationPurpose purpose,
    Map<String, Object?> payload, {
    String? dedupeKey,
  }) async {
    var id = newUuid();
    await _mutate(() {
      if (dedupeKey != null) {
        final existing = _items.where((item) => item.dedupeKey == dedupeKey);
        if (existing.isNotEmpty) {
          id = existing.first.id;
          return;
        }
      }
      final next = PendingMutation(
        id: id,
        kind: kind,
        purpose: purpose,
        payload: payload,
        createdAt: DateTime.now().toUtc().toIso8601String(),
        dedupeKey: dedupeKey,
      );
      if (purpose == MutationPurpose.essential) {
        _items.insert(0, next);
      } else {
        _items.add(next);
      }
    });
    return id;
  }

  Future<void> remove(String id) => _mutate(
        () => _items.removeWhere((item) => item.id == id),
      );

  Future<void> removePurpose(MutationPurpose purpose) => _mutate(
        () => _items.removeWhere((item) => item.purpose == purpose),
      );

  Future<void> clear() => _mutate(_items.clear);

  Future<void> _mutate(void Function() change) {
    final next = _serial.then((_) async {
      final previous = List<PendingMutation>.of(_items);
      try {
        change();
        final persisted = await _writeStrict(
          _key,
          jsonEncode(<String, Object?>{
            'version': 1,
            'items':
                _items.map((item) => item.toJson()).toList(growable: false),
          }),
        );
        if (!persisted) throw StateError('failed to persist mutation queue');
      } on Object {
        _items = previous;
        rethrow;
      }
    });
    _serial = next.catchError((Object _) {});
    return next;
  }
}
