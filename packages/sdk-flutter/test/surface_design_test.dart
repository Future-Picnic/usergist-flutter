import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usergist_feedback/src/models/inapp_message.dart';
import 'package:usergist_feedback/src/models/prompt.dart';
import 'package:usergist_feedback/src/models/question.dart';
import 'package:usergist_feedback/src/ui/inapp_layout.dart';
import 'package:usergist_feedback/src/ui/prompt_sheet.dart';
import 'package:usergist_feedback/src/ui/questions/nps_question.dart';
import 'package:usergist_feedback/src/ui/surface_controls.dart';
import 'package:usergist_feedback/src/ui/surface_primitives.dart';
import 'package:usergist_feedback/src/ui/surface_tokens.dart';
import 'package:usergist_feedback/src/ui/theme_resolver.dart';

const _midnight = ResolvedPromptTheme(
  primary: Color(0xFF8B7CFF),
  background: Color(0xFF14121F),
  text: Color(0xFFF4F2FF),
  subtext: Color(0xFFA9A4C4),
  border: Color(0xFF2C2840),
  radius: 20,
);

void _setView(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _openSheet(WidgetTester tester, ClientPrompt prompt) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showModalBottomSheet<PromptSheetResult>(
              context: context,
              isScrollControlled: true,
              enableDrag: false,
              backgroundColor: Colors.transparent,
              elevation: 0,
              constraints: const BoxConstraints(),
              builder: (_) => PromptSheet(prompt: prompt, themeOverrides: null),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

const _textPrompt = ClientPrompt(
  id: 'p',
  questions: <Question>[
    ShortTextQuestion(id: 'q', title: 'What should improve?'),
  ],
);

void main() {
  group('label colour on primary uses real WCAG contrast', () {
    test('orange and yellow brands get black labels', () {
      expect(surfaceReadableOn(const Color(0xFFD97706)), const Color(0xFF000000));
      expect(surfaceReadableOn(const Color(0xFFFACC15)), const Color(0xFF000000));
      expect(surfaceReadableOn(const Color(0xFFFFFFFF)), const Color(0xFF000000));
    });

    test('dark and saturated brands get white labels', () {
      expect(surfaceReadableOn(const Color(0xFF111111)), const Color(0xFFFFFFFF));
      expect(surfaceReadableOn(const Color(0xFF6154E8)), const Color(0xFFFFFFFF));
      expect(surfaceReadableOn(const Color(0xFF1D4ED8)), const Color(0xFFFFFFFF));
    });

    test('derived washes come from the theme, not fixed greys', () {
      expect(_midnight.fill, _midnight.text.withAlpha(15));
      expect(_midnight.tint, _midnight.primary.withAlpha(26));
      expect(_midnight.onPrimary, const Color(0xFF000000));
    });
  });

  testWidgets('feedback sheet spans the full width in landscape with Close '
      'leading and a full-width footer action', (tester) async {
    _setView(tester, const Size(900, 420));
    await _openSheet(tester, _textPrompt);

    final sheet = tester.getRect(find.byType(PromptSheet));
    expect(sheet.width, 900);
    final close = tester.getRect(find.bySemanticsLabel('Close'));
    final submit = tester.getRect(find.byKey(const ValueKey('feedback-next')));
    final field = tester.getRect(find.byType(TextField));
    // Close leading; feedback has no Back, so nothing trails in the header.
    expect(close.left, lessThan(80));
    expect(find.bySemanticsLabel('Back'), findsNothing);
    // Submit is the footer below the question, spanning the readable column.
    expect(submit.top, greaterThan(field.bottom));
    expect(submit.width, greaterThan(kSurfaceContentMaxWidth - 40));
    expect((submit.center.dx - 450).abs(), lessThan(1));
    // Content keeps the 560 readable measure, centred.
    expect(field.width, lessThanOrEqualTo(kSurfaceContentMaxWidth));
    expect((field.center.dx - 450).abs(), lessThan(1));
  });

  testWidgets('feedback sheet keeps the primary action in a portrait footer',
      (tester) async {
    _setView(tester, const Size(390, 844));
    await _openSheet(tester, _textPrompt);

    final sheet = tester.getRect(find.byType(PromptSheet));
    expect(sheet.width, 390);
    final submit = tester.getRect(find.byKey(const ValueKey('feedback-next')));
    final field = tester.getRect(find.byType(TextField));
    expect(submit.top, greaterThan(field.bottom));
    expect(submit.width, greaterThan(300));
  });

  testWidgets('wide NPS row centres every numeral, including 10',
      (tester) async {
    _setView(tester, const Size(900, 420));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 560,
            child: NpsQuestionView(
              question: const NpsQuestion(id: 'n', title: 'Recommend us?'),
              theme: _midnight,
              score: 10,
              followUp: '',
              onScore: (_) {},
              onFollowUp: (_) {},
            ),
          ),
        ),
      ),
    );
    for (final n in <int>[0, 5, 10]) {
      final digit = tester.getRect(find.text('$n'));
      final cell = tester.getRect(
        find.ancestor(of: find.text('$n'), matching: find.byType(Material)).first,
      );
      expect((digit.center.dx - cell.center.dx).abs(), lessThan(0.5));
      expect((digit.center.dy - cell.center.dy).abs(), lessThan(1));
    }
    // Selected label uses the contrast colour on the primary fill.
    final ten = tester.widget<Text>(find.text('10'));
    expect(ten.style?.color, _midnight.onPrimary);
  });

  testWidgets('narrow portrait NPS keeps the vertical list with 10 at the top',
      (tester) async {
    _setView(tester, const Size(390, 844));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: NpsQuestionView(
              question: const NpsQuestion(id: 'n', title: 'Recommend us?'),
              theme: _midnight,
              score: null,
              followUp: '',
              onScore: (_) {},
              onFollowUp: (_) {},
            ),
          ),
        ),
      ),
    );
    final ten = tester.getRect(find.text('10'));
    final zero = tester.getRect(find.text('0'));
    expect(ten.top, lessThan(zero.top));
    expect(find.text('Extremely likely'), findsOneWidget);
  });

  testWidgets('NPS picks its layout from its own width, not the window',
      (tester) async {
    _setView(tester, const Size(1024, 768));
    Widget nps(double width) => MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Center(
                child: SizedBox(
                  width: width,
                  child: NpsQuestionView(
                    question: const NpsQuestion(id: 'n', title: 'Recommend?'),
                    theme: _midnight,
                    score: null,
                    followUp: '',
                    onScore: (_) {},
                    onFollowUp: (_) {},
                  ),
                ),
              ),
            ),
          ),
        );
    // A narrow column on a wide window keeps the vertical list.
    await tester.pumpWidget(nps(400));
    expect(
      tester.getRect(find.text('10')).top,
      lessThan(tester.getRect(find.text('0')).top),
    );
    // A 536-wide content column (560 measure minus padding) gets the row.
    await tester.pumpWidget(nps(536));
    expect(
      (tester.getRect(find.text('10')).center.dy -
              tester.getRect(find.text('0')).center.dy)
          .abs(),
      lessThan(1),
    );
  });

  testWidgets('selected choice uses tint and border, not a solid flood',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChoiceRow(
            label: 'For work',
            selected: true,
            kind: ChoiceKind.radio,
            onTap: () {},
            theme: _midnight,
          ),
        ),
      ),
    );
    final material = tester.widget<Material>(
      find.descendant(of: find.byType(ChoiceRow), matching: find.byType(Material)),
    );
    expect(material.color, _midnight.tint);
    final label = tester.widget<Text>(find.text('For work'));
    expect(label.style?.color, _midnight.text);
  });

  testWidgets('slide-up message floats as an inset card above the safe edge',
      (tester) async {
    _setView(tester, const Size(390, 844));
    const message = ArmedInAppMessage(
      messageId: 'm',
      eventName: 'e',
      format: 'slideup',
      title: 'New in this version',
      body: 'Plan trips together with shared lists.',
      imageUrl: null,
      backgroundColor: null,
      accentColor: null,
      backdropEnabled: true,
      ctas: <InAppCta>[
        InAppCta(label: 'Try shared lists', action: 'dismiss'),
        InAppCta(label: 'Later', action: 'dismiss'),
      ],
      autoDismissSeconds: null,
      screenAllowlist: <String>[],
      screenDenylist: <String>[],
      forceShow: false,
    );
    InAppCta? tapped;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: InAppMessageLayout(
              message: message,
              format: InAppFormat.slide,
              theme: _midnight,
              onClose: () {},
              onCta: (cta, _) => tapped = cta,
            ),
          ),
        ),
      ),
    );
    final card = tester.getRect(
      find
          .descendant(
            of: find.byType(InAppMessageLayout),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(card.left, greaterThanOrEqualTo(12));
    expect(card.right, lessThanOrEqualTo(378));
    expect(card.bottom, lessThanOrEqualTo(844 - 12));
    // Primary sits trailing when side by side.
    final primary = tester.getRect(find.text('Try shared lists'));
    final secondary = tester.getRect(find.text('Later'));
    expect(primary.left, greaterThan(secondary.left));
    await tester.tap(find.text('Try shared lists'));
    expect(tapped?.label, 'Try shared lists');
  });

  testWidgets('disabled primary action uses a neutral fill', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SurfaceNext(
            onPressed: () {},
            theme: _midnight,
            disabled: true,
          ),
        ),
      ),
    );
    final material = tester.widget<Material>(
      find.descendant(of: find.byType(SurfaceNext), matching: find.byType(Material)),
    );
    expect(material.color, _midnight.fill);
  });
}
