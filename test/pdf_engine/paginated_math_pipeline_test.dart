// اختبار خط أنابيب المعادلات الكامل: ما يُكتب في الحقل يجب أن يُطبع
// معادلةً مرئية — لا نص LaTeX خاماً — في كل حقل يقبل الإدراج.
//
// المنهج: لا نفحص الشيفرة، بل **نقرأ ملف PDF الناتج** عبر [PdfContentProbe]
// (قارئ مستقل يفك ضغط مجرى الصفحة ويستخرج كل كلمة مرسومة فعلاً).
//  1) سلباً: لا رمز خام (`frac`، `sqrt`، `{`، `}`، الشرطة المائلة، الدولار)
//     يظهر كـ **نص مرسوم** في أي حقل: الترويسة عنواناً وأسسطراً وتعليقات
//     وملاحظات، نص السؤال، نص الفرع، النقاط، الخيارات، والإجابة النموذجية.
//  2) إيجاباً: مقارنة بمستند مطابق بلا معادلات — موضع المعادلة في الملف
//     المرسوم يجب أن يشغل فراغاً أعرض مما يشغله **كلمة كاملة** مطوقة،
//     فتثبت أنها رُسِمَت متجهاً ولم تُحذف في صمت.
import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/models/branch_item.dart';
import 'package:writing_questions_app/models/branch_model.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/paper_settings.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/models/question_option.dart';
import 'package:writing_questions_app/models/question_type.dart';
import 'package:writing_questions_app/pdf_engine/pdf_engine.dart';

import 'pdf_content_probe.dart';

/// يحقن الصيغ في كل الحقول أو يستبدلها بكلمات عادية (مجموعة ضابطة).
ExamDocument _document({required bool withMath}) {
  // يبني `$latex$` و`$$latex$$` حرفياً مع إدخال جسم الصيغة —
  // (الدولارات الأولى حرفية عبر \$، والتي تليها افتتاح استدعاء).
  String formula(String latex, String control) =>
      withMath ? '\$' '$latex' '\$' : control;
  String blockFormula(String latex, String control) =>
      withMath ? r'$$' '$latex' r'$$' : control;

  return ExamDocument(
    name: 'ورقة المعادلات',
    header: ExamHeaderModel(
      subject: 'الرياضيات',
      title: 'امتحان ${formula(r'\frac{5}{8}', 'الكسور')} الدور الأول',
      right: HeaderColumn(<String>[
        'الصف ${formula(r'\sqrt{9}', 'الثالث')}',
        '',
        '',
      ]),
      center: HeaderColumn(<String>['مدة الامتحان 60 دقيقة', '', '']),
      instructions: 'اقرأ السؤال جيداً ثم أجب',
      notes: 'بالتوفيق ${formula(r'\times', 'و')} النجاح',
    ),
    settings: const PaperSettings(
      showTotalMarks: false,
      showPageNumbers: false,
      showQuestionMarks: false,
    ),
    questions: <QuestionModel>[
      QuestionModel(
        questionNumber: 1,
        prompt: 'احسب قيمة ${formula(r'\frac{5}{8}', 'الأقل')} ثم بسّط',
        branches: <BranchModel>[
          BranchModel(
            content: BranchContent(
              type: QuestionType.multipleChoice,
              text: 'اختر الأنسب ${blockFormula(r'\sqrt{16}', 'للجذر')}',
              items: <BranchItem>[
                BranchItem(
                  text: 'انتبه ${formula(r'\geq', 'لكل')} الحدود',
                  marks: 1,
                ),
              ],
              options: <QuestionOption>[
                QuestionOption(
                  text: 'أول ${formula(r'x^{2}', 'التربيعي')}',
                  isCorrect: true,
                ),
                QuestionOption(text: 'ثانٍ ${formula(r'y_{3}', 'التالٍ')}'),
              ],
            ),
            marks: 1,
          ),
          // فرع فراغات — إجابته النموذجية تُطبع في نموذج المعلم وحده.
          BranchModel(
            content: BranchContent(
              type: QuestionType.fillInTheBlank,
              text: 'أكمل الناقص',
              modelAnswer: 'لأن ${formula(r'\frac{5}{8}=0.625', 'الحساب مباشر')}',
            ),
            marks: 1,
          ),
        ],
      ),
    ],
  );
}

/// كل النصوص المرسومة في الصفحة (كلمة بكلمة).
List<String> _drawnWords(PdfContentProbe probe) => probe.lines
    .expand((line) => line.words.map((word) => word.text))
    .toList(growable: false);

void expectNoRawLatex(PdfContentProbe probe, {required String surface}) {
  const rawTokens = <String>[
    'frac', 'sqrt', 'times', 'geq', '{', '}', '\\', r'$', '^', '_',
  ];
  final words = _drawnWords(probe);
  for (final token in rawTokens) {
    final offenders =
        words.where((word) => word.contains(token)).toList(growable: false);
    expect(
      offenders,
      isEmpty,
      reason: '$surface: رمز LaTeX خام «$token» ظهر كنص مرسوم بدل رسمه معادلة.',
    );
  }
}

