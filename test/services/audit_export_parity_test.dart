// =============================================================================
// تدقيق التصدير (PDF + DOCX) — مرافقة لـ test/wizard/preview_buttons_functional_audit_test.dart
//
// كل اختبار يقيس الناتج الفعلي (محتوى PDF عبر PdfContentProbe، وXML حقيقي من
// ملف DOCX مفكوك) ويكافئه بسلوك Microsoft Word/المعاينة. نتائج PASS/FAIL في
// سجلات CI هي الأدلة (gh run view <id> --log-failed).
//
// الدليل ليس: وجود الشيفرة، نظافة المحلل، أو أن "الناتج وُجد".
// =============================================================================
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writing_questions_app/layout/paper_metrics.dart';
import 'package:writing_questions_app/models/branch_item.dart';
import 'package:writing_questions_app/models/branch_model.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_font.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/floating_element.dart';
import 'package:writing_questions_app/models/paper_divider.dart';
import 'package:writing_questions_app/models/paper_font.dart';
import 'package:writing_questions_app/models/paper_text_style.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/models/question_option.dart';
import 'package:writing_questions_app/models/question_type.dart';
import 'package:writing_questions_app/models/subject_layout.dart';
import 'package:writing_questions_app/pdf_engine/exam_fonts.dart';
import 'package:writing_questions_app/pdf_engine/paginated_pdf_exam_engine.dart';
import 'package:writing_questions_app/services/docx_document_export_service.dart';
import 'package:writing_questions_app/views/wizard/paper_styles.dart';

import '../pdf_engine/pdf_content_probe.dart';

// نص طويل مشترك لقياس تباعد الأسطر (شاشة مقابل PDF).
const String _longArabic =
    'يتضمن هذا السؤال نصاً طويلاً من اللغة العربية يهدف إلى قياس تباعد الأسطر '
    'على الشاشة ومقارنته بما يُطبع في ملف PDF دون أي فروق تُذكر بين المحركين.';

String get _longTextSample =>
    List<String>.filled(8, _longArabic).join(' ');

ExamDocument _doc({
  required List<QuestionModel> questions,
  String subject = 'اللغة العربية',
  ExamHeaderModel? header,
  List<FloatingElement> floatingElements = const <FloatingElement>[],
}) =>
    ExamDocument(
      name: 'audit-export',
      header: header ?? ExamHeaderModel.ministerialDefault(subject: subject),
      questions: questions,
      floatingElements: floatingElements,
    );

QuestionModel _essay(
  String id, {
  String prompt = '',
  String text = 'نص الفرع',
  PaperTextStyle? style,
}) =>
    QuestionModel(
      id: id,
      questionNumber: 1,
      prompt: prompt,
      branches: <BranchModel>[
        BranchModel(
          id: '${id}b',
          style: style,
          content: BranchContent(
            type: QuestionType.essay,
            text: text,
          ),
        ),
      ],
    );

