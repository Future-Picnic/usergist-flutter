import 'dart:async';
import 'dart:ui' show SemanticsFlag;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usergist_feedback/src/models/survey.dart';
import 'package:usergist_feedback/src/ui/modal_coordinator.dart';
import 'package:usergist_feedback/src/ui/surface_controls.dart';
import 'package:usergist_feedback/src/ui/surface_tokens.dart';
import 'package:usergist_feedback/src/ui/survey_presenter.dart';

const _survey = SurveyCampaignWithFlow(
  id: 'survey',
  name: 'Survey',
  flow: SurveyFlow(
    startQuestionId: 'use',
    questions: <SurveyQuestion>[
      SurveyQuestion(
        id: 'use',
        type: 'multi_choice',
        title: 'What do you use it for?',
        required: true,
        options: <SurveyChoice>[
          SurveyChoice(id: 'work', label: 'For work'),
          SurveyChoice(id: 'lists', label: 'Lists'),
        ],
        items: <SurveyChoice>[],
      ),
      SurveyQuestion(
        id: 'why',
        type: 'long_text',
        title: 'Anything else?',
        required: false,
        options: <SurveyChoice>[],
        items: <SurveyChoice>[],
      ),
    ],
    branches: <SurveyBranch>[],
    progressStyle: 'bar',
    backNavigation: true,
  ),
);

const _attempt = SurveyAttemptSession(
  attemptId: 'attempt',
  startQuestionId: 'use',
  progressSnapshot: <String, Object?>{},
  currentQuestionId: null,
  resumed: false,
);

