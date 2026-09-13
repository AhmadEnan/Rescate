// LessonProgress semantics: intermediate steps must NOT mark the lesson
// complete; only an explicit Finish tap does.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rescate_app/features/educational/screens/educational_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('never-opened lesson reports zero progress', () async {
    final (reached, total, completed) = await LessonProgress.load('x');
    expect(reached, 0);
    expect(total, 0);
    expect(completed, isFalse);
  });

  test('advancing steps records progress without completing', () async {
    await LessonProgress.recordStep('cpr_basics', 0, 4);
    await LessonProgress.recordStep('cpr_basics', 1, 4);

    final (reached, total, completed) = await LessonProgress.load('cpr_basics');
    expect(reached, 2);
    expect(total, 4);
    expect(completed, isFalse);
  });

  test('recordStep keeps the furthest step (no regress on back-swipe)',
      () async {
    await LessonProgress.recordStep('cpr_basics', 2, 4);
    await LessonProgress.recordStep('cpr_basics', 0, 4); // swiped back

    final (reached, _, _) = await LessonProgress.load('cpr_basics');
    expect(reached, 3);
  });

  test('markCompleted sets the flag and clamps reached to the total',
      () async {
    await LessonProgress.recordStep('cpr_basics', 1, 4);
    await LessonProgress.markCompleted('cpr_basics', 4);

    final (reached, total, completed) = await LessonProgress.load('cpr_basics');
    expect(completed, isTrue);
    expect(reached, 4);
    expect(total, 4);
  });

  test('lessons are isolated by id', () async {
    await LessonProgress.markCompleted('cpr_basics', 4);
    await LessonProgress.recordStep('burns', 0, 5);

    final (_, _, cprCompleted) = await LessonProgress.load('cpr_basics');
    final (burnsReached, _, burnsCompleted) = await LessonProgress.load('burns');
    expect(cprCompleted, isTrue);
    expect(burnsReached, 1);
    expect(burnsCompleted, isFalse);
  });
}
