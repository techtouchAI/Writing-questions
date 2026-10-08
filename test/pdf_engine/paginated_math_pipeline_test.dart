// اختبار خط أنابيب المعادلات الكامل: ما يُكتب في الحقل يجب أن يُطبع
// معادلةً مرئية — لا نص LaTeX خاماً — في كل حقل يقبل الإدراج.
//
// المسار المقصوص: LaTeX ← محرك العرض نفسه (flutter_math_fork عبر مضيف
// اللقطات) ← لقطة عالية الدقة ← صورة في الصفحة. المضيف هنا وهمي لكنه يُلصق
// صوراً حقيقية من `dart:ui` (انظر fake_math_host.dart)، فيُختبر المسار كله:
// الصيغ التي طلبتها الشجرة فعلاً، وعدد الصور التي نزلت الملف، وفراغ السطر.
//
// المنهج: لا نفحص الشيفرة، بل **نقرأ ملف PDF الناتج** عبر [PdfContentProbe]
// (قارئ مستقل يفك ضغط مجرى الصفحة ويستخرج كل كلمة مرسومة فعلاً). ملاحظة
// هندسية: طبقة النص في الـ PDF تُخزَّن بالعربية مشكّلة (أشكال عرض + قلب
// بصري)، لذلك المطابقة تتم على **مراسي ASCII** لا تتأثر بالتشكيل.
//  1) سلباً: لا رمز خام (frac/sqrt/{/}/\/$) يظهر كـ **نص مرسوم** في أي حقل:
//     منطوق السؤال ونصه، منطوق الفرع، النقاط، والخيارات.
//  2) عددياً: كل معادلة تُلغي كلمة مطبوعة واحدة — الفرق بين عدد كلمات
//     المستند الضابط (بلا صيغ) ومستند الصيغ يساوي عدد المقاطع بالضبط؛ لو
//     طُبعت صيغة خاماً لَظهرت كلماتها الزائدة عن العدد، ولو حُذفت لصمتاً
//     لاستحالت الفجوة المكانية أدناه.
//  3) مكانياً: سطر نص السؤال يحمل مِرساة ASCII على كل جانب من المعادلة؛
//     المسافة الأفقية بين المِرساتين في ملف الصيغ يجب أن تتجاوز نظيرتها
//     في الملف الضابط — دليل فراغ صورة المعادلة لا فراغ كلمة.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/models/branch_item.dart';
import 'package:writing_questions_app/models/branch_model.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/paper_settings.dart';
import 'package:writing_questions_app/models/point_kind.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/models/question_option.dart';
import 'package:writing_questions_app/pdf_engine/pdf_engine.dart';

import 'fake_math_host.dart';
import 'pdf_content_probe.dart';

/// عدد مقاطع الصيغ التي تُلغي كلمة ضابطة واحدة من طبقة النص (صيغة المِرساتين
/// لا تُلغي كلمة: الضابط يترك F5A وF5B متجاورتين).
const int _documentFormulaCount = 7;