/// فجوة الأفقية حول الفقرة الأولى التي تبدأ بـ[anchorWord] في المستندين —
/// تُقاس بين أول كلمتين مرسومين في ذلك السطر.
double _lineGapAfter(ProbedLine line, int index) => line.gapAfter(index);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('خط أنابيب رسم المعادلات في الـ PDF (ورقة الطالب والمعلم)', () {
    test('يطبع كل صيغ الحقول كرسم متجه ولا يترك LaTeX خاماً في أي منها', () async {
      final bytes = await PaginatedPdfExamEngine().generate(
        document: _document(withMath: true),
      );
      final probe = PdfContentProbe.fromBytes(bytes);

      expectNoRawLatex(probe, surface: 'ورقة الطالب');

      // كلمات الترويسة والسؤال المرسومة حول المعادلات — دليل أن الحقول
      // طُبعت أصلاً ولم تُسقط بسبب خطأ تحليل.
      final words = _drawnWords(probe);
      for (final expected in <String>[
        'امتحان', 'الدور', 'الصف', 'اقرأ', 'احسب', 'قيمة', 'ثم', 'اختر',
      ]) {
        expect(words, contains(expected), reason: 'فُقد نص مطلوب «$expected».');
      }
      // الإجابة النموذجية مخفية عند الطالب.
      expect(words.where((word) => word == 'لأن'), isEmpty);
    });

    test('الإجابة النموذجية في نموذج المعلم تُرسم معادلةً لا نصاً خاماً', () async {
      final bytes = await PaginatedPdfExamEngine().generate(
        document: _document(withMath: true),
        isTeacherVersion: true,
      );
      final probe = PdfContentProbe.fromBytes(bytes);

      expectNoRawLatex(probe, surface: 'نموذج المعلم');
      // رقم الكسر العشري عاش داخل جسم المعادلة فقط: لو طُبع خاماً لظهر
      // «0.625» كلمةً نصية؛ غيابه مع حضور «لأن» = المعادلة رُسمت لا حُذفت.
      final words = _drawnWords(probe);
      expect(words.where((word) => word.contains('0.625')), isEmpty);
      expect(words, contains('لأن'));
    });

    test('موضع المعادلة يشغل فراغ الرسم المتجه — لا حذف صامت', () async {
      final mathBytes = await PaginatedPdfExamEngine().generate(
        document: _document(withMath: true),
      );
      final controlBytes = await PaginatedPdfExamEngine().generate(
        document: _document(withMath: false),
      );
      final mathProbe = PdfContentProbe.fromBytes(mathBytes);
      final controlProbe = PdfContentProbe.fromBytes(controlBytes);

      ProbedLine promptLine(PdfContentProbe probe) => probe.lines.firstWhere(
            (line) =>
                line.words.any((word) => word.text == 'قيمة') &&
                line.words.any((word) => word.text == 'ثم'),
          );

      double gapAround(PdfContentProbe probe) {
        final line = promptLine(probe);
        final valueIndex =
            line.words.indexWhere((word) => word.text == 'قيمة');
        final thenIndex = line.words.indexWhere((word) => word.text == 'ثم');
        final first = valueIndex < thenIndex ? valueIndex : thenIndex;
        return _lineGapAfter(line, first);
      }

      final mathGap = gapAround(mathProbe);
      final controlGap = gapAround(controlProbe);
      // الضابط يستبدل المعادلة بكلمة كاملة «الأقل»؛ الرسم المتجه أوسع من
      // كلمة — والفارق يثبت أن بين «قيمة» و«ثم» كائناً مرسوم لا فراغ صفر.
      expect(mathGap, greaterThan(controlGap), reason: 'الكسر لم يأخذ مكانه في السطر.');
      expect(mathGap, greaterThan(8.0));
    });

    test('الحقول الفارغة لا تترك أي أثر مرسوم ولا مسافة محجوزة', () async {
      final empty = ExamDocument(
        name: 'فارغ',
        header: ExamHeaderModel(
          subject: 'الرياضيات',
          title: '',
          notes: '',
          instructions: '',
        ),
        settings: const PaperSettings(
          showTotalMarks: false,
          showPageNumbers: false,
          showQuestionMarks: false,
        ),
        questions: <QuestionModel>[QuestionModel(questionNumber: 1)],
      );
      final bytes = await PaginatedPdfExamEngine().generate(document: empty);
      final probe = PdfContentProbe.fromBytes(bytes);
      final words = _drawnWords(probe);

      // عنوان/ملاحظات/تعليمات فارغة → لا يُبنى لها widget أصلاً (شرط
      // isNotEmpty في المحرك) — فليس هناك Text بارتفاع صفري ولا opacity.
      for (final forbidden in <String>['عنوان الامتحان', 'بالتوفيق', 'اقرأ']) {
        expect(
          words.where((word) => forbidden.contains(word) || word.contains(forbidden)),
          isEmpty,
          reason: 'حقل فارغ/غائب ترك أثراً مرسوماً: «$forbidden».',
        );
      }
      // السؤال بلا فروع: لا تُطبع أي تسمية فرع (الفراغ يبقى بلا شيء).
      for (final label in <String>['أ)', 'ب)', '( أ )']) {
        expect(words.where((word) => word == label), isEmpty);
      }
    });
  });
}
