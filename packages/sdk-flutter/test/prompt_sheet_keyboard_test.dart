import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usergist_feedback/src/models/prompt.dart';
import 'package:usergist_feedback/src/models/question.dart';
import 'package:usergist_feedback/src/ui/prompt_sheet.dart';

void main() {
  testWidgets('landscape keyboard leaves Next fully reachable at larger text',
      (tester) async {
    tester.view.physicalSize = const Size(900, 400);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    PromptSheetResult? result;
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data:
            MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(1.3)),
        child: child!,
      ),
      home: Builder(
          builder: (context) => Scaffold(
                body: Center(
                    child: TextButton(
                  onPressed: () async {
                    result = await showModalBottomSheet<PromptSheetResult>(
                      context: context,
                      isScrollControlled: true,
                      enableDrag: false,
                      builder: (_) => const PromptSheet(
                        prompt:
                            ClientPrompt(id: 'keyboard', questions: <Question>[
                          ShortTextQuestion(
                              id: 'answer', title: 'Tell us more'),
                        ]),
                        themeOverrides: null,
                      ),
                    );
                  },
                  child: const Text('Open'),
                )),
              )),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Landscape answer');
    expect(
        MediaQuery.of(tester.element(find.byType(PromptSheet)))
            .viewInsets
            .bottom,
        240);
    final scrollBounds =
        tester.getRect(find.byType(SingleChildScrollView).first);
    // Drag the sheet margin, rather than the text editor's own scroll view.
    await tester.dragFrom(
        Offset(scrollBounds.left + 12, scrollBounds.bottom - 12),
        const Offset(0, -600));
    await tester.pumpAndSettle();
    // A single-question prompt's action reads Submit (last step).
    final next = find.text('Submit');
    final bounds = tester.getRect(next);
    expect(bounds.top, greaterThanOrEqualTo(0));
    expect(bounds.bottom, lessThanOrEqualTo(160));
    // Landscape keeps Submit as the full-width footer, below the field and
    // outside the scrolling question (never a compact header action).
    final footer =
        tester.getRect(find.byKey(const ValueKey<String>('feedback-next')));
    expect(footer.width, greaterThan(400));
    expect(footer.top,
        greaterThanOrEqualTo(tester.getRect(find.byType(TextField)).top));
    expect(
      find.ancestor(
        of: find.byKey(const ValueKey<String>('feedback-next')),
        matching: find.byType(SingleChildScrollView),
      ),
      findsNothing,
    );
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(result?.dismissed, isFalse);
    expect(result?.answers.single.value, 'Landscape answer');
  });
}
