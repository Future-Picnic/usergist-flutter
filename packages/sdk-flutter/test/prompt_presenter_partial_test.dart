import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usergist_feedback/src/models/prompt.dart';
import 'package:usergist_feedback/src/models/question.dart';
import 'package:usergist_feedback/src/models/response_info.dart';
import 'package:usergist_feedback/src/ui/modal_coordinator.dart';
import 'package:usergist_feedback/src/ui/prompt_presenter.dart';

void main() {
  const prompt = ClientPrompt(
    id: 'prompt',
    questions: <Question>[
      NpsQuestion(id: 'q1', title: 'Recommend us?'),
      ShortTextQuestion(id: 'q2', title: 'Tell us more'),
    ],
  );

  for (final dismissal in <String>['backdrop', 'back', 'close', 'reset']) {
    testWidgets('$dismissal preserves partial answers except SDK reset',
        (tester) async {
      final stream = StreamController<PromptShowRequest>();
      final outcomes = <PromptResponseInfo>[];
      final presenter = PromptPresenter(
        stream: stream.stream,
        onResponded: outcomes.add,
        onShown: (_) {},
        onPresentationFailed: (_) => fail('Presentation failed'),
        coordinator: SdkModalCoordinator(),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              presenter.attach(context);
              return const Scaffold(body: Text('Host'));
            },
          ),
        ),
      );
      stream.add(const PromptShowRequest(prompt: prompt));
      await tester.pump();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('0'));
      await tester.tap(find.text('0'));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      expect(find.text('Tell us more'), findsOneWidget);
      // The last input is also retained before its Next button is pressed.
      await tester.enterText(find.byType(TextField), 'Still writing');
      if (dismissal == 'backdrop') {
        await tester.tapAt(const Offset(10, 10));
      } else if (dismissal == 'back') {
        unawaited(tester.binding.handlePopRoute());
      } else if (dismissal == 'reset') {
        unawaited(presenter.reset());
      } else {
        await tester.tap(find.byIcon(Icons.close));
      }
      await tester.pumpAndSettle();
      if (dismissal == 'reset') {
        expect(outcomes, isEmpty);
      } else {
        expect(outcomes, hasLength(1));
        expect(outcomes.single.dismissed, isTrue);
        expect(
            outcomes.single.answers.map((answer) => answer.toJson()), <Object>[
          <String, Object>{'questionId': 'q1', 'value': 0},
          <String, Object>{'questionId': 'q2', 'value': 'Still writing'},
        ]);
      }
      outcomes.clear();
      stream.add(const PromptShowRequest(prompt: prompt));
      await tester.pump();
      await tester.pumpAndSettle();
      unawaited(tester.binding.handlePopRoute());
      await tester.pumpAndSettle();
      expect(outcomes, hasLength(1));
      expect(outcomes.single.answers, isEmpty);
      await tester.runAsync(() async {
        await presenter.detach();
        await stream.close();
      });
    });
  }
}
