import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usergist_feedback/src/models/prompt.dart';
import 'package:usergist_feedback/src/models/question.dart';
import 'package:usergist_feedback/src/ui/modal_coordinator.dart';
import 'package:usergist_feedback/src/ui/prompt_presenter.dart';

void main() {
  testWidgets('saved acknowledgement uses the root navigator overlay and clears on reset',
      (tester) async {
    final requests = StreamController<PromptShowRequest>();
    final navigator = GlobalKey<NavigatorState>();
    late PromptPresenter presenter;
    var responses = 0;
    presenter = PromptPresenter(
      stream: requests.stream,
      coordinator: SdkModalCoordinator(),
      onShown: (_) {},
      onPresentationFailed: (_) => fail('Prompt did not present'),
      onResponded: (info) {
        responses++;
        presenter.showSavedNotice(info.promptId);
      },
    );
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      home: const Scaffold(body: Text('Host')),
    ));
    presenter.attach(navigator.currentState!.overlay!.context);
    requests.add(const PromptShowRequest(prompt: ClientPrompt(
      id: 'saved-feedback',
      questions: [ShortTextQuestion(id: 'text', title: 'Tell us more')],
    )));
    await tester.pump();
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Save my feedback');
    await tester.pump();
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
    expect(responses, 1);
    expect(find.text('Feedback saved. We’ll send it automatically.'), findsOneWidget);
    await presenter.reset();
    await tester.pump();
    expect(find.text('Feedback saved. We’ll send it automatically.'), findsNothing);
    await tester.runAsync(() async {
      await presenter.detach();
      await requests.close();
    });
  });
}
