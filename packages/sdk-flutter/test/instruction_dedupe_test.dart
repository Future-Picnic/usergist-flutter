import 'package:flutter_test/flutter_test.dart';
import 'package:usergist_feedback/src/internal/instruction_dedupe.dart';

void main() {
  test('matching instruction is consumed once after restart', () async {
    final memory = <String, String>{};
    LocalInstructionDedupe makeDedupe() =>
        LocalInstructionDedupe.withPersistence(
          read: (key) async => memory[key],
          writeStrict: (key, value) async {
            memory[key] = value;
            return true;
          },
          remove: (key) async {
            memory.remove(key);
          },
        );
    const key = 'inapp.show:message-1:event:event-1';

    final first = makeDedupe()..remember(key);
    await first.flush();
    final restored = makeDedupe();
    await restored.hydrate();

    expect(restored.consume(key), isTrue);
    expect(restored.consume(key), isFalse);
    await restored.flush();
    final afterConsume = makeDedupe();
    await afterConsume.hydrate();
    expect(afterConsume.contains(key), isFalse);
  });

  test('only latest two hundred instructions are retained', () async {
    final memory = <String, String>{};
    final dedupe = LocalInstructionDedupe.withPersistence(
      read: (key) async => memory[key],
      writeStrict: (key, value) async {
        memory[key] = value;
        return true;
      },
      remove: (key) async {
        memory.remove(key);
      },
    );

    for (var index = 0; index < 205; index += 1) {
      dedupe.remember('inapp.show:message:event:$index');
    }

    expect(dedupe.length, 200);
    expect(dedupe.contains('inapp.show:message:event:0'), isFalse);
    expect(dedupe.contains('inapp.show:message:event:204'), isTrue);
    await dedupe.flush();
  });
}
