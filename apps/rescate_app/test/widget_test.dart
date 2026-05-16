import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('test harness can build material widgets', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: Text('Rescate')));
    await tester.pump();

    expect(find.text('Rescate'), findsOneWidget);
  });
}
