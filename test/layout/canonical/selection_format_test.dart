// تنسيق التحديد من التخزين إلى **التخطيط القانوني** ثم إلى **PDF**.
//
// المعاينة وPDF يقرآن نفس `LayoutDocument` (نفس المحرك القانوني)، ولذلك يكفي
// أن نُثبت أن نطاقات التنسيق تصل إلى جريانات ذلك التخطيط لتصل إلى الاثنين.
// ثم نُثبت أثرها في ملف PDF فعلي: الكلمة المحدَّدة وحدها تُرسم بالخط العريض.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/layout/blueprint/exam_blueprint.dart';
import 'package:writing_questions_app/layout/canonical/exam_document_layout_adapter.dart';
import 'package:writing_questions_app/layout/canonical/flutter_text_metrics.dart';
import 'package:writing_questions_app/layout/canonical/layout_document.dart';
import 'package:writing_questions_app/layout/canonical/layout_engine.dart';
import 'package:writing_questions_app/layout/document_ir.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/models/text_format_span.dart';
import 'package:writing_questions_app/pdf_engine/exam_fonts.dart';
import 'package:writing_questions_app/pdf_engine/paginated_pdf_exam_engine.dart';

import '../../pdf_engine/pdf_content_probe.dart';

const String _statement = 'اختر الإجابة الصحيحة';
const String _body = 'قل هو الله أحد';

ExamDocument _document({
  List<TextFormatSpan> statementFormats = const <TextFormatSpan>[],
  List<TextFormatSpan> bodyFormats = const <TextFormatSpan>[],
}) {
  return ExamDocument(
    name: 'اختبار تنسيق التحديد',
    header: ExamHeaderModel(
      schoolName: 'مدرسة',
      examType: 'نصف السنة',
      academicYear: '2026/2027',
      subject: 'اللغة العربية',
      showBismillah: false,
    ),
    questions: <QuestionModel>[
      QuestionModel(
        id: 'q1',
        questionNumber: 1,
        statement: _statement,
        body: _body,
        marksOverride: 20,
        statementFormats: statementFormats,
        bodyFormats: bodyFormats,
      ),
    ],
  );
}

LayoutDocument _layout(ExamDocument document) {
  final ir = DocumentIR.fromBlueprint(
    blueprint: ExamBlueprint.from(document),
    document: document,
  );
  return const LayoutEngine().layout(
    document: ir,
    configuration: ExamDocumentLayoutAdapter.configurationFor(document),
    fontMetrics: const FlutterTextMetrics(),
  );
}

Iterable<LayoutBlock> _allBlocks(Iterable<LayoutBlock> blocks) sync* {
  for (final block in blocks) {
    yield block;
    yield* _allBlocks(block.children);
  }
}

LayoutBlock _titleBlock(LayoutDocument layout) {
  for (final page in layout.pages) {
    for (final block in _allBlocks(page.blocks)) {
      if (block.kind == LayoutBlockKind.title) return block;
    }
  }
  throw StateError('لا كتلة عنوان في التخطيط.');
}

/// أول كتلة تحمل جريانات يبدأ معرّفها الدلالي بـ[prefix] (نص السؤال مثلًا).
LayoutBlock _blockWithPrefix(LayoutDocument layout, String prefix) {
  for (final page in layout.pages) {
    for (final block in _allBlocks(page.blocks)) {
      for (final line in block.allLines) {
        if (line.runs.any((run) => run.semanticNodeId.startsWith(prefix))) {
          return block;
        }
      }
    }
  }
  throw StateError('لا كتلة جريانات بادئتها $prefix.');
}

/// جريانات نصّ الكتلة التي يبدأ معرّفها بـ[prefix] فقط — بلا رقم السؤال ولا
/// مجموعته ولا الدرجة، فالمقارنة تكون على نصّ الحقل نفسه.
List<LayoutRun> _textRuns(LayoutBlock block, String prefix) => <LayoutRun>[
      for (final line in block.allLines)
        ...line.runs.where(
          (run) => !run.isMath && run.semanticNodeId.startsWith(prefix),
        ),
    ];

