import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usergist_feedback/src/ui/surface_controls.dart';
import 'package:usergist_feedback/usergist_feedback.dart';

void main() {
  testWidgets('board, new suggestion and a failed post use themed controls',
      (tester) async {
    tester.view.physicalSize = const Size(900, 420);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        builder: (context, child) => UserGistProvider(
          navigatorKey: navigatorKey,
          child: child ?? const SizedBox.shrink(),
        ),
        home: const Scaffold(body: Text('Host app')),
      ),
    );
    await tester.pumpAndSettle();

    UserGist.openRequestsBoard();
    await tester.pumpAndSettle();
    expect(find.text('No suggestions yet'), findsOneWidget);
    expect(find.text('0 ideas'), findsOneWidget);
    expect(find.bySemanticsLabel('Close requests board'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('requests-board-create')));
    await tester.pumpAndSettle();
    expect(find.text('New suggestion'), findsOneWidget);
    SurfaceNext post() => tester.widget<SurfaceNext>(
          find.byKey(const ValueKey('request-submit-post')),
        );
    expect(post().disabled, isTrue);

    await tester.enterText(find.byType(TextField).first, 'Shared lists');
    await tester.enterText(find.byType(TextField).last, 'Plan trips together.');
    await tester.pump();
    expect(post().disabled, isFalse);

    // The SDK is not started, so the post fails and explains it inline.
    await tester.tap(find.byKey(const ValueKey('request-submit-post')));
    await tester.pumpAndSettle();
    expect(find.textContaining("wasn't posted"), findsOneWidget);
    expect(find.text('New suggestion'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('landscape keyboard keeps the focused description first line '
      'and Post visible', (tester) async {
    tester.view.physicalSize = const Size(874, 402);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        builder: (context, child) => UserGistProvider(
          navigatorKey: navigatorKey,
          child: child ?? const SizedBox.shrink(),
        ),
        home: const Scaffold(body: Text('Host app')),
      ),
    );
    await tester.pumpAndSettle();
    UserGist.openRequestsBoard();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('requests-board-create')));
    await tester.pumpAndSettle();

    // Software keyboard covers the lower 60% of a landscape phone.
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    await tester.pumpAndSettle();
    await tester.showKeyboard(find.byType(TextField).last);
    await tester.enterText(find.byType(TextField).last, 'Plan trips');
    await tester.pumpAndSettle();

    const keyboardTop = 402.0 - 240.0;
    final header = tester.getRect(
      find.byKey(const ValueKey('request-submit-post')),
    );
    final description = tester.getRect(find.byType(TextField).last);
    // The field's first line sits between the header and the keyboard.
    expect(description.top, greaterThanOrEqualTo(header.bottom));
    expect(description.top + 40, lessThanOrEqualTo(keyboardTop));
    expect(find.text('Plan trips'), findsOneWidget);
    // Post stays in the header, above the keyboard.
    expect(header.bottom, lessThanOrEqualTo(keyboardTop));
  });
}
