// اختبار شامل لمحرك تصدير الاختبار: يقيس المسافات بين الكلمات في ملف PDF
// الناتج عن PdfExamEngine نفسه (لا عن محرّك تجريبي)، للتأكد أن المسافات العربية
// لا تتآكل في أي جزء من ورقة الامتحان (الترويسة، الأسئلة، الخيارات، الفروع...).
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/models/exam.dart';
import 'package:writing_questions_app/models/exam_header.dart';
import 'package:writing_questions_app/models/question.dart';
import 'package:writing_questions_app/models/question_type.dart';
import 'package:writing_questions_app/pdf_engine/pdf_engine.dart';

import 'pdf_content_probe.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ByteData regularFontData;
  late ByteData boldFontData;

  /// أصغر عرض مسافة ممكن عند حجم خط معيّن (بين الخط العادي والعريض).
  double minimumSpaceAdvance(double fontSize) {
    final regular = spaceAdvanceFor(regularFontData, fontSize);
    final bold = spaceAdvanceFor(boldFontData, fontSize);
    return regular < bold ? regular : bold;
  }

  setUpAll(() async {
    regularFontData = await rootBundle.load(ExamFonts.regularAsset);
    boldFontData = await rootBundle.load(ExamFonts.boldAsset);
  });

  Exam buildExam() {
    return Exam(
      name: 'اختبار اللغة العربية',
      header: ExamHeader(
        subject: 'اللغة العربية',
        gradeStage: 'الثالث المتوسط',
        directorate: 'مديرية التربية',
        examType: 'اختبار نصف السنة',
        instructor: 'أ. مصطفى',
        duration: 'ساعتان',
        generalInstructions: 'اقرأ الأسئلة بتأنٍ ثم أجب عن جميع الفقرات.',
      ),
      questions: <Question>[
        Question(
          title: 'تدور الأرض',
          type: QuestionType.multipleChoice,
          marks: 2,
          category: 'القواعد',
          branches: <QuestionBranch>[
            QuestionBranch(text: 'تدور الأرض حول محورها', marks: 1),
            QuestionBranch(text: 'مدار دائري كامل', marks: 1),
          ],
          options: <QuestionOption>[
            QuestionOption(text: 'تدور الأرض حول الشمس', isCorrect: true),
            QuestionOption(text: 'مدار دائري ثابت'),
            QuestionOption(text: 'التيار الكهربائي قوي'),
          ],
        ),
        Question(
          title: 'مدار الأرض',
          type: QuestionType.trueFalse,
          marks: 1,
          options: <QuestionOption>[
            QuestionOption(text: 'صح', isCorrect: true),
            QuestionOption(text: 'خطأ'),
          ],
        ),
        Question(
          title: 'التيار الأرضي',
          type: QuestionType.fillInTheBlank,
          marks: 2,
          modelAnswer: 'مدار دائري حول المركز',
        ),
      ],
    );
  }

  test('كل فجوة بين كلمتين في ورقة الاختبار لا تقل عن عرض مسافة كاملة',
      () async {
    final bytes = await const PdfExamEngine().generate(
      exam: buildExam(),
      isTeacherVersion: false,
    );
    final probe = PdfContentProbe.fromBytes(bytes);

    expect(probe.lines, isNotEmpty, reason: 'يجب أن يحتوي الملف نصاً');

    var checkedPairs = 0;
    for (final line in probe.lines) {
      // نفحص الأزواج المتجاورة فعلاً داخل المقطع نفسه؛ فالسطر الواحد قد يضم
      // كلمات من عنصرين مختلفين (صفّان في Wrap مثلاً) وفجوتهما تباعد تخطيط
      // لا فراغ بين كلمتين (انظر ProbedLine.areAdjacentInRun).
      for (final index in line.adjacencyIndices) {
        final expected = minimumSpaceAdvance(line.words[index].fontSize);
        if (expected <= 0) {
          continue;
        }
        checkedPairs++;
        expect(
          line.gapAfter(index),
          closeTo(expected, 0.05),
          reason: 'الفجوة بين "${line.words[index].text}" و '
              '"${line.words[index + 1].text}" يجب أن تساوي عرض المسافة '
              '(${expected.toStringAsFixed(3)} نقطة عند '
              '${line.words[index].fontSize}).\n'
              'كل الفجوات في السطر: '
              '${line.gaps.map((gap) => gap.toStringAsFixed(3)).toList()}\n'
              'المُقاس: ${line.describe()}',
        );
      }
    }
    expect(
      checkedPairs,
      greaterThan(10),
      reason: 'يجب أن يفحص الاختبار عدداً معتبراً من أزواج الكلمات',
    );
  });

  test('عنوان السؤال يحافظ على مسافة كاملة مهما كانت الكلمات', () async {
    final bytes = await const PdfExamEngine().generate(
      exam: buildExam(),
      isTeacherVersion: false,
    );
    final probe = PdfContentProbe.fromBytes(bytes);

    final questionFontSize = ExamTextStyles.standard.question.fontSize!;
    final expected = minimumSpaceAdvance(questionFontSize);

    // سطر عنوان السؤال يُرسم بحجم خط السؤال (11 نقطة) وهو نص واحد متصل:
    // "س1: تدور الأرض [2 درجة]" — أي أن كل الفراغات فيه فراغاتُ نصٍّ عادية،
    // فيجب أن تساوي كلها عرض المسافة في الخط، مهما كانت الكلمات.
    final titleLines = probe.lines
        .where((line) => line.fontSize == questionFontSize)
        .toList(growable: false);
    expect(
      titleLines.length,
      3,
      reason: 'يجب أن تُرسم عناوين الأسئلة الثلاثة بحجم خط السؤال — '
          'الأسطر المقيسة: ${titleLines.map((l) => l.describe()).toList()}',
    );

    var measured = 0;
    for (final line in titleLines) {
      expect(
        line.words.length,
        greaterThanOrEqualTo(4),
        reason: 'سطر العنوان يحتوي رقم السؤال وكلمتي العنوان والدرجة — '
            '${line.describe()}',
      );
      expect(
        line.words.any((word) => word.text.contains(':')),
        isTrue,
        reason: 'سطر العنوان يجب أن يحمل رقم السؤال بعلامة النقطتين — '
            '${line.describe()}',
      );
      for (final index in line.adjacencyIndices) {
        final pairFontSize = line.words[index].fontSize;
        measured++;
        expect(
          line.gapAfter(index),
          closeTo(minimumSpaceAdvance(pairFontSize), 0.05),
          reason: 'الفجوة بين "${line.words[index].text}" و '
              '"${line.words[index + 1].text}" في سطر العنوان يجب أن تساوي '
              'عرض المسافة (${expected.toStringAsFixed(3)} نقطة عند '
              '$pairFontSize) — ${line.describe()}',
        );
      }
    }
    expect(
      measured,
      greaterThanOrEqualTo(9),
      reason: 'يجب أن تُقاس فراغات عناوين الأسئلة الثلاثة فعلاً (3 أسطر × 4 '
          'فراغات على الأقل) — الأسطر المقيسة: '
          '${titleLines.map((l) => l.describe()).toList()}',
    );
  });
}