/// يحقن الصيغ في كل الحقول، أو يبني المستند الضابط المطابق بكلمة
/// (بلا كلمة في منطوق السؤال — مِرساتا F5A/F5B بقيتا لقياس الفجوة).
ExamDocument _document({required bool withMath}) {
  // يبني `$latex$` و`$$latex$$` حرفياً مع إدخال جسم الصيغة.
  String formula(String latex, String control) =>
      withMath ? '\$' '$latex' '\$' : control;
  String blockFormula(String latex, String control) =>
      withMath ? r'$$' '$latex' r'$$' : control;
  // صيغة المنطوق محشورة بين مِرساة ASCII: الضابط يترك المِرساتين
  // متجاورتين بمسافة واحدة، والمرسوم يضع بينهما صورة المعادلة أعرض.
  String anchored(String latex, String controlWord) => withMath
      ? 'F5A \$' '$latex' '\$ F5B'
      : (controlWord.isEmpty ? 'F5A F5B' : 'F5A $controlWord F5B');

  return ExamDocument(
    name: 'ورقة المعادلات',
    header: ExamHeaderModel(subject: 'الرياضيات', time: '60'),
    settings: const PaperSettings(showQuestionMarks: false),
    questions: <QuestionModel>[
      QuestionModel(
        questionNumber: 1,
        statement: anchored(r'\frac{5}{8}', ''),
        body: 'اشرح ${formula(r'\sqrt{9}', 'الجذر')} ثم أجب',
        branches: <BranchModel>[
          BranchModel(
            content: BranchContent(
              statement: 'اختر الأنسب ${blockFormula(r'\sqrt{16}', 'للجذر')}',
              items: <BranchItem>[
                BranchItem(
                  text: 'انتبه ${formula(r'\geq', 'لكل')} الحدود',
                  marks: 1,
                ),
                BranchItem(
                  kind: PointKind.multipleChoice,
                  text: 'اختر',
                  options: <QuestionOption>[
                    QuestionOption(text: 'أول ${formula(r'x^{2}', 'التربيعي')}'),
                    QuestionOption(text: 'ثانٍ ${formula(r'y_{3}', 'التالين')}'),
                  ],
                ),
              ],
            ),
            marks: 1,
          ),
          // فرع فراغات — منطوقه ونقطته يحملان صيغة تُرسم معادلةً لا نصاً خاماً.
          BranchModel(
            content: BranchContent(
              statement: 'أكمل الناقص ${formula(r'\frac{5}{8}=0.625', 'مباشر')}',
              items: <BranchItem>[
                BranchItem(
                  kind: PointKind.fillBlank,
                  text: 'جملة ${formula(r'\times', 'وثم')} فراغ',
                ),
              ],
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

/// ست صيغ تُرسَم صوراً في الـ PDF — اثنتان لكل سؤال من الستة بالتناوب.
///
/// (نُقلت مع اختبار ٦×٣ من مسار Word المحذوف في C5؛ الاختبار نفسه لم
/// يمسّ Word قط — يقرأ ملف PDF الناتج فقط.)
const List<String> _pool = <String>[
  r'5^{2} + 9',
  r'\sqrt{66}',
  r'\frac{5}{8}',
  r'x_{1} - x_{2}',
  r'\frac{\frac{1}{2}}{3}',
  r'\vec{F}',
];

/// ورقة ٦ أسئلة × ٣ معادلات في النقاط (١٨ موضعاً من ٦ صيغ فريدة).
ExamDocument _sixByThree() => ExamDocument(
      name: '٦×٣',
      header: ExamHeaderModel.initial(subject: 'الرياضيات'),
      questions: <QuestionModel>[
        for (var q = 0; q < 6; q++)
          QuestionModel(
            id: 'q${q + 1}',
            questionNumber: q + 1,
            statement: 'س${q + 1}/ احسب مما يأتي ثم علل',
            items: <BranchItem>[
              for (var i = 0; i < 3; i++)
                BranchItem(
                  id: 'q${q + 1}i$i',
                  text: 'نق${q + 1}$i: أوجد قيمة \$${_pool[(q * 3 + i) % _pool.length]}\$',
                ),
            ],
          ),
      ],
    );

/// سطر مِرساتَي نص السؤال؛ يعيد المسافة الأفقية المطلقة بينهما بالنقاط.
///
/// مرن عمداً: يبحث عن سطر واحد يحمل بالضبط مِرساة F5A واحدة وF5B واحدة
/// (متساهلاً مع أي كلمات أخرى على نفس السطر)، ويقارن بين حافتي المِرساتين.
double _anchorsSpan(PdfContentProbe probe) {
  List<ProbedWord> anchors(ProbedLine line, String name) => line.words
      .where((word) => word.text.trim() == name)
      .toList(growable: false);
  final candidates = probe.lines
      .where((line) => anchors(line, 'F5A').length == 1 && anchors(line, 'F5B').length == 1)
      .toList(growable: false);
  expect(
    candidates,
    hasLength(1),
    reason: 'لم يُعثر على سطر المِرساتين F5A/F5B. الأسطر المرسومة:\n'
        '${probe.lines.map((line) => line.describe()).join('\n')}',
  );
  final line = candidates.single;
  final a = anchors(line, 'F5A').single;
  final b = anchors(line, 'F5B').single;
  final left = a.x < b.x ? a : b;
  final right = identical(left, a) ? b : a;
  return right.x - (left.x + left.advanceWidth);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // مضيف يلتقط كل صيغة كما تطلبها الشجرة: بلا هذا يغيب المضيف فتُطبع
  // الصيغ نصاً مقروءاً (وهو ارتداد صحيح يُغطّى في مكانه) ولا يُختبر الرسم.
  final host = FakeMathHost();
  setUp(host.attach);
  tearDown(host.detach);

  group('خط أنابيب رسم المعادلات في الـ PDF (ورقة الأسئلة)', () {
    test('يطبع كل صيغ الحقول صورةً من محرك العرض ولا يترك LaTeX خاماً', () async {
      final bytes = await PaginatedPdfExamEngine().generate(
        document: _document(withMath: true),
      );
      final probe = PdfContentProbe.fromBytes(bytes);

      // ملف للمراجعة البشرية: هذا ملف المُصدِّر الحقيقي بأكمله (ورقة بصيغ في
      // كل حقل). ملاحظة صادقة: في بيئة الاختبار لا شجرة ودجت، فاللقطات تأتي
      // من المضيف الوهمي — أي أن مواضع المعادلات وأبعادها وطبقة النص حقيقية،
      // وصور المعادلات نفسها مربعات سواد مكانية. الملف يُراجع للهيكل، وشكل
      // المعادلة يُراجع بالتصدير من التطبيق نفسه.
      final sample = File('build/math_samples/math-pdf-samples.pdf');
      await sample.parent.create(recursive: true);
      await sample.writeAsBytes(bytes);

      expectNoRawLatex(probe, surface: 'ورقة الأسئلة');

      // كل صيغة في كل حقل وصلت إلى المحرك تُلتمس له لقطة: لا حقل يُنسى
      // (منطوق، نص، منطوق فرع، نقطة، خيار، صيغة عرض $$…$$).
      expect(
        host.requestedLatex,
        containsAll(<String>[
          r'\frac{5}{8}',
          r'\sqrt{9}',
          r'\sqrt{16}',
          r'\geq',
          r'x^{2}',
          r'y_{3}',
          r'\frac{5}{8}=0.625',
          r'\times',
        ]),
        reason: 'صيغ لم تطلب المحرك: كل حقل يقبل LaTeX يجب أن يمرّ باللقطة.',
      );
      // وفي الملف صورٌ بقدرها: معادلة مرسومة = كائن صورة في الصفحة.
      expect(imagesInPdf(bytes), greaterThanOrEqualTo(host.requests.length));

      // المِرساة الرقمية الوحيدة في الترويسة (الوقت 60) حية — طبقة النص
      // تعمل ولم تُبتلع الصفحة كلها. (الأرقام تُطبع مشرقية: ٦٠)
      final words = _drawnWords(probe);
      expect(words, contains('٦٠'));
      expect(words, contains('F5A'));
      expect(words, contains('F5B'));
      // ولا وجود لأي أثر إجابة (لا نص مكتوب ولا علامة).
      expect(words.where((word) => word.contains('الإجابة')), isEmpty);
      expect(words.where((word) => word == 'M7'), isEmpty);
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
      expect(controlWords.length - mathWords.length, _documentFormulaCount);
    });

    test('موضع المعادلة يشغل فراغ صورتها في السطر — لا حذف صامت', () async {
      final mathBytes = await PaginatedPdfExamEngine().generate(
        document: _document(withMath: true),
      );
      final controlBytes = await PaginatedPdfExamEngine().generate(
        document: _document(withMath: false),
      );

      final mathProbe = PdfContentProbe.fromBytes(mathBytes);
      final controlProbe = PdfContentProbe.fromBytes(controlBytes);
      final mathSpan = _anchorsSpan(mathProbe);
      final controlSpan = _anchorsSpan(controlProbe);
      final mathAnchorLines = mathProbe.lines
          .where((line) => line.words.any((word) => word.text.trim() == 'F5A') &&
              line.words.any((word) => word.text.trim() == 'F5B'))
          .map((line) => line.describe())
          .join(' | ');

      // الضابط: «F5A F5B» بمسافة كلمة واحدة. المرسوم: بينهما صورة الكسر
      // المعادلة المرسومة — الفارق أعرض من نصف حرف وأصغر من سطر — إن حُذفت المعادلة
      // لتساوى الحقلان تماماً.
      expect(mathSpan, greaterThan(controlSpan + 5.0),
          reason: 'الكسر لم يأخذ مكانه في السطر — رُسم؟ حُذف؟');
      expect(
        mathSpan,
        greaterThan(9.0),
        reason: 'mathSpan=${mathSpan.toStringAsFixed(3)}pt; '
            'anchors=$mathAnchorLines; '
            'images=${mathProbe.images.map((image) => image.toString()).join(' | ')}',
      );
    });

    test('الحقول الفارغة لا تترك أي أثر مرسوم ولا مسافة محجوزة', () async {
      final empty = ExamDocument(
        name: 'فارغ',
        header: ExamHeaderModel(subject: 'الرياضيات'),
        settings: const PaperSettings(showQuestionMarks: false),
        questions: <QuestionModel>[QuestionModel(questionNumber: 1)],
      );
      final bytes = await PaginatedPdfExamEngine().generate(document: empty);
      final probe = PdfContentProbe.fromBytes(bytes);
      final words = _drawnWords(probe);

      // حقول المنطوق/النص الفارغة → لا يُبنى لها widget أصلاً — فليس هناك Text
      // بارتفاع صفري ولا opacity.
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

    // (نُقل من مسار Word المحذوف في C5؛ كان يقرأ PDF فقط.)
    test('PDF الموازي: الورقة نفسها ٦×٣ تُرسم من محرك المعاينة بلا نص خام',
        () async {
      // نفس المحرك الذي يعرض المعاينة (flutter_math_fork عبر مضيف اللقطات):
      // كل الصيغ الست الفريدة تُطلب له وتُنزل صوراً — المكتبة تعيد استعمال
      // صورة الصيغة المتطابقة، فالعدد ≥ ٦ صور لـ١٨ موضعاً.
      final bytes =
          await PaginatedPdfExamEngine().generate(document: _sixByThree());

      expect(host.requestedLatex, containsAll(_pool));
      expect(imagesInPdf(bytes), greaterThanOrEqualTo(_pool.length));

      // لا رمز LaTeX خاماً في طبقة النص المرسومة (كل صيغة صورة).
      final words = <String>[
        for (final line in PdfContentProbe.fromBytes(bytes).lines)
          ...line.words.map((word) => word.text),
      ];
      expect(words, isNotEmpty);
      for (final token in <String>[
        'frac', 'sqrt', '{', '}', '\\\\', r'$', '^', '_',
      ]) {
        expect(
          words.where((word) => word.contains(token)).toList(),
          isEmpty,
          reason: 'رمز خام «$token» ظهر نصاً مرسوماً في PDF الورقة ٦×٣.',
        );
      }

      final sample = File('build/math_samples/real-pdf-6x3-math.pdf');
      await sample.parent.create(recursive: true);
      await sample.writeAsBytes(bytes);
    });
  });
}
