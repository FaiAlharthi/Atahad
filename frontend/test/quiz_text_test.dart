import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:atahad/features/proofs/quiz_text.dart';

void main() {
  test('Arabic questions keep Latin parentheses and square brackets together', () {
    expect(quizTextDirection('ما ناتج (x + 1) في [score]?'), TextDirection.rtl);
    final display = quizDisplayText('ما ناتج (x + 1) في [score]?');
    expect(display, contains('\u2066(x + 1)\u2069'));
    expect(display, contains('\u2066[score]\u2069'));
  });
  test('English questions retain English direction and isolate Arabic phrases', () {
    expect(quizTextDirection('What does (تحسين الأداء) mean?'), TextDirection.ltr);
    expect(quizDisplayText('What does (تحسين الأداء) mean?'), contains('(\u2067تحسين الأداء\u2069)'));
  });
  test('Options remove only their leading label, not parentheses in the answer', () {
    expect(quizOptionBody('B) improve (يحسّن)'), 'improve (يحسّن)');
    expect(quizOptionBody('A) (x + 1)'), '(x + 1)');
    expect(quizTextDirection(quizOptionBody('C) فائدة (benefit)')), TextDirection.rtl);
  });
  testWidgets('English quiz text is readable inside the Arabic app layout', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(body: QuizQuestionText('Choose the synonym of (benefit).')),
    )));
    final text = tester.widget<Text>(find.byType(Text).last);
    expect(text.textDirection, TextDirection.ltr);
    expect(text.data, contains('(benefit)'));
    expect(tester.takeException(), isNull);
  });
}