Future<List<Map<String, Object?>>> _present(
  WidgetTester tester, {
  required bool deliver,
}) async {
  final completed = <Map<String, Object?>>[];
  final stream = StreamController<SurveyShowRequest>();
  addTearDown(stream.close);
  final presenter = SurveyPresenter(
    stream: stream.stream,
    onSaveProgress: (_, __, ___) async {},
    onCompleteAttempt: (_, answers) async {
      completed.add(answers);
      return deliver;
    },
    onAbandonAttempt: (_) async => true,
    onShown: (_) {},
    onPresentationFailed: (_) {},
    onComplete: (_, __) {},
    onAbandon: (_, __) {},
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
  stream.add(
    const SurveyShowRequest(survey: _survey, attempt: _attempt, source: 'test'),
  );
  await tester.pumpAndSettle();
  return completed;
}

void main() {
  testWidgets(
      'landscape survey: Close leads without Back, Back leads + Close trails '
      'with Back, Next/Submit is a full-width footer', (tester) async {
    tester.view.physicalSize = const Size(900, 420);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final completed = await _present(tester, deliver: true);

    expect(find.text('What do you use it for?'), findsOneWidget);
    // First question: no Back, Close leading, trailing slot empty.
    expect(find.bySemanticsLabel('Back'), findsNothing);
    final close = tester.getRect(find.byKey(const ValueKey('survey-close')));
    final next = tester.getRect(find.byKey(const ValueKey('survey-next')));
    final title = tester.getRect(find.text('What do you use it for?'));
    expect(close.left, lessThan(80));
    // Footer: below the question, centred readable width, never compact.
    expect(next.top, greaterThan(title.bottom));
    expect(next.width, greaterThan(kSurfaceContentMaxWidth - 40));
    expect((next.center.dx - 450).abs(), lessThan(1));
    expect(next.bottom, lessThanOrEqualTo(420));

    await tester.tap(find.text('Lists'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('survey-next')));
    await tester.pumpAndSettle();
    expect(find.text('Anything else?'), findsOneWidget);
    // With Back: Back leading, Close trailing, Back absent from the footer.
    final back = tester.getRect(find.byKey(const ValueKey('survey-back')));
    final trailingClose =
        tester.getRect(find.byKey(const ValueKey('survey-close')));
    final submitRect = tester.getRect(find.byKey(const ValueKey('survey-next')));
    expect(back.left, lessThan(80));
    expect(trailingClose.right, greaterThan(820));
    expect(back.bottom, lessThan(submitRect.top));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('survey-footer')),
        matching: find.byKey(const ValueKey('survey-back')),
      ),
      findsNothing,
    );
    final submit = tester.widget<SurfaceNext>(
      find.byKey(const ValueKey('survey-next')),
    );
    expect(submit.label, 'Submit');
    expect(submit.compact, isFalse);
    expect(submit.expand, isTrue);

    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();
    // Going back keeps the previous selection.
    final lists = tester.getSemantics(find.bySemanticsLabel('Lists'));
    expect(lists.hasFlag(SemanticsFlag.isChecked), isTrue);

    await tester.tap(find.byKey(const ValueKey('survey-next')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Shared lists');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('survey-next')));
    await tester.pumpAndSettle();
    expect(completed.single['why'], 'Shared lists');
    expect(completed.single['use'], <String>['lists']);
    expect(find.text('Thanks!'), findsOneWidget);
    // End screen: no Back, Close leading, Done is the full-width footer CTA.
    expect(find.bySemanticsLabel('Back'), findsNothing);
    final endClose = tester.getRect(find.byKey(const ValueKey('survey-close')));
    final done =
        tester.getRect(find.byKey(const ValueKey('survey-complete-close')));
    expect(endClose.left, lessThan(80));
    expect(done.top, greaterThan(tester.getRect(find.text('Thanks!')).bottom));
    expect(done.width, greaterThan(kSurfaceContentMaxWidth - 40));
    expect(find.text('Done'), findsOneWidget);
  });

  testWidgets('keyboard open: footer Submit stays above the keyboard in '
      'portrait and landscape', (tester) async {
    for (final size in const <Size>[Size(390, 844), Size(844, 390)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = FakeViewPadding.zero;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      await _present(tester, deliver: true);
      await tester.tap(find.text('Lists'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('survey-next')));
      await tester.pumpAndSettle();

      final keyboard = size.height > size.width ? 336.0 : 200.0;
      tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
      await tester.showKeyboard(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'Shared lists');
      await tester.pumpAndSettle();
      expect(find.text('Shared lists'), findsOneWidget);

      final submit =
          tester.getRect(find.byKey(const ValueKey('survey-next')));
      final footer =
          tester.getRect(find.byKey(const ValueKey('survey-footer')));
      final headerBottom =
          tester.getRect(find.byKey(const ValueKey('survey-close'))).bottom;
      expect(submit.bottom, lessThanOrEqualTo(size.height - keyboard));
      expect(submit.width, greaterThan(300));
      // The entered text's first line is visible between header and footer.
      final editable = tester
          .state<EditableTextState>(find.byType(EditableText))
          .renderEditable;
      expect(editable.plainText, 'Shared lists');
      final lineLocal =
          editable.getLocalRectForCaret(const TextPosition(offset: 0));
      final lineTop =
          editable.localToGlobal(lineLocal.topLeft).dy;
      final lineBottom =
          editable.localToGlobal(lineLocal.bottomLeft).dy;
      expect(lineTop, greaterThanOrEqualTo(headerBottom));
      expect(lineBottom, lessThanOrEqualTo(footer.top));
      expect(lineBottom - lineTop, greaterThanOrEqualTo(16));
      // Header keeps Back leading and Close trailing with the keyboard up.
      final back = tester.getRect(find.byKey(const ValueKey('survey-back')));
      final close = tester.getRect(find.byKey(const ValueKey('survey-close')));
      expect(back.left, lessThan(close.left));
      expect(back.bottom, lessThan(submit.top));
      // Footer sits outside the scrolling question.
      expect(
        find.ancestor(
          of: find.byKey(const ValueKey('survey-next')),
          matching: find.byType(SingleChildScrollView),
        ),
        findsNothing,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });

  testWidgets('failed completion shows an inline retry', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final completed = await _present(tester, deliver: false);

    await tester.tap(find.text('For work'));
    await tester.pump();
    // Portrait: the action sits below the question in the footer.
    final next = tester.getRect(find.byKey(const ValueKey('survey-next')));
    final row = tester.getRect(find.text('Lists'));
    expect(next.top, greaterThan(row.bottom));
    await tester.tap(find.byKey(const ValueKey('survey-next')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Later');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('survey-next')));
    await tester.pumpAndSettle();
    expect(completed, hasLength(1));
    expect(find.textContaining('saved on this device'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('survey-retry')));
    await tester.pumpAndSettle();
    expect(completed, hasLength(2));
  });
}
