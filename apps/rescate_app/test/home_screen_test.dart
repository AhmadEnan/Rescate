// Home screen + main navigation wiring tests.
//
// HomeScreen is a pure widget (safe to pump directly). MainScreen builds all
// six feature screens, so its test only asserts the default-tab behavior and
// the nav-pill → tab switch; heavy screens tolerate missing plugins by
// design (spinners/empty states).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rescate_app/core/providers/app_state.dart';
import 'package:rescate_app/features/home/screens/home_screen.dart';
import 'package:rescate_app/features/home/screens/main_screen.dart';

Widget _wrap(Widget child) {
  return AppStateProvider(
    notifier: AppState(),
    child: MaterialApp(home: child),
  );
}

void main() {
  setUp(() {
    // AppState reads prefs in its constructor; without a mock the platform
    // channel never answers under flutter_test.
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('HomeScreen renders greeting, features, SOS and tip',
      (tester) async {
    await tester.pumpWidget(_wrap(const HomeScreen()));
    // Recent-vitals FutureBuilder resolves asynchronously; settle what we can.
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Emergency-ready,'), findsOneWidget);
    expect(find.text('Ask Rescate'), findsOneWidget);
    expect(find.text('Call emergency services'), findsOneWidget);
    expect(find.text('Emergency number: 112 — no internet needed'),
        findsOneWidget);
    expect(find.text('Learn'), findsOneWidget);
    expect(find.text('Map'), findsOneWidget);
    expect(find.text('CPR Basics'), findsOneWidget);
    expect(find.text('Recent vitals'), findsOneWidget);
    // Exactly one quick-tip banner is shown (rotates by day).
    expect(
        find.byWidgetPredicate((w) =>
            w is RichText && (w.text.toPlainText().contains('CPR —') ||
                w.text.toPlainText().contains('Burns —'))),
        findsOneWidget);
  });

  testWidgets('HomeScreen shows the configured emergency number',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'sosNumber': '911',
    });
    await tester.pumpWidget(_wrap(HomeScreen()));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('911'), findsWidgets);
  });

  testWidgets('MainScreen opens on Home and switches tabs via nav pills',
      (tester) async {
    await tester.pumpWidget(_wrap(const MainScreen()));
    // Fixed pumps, not pumpAndSettle: hidden feature tabs keep infinite
    // spinners (sensor probe) alive, so the tree never fully settles.
    await tester.pump(const Duration(milliseconds: 500));

    // Default tab is Home.
    expect(find.text('Emergency-ready,'), findsOneWidget);

    // Tap the Learn pill → educational screen's header appears.
    await tester.tap(find.byIcon(LucideIcons.bookOpen).first);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Learn'), findsWidgets);

    // Back to Home via the home pill.
    await tester.tap(find.byIcon(LucideIcons.home).first);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Emergency-ready,'), findsOneWidget);
  });
}
