import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usergist_feedback/usergist_feedback.dart';

void main() {
  testWidgets('builder integration presents SDK routes through navigator key', (
    tester,
  ) async {
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

    expect(find.text('Suggestions'), findsOneWidget);
    expect(find.text('No suggestions yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
