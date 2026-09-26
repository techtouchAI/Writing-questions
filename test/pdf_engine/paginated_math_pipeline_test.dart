// اختبار خط أنابيب المعادلات الكامل: ما يُكتب في الحقل يجب أن يُطبع
// معادلةً مرئية — لا نص LaTeX خاماً — في كل حقل يقبل الإدراج.
//
// المنهج: لا نفحص الشيفرة، بل **نقرأ ملف PDF الناتج** عبر [PdfContentProbe]
// (قارئ مستقل يفك ضغط مجرى الصفحة ويستخرج كل كلمة مرسومة فعلاً). ملاحظة
// هندسية: طبقة النص في الـ PDF تُخزَّن بالعربية مشكّلة (أشكال عرض + قلب
// بصري)، لذلك المطابقة تتم على **مراسي ASCII** لا تتأثر بالتشكيل.
//  1) سلباً: لا رمز خام (frac/sqrt/{/}/\/$) يظهر كـ **نص مرسوم** في أي حقل:
//     الترويسة عنواناً وأسسطراً وتعليقات وملاحظات، نص السؤال، نص الفرع،
//     النقاط، الخيارات، والإجابة النموذجية في نموذج المعلم.
//  2) عددياً: كل معادلة تُلغي كلمة مطبوعة واحدة — الفرق بين عدد كلمات
//     المستند الضابط (بلا صيغ) ومستند الصيغ يساوي عدد المقاطع بالضبط؛ لو
//     طُبعت صيغة خاماً لَظهرت كلماتها الزائدة عن العدد، ولو حُذفت لصمتاً
//     لاستحالت الفجوة المكانية أدناه.
//  3) مكانياً: سطر نص السؤال يحمل مِرساة ASCII على كل جانب من المعادلة؛
//     المسافة الأفقية بين المِرساتين في ملف الصيغ يجب أن تتجاوز نظيرتها
//     في الملف الضابط — دليل فراغ الرسم المتجه لا فراغ كلمة.
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

/// عدد مقاطع الصيغ في نسخة الطالب (الإجابة النموذجية مخفية) — كل مقطع
/// يُلغي كلمة ضابطة واحدة من طبقة النص.
const int _studentFormulaCount = 7;

/// ونسخة المعلم تضيف مقطع الإجابة النموذجية.
const int _teacherFormulaCount = 8;

