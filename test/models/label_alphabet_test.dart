import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/models/label_alphabet.dart';

void main() {
  group('LabelAlphabet', () {
    test('starts with أ ب ج د and covers the extended letters', () {
      expect(LabelAlphabet.at(0), 'أ');
      expect(LabelAlphabet.at(1), 'ب');
      expect(LabelAlphabet.at(2), 'ج');
      expect(LabelAlphabet.at(3), 'د');
      expect(LabelAlphabet.at(11), 'ل');
      expect(LabelAlphabet.at(12), 'م');
      expect(LabelAlphabet.at(13), 'ن');
      expect(LabelAlphabet.letters.length, greaterThanOrEqualTo(24));
    });

    test('falls back to numbers past the alphabet without a branch cap', () {
      final last = LabelAlphabet.letters.length;
      expect(LabelAlphabet.at(last), '${last + 1}');
      expect(LabelAlphabet.at(last + 50), '${last + 51}');
    });

    test('guards negative indices', () {
      expect(LabelAlphabet.at(-1), '1');
    });
  });
}
