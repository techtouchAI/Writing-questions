// المعادلة المنفصلة والمضمّنة: موضعهما الفعلي في التخطيط وفي PDF المُصدَّر.
//
// الفجوة التي يسدّها هذا الملف: `math_flow_layout_test` يقيس **التخطيط**
// (كتلة معادلة منفصلة، وعدم تداخل رأسياً) و`paginated_math_pipeline_test`
// يقيس **الرسم** (صورة لا LaTeX خاماً، وتوسّع الفراغ في السطر). لا يقيس أيٌّ
// منهما الترتيب الفعلي في الملف الناتج: أن تقع المعادلة المنفصلة **بين** سطر
// النص الذي قبلها وسطر النص الذي بعدها، وأن يبقى حبرها داخل شريطها الرأسي
// وحده (لا تندمج في سطر نصّي، ولا تخرج عن هوامش الصفحة).
//
// المرجع: مستند فيه ثلاث علامات ASCII فريدة (DMTOP / DMBOTTOM للسطرين
// المحيطين بالمعادلة المنفصلة، وIMMARK/INMARK للسطر الذي يحمل معادلة سطرية)
// ثم قراءة الملف الناتج عبر [PdfContentProbe]: كلمات مرسومة فعلًا بمواضعها،
// وصور مضمَّنة بمستطيلاتها. كل الأحكام هندسية على الإحداثيات لا على العدّ.

import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/layout/blueprint/exam_blueprint.dart';
import 'package:writing_questions_app/layout/canonical/exam_document_layout_adapter.dart';
import 'package:writing_questions_app/layout/canonical/flutter_text_metrics.dart';
import 'package:writing_questions_app/layout/canonical/layout_document.dart';
import 'package:writing_questions_app/layout/canonical/layout_engine.dart';
import 'package:writing_questions_app/layout/document_ir.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/paper_settings.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/pdf_engine/pdf_engine.dart';

import 'fake_math_host.dart';
import 'pdf_content_probe.dart';

/// A4 بالنقاط (794×1123 بكسل عند 96dpi ⇔ 595.28×841.89pt).
const double _pageWidthPt = 595.28;
const double _pageHeightPt = 841.89;

/// هامش الصفحة الافتراضي في التطبيق (15mm) بالنقاط، مع تسامح صغير للتقريب.
const double _marginPt = 42.5;

/// المعادلة المنفصلة تبقى كتلة مستقلة (علامة `/block-math/` في معرّف السطر).
bool _isDisplayMathLine(LayoutLine line) => line.id.contains('/block-math/');

ExamDocument _document() => ExamDocument(
      name: 'المعادلات: منفصلة ومضمّنة',
      header: ExamHeaderModel(subject: 'الرياضيات'),
      settings: const PaperSettings(showQuestionMarks: false, marginMm: 15),
      questions: <QuestionModel>[
        QuestionModel(
          id: 'dmq',
          questionNumber: 1,
          // معادلة سطرية بين علامتين في السطر نفسه.
          statement: r'سطر سطري IMMARK $\frac{a}{b}$ INMARK',
          // معادلة منفصلة بين سطرين يحملان علامتين فريدتين.
          body: r'سطر أول DMTOP $$ x^2 - 4 = 0 $$ سطر ثالث DMBOTTOM',
        ),
      ],
    );

LayoutDocument _layout(ExamDocument document) => const LayoutEngine().layout(
      document: DocumentIR.fromBlueprint(
        blueprint: ExamBlueprint.from(document),
        document: document,
      ),
      configuration: ExamDocumentLayoutAdapter.configurationFor(document),
      fontMetrics: const FlutterTextMetrics(),
    );