/// يحقن الصيغ في كل الحقول، أو يبني المستند الضابط المطابق بكلمة
/// (بلا كلمة في نص السؤال — مِرساتا F5A/F5B بقيتا لقياس الفجوة).
ExamDocument _document({required bool withMath}) {
  // يبني `$latex$` و`$$latex$$` حرفياً مع إدخال جسم الصيغة.
  String formula(String latex, String control) =>
      withMath ? '\$' '$latex' '\$' : control;
  String blockFormula(String latex, String control) =>
      withMath ? r'$$' '$latex' r'$$' : control;
  // صيغة نص السؤال محشورة بين مِرساة ASCII: الضابط يترك المِرساتين
  // متجاورتين بمسافة واحدة، والمرسوم يضع بينهن صورة متجهة أعرض.
  String anchored(String latex, String controlWord) => withMath
      ? 'F5A \$' '$latex' '\$ F5B'
      : (controlWord.isEmpty ? 'F5A F5B' : 'F5A $controlWord F5B');

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
      notes: 'بالتوفيق ${formula(r'\times', 'وثم')} النجاح',
    ),
    settings: const PaperSettings(
      showTotalMarks: false,
      showPageNumbers: false,
      showQuestionMarks: false,
    ),
    questions: <QuestionModel>[
      QuestionModel(
        questionNumber: 1,
        prompt: anchored(r'\frac{5}{8}', ''),
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
                QuestionOption(text: 'ثانٍ ${formula(r'y_{3}', 'التالين')}'),
              ],
            ),
            marks: 1,
          ),
          // فرع فراغات — إجابته النموذجية تُطبع في نموذج المعلم وحده.
          BranchModel(
            content: BranchContent(
              type: QuestionType.fillInTheBlank,
              text: 'أكمل الناقص',
              modelAnswer: 'M7 ${formula(r'\frac{5}{8}=0.625', 'مباشر')}',
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

/// سطر مِرساتَي نص السؤال؛ يعيد المسافة الأفقية المطلقة بينهما بالنقاط.
double _anchorsSpan(PdfContentProbe probe) {
  final candidates = probe.lines
      .where((candidate) =>
          candidate.words.length == 2 &&
          candidate.words.every((word) => word.text == 'F5A' || word.text == 'F5B') &&
          candidate.words.any((word) => word.text == 'F5A') &&
          candidate.words.any((word) => word.text == 'F5B'))
      .toList(growable: false);
  expect(candidates, hasLength(1),
      reason: 'لم يُعثر على سطر المِرساتين F5A/F5B — طبقة النص تغيّرت.');
  final line = candidates.single;
  final left = line.words[0].x < line.words[1].x ? line.words[0] : line.words[1];
  final right = identical(left, line.words[0]) ? line.words[1] : line.words[0];
  return right.x - (left.x + left.advanceWidth);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('خط أنابيب رسم المعادلات في الـ PDF (ورقة الطالب والمعلم)', () {
    test('يطبع كل صيغ الحقول كرسم متجه ولا يترك LaTeX خاماً في أي منها', () async {
      final bytes = await PaginatedPdfExamEngine().generate(
        document: _document(withMath: true),
      );
      final probe = PdfContentProbe.fromBytes(bytes);

      expectNoRawLatex(probe, surface: 'ورقة الطالب');

      // المِرساة الرقمية الوحيدة في الترويسة (60 دقيقة) حية — طبقة النص
      // تعمل ولم تُبتلع الصفحة كلها؛ والإجابة النموذجية مخفية عند الطالب.
      final words = _drawnWords(probe);
      expect(words, contains('60'));
      expect(words, contains('F5A'));
      expect(words, contains('F5B'));
      expect(words.where((word) => word == 'M7'), isEmpty);
    });

    test('الإجابة النموذجية في نموذج المعلم تُرسم معادلةً لا نصاً خاماً', () async {
      final bytes = await PaginatedPdfExamEngine().generate(
        document: _document(withMath: true),
        isTeacherVersion: true,
      );
      final probe = PdfContentProbe.fromBytes(bytes);

      expectNoRawLatex(probe, surface: 'نموذج المعلم');
      // رقم الكسر العشري عاش داخل جسم المعادلة فقط: لو طُبعت الصيغة خاماً
      // لظهر «0.625» كلمةً نصية؛ غيابه مع حضور مِرساة الإجابة «M7» يثبت
      // أنها رُسِمَت متجهه هناك بالذات.
      final words = _drawnWords(probe);
      expect(words.where((word) => word.contains('0.625')), isEmpty);
      expect(words, contains('M7'));
    });

    test('عدد الكلمات المطبوعة ينقص بمقدار عدد الصيغ بالضبط — لا نص زائد', () async {
      final mathBytes = await PaginatedPdfExamEngine().generate(
        document: _document(withMath: true),
      );
      final controlBytes = await PaginatedPdfExamEngine().generate(
        document: _document(withMath: false),
      );
      final mathWords = _drawnWords(PdfContentProbe.fromBytes(mathBytes));
      final controlWords = _drawnWords(PdfContentProbe.fromBytes(controlBytes));

      // لو طُبعت أي صيغة خاماً لَظهرت كلماتها (مثل $\frac{5}{8}$) وزاد
      // العدد عن الضابط؛ والنقصان المطلوب = عدد المقاطع بالضبط.
      expect(controlWords.length - mathWords.length, _studentFormulaCount);

      final teacherMath = _drawnWords(
        PdfContentProbe.fromBytes(
          await PaginatedPdfExamEngine().generate(
            document: _document(withMath: true),
            isTeacherVersion: true,
          ),
        ),
      );
      final teacherControl = _drawnWords(
        PdfContentProbe.fromBytes(
          await PaginatedPdfExamEngine().generate(
            document: _document(withMath: false),
            isTeacherVersion: true,
          ),
        ),
      );
      expect(teacherControl.length - teacherMath.length, _teacherFormulaCount);
    });

    test('موضع المعادلة يشغل فراغ الرسم المتجه — لا حذف صامت', () async {
      final mathBytes = await PaginatedPdfExamEngine().generate(
        document: _document(withMath: true),
      );
      final controlBytes = await PaginatedPdfExamEngine().generate(
        document: _document(withMath: false),
      );

      final mathSpan = _anchorsSpan(PdfContentProbe.fromBytes(mathBytes));
      final controlSpan = _anchorsSpan(PdfContentProbe.fromBytes(controlBytes));

      // الضابط: «F5A F5B» بمسافة كلمة واحدة. المرسوم: بينهما صورة الكسر
      // المتجه — الفارق أعرض من نصف حرف وأصغر من سطر — إن حُذفت المعادلة
      // لتساوى الحقلان تماماً.
      expect(mathSpan, greaterThan(controlSpan + 5.0),
          reason: 'الكسر لم يأخذ مكانه في السطر — رُسم؟ حُذف؟');
      expect(mathSpan, greaterThan(9.0));
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
      for (final forbidden in <String>['F5A', 'F5B', 'M7']) {
        expect(
          words.where((word) => word == forbidden),
          isEmpty,
          reason: 'حقل فارغ/غائب ترك أثراً مرسوماً: «$forbidden».',
        );
      }
      // السؤال بلا فروع: لا تُطبع أي تسمية فرع ولا أقواس خيارات.
      for (final label in <String>['(', ')', 'M7']) {
        expect(words.where((word) => word == label), isEmpty);
      }
    });
  });
}
