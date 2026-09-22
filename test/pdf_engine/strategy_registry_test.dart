import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/models/label_alphabet.dart';
import 'package:writing_questions_app/models/question.dart';
import 'package:writing_questions_app/models/question_type.dart';
import 'package:writing_questions_app/pdf_engine/pdf_engine.dart';

IndexedQuestion _item(int number, {String category = '', String title = ''}) {
  return IndexedQuestion(
    number: number,
    question: Question(
      title: title.isEmpty ? 'سؤال $number' : title,
      type: QuestionType.essay,
      category: category,
    ),
  );
}

void main() {
  group('ExamStrategies.forSubject', () {
    test('maps Arabic subject to ArabicExamStrategy', () {
      final strategy = ExamStrategies.forSubject('اللغة العربية');
      expect(strategy, isA<ArabicExamStrategy>());
      expect(strategy.textDirection, isNotNull);
      expect(strategy.sectionsByCategory, isTrue);
      expect(strategy.questionNumberLabel(3), 'س3');
      expect(strategy.marksUnit, 'درجة');
    });

    test('maps Islamic subject to IslamicExamStrategy', () {
      final strategy = ExamStrategies.forSubject('التربية الإسلامية');
      expect(strategy, isA<IslamicExamStrategy>());
      expect(strategy.sectionsByCategory, isTrue);
    });

    test('maps English subject to a flat LTR strategy', () {
      final strategy = ExamStrategies.forSubject('اللغة الإنجليزية');
      expect(strategy, isA<EnglishExamStrategy>());
      expect(strategy.sectionsByCategory, isFalse);
      expect(strategy.questionNumberLabel(1), 'Q1');
      expect(strategy.marksUnit, 'marks');
    });

    test('falls back to GenericExamStrategy for other subjects', () {
      expect(ExamStrategies.forSubject('الرياضيات'), isA<GenericExamStrategy>());
      expect(ExamStrategies.forSubject(''), isA<GenericExamStrategy>());
    });
  });

  group('groupQuestionsByCategory', () {
    test('groups consecutive runs while preserving order and numbering', () {
      final groups = groupQuestionsByCategory([
        _item(1, category: 'القواعد'),
        _item(2, category: 'القواعد'),
        _item(3, category: 'الأدب'),
        _item(4, category: 'الأدب'),
        _item(5, category: 'القواعد'),
      ]);

      expect(groups, hasLength(3));
      expect(groups[0].category, 'القواعد');
      expect(groups[0].items.map((item) => item.number), [1, 2]);
      expect(groups[1].category, 'الأدب');
      expect(groups[1].items.map((item) => item.number), [3, 4]);
      expect(groups[2].category, 'القواعد');
      expect(groups[2].items.map((item) => item.number), [5]);
    });

    test('treats blank categories as a single null group', () {
      final groups = groupQuestionsByCategory([_item(1), _item(2)]);
      expect(groups, hasLength(1));
      expect(groups.single.category, isNull);
      expect(groups.single.items, hasLength(2));
    });

    test('returns no groups for an empty list', () {
      expect(groupQuestionsByCategory(const []), isEmpty);
    });
  });

  group('LabelAlphabet', () {
    test('assigns Arabic labels beyond the alphabet as numbers', () {
      expect(LabelAlphabet.at(0), 'أ');
      expect(LabelAlphabet.at(5), 'و');
      expect(LabelAlphabet.at(12), '13');
    });
  });
}