double _wordY(PdfContentProbe probe, String marker) {
  final words = probe.words.where((word) => word.text.trim() == marker).toList();
  expect(words, hasLength(1),
      reason: 'العلامة $marker ظهرت ${words.length} مرة في PDF '
          '(المطلوب مرة واحدة).');
  return words.single.y;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await FlutterTextMetrics.ensureFontsLoaded();
  });

  group('التخطيط: المنفصلة كتلة بين السطرين، والمضمّنة داخل سطرها', () {
    test('المعادلة المنفصلة تقع بين سطر النص قبلها وسطر النص بعدها', () {
      final layout = _layout(_document());
      final lines = <LayoutLine>[
        for (final page in layout.pages)
          for (final block in page.blocks) ...block.allLines,
      ];
      final top = lines.where((line) =>
          line.runs.any((run) => run.text.contains('DMTOP')));
      final bottom = lines.where((line) =>
          line.runs.any((run) => run.text.contains('DMBOTTOM')));
      final display = lines.where(_isDisplayMathLine).toList();

      expect(display, isNotEmpty,
          reason: 'لا كتلة معادلة منفصلة في التخطيط: القياس بلا عيّنة.');
      expect(top, isNotEmpty, reason: 'سطر DMTOP مفقود من التخطيط.');
      expect(bottom, isNotEmpty, reason: 'سطر DMBOTTOM مفقود من التخطيط.');

      final displayRect = display.first.rect;
      final topRect = top.first.rect;
      final bottomRect = bottom.first.rect;

      // ترتيب رأسي: فوق المعادلة سطر DMTOP وتحتها سطر DMBOTTOM (y للأسفل).
      expect(topRect.bottom, lessThanOrEqualTo(displayRect.top + 0.5),
          reason: 'سطر DMTOP (${topRect.bottom.toStringAsFixed(2)}) ليس فوق '
              'كتلة المعادلة (${displayRect.top.toStringAsFixed(2)}).');
      expect(bottomRect.top, greaterThanOrEqualTo(displayRect.bottom - 0.5),
          reason: 'سطر DMBOTTOM (${bottomRect.top.toStringAsFixed(2)}) ليس تحت '
              'كتلة المعادلة (${displayRect.bottom.toStringAsFixed(2)}).');

      // كتلة المنفصلة لا تحمل نصاً عادياً معها في سطرها (لا اندماج دلالي).
      for (final line in display) {
        final textRuns = line.runs
            .where((run) => !run.isMath && run.text.trim().isNotEmpty)
            .toList();
        expect(textRuns, isEmpty,
            reason: 'سطر معادلة منفصلة يحمل نصاً عادياً: '
                '${textRuns.map((run) => run.text).toList()}');
      }
    });

    test('المعادلة المضمّنة تشترك في السطر مع نصها ولا تنفصل عنه', () {
      final layout = _layout(_document());
      final line = <LayoutLine>[
        for (final page in layout.pages)
          for (final block in page.blocks) ...block.allLines,
      ].where((line) => line.runs.any((run) => run.text.contains('IMMARK')));

      expect(line, isNotEmpty, reason: 'سطر IMMARK/INMARK مفقود من التخطيط.');
      final runs = line.first.runs.toList();
      expect(runs.any((run) => run.isMath), isTrue,
          reason: 'لا جريان رياضي في سطر المعادلة المضمّنة.');
      expect(
        runs.any((run) => !run.isMath && run.text.contains('INMARK')),
        isTrue,
        reason: 'المعادلة المضمّنة أخرجت نصّها من السطر: '
            '${runs.map((run) => run.text).toList()}',
      );
      expect(_isDisplayMathLine(line.first), isFalse,
          reason: 'المعادلة المضمّنة عوملت كمنفصلة (سطر مستقل).');
    });
  });

  group('PDF: موضع المعادلتين في الملف المُصدَّر', () {
    final host = FakeMathHost();
    setUp(host.attach);
    tearDown(host.detach);

    test('المنفصلة بين السطرين، وحبرها في شريطها، وداخل هوامش الصفحة',
        () async {
      final bytes =
          await PaginatedPdfExamEngine().generate(document: _document());
      final probe = PdfContentProbe.fromBytes(bytes);

      // الطبقة النصية حيّة: العلامات الأربع مرسومة.
      final topY = _wordY(probe, 'DMTOP');
      final bottomY = _wordY(probe, 'DMBOTTOM');
      _wordY(probe, 'IMMARK');
      _wordY(probe, 'INMARK');

      // المعادلة صورة واحدة على الأقل، والمنفصلة هي الشريط الذي بين السطرين.
      expect(probe.images, isNotEmpty,
          reason: 'لا صورة معادلة مضمَّنة في PDF: '
              'images=${probe.images.map((image) => image.toString()).toList()}');

      final display = probe.images
          .where((image) =>
              image.y > bottomY && image.y + image.height < topY)
          .toList();
      expect(display, hasLength(1),
          reason: 'المعادلة المنفصلة ليست شريطاً واحداً بين DMTOP وDMBOTTOM: '
              '${probe.images.map((image) => image.toString()).toList()} '
              'DMTOP=$topY DMBOTTOM=$bottomY');
      final math = display.single;

      // ترتيب صريح: فوق المعادلة سطر، وتحتها سطر، والفجوتان موجبتان.
      final above = topY - (math.y + math.height);
      final below = math.y - bottomY;
      expect(above, greaterThan(0.0),
          reason: 'سطر DMTOP داخل شريط المعادلة (فجوة ${above.toStringAsFixed(2)}pt).');
      expect(below, greaterThan(0.0),
          reason: 'سطر DMBOTTOM داخل شريط المعادلة (فجوة ${below.toStringAsFixed(2)}pt).');

      // لا كلمة نصّية داخل شريط المعادلة: لا اندماج مع نص السؤال.
      for (final word in probe.words) {
        if (word.text.trim().isEmpty) continue;
        final wordBottom = word.y - word.fontSize * 0.25;
        final wordTop = word.y + word.fontSize * 0.75;
        final overlaps = wordBottom < math.y + math.height &&
            math.y < wordTop &&
            word.x < math.x + math.width &&
            math.x < word.x + word.advanceWidth;
        expect(overlaps, isFalse,
            reason: 'كلمة «${word.text}» داخل مستطيل المعادلة: '
                'word=(${word.x.toStringAsFixed(2)},${word.y.toStringAsFixed(2)}) '
                'math=(${math.x.toStringAsFixed(2)},${math.y.toStringAsFixed(2)},'
                '${math.width.toStringAsFixed(2)}x${math.height.toStringAsFixed(2)}).');
      }

      // داخل هوامش الصفحة: لا تلامس حدّ الورقة ولا التذييل.
      expect(math.x, greaterThanOrEqualTo(_marginPt - 0.5),
          reason: 'المعادلة تخرج من الهامش الأيسر (x=${math.x.toStringAsFixed(2)}).');
      expect(math.x + math.width,
          lessThanOrEqualTo(_pageWidthPt - _marginPt + 0.5),
          reason: 'المعادلة تخرج من الهامش الأيمن.');
      expect(math.y, greaterThanOrEqualTo(_marginPt - 0.5),
          reason: 'المعادلة تلامس حدّ الصفحة السفلي (y=${math.y.toStringAsFixed(2)}).');
      expect(math.y + math.height,
          lessThanOrEqualTo(_pageHeightPt - _marginPt + 0.5),
          reason: 'المعادلة تخرج من أعلى منطقة المحتوى.');
    });

    test('المضمّنة تبقى داخل سطرها: صورتُها بين علامتي السطر نفسه', () async {
      final bytes =
          await PaginatedPdfExamEngine().generate(document: _document());
      final probe = PdfContentProbe.fromBytes(bytes);

      final immark = probe.words
          .firstWhere((word) => word.text.trim() == 'IMMARK');
      final inmark = probe.words
          .firstWhere((word) => word.text.trim() == 'INMARK');
      expect(immark.y, closeTo(inmark.y, immark.fontSize * 0.5),
          reason: 'العلامتان ليستا على سطر واحد: '
              'IMMARK@${immark.y.toStringAsFixed(2)} '
              'INMARK@${inmark.y.toStringAsFixed(2)}.');

      final lineBottom = (immark.y < inmark.y ? immark.y : inmark.y) -
          immark.fontSize * 0.5;
      final lineTop =
          (immark.y > inmark.y ? immark.y : inmark.y) + immark.fontSize * 0.5;
      final inline = probe.images
          .where((image) =>
              image.y + image.height > lineBottom && image.y < lineTop)
          .toList();
      expect(inline, hasLength(1),
          reason: 'عدد صور المعادلة داخل سطر IMMARK/INMARK = ${inline.length}.');

      final left = immark.x < inmark.x ? immark.x : inmark.x;
      final right = (immark.x < inmark.x ? inmark : immark);
      final rightEdge = right.x + right.advanceWidth;
      final image = inline.single;
      expect(image.x, greaterThanOrEqualTo(left - 1.0),
          reason: 'المعادلة المضمّنة خارج نطاق السطر من اليسار.');
      expect(image.x + image.width, lessThanOrEqualTo(rightEdge + 1.0),
          reason: 'المعادلة المضمّنة خارج نطاق السطر من اليمين.');
    });
  });
}
