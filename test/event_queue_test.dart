import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ritmus_feedback/src/internal/event_queue.dart';
import 'package:ritmus_feedback/src/models/event.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('ritmus_queue_');
  });

  tearDown(() async {
    if (await tmp.exists()) {
      await tmp.delete(recursive: true);
    }
  });

  IngestEvent mkEvent(int i) => IngestEvent(
        name: 'evt_$i',
        timestamp: DateTime.utc(2025).toIso8601String(),
        anonymousId: 'anon',
        properties: <String, Object?>{'i': i},
      );

  test('appends and peeks FIFO order', () async {
    final q = EventQueue(file: File('${tmp.path}/q.jsonl'), maxSize: 10);
    await q.hydrate();
    for (var i = 0; i < 5; i++) {
      await q.append(mkEvent(i));
    }
    expect(q.length, 5);
    final head = q.peek(3);
    expect(head.map((e) => e.name).toList(), <String>['evt_0', 'evt_1', 'evt_2']);
  });

  test('drop removes from the head', () async {
    final q = EventQueue(file: File('${tmp.path}/q.jsonl'), maxSize: 10);
    await q.hydrate();
    for (var i = 0; i < 4; i++) {
      await q.append(mkEvent(i));
    }
    await q.drop(2);
    final rest = q.peek(10);
    expect(rest.map((e) => e.name).toList(), <String>['evt_2', 'evt_3']);
  });

  test('overflow drops the oldest', () async {
    final q = EventQueue(file: File('${tmp.path}/q.jsonl'), maxSize: 3);
    await q.hydrate();
    for (var i = 0; i < 5; i++) {
      await q.append(mkEvent(i));
    }
    expect(q.length, 3);
    expect(q.droppedCount, 2);
    final rest = q.peek(10);
    expect(rest.map((e) => e.name).toList(),
        <String>['evt_2', 'evt_3', 'evt_4']);
  });

  test('persistence survives a restart', () async {
    final file = File('${tmp.path}/q.jsonl');
    final first = EventQueue(file: file, maxSize: 10);
    await first.hydrate();
    await first.append(mkEvent(1));
    await first.append(mkEvent(2));

    final second = EventQueue(file: file, maxSize: 10);
    await second.hydrate();
    expect(second.length, 2);
    expect(second.peek(2).map((e) => e.name).toList(),
        <String>['evt_1', 'evt_2']);
  });

  test('clear empties the queue and the file', () async {
    final file = File('${tmp.path}/q.jsonl');
    final q = EventQueue(file: file, maxSize: 10);
    await q.hydrate();
    await q.append(mkEvent(1));
    await q.clear();
    expect(q.length, 0);
    expect(q.isEmpty, true);
  });

  test('persisted file is prefixed with a version header line', () async {
    final file = File('${tmp.path}/q.jsonl');
    final q = EventQueue(file: file, maxSize: 10);
    await q.hydrate();
    await q.append(mkEvent(1));
    final lines = (await file.readAsString()).split('\n');
    expect(lines.first, '{"version":1}');
  });

  test('hydrates legacy bare-line snapshots and rewrites with header',
      () async {
    final file = File('${tmp.path}/q.jsonl');
    // Pre-versioning SDK builds wrote bare event lines with no header.
    // Mirrors the fallback in packages/sdk-react-native/src/internal/queue.ts.
    await file.writeAsString(
      '{"name":"legacy","timestamp":"2026-01-01T00:00:00.000Z","anonymousId":"a"}\n',
    );
    final q = EventQueue(file: file, maxSize: 10);
    await q.hydrate();
    expect(q.length, 1);
    expect(q.peek(1).first.name, 'legacy');

    // Force a rewrite — next persist should emit the header.
    await q.append(mkEvent(99));
    final lines = (await file.readAsString()).split('\n');
    expect(lines.first, '{"version":1}');
  });

  test('discards persisted snapshots from an unknown schema version',
      () async {
    final file = File('${tmp.path}/q.jsonl');
    await file.writeAsString(
      '{"version":999}\n{"name":"x","timestamp":"2026-01-01T00:00:00.000Z","anonymousId":"a"}\n',
    );
    final q = EventQueue(file: file, maxSize: 10);
    await q.hydrate();
    expect(q.length, 0);
  });
}