Future<String> _docxXml(ExamDocument document) async {
  final bytes = await DocxDocumentExportService.buildDocumentDocxBytes(
    document: document,
  );
  final archive = ZipDecoder().decodeBytes(bytes);
  final xml = archive.findFile('word/document.xml');
  return utf8.decode(xml!.content as List<int>);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ===========================================================================
  // PDF: الخطوط والأحجام
  // ===========================================================================
  test('AUD-PDF-01: أحجام الخطوط والخطوط المستخدمة في PDF تطابق الموديل', () async {
    final document = _doc(questions: <QuestionModel>[
      _essay('q1', text: 'نص الفرع بالخط الافتراضي'),
      _essay(
        'q2',
        text: 'نص الفرع بخط الطاولة',
        style: const PaperTextStyle(font: PaperFont.tajawal),
      ),
      _essay(
        'q3',
        text: 'نص الفرع بحجم مخصص',
        style: const PaperTextStyle(fontSize: 13),
      ),
    ]);
    final bytes =
        await PaginatedPdfExamEngine().generate(document: document);
    final probe = PdfContentProbe.fromBytes(bytes);

    final bodyLines =
        probe.lines.where((line) => line.fontSize == 10.5).toList();
    expect(bodyLines, isNotEmpty,
        reason: 'AUD-PDF-01: لا يوجد نص متن في PDF بحجم 10.5 المعياري.');

    expect(
      bodyLines.any((line) =>
          line.words.first.baseFont.contains('NotoNaskh')),
      isTrue,
      reason: 'AUD-PDF-01: المتن الافتراضي يجب أن يُطبع بخط Noto Naskh '
          '(الحجم 10.5) كما في المعاينة.',
    );
    expect(
      bodyLines.any(
          (line) => line.words.first.baseFont.contains('Tajawal')),
      isTrue,
      reason: 'AUD-PDF-01: اختيار خط Tajawal على الفرع لم يصل إلى PDF — '
          'الخط المطبوع غير خط الواجهة المختار.',
    );

    final size13 =
        probe.lines.where((line) => line.fontSize == 13.0).toList();
    expect(size13, isNotEmpty,
        reason: 'AUD-PDF-01: حجم الخط المخصص 13 لم يُطبَّق في PDF '
            '(Tf=13.0 غير موجود في المجرى).');
    expect(
      size13.every((line) => line.words.first.baseFont.contains('NotoNaskh')),
      isTrue,
      reason: 'AUD-PDF-01: تغيير الحجم يجب ألا يغيّر عائلة الخط (الورقة تبقى '
          'Noto Naskh).',
    );
  });

  // ===========================================================================
  // PDF: المحاذاة والضبط (حدود صحيحة + فجوات متسعة)
  // ===========================================================================
  test(
      'AUD-PDF-02: المحاذاة الأربع في PDF — حواف المحتوى الصحيحة والسطر الأخير '
      'غير ممدود (تطابق MSO)', () async {
    final document = _doc(questions: <QuestionModel>[
      _essay('q1',
          text: 'يمين قصير جدا',
          style: const PaperTextStyle(align: PaperAlign.right)),
      _essay('q2',
          text: 'يسار قصير جدا',
          style: const PaperTextStyle(align: PaperAlign.left)),
      _essay('q3',
          text: 'وسط قصير جدا',
          style: const PaperTextStyle(align: PaperAlign.center)),
      _essay('q4',
          text: List<String>.filled(5, _longArabic).join(' '),
          style: const PaperTextStyle(align: PaperAlign.justify)),
      _essay('q5',
          text: 'سطر أخير قصير جدا',
          style: const PaperTextStyle(align: PaperAlign.justify)),
    ]);
    final bytes =
        await PaginatedPdfExamEngine().generate(document: document);
    final probe = PdfContentProbe.fromBytes(bytes);

    // صندوق المحتوى: هوامش 15مم على A4 → 42.52 … 552.76 نقطة.
    const leftEdge = 42.52;
    const rightEdge = 552.76;
    const edgeTolerance = 1.5;
    // النص المقيس هنا نص **فرع**، وكتلة الفرع مُزاحة عن بداية صندوق المحتوى
    // بمقدار [PaginatedPdfExamEngine.branchIndent] (كما تُزاح فقرة الفرع في
    // Word)؛ فمساحة نص الفرع تبدأ من حدّ المحتوى الأيسر وتنتهي عند الحدّ
    // الأيمن ناقص الإزاحة — وعليها تُقاس المحاذاة والضبط.
    const branchRightEdge = rightEdge - PaginatedPdfExamEngine.branchIndent;
    const branchWidth = branchRightEdge - leftEdge;
    const branchCenterLine = (leftEdge + branchRightEdge) / 2;

    final body =
        probe.lines.where((line) => line.fontSize == 10.5).toList();
    expect(body.length, greaterThanOrEqualTo(7),
        reason: 'AUD-PDF-02: ترتيب سطور المتن غير متوقع (${body.length} سطراً) '
            '— يجب أن يضم: 3 أسطر قصيرة + ≥3 أسطر الضبط + سطر أخير.');

    final rightLine = body[0];
    final rightMost = rightLine.words.first.x + rightLine.words.first.advanceWidth;
    expect(rightMost, closeTo(branchRightEdge, edgeTolerance),
        reason: 'AUD-PDF-02: محاذاة «لليمين» يجب أن تصل بحدّ مساحة نص الفرع '
            'الأيمن ($branchRightEdge) — القيمة الفعلية $rightMost. سطر: '
            '${rightLine.describe()}');

    final leftLine = body[1];
    final leftMost =
        leftLine.words.map((word) => word.x).reduce((a, b) => a < b ? a : b);
    expect(leftMost, closeTo(leftEdge, edgeTolerance),
        reason: 'AUD-PDF-02: محاذاة «لليسار» يجب أن تصل بحدّ مساحة نص الفرع '
            'الأيسر ($leftEdge) — القيمة الفعلية $leftMost. سطر: '
            '${leftLine.describe()}');

    final centerParagraph = body[2];
    final minLeft = centerParagraph.words
        .map((word) => word.x)
        .reduce((a, b) => a < b ? a : b);
    final maxRight = centerParagraph.words
        .map((word) => word.x + word.advanceWidth)
        .reduce((a, b) => a > b ? a : b);
    expect((minLeft + maxRight) / 2, closeTo(branchCenterLine, edgeTolerance),
        reason: 'AUD-PDF-02: محاذاة «توسيط» يجب أن تتوسط مساحة نص الفرع '
            '($branchCenterLine) — القيمة الفعلية ${(minLeft + maxRight) / 2}.');

    // فجوة المسافة الطبيعية لنفس الخط/الحجم (مرجع خارجي من ملف الخط نفسه).
    final naskh = await rootBundle.load(ExamFonts.regularAsset);
    final natural = spaceAdvanceFor(naskh, 10.5);

    final justifyLines = body.sublist(3, body.length - 1);
    expect(justifyLines.length, greaterThanOrEqualTo(3),
        reason: 'AUD-PDF-02: نص الضبط يجب أن يلتف على ≥3 أسطر لقياس التمدّد.');

    // الأسطر الملتفّة: يمتد كل سطر متوسط حتى حافة مساحة نص الفرع
    // (MSO: الضبط يملأ السطر من الحافة إلى الحافة).
    const contentWidth = branchWidth;
    for (final line in justifyLines.sublist(0, justifyLines.length - 1)) {
      final minLeft = line.words
          .map((word) => word.x)
          .reduce((a, b) => a < b ? a : b);
      final maxRight = line.words
          .map((word) => word.x + word.advanceWidth)
          .reduce((a, b) => a > b ? a : b);
      expect(
        maxRight - minLeft,
        greaterThanOrEqualTo(contentWidth - 2.0),
        reason: 'AUD-PDF-02: سطر ضبط ملتفّ لم يمتد حتى حافة صندوق المحتوى '
            '(${(maxRight - minLeft).toStringAsFixed(2)} من $contentWidth) — '
            'الضبط غير مطبَّق على الأسطر الملتفّة في PDF.',
      );
    }

    // السطر الأخير من الضبط: غير ممدود (MSO: لا يُشدّ السطر الأخير).
    final lastJustifyLine = justifyLines.last;
    for (final index in lastJustifyLine.adjacencyIndices) {
      expect(
        lastJustifyLine.gapAfter(index),
        lessThanOrEqualTo(natural + 0.35),
        reason: 'AUD-PDF-02: السطر الأخير لفقرة الضبط ممدود داخل PDF — '
            'Microsoft Word لا تمدّد السطر الأخير أبداً.',
      );
    }

    // سطر منفرد بوضع الضبط: لا تمديد إطلاقاً (MSO: الضبط يخص الأسطر الملتفّة).
    final singleJustify = body.last;
    expect(singleJustify.adjacencyIndices, isNotEmpty,
        reason: 'اختبار سطر الضبط المنفرد يجب أن يحوي كلمتين متجاورتين.');
    for (final index in singleJustify.adjacencyIndices) {
      expect(
        singleJustify.gapAfter(index),
        lessThanOrEqualTo(natural + 0.35),
        reason: 'AUD-PDF-02: سطر واحد في فقرة «ضبط» ممدود في PDF — '
            'Microsoft Word لا تمدّد السطر الواحد.',
      );
    }
  });

  // ===========================================================================
  // PDF ↔ شاشة: تباعد الأسطر
  // ===========================================================================
  test('AUD-PDF-03: تباعد الأسطر — الشاشة مقابل PDF لكل قيم lineHeight',
      () async {
    final naskh = await rootBundle.load(ExamFonts.regularAsset);
    // خط الشاشة الحقيقي نفسه المستخدم في الورقة (وإلا قاست قياسات خط الاختبار).
    final fontLoader = FontLoader(ExamFont.arabicFamily);
    fontLoader.addFont(Future<ByteData>.value(naskh));
    await fontLoader.load();
    final natural = spaceAdvanceFor(naskh, 10.5);
    expect(natural, greaterThan(0));

    for (final lineHeight in <double?>[null, 1.0, 2.0, 3.0]) {
      // الشاشة: نفس مسار paper_field — resolve فوق body بقالب عربي.
      final style = PaperStyles.resolve(
        PaperStyles.body(SubjectLayoutTemplate.arabic),
        lineHeight == null ? null : PaperTextStyle(lineHeight: lineHeight),
      );
      final painter = TextPainter(
        text: TextSpan(text: _longTextSample, style: style),
        textDirection: TextDirection.rtl,
      )..layout(maxWidth: PaperMetrics.contentWidthPx);
      final metrics = painter.computeLineMetrics();
      expect(metrics.length, greaterThanOrEqualTo(3),
          reason: 'نص الشاشة يجب أن يلتف ≥3 أسطر (lineHeight=$lineHeight).');
      final screenDeltas = <double>[
        for (var i = 0; i + 1 < metrics.length; i++)
          metrics[i + 1].baseline - metrics[i].baseline,
      ];
      final screenPt =
          screenDeltas.reduce((a, b) => a + b) / screenDeltas.length *
              PaperMetrics.pointsPerPixel;

      // PDF: نفس النص ونفس تجاوز النمط، مقاساً من إحداثيات Y الحقيقية.
      final document = _doc(questions: <QuestionModel>[
        _essay(
          'q1',
          text: _longTextSample,
          style: lineHeight == null
              ? null
              : PaperTextStyle(lineHeight: lineHeight),
        ),
      ]);
      final bytes =
          await PaginatedPdfExamEngine().generate(document: document);
      final probe = PdfContentProbe.fromBytes(bytes);
      final body =
          probe.lines.where((line) => line.fontSize == 10.5).toList();
      expect(body.length, greaterThanOrEqualTo(3),
          reason: 'PDF يجب أن يلتف ≥3 أسطر متن (lineHeight=$lineHeight).');
      final pdfDeltas = <double>[
        for (var i = 0; i + 1 < body.length; i++)
          (body[i].words.first.y - body[i + 1].words.first.y).abs(),
      ];
      final pdfPt = pdfDeltas.reduce((a, b) => a + b) / pdfDeltas.length;

      final tolerance = screenPt * 0.08 + 0.5;
      expect(
        (pdfPt - screenPt).abs(),
        lessThanOrEqualTo(tolerance),
        reason: 'AUD-PDF-03: فرق تباعد الأسطر شاشة↔PDF عند '
            'lineHeight=$lineHeight: الشاشة=${screenPt.toStringAsFixed(2)}pt، '
            'PDF=${pdfPt.toStringAsFixed(2)}pt، '
            'الفارق=${(pdfPt - screenPt).abs().toStringAsFixed(2)}pt '
            'والحد المسموح ${tolerance.toStringAsFixed(2)}pt (8%). '
            'WYSIWYG يتطلب تطابق الارتفاع المطبوع مع المرئي.',
      );
    }
  });

  // ===========================================================================
  // PDF: المسافة بين الأسئلة والمسافة بين الفقرات
  // ===========================================================================
  test('AUD-PDF-04: المسافة بين الأسئلة تظهر في PDF بالمقدار المحدد (px→pt)',
      () async {
    Future<double> firstBodyY(double spacing) async {
      final document = _doc(questions: <QuestionModel>[
        QuestionModel(
          id: 'q1',
          questionNumber: 1,
          prompt: 'سؤال أول بلا فروع',
          spacingAfter: spacing,
          branches: const <BranchModel>[],
        ),
        _essay('q2', text: 'متن السؤال الثاني الذي يقيس المسافة'),
      ]);
      final bytes =
          await PaginatedPdfExamEngine().generate(document: document);
      final probe = PdfContentProbe.fromBytes(bytes);
      final body =
          probe.lines.where((line) => line.fontSize == 10.5).toList();
      expect(body, isNotEmpty,
          reason: 'لا يوجد متن للسؤال الثاني (spacing=$spacing).');
      return body.first.words.first.y;
    }

    final y0 = await firstBodyY(0);
    final y40 = await firstBodyY(40);
    final delta = y0 - y40; // 40px إضافية تدفع الثاني للأسفل → أصغر y.
    final expected = PaperMetrics.pt(40);
    expect(delta, closeTo(expected, 2.5),
        reason: 'AUD-PDF-04: المسافة بين السؤالين يجب أن يساوي '
            '${expected.toStringAsFixed(2)}pt (40px) — القيمة الفعلية '
            '${delta.toStringAsFixed(2)}pt؛ إما أن spacingAfter غير مطبَّق في '
            'PDF أو محوّل بوحدات خاطئة.');
  });

  test('AUD-PDF-05: المسافة بين الفقرات (النقاط) تظهر في PDF بالمقدار المحدد',
      () async {
    Future<double> itemGap(double paragraphSpacing) async {
      final document = _doc(questions: <QuestionModel>[
        QuestionModel(
          id: 'q1',
          questionNumber: 1,
          prompt: '',
          style: PaperTextStyle(paragraphSpacing: paragraphSpacing),
          items: <BranchItem>[
            BranchItem(id: 'i1', text: 'البند الأول قصير'),
            BranchItem(id: 'i2', text: 'البند الثاني قصير'),
          ],
          branches: const <BranchModel>[],
        ),
      ]);
      final bytes =
          await PaginatedPdfExamEngine().generate(document: document);
      final probe = PdfContentProbe.fromBytes(bytes);
      final body =
          probe.lines.where((line) => line.fontSize == 10.5).toList();
      expect(body, hasLength(2),
          reason: 'النقاط يجب أن تُرسم سطراً لكل نقطة (spacing=$paragraphSpacing، '
              'أسطر=${body.length}).');
      return (body[0].words.first.y - body[1].words.first.y).abs();
    }

    final gap0 = await itemGap(0);
    final gap20 = await itemGap(20);
    final delta = gap20 - gap0;
    final expected = PaperMetrics.pt(20);
    expect(delta, closeTo(expected, 2.0),
        reason: 'AUD-PDF-05: فرق تباعد الفقرات 0↔20px يجب أن يساوي '
            '${expected.toStringAsFixed(2)}pt — القيمة الفعلية '
            '${delta.toStringAsFixed(2)}pt (gap0=${gap0.toStringAsFixed(2)}, '
            'gap20=${gap20.toStringAsFixed(2)}).');
  });

  // ===========================================================================
  // PDF: نموذج المعلم/الطالب — عدم تسرّب الإجابات
  // ===========================================================================
  test('AUD-PDF-06: لا أثر لأي إجابة (نموذجية أو صح/خطأ أو خيار صحيح) في PDF',
      () async {
    ExamDocument englishDoc() => _doc(
          subject: 'English',
          questions: <QuestionModel>[
            _essay('q1',
                text: 'Write your answer here.',
                ),
            QuestionModel(
              id: 'q2',
              questionNumber: 1,
              branches: <BranchModel>[
                BranchModel(
                  id: 'q2b',
                  content: BranchContent(
                    type: QuestionType.trueFalse,
                    text: 'True or false statement.',
                  ),
                ),
              ],
            ),
            QuestionModel(
              id: 'q3',
              questionNumber: 1,
              branches: <BranchModel>[
                BranchModel(
                  id: 'q3b',
                  content: BranchContent(
                    type: QuestionType.trueFalse,
                    text: 'Item based statement.',
                    items: <BranchItem>[
                      BranchItem(id: 'i1', text: 'First statement'),
                    ],
                  ),
                ),
              ],
            ),
            QuestionModel(
              id: 'q4',
              questionNumber: 1,
              branches: <BranchModel>[
                BranchModel(
                  id: 'q4b',
                  content: BranchContent(
                    type: QuestionType.multipleChoice,
                    text: 'Choose one.',
                    options: <QuestionOption>[
                      QuestionOption(text: 'Option one'),
                      QuestionOption(text: 'Option two'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        );

    Future<Map<String, bool>> tokens() async {
      final bytes = await PaginatedPdfExamEngine().generate(
        document: englishDoc(),
      );
      final probe = PdfContentProbe.fromBytes(bytes);
      final joined = probe.lines
          .expand((line) => line.words.map((word) => word.text))
          .join(' ');
      return <String, bool>{
        'Model answer': joined.contains('Model answer'),
        'Answer:': joined.contains('Answer:'),
        '(True)': joined.contains('(True)'),
        '(False)': joined.contains('(False)'),
        '•': joined.contains('•'),
        'Statements': joined.contains('True or false statement') &&
            joined.contains('First statement'),
      };
    }

    final rendered = await tokens();
    expect(
      rendered,
      <String, bool>{
        // لا إجابة نموذجية ولا سطر إجابة ولا علامة صح/خطأ ولا تمييز خيار،
        // والنص المكتوب فقط هو ما يُطبع.
        'Model answer': false,
        'Answer:': false,
        '(True)': false,
        '(False)': false,
        '•': false,
        'Statements': true,
      },
      reason: 'AUD-PDF-06: ورق الأسئلة يجب أن يخلو من أي عنصر إجابة — '
          'المخالف: $rendered.',
    );
  });

  // ===========================================================================
  // DOCX: تنسيقات الفقرات (تشابه مع MSO عبر وسم OOXML)
  // ===========================================================================
  test('AUD-DOCX-01: تنسيقات الموديل تصل كوسوم OOXML صحيحة (b/u/color/size/font/jc/line/after)',
      () async {
    const style = PaperTextStyle(
      bold: true,
      underline: true,
      color: 0xFFDC2600,
      fontSize: 13,
      align: PaperAlign.justify,
      lineHeight: 2.0,
      paragraphSpacing: 12,
      font: PaperFont.tajawal,
    );
    final xml = await _docxXml(
      _doc(questions: <QuestionModel>[
        QuestionModel(
          id: 'q1',
          questionNumber: 1,
          prompt: 'متن السؤال المنسق',
          style: style,
          branches: <BranchModel>[
            BranchModel(
              id: 'b1',
              style: style,
              content:
                  BranchContent(
                      type: QuestionType.essay, text: 'نص الفرع'),
            ),
          ],
        ),
      ]),
    );

    expect(
      <String, bool>{
        'bold <w:b/>': xml.contains('<w:b/>'),
        'underline <w:u w:val="single"/>':
            xml.contains('<w:u w:val="single"/>'),
        'color DC2600': xml.contains('<w:color w:val="DC2600"/>'),
        'size 13pt→<w:sz w:val="26"/>': xml.contains('<w:sz w:val="26"/>'),
        'font Tajawal': xml.contains('<w:rFonts w:cs="Tajawal"/>'),
        'justify→jc both': xml.contains('w:jc w:val="both"'),
        'lineHeight 2.0→w:line=480': xml.contains('w:line="480"'),
        'paragraphSpacing 12→w:after=180':
            xml.contains('w:after="180"'),
      },
      <String, bool>{
        'bold <w:b/>': true,
        'underline <w:u w:val="single"/>': true,
        'color DC2600': true,
        'size 13pt→<w:sz w:val="26"/>': true,
        'font Tajawal': true,
        'justify→jc both': true,
        'lineHeight 2.0→w:line=480': true,
        'paragraphSpacing 12→w:after=180': true,
      },
      reason: 'AUD-DOCX-01: تنسيق من الموديل لم يصل إلى XML الواصل لـ Word '
          '(المطلوب في Word: نفس الوسوم — b/u/color/sz/rFonts/jc/line/after).',
    );
  });

  // ===========================================================================
  // DOCX: اتجاه المستند (RTL/LTR)
  // ===========================================================================
  test('AUD-DOCX-02: مستند LTR لا يحمل وسوم RTL (bidi/rtl) — تطابق MSO وWord',
      () async {
    final xml = await _docxXml(
      _doc(
        subject: 'English',
        questions: <QuestionModel>[
          _essay('q1', text: 'An English paragraph for direction testing.'),
        ],
      ),
    );

    expect(
      <String, bool>{
        '<w:bidi/>': xml.contains('<w:bidi/>'),
        '<w:rtl/>': xml.contains('<w:rtl/>'),
      },
      <String, bool>{
        '<w:bidi/>': false,
        '<w:rtl/>': false,
      },
      reason: 'AUD-DOCX-02: مستند إنجليزي (LTR) كُتب بوسوم اتجاه RTL على كل '
          'فقرة/تشغيل. Microsoft Word يكتب فقرات LTR بلا <w:bidi/> وباتجاه '
          'اتجاه افتراضي لاتيني؛ الناتج الحالي يجبر Word على قراءة كل شيء RTL '
          '(محاذاة يمين + ترتيب منطق معكوس للمixed).',
    );
  });

  // ===========================================================================
  // DOCX: نموذج المعلم/الطالب
  // ===========================================================================
  test('AUD-DOCX-03: لا يُكتب أي عنصر إجابة في Word (نموذجية أو صح/خطأ أو خيار)',
      () async {
    ExamDocument examDoc() => _doc(questions: <QuestionModel>[
          _essay('q1',
              text: 'مقالي', ),
          QuestionModel(
            id: 'q2',
            questionNumber: 1,
            branches: <BranchModel>[
              BranchModel(
                id: 'q2b',
                content: BranchContent(
                  type: QuestionType.trueFalse,
                  text: 'عبارة صح/خطأ بلا نقاط',
                ),
              ),
            ],
          ),
          QuestionModel(
            id: 'q3',
            questionNumber: 1,
            branches: <BranchModel>[
              BranchModel(
                id: 'q3b',
                content: BranchContent(
                  type: QuestionType.trueFalse,
                  text: 'عبارة صح/خطأ بنقاط',
                  items: <BranchItem>[
                    BranchItem(id: 'i1', text: 'عبارة أولى'),
                  ],
                ),
              ),
            ],
          ),
          QuestionModel(
            id: 'q4',
            questionNumber: 1,
            branches: <BranchModel>[
              BranchModel(
                id: 'q4b',
                content: BranchContent(
                  type: QuestionType.multipleChoice,
                  text: 'اختر',
                  options: <QuestionOption>[
                    QuestionOption(text: 'الخيار الأول'),
                    QuestionOption(text: 'الخيار الثاني'),
                  ],
                ),
              ),
            ],
          ),
        ]);

    Future<Map<String, bool>> flags() async {
      final xml = await _docxXml(examDoc());
      return <String, bool>{
        'الإجابة النموذجية': xml.contains('الإجابة النموذجية'),
        'الإجابة الصحيحة': xml.contains('الإجابة الصحيحة'),
        '✔': xml.contains('✔'),
        '(صح)': xml.contains('(صح)'),
        '(خطأ)': xml.contains('(خطأ)'),
        '(✓)': xml.contains('(✓)'),
        'العبارات مطبوعة': xml.contains('عبارة صح/خطأ بنقاط') &&
            xml.contains('عبارة أولى'),
      };
    }

    final rendered = await flags();
    expect(
      rendered,
      <String, bool>{
        // النص المكتوب فقط يُطبع؛ ولا كلمة ولا علامة ولا سطر إجابة.
        'الإجابة النموذجية': false,
        'الإجابة الصحيحة': false,
        '✔': false,
        '(صح)': false,
        '(خطأ)': false,
        '(✓)': false,
        'العبارات مطبوعة': true,
      },
      reason: 'AUD-DOCX-03: ملف Word يجب أن يخلو من أي عنصر إجابة — '
          'المخالف: $rendered.',
    );
  });

  test('AUD-DOCX-04: لا علامة «خيار صحيح» في Word (لا • ولا ✔ ولا سطر إجابة)',
      () async {
    final xml = await _docxXml(
      _doc(questions: <QuestionModel>[
        QuestionModel(
          id: 'q1',
          questionNumber: 1,
          branches: <BranchModel>[
            BranchModel(
              id: 'b1',
              content: BranchContent(
                type: QuestionType.multipleChoice,
                text: 'اختر',
                options: <QuestionOption>[
                  QuestionOption(text: 'الخيار الصحيح'),
                  QuestionOption(text: 'بديل'),
                ],
              ),
            ),
          ],
        ),
      ]),
      );

    for (final marker in <String>['•', '✔', 'الإجابة الصحيحة', '✓']) {
      expect(
        xml.contains(marker),
        isFalse,
        reason: 'AUD-DOCX-04: لا يوجد خيار صحيح ولا أي علامة إجابة في الملف — '
            'الخيارات نصّية فقط (المخالف: «$marker»).',
      );
    }
    expect(xml.contains('الخيار الصحيح'), isTrue,
        reason: 'AUD-DOCX-04: نصوص الخيارات المكتوبة هي وحدها ما يُصدَّر.');
  });

  test('AUD-DOCX-05: تعليمات/ملاحظات الترويسة في Word بلا مائل (كالمعاينة وMSO)',
      () async {
    final document = _doc(
      questions: <QuestionModel>[_essay('q1', text: 'متن')],
      header: ExamHeaderModel.ministerialDefault(subject: 'اللغة العربية')
          .copyWith(instructions: 'تعليمات الاختبار العامة.'),
    );
    final xml = await _docxXml(document);

    final index = xml.indexOf('تعليمات الاختبار العامة.');
    expect(index, greaterThan(0),
        reason: 'تعليمات الترويسة مفقودة من DOCX.');
    final run = xml.substring(index < 600 ? 0 : index - 600, index);
    expect(
      run.contains('<w:i/>'),
      isFalse,
      reason: 'AUD-DOCX-05: التعليمات مكتوبة مائلة (italic:true) في DOCX بينما '
          'المعاينة تعرضها عادية والنص المكتوب في Word يُطلب من المستخدم بلا '
          'مائل — تطابق MSO يتطلب عدم فرض المائل.',
    );
  });

  // ===========================================================================
  // DOCX: العناصر العائمة (موضع/تدوير/وسائط)
  // ===========================================================================
  test('AUD-DOCX-06: صورة عائمة — موضع LTR/RTL فيزيائي، تدوير، ووسادة media',
      () async {
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
    );
    ExamDocument imageDoc(String subject) => _doc(
          subject: subject,
          questions: <QuestionModel>[_essay('q1', text: 'نص')],
          header:
              ExamHeaderModel.ministerialDefault(subject: subject).copyWith(
            instructions: '',
          ),
          floatingElements: <FloatingElement>[
            FloatingElement(
              id: 'img',
              type: FloatingElementType.image,
              bytes: Uint8List.fromList(png),
              dx: 100,
              dy: 200,
              width: 120,
              height: 60,
              rotationDegrees: 90,
            ),
          ],
        );

    Future<({String xml, Archive archive, String offsetX})> build(
        String subject) async {
      final document = imageDoc(subject);
      final bytes = await DocxDocumentExportService.buildDocumentDocxBytes(
        document: document,
      );
      final archive = ZipDecoder().decodeBytes(bytes);
      final file = archive.findFile('word/document.xml');
      final xml = utf8.decode(file!.content as List<int>);
      final match =
          RegExp(r'positionH relativeFrom="page"><wp:posOffset>(-?\d+)')
              .firstMatch(xml);
      expect(match, isNotNull, reason: 'لا يوجد موضع أفقي للصورة في XML.');
      return (xml: xml, archive: archive, offsetX: match!.group(1)!);
    }

    final rtl = await build('اللغة العربية');
    final ltr = await build('English');

    expect(
      rtl.offsetX,
      isNot(ltr.offsetX),
      reason: 'AUD-DOCX-06: نفس العنصر (dx=100) يجب أن ينعكس فيزيائياً بين '
          'RTL وLTR في Word (الحافة اليمنى مقابل اليسرى) — القيمتان متطابقتان '
          '(${rtl.offsetX}) أي أن الاتجاه متجاهل في التحويل.',
    );
    expect(rtl.xml.contains('rot="5400000"'), isTrue,
        reason: 'AUD-DOCX-06: تدوير 90° لم يُكتب في XML (rot=90×60000=5400000) '
            '— Word سيعرض الصورة بلا دوران.');
    expect(rtl.archive.findFile('word/media/image1.png'), isNotNull,
        reason: 'AUD-DOCX-06: ملف الصورة media/image1.png غير مضمّن في الأرشيف.');
  });

  // ===========================================================================
  // DOCX: فاصل بين الأسئلة + محتوى الترويسة
  // ===========================================================================
  test('AUD-DOCX-07: الفاصل والترويسة يصلان إلى Word (pBdr بالسماكة + العنوان)',
      () async {
    final document = _doc(
      questions: <QuestionModel>[
        QuestionModel(
          id: 'q1',
          questionNumber: 1,
          prompt: 'سؤال قبل الفاصل',
          dividerAfter: const PaperDivider(thickness: 2),
          branches: <BranchModel>[
            BranchModel(
              id: 'b1',
              content:
                  BranchContent(type: QuestionType.essay, text: 'متن'),
            ),
          ],
        ),
      ],
      header: ExamHeaderModel.ministerialDefault(subject: 'اللغة العربية')
          .copyWith(title: 'عنوان مخصص للترويسة'),
    );
    final xml = await _docxXml(document);

    expect(xml.contains('عنوان مخصص للترويسة'), isTrue,
        reason: 'AUD-DOCX-07: عنوان الترويسة مفقود من DOCX.');
    expect(
      xml.contains('w:sz="16"'),
      isTrue,
      reason: 'AUD-DOCX-07: الفاصل (thickness=2 → w:sz=16) غير مرسوم في Word — '
          'الفاصل بين الأسئلة سيضيع عند الطباعة.',
    );
  });
}
