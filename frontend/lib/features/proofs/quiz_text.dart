import 'package:flutter/material.dart';

final _arabicLetter = RegExp(r'[\u0621-\u064A\u066E-\u06D3\u06FA-\u06FF]');
final _firstLetter = RegExp(r'[A-Za-z\u0621-\u064A\u066E-\u06D3\u06FA-\u06FF]');
final _bidiControls = RegExp(r'[\u202A-\u202E\u2066-\u2069]');
final _latinRun = RegExp(
  r'\([^()\n\u0600-\u06FF]*[A-Za-z][^()\n\u0600-\u06FF]*\)'
  r'|\[[^\[\]\n\u0600-\u06FF]*[A-Za-z][^\[\]\n\u0600-\u06FF]*\]'
  r'|[A-Za-z][A-Za-z0-9_./:+\-]*(?:[ \t]+[A-Za-z0-9_./:+\-]+)*',
);
final _arabicRun = RegExp(r'[\u0621-\u064A\u066E-\u06D3\u06FA-\u06FF][\u0621-\u065F\u066E-\u06D3\u06FA-\u06FF]*(?:[ \t]+[\u0621-\u064A\u066E-\u06D3\u06FA-\u06FF][\u0621-\u065F\u066E-\u06D3\u06FA-\u06FF]*)*');

TextDirection quizTextDirection(String text) {
  final letter = _firstLetter.firstMatch(text)?.group(0);
  return letter != null && !_arabicLetter.hasMatch(letter)
      ? TextDirection.ltr : TextDirection.rtl;
}

String quizDisplayText(String text) {
  final clean = text.replaceAll(_bidiControls, '');
  final rtl = quizTextDirection(clean) == TextDirection.rtl;
  // Isolate opposite-direction phrases so brackets stay with their contents.
  return clean.replaceAllMapped(rtl ? _latinRun : _arabicRun,
      (match) => '${rtl ? '\u2066' : '\u2067'}${match[0]}\u2069');
}

class QuizQuestionText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  const QuizQuestionText(this.text, {super.key, this.style});
  @override
  Widget build(BuildContext context) => Text(
    quizDisplayText(text),
    textDirection: quizTextDirection(text),
    textAlign: TextAlign.start,
    style: style,
  );
}

String quizOptionBody(String text) => text.replaceFirst(RegExp(r'^\s*[ABCabc][).:\-]\s*'), '').trim();
