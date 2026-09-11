import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rescate_app/features/community/widgets/case_payload_sheet.dart';

void main() {
  testWidgets(
      'Task 1(a): consent + successful location read populates coordinates in payload',
      (tester) async {
    CasePayloadSheetResult? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showCasePayloadSheet(
                  context,
                  responderName: 'Dr. Test Responder',
                  availableVitals: const [],
                  locationReader: () async =>
                      const LocationReadResult.success(31.2357, 30.0444),
                );
              },
              child: const Text('Open Sheet'),
            ),
          ),
        ),
      ),
    );

    // Open the bottom sheet
    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    // Verify sheet is displayed
    expect(find.text('Send consult to Dr. Test Responder'), findsOneWidget);

    // Find the location toggle switch
    final switchFinder = find.byType(Switch);
    expect(switchFinder, findsOneWidget);
    final Switch initialSwitch = tester.widget(switchFinder);
    expect(initialSwitch.value, isFalse);

    // Turn on location consent
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    // Verify switch is now ON and coordinates are displayed in subtitle
    final Switch enabledSwitch = tester.widget(switchFinder);
    expect(enabledSwitch.value, isTrue);
    expect(find.textContaining('31.23570, 30.04440'), findsOneWidget);

    // Tap "Send consult request"
    await tester.tap(find.text('Send consult request'));
    await tester.pumpAndSettle();

    // Verify the resulting payload has real coordinates and includeLocation is true
    expect(result, isNotNull);
    expect(result!.payload.includeLocation, isTrue);
    expect(result!.payload.latitude, closeTo(31.2357, 0.0001));
    expect(result!.payload.longitude, closeTo(30.0444, 0.0001));
  });

  testWidgets(
      'Task 1(b): location denial leaves payload without coordinates and surfaces UI reason',
      (tester) async {
    CasePayloadSheetResult? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showCasePayloadSheet(
                  context,
                  responderName: 'Dr. Test Responder',
                  availableVitals: const [],
                  locationReader: () async => const LocationReadResult.failure(
                      'Location permission denied.'),
                );
              },
              child: const Text('Open Sheet'),
            ),
          ),
        ),
      ),
    );

    // Open the bottom sheet
    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    // Toggle location consent ON
    final switchFinder = find.byType(Switch);
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    // Because location read failed with denial, switch must NOT stay on
    final Switch afterDenialSwitch = tester.widget(switchFinder);
    expect(afterDenialSwitch.value, isFalse);

    // The UI must explicitly surface the denial reason
    expect(
      find.textContaining(
          'Location permission denied. Your consult will be sent without a location.'),
      findsOneWidget,
    );

    // Tap "Send consult request"
    await tester.tap(find.text('Send consult request'));
    await tester.pumpAndSettle();

    // Verify payload has NO coordinates and includeLocation is false
    expect(result, isNotNull);
    expect(result!.payload.includeLocation, isFalse);
    expect(result!.payload.latitude, isNull);
    expect(result!.payload.longitude, isNull);
  });
}
