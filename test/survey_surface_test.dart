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
      'landscape survey: Close then Back and primary share an aligned header',
      (tester) async {
    tester.view.physicalSize = const Size(900, 420);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final completed = await _present(tester, deliver: true);

    expect(find.text('What do you use it for?'), findsOneWidget);
    // First question: no Back, Close leading and compact Next trailing.
    expect(find.bySemanticsLabel('Back'), findsNothing);
    final close = tester.getRect(find.byKey(const ValueKey('survey-close')));
    final next = tester.getRect(find.byKey(const ValueKey('survey-next')));
    final title = tester.getRect(find.text('What do you use it for?'));
    expect(close.left, closeTo((900 - kSurfaceContentMaxWidth) / 2, 1));
    expect(next.bottom, lessThan(title.top));
    expect(next.width, lessThan(150));
    expect(next.center.dy, closeTo(close.center.dy, 1));
    expect(find.byKey(const ValueKey('survey-footer')), findsNothing);

    await tester.tap(find.text('Lists'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('survey-next')));
    await tester.pumpAndSettle();
    expect(find.text('Anything else?'), findsOneWidget);
    // With Back: Close then Back on the left, Submit on the right.
    final back = tester.getRect(find.byKey(const ValueKey('survey-back')));
    final trailingClose =
        tester.getRect(find.byKey(const ValueKey('survey-close')));
    final submitRect = tester.getRect(find.byKey(const ValueKey('survey-next')));
    expect(trailingClose.right, lessThan(back.left));
    expect(back.right, lessThan(submitRect.left));
    expect(back.center.dy, closeTo(submitRect.center.dy, 1));
    final field = tester.getRect(find.byType(TextField));
    expect(field.left, closeTo(trailingClose.left, 1));
    expect(field.right, closeTo(submitRect.right, 1));
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
    expect(submit.compact, isTrue);
    expect(submit.expand, isFalse);

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
    // End screen retains the same compact header action.
    expect(find.bySemanticsLabel('Back'), findsNothing);
    final endClose = tester.getRect(find.byKey(const ValueKey('survey-close')));
    final done =
        tester.getRect(find.byKey(const ValueKey('survey-complete-close')));
    expect(endClose.left, closeTo(close.left, 1));
    expect(done.bottom, lessThan(tester.getRect(find.text('Thanks!')).top));
    expect(done.width, lessThan(150));
    expect(find.text('Done'), findsOneWidget);
  });

  testWidgets('keyboard open: Submit and entered text stay visible in '
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
      final landscape = size.width > size.height;
      final contentBottom = landscape
          ? size.height - keyboard
          : tester.getRect(find.byKey(const ValueKey('survey-footer'))).top;
      final headerBottom =
          tester.getRect(find.byKey(const ValueKey('survey-close'))).bottom;
      expect(submit.bottom, lessThanOrEqualTo(size.height - keyboard));
      expect(submit.width, landscape ? lessThan(150) : greaterThan(300));
      // The entered text's first line remains in the visible content viewport.
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
      expect(lineBottom, lessThanOrEqualTo(contentBottom));
      expect(lineBottom - lineTop, greaterThanOrEqualTo(16));
      final back = tester.getRect(find.byKey(const ValueKey('survey-back')));
      final close = tester.getRect(find.byKey(const ValueKey('survey-close')));
      if (landscape) {
        expect(close.right, lessThan(back.left));
        expect(back.center.dy, closeTo(submit.center.dy, 1));
        expect(find.byKey(const ValueKey('survey-footer')), findsNothing);
      } else {
        expect(back.left, lessThan(close.left));
        expect(back.bottom, lessThan(submit.top));
      }
      // Both action placements sit outside the scrolling question.
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