String _joined(List<LayoutRun> runs) =>
    runs.map((run) => run.text).join().replaceAll('\u00A0', ' ').trim();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await FlutterTextMetrics.ensureFontsLoaded();
  });

  group('التخطيط القانوني يحمل التنسيق الجزئي', () {
    test('تعريض كلمة واحدة في المنطوق يصل إلى جريان واحد فقط', () {
      final layout = _layout(_document(
        statementFormats: const <TextFormatSpan>[
          TextFormatSpan(start: 5, end: 12, bold: true),
        ],
      ));
      final runs = _textRuns(_titleBlock(layout), 'q1/title/statement');
      expect(_joined(runs), _statement,
          reason: 'تنسيق التحديد غيّر نص العنوان المرسوم: $_joined(runs)');
      final boldRuns = runs.where((run) => run.style.bold == true).toList();
      expect(boldRuns, hasLength(1),
          reason: 'التعريض أصاب ${boldRuns.length} جريانًا بدل جريان واحد:\n'
              '${runs.map((run) => '"${run.text}" bold=${run.style.bold}').toList()}');
      expect(boldRuns.single.text.trim(), 'الإجابة');
      for (final run in runs) {
        if (identical(run, boldRuns.single)) continue;
        expect(run.style.bold, isNot(isTrue),
            reason: 'جريان خارج التحديد صار عريضًا: "${run.text}"');
      }
    });

    test('مائل للنص كله + تعريض لكلمة: التداخل محفوظ', () {
      final layout = _layout(_document(
        bodyFormats: const <TextFormatSpan>[
          TextFormatSpan(start: 0, end: 14, italic: true),
          TextFormatSpan(start: 3, end: 5, bold: true),
        ],
      ));
      final runs = _textRuns(_blockWithPrefix(layout, 'q1/body'), 'q1/body');
      expect(_joined(runs), _body);
      final bold = runs.where((run) => run.style.bold == true).toList();
      expect(bold, hasLength(1));
      expect(bold.single.text.trim(), 'هو');
      expect(bold.single.style.italic, isTrue,
          reason: 'التعريض محا الميل الخارجي.');
      final others = runs.where((run) => run.text.trim().isNotEmpty &&
          run.style.bold != true).toList();
      expect(others, isNotEmpty);
      for (final run in others) {
        expect(run.style.italic, isTrue,
            reason: 'الميل ضاع خارج كلمة التعريض: "${run.text}"');
      }
    });

    test('الألوان الجزئية لا تتسرّب إلى بقية السطر', () {
      final layout = _layout(_document(
        bodyFormats: const <TextFormatSpan>[
          TextFormatSpan(start: 3, end: 5, color: 0xFFCC0000),
        ],
      ));
      final runs = _textRuns(_blockWithPrefix(layout, 'q1/body'), 'q1/body');
      final colored =
          runs.where((run) => run.style.colorArgb == 0xFFCC0000).toList();
      expect(colored, hasLength(1));
      expect(colored.single.text.trim(), 'هو');
      for (final run in runs) {
        if (identical(run, colored.single)) continue;
        expect(run.style.colorArgb, isNot(0xFFCC0000));
      }
    });

    test('الحفظ والتحميل ثم التخطيط: التنسيق نفسه على الكلمة نفسها', () {
      final original = _document(
        statementFormats: const <TextFormatSpan>[
          TextFormatSpan(start: 5, end: 12, bold: true, color: 0xFF123456),
        ],
      );
      final restored = ExamDocument.fromMap(original.toMap());
      expect(
        restored.questions.single.statementFormats,
        original.questions.single.statementFormats,
      );
      final runs =
          _textRuns(_titleBlock(_layout(restored)), 'q1/title/statement');
      final styled = runs
          .where((run) => run.style.bold == true && run.style.colorArgb == 0xFF123456)
          .toList();
      expect(styled, hasLength(1),
          reason: 'التنسيق لم يصل بعد إعادة التحميل: '
              '${runs.map((run) => '"${run.text}" ${run.style.bold}/${run.style.colorArgb}').toList()}');
      expect(styled.single.text.trim(), 'الإجابة');
    });
  });

  group('أثر التنسيق في ملف PDF فعلي', () {
    late ExamFonts fonts;

    setUpAll(() async {
      fonts = await ExamFonts.load();
    });

    Future<Uint8List> export(ExamDocument document) =>
        PaginatedPdfExamEngine().generate(document: document, fonts: fonts);

    int boldWordCount(Uint8List bytes) {
      final probe = PdfContentProbe.fromBytes(bytes, pageIndex: 0);
      return probe.words
          .where((word) => word.baseFont.toUpperCase().contains('BOLD'))
          .length;
    }

    test('تعريض كلمة في النص يضيف كلمة عريضة واحدة في PDF فقط', () async {
      final plain = await export(_document());
      final formatted = await export(_document(
        bodyFormats: const <TextFormatSpan>[
          TextFormatSpan(start: 3, end: 5, bold: true),
        ],
      ));
      final plainBold = boldWordCount(plain);
      final formattedBold = boldWordCount(formatted);
      expect(
        formattedBold,
        plainBold + 1,
        reason: 'عدد الكلمات المرسومة بخط عريض لم يتغيّر بمقدار كلمة واحدة: '
            '$plainBold ← $formattedBold.',
      );

      // النص يبقى نصًّا قابلًا للبحث: كلمات النص كلها موجودة في مجرى الصفحة.
      final probe = PdfContentProbe.fromBytes(formatted, pageIndex: 0);
      expect(probe.words, isNotEmpty);
      expect(
        probe.words.where((word) => word.baseFont.toUpperCase().contains('BOLD')),
        hasLength(formattedBold),
      );
    });
  });
}
