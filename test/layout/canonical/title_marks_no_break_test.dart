// =============================================================================
// قاعدة موضع درجة السؤال في سطر العنوان (المحرك القانوني المشترك).
//
// المطلوب ليس «تبدو في نهاية السطر» بل ثلاث خصائص تُقاس على `LayoutDocument`
// نفسه — وهو المصدر الذي يرسمه كلٌّ من المعاينة وPDF:
//   1. **عدم الانفصال**: لا تبدأ مجموعة الدرجة `(٢٠ درجة)` سطرًا وحدها؛
//      تبقى على سطر يحمل كلمةً من عنوان السؤال.
//   2. **عدم الانقسام الداخلي**: `(٢٠` و`درجة)` و`٢٠` لا تفترق بين سطرين:
//      المجموعة وحدة واحدة (فواصلها الداخلية غير كاسرة).
//   3. **الالتفاف الكامل**: عند ضيق العرض تنتقل الدرجة **مع** آخر كلمة من
//      العنوان، لا منفردة؛ ولا تُقتطع ولا تُخفى.
//
// الحالات المغطاة: عنوان قصير يتّسع، عنوان طويل يلتف، عرض ضيّق (هامش كبير)،
// ونص درجة متغيّر الطول — كلها على نفس المسار الإنتاجي
// (`ExamBlueprint` → `DocumentIR` → `LayoutEngine`).
// =============================================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/layout/blueprint/exam_blueprint.dart';
import 'package:writing_questions_app/layout/canonical/exam_document_layout_adapter.dart';
import 'package:writing_questions_app/layout/canonical/flutter_text_metrics.dart';
import 'package:writing_questions_app/layout/canonical/layout_document.dart';
import 'package:writing_questions_app/layout/canonical/layout_engine.dart';
import 'package:writing_questions_app/layout/canonical/layout_units.dart';
import 'package:writing_questions_app/layout/document_ir.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/paper_settings.dart';
import 'package:writing_questions_app/models/question_model.dart';

/// عنوان قصير: يتّسع سطرًا واحدًا مع الدرجة.
const String _shortStatement = 'اختر الإجابة';

/// عنوان طويل يلتف على أسطر في عرض A4 القابل للطباعة.
const String _longStatement =
    'اشرح بالتفصيل دلالة الاستعارة في البيت الشعري الآتي ثم بيّن أثرها في '
    'المعنى العام ووازن بينها وبين الكناية في البيت الثاني مع التعليل';

ExamDocument _document({
  required String statement,
  required double marksOverride,
  PaperSettings settings = const PaperSettings(),
}) {
  return ExamDocument(
    name: 'اختبار موضع الدرجة',
    header: ExamHeaderModel(
      schoolName: 'مدرسة',
      examType: 'نصف السنة',
      academicYear: '2026/2027',
      subject: 'اللغة العربية',
      showBismillah: false,
    ),
    settings: settings,
    questions: <QuestionModel>[
      QuestionModel(
        id: 'q1',
        questionNumber: 1,
        statement: statement,
        marksOverride: marksOverride,
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

/// أسطر كتلة العنوان (أول كتلة `title` في الصفحة الأولى).
List<LayoutLine> _titleLines(LayoutDocument layout) {
  for (final page in layout.pages) {
    for (final block in _allBlocks(page.blocks)) {
      if (block.kind == LayoutBlockKind.title) {
        return block.allLines.toList(growable: false);
      }
    }
  }
  throw StateError('لا كتلة عنوان في التخطيط.');
}

bool _isMarksRun(LayoutRun run) =>
    run.semanticRole == LayoutSemanticRole.marks;

/// يتحقق من قاعدة الدرجة ويعيد (عدد أسطر العنوان، عدد جريانات الدرجة).
({int titleLineCount, int marksRunCount}) _expectGradeRule(
  LayoutDocument layout, {
  required String caseName,
}) {
  final lines = _titleLines(layout);
  final marksLines = <int>{};
  final marksRunCount = <String>{};
  var sawMarks = false;

  for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
    final line = lines[lineIndex];
    final marksOnLine = line.runs.where(_isMarksRun).toList(growable: false);
    if (marksOnLine.isEmpty) continue;
    sawMarks = true;
    marksLines.add(lineIndex);
    // (1) لا سطر يحمل الدرجة وحدها: لا بد أن يحمل معها جريانًا من العنوان.
    final withTitleContent = line.runs.any(
      (run) => !_isMarksRun(run) && run.semanticRole != LayoutSemanticRole.separator,
    );
    expect(
      withTitleContent,
      isTrue,
      reason: '[$caseName] السطر $lineIndex يحمل الدرجة منفردة عن عنوانها.\n'
          'الكلمات: ${_describe(line)}',
    );
    for (final run in marksOnLine) {
      marksRunCount.add(run.id);
    }
  }

  expect(sawMarks, isTrue,
      reason: '[$caseName] لم تُسقَط الدرجة من التخطيط إطلاقًا — '
          'الاختبار لم يقس شيئًا.');

  // (2) مجموعة الدرجة كلها على سطر واحد: لا انقسام داخلي.
  expect(
    marksLines.length,
    1,
    reason: '[$caseName] مجموعة الدرجة انقسمت على ${marksLines.length} سطرًا '
        '(الأسطر: $marksLines) — فواصلها الداخلية يجب أن تكون غير كاسرة.\n'
        'أسطر العنوان: ${lines.map(_describe).toList()}',
  );

  return (titleLineCount: lines.length, marksRunCount: marksRunCount.length);
}

String _describe(LayoutLine line) =>
    '[${line.runs.map((run) => '"${run.text}"').join(' ')}]';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await FlutterTextMetrics.ensureFontsLoaded();
  });

  group('موضع الدرجة في عنوان السؤال', () {
    test('عنوان قصير: الدرجة في سطر العنوان نفسه ولا تنفرد بسطر', () {
      final layout = _layout(
        _document(statement: _shortStatement, marksOverride: 20),
      );
      final measured = _expectGradeRule(layout, caseName: 'قصير');
      expect(measured.titleLineCount, 1,
          reason: 'عنوان قصير + درجة يجب أن يبقى سطرًا واحدًا.');
      expect(measured.marksRunCount, greaterThanOrEqualTo(3),
          reason: 'مجموعة الدرجة تتكوّن من قوس ورقم وفراغ ووحدة وقوس: '
              '${measured.marksRunCount} جريانًا فقط — أُسقط جزء منها.');
    });

    test('عنوان طويل يلتف: الدرجة تبقى مع آخر كلمة لا منفردة', () {
      final layout = _layout(
        _document(statement: _longStatement, marksOverride: 20),
      );
      final measured = _expectGradeRule(layout, caseName: 'طويل');
      expect(measured.titleLineCount, greaterThan(1),
          reason: 'العنوان الطويل يجب أن يلتف على أكثر من سطر حتى يقيس '
              'الاختبار حالة الالتفاف فعلاً.');
    });

    test('نص درجة طويل (مئة وخمسون درجة) لا ينفصل ولا ينقسم', () {
      final layout = _layout(
        _document(statement: _longStatement, marksOverride: 150),
      );
      _expectGradeRule(layout, caseName: 'درجة طويلة');
    });

    test('عرض ضيّق (هامش 34 مم): الالتفاف لا يبتر الدرجة', () {
      final layout = _layout(
        _document(
          statement: _longStatement,
          marksOverride: 20,
          settings: const PaperSettings(marginMm: 34),
        ),
      );
      final measured = _expectGradeRule(layout, caseName: 'عرض ضيق');
      expect(measured.titleLineCount, greaterThan(1),
          reason: 'الهامش الكبير يضيّق العمود فيجب أن يلتف العنوان.');
    });

    test('كل جريانات الدرجة داخل الصفحة الأولى ومرتّبة مع العنوان', () {
      final layout = _layout(
        _document(statement: _shortStatement, marksOverride: 20),
      );
      final lines = _titleLines(layout);
      final marksLines = <LayoutLine>[
        for (final line in lines)
          if (line.runs.any(_isMarksRun)) line,
      ];
      expect(marksLines.length, 1,
          reason: 'جريانات الدرجة موزّعة على ${marksLines.length} سطرًا.');
      final sorted = marksLines.single.runs.where(_isMarksRun).toList()
        ..sort((a, b) => a.x.compareTo(b.x));
      for (var index = 0; index + 1 < sorted.length; index++) {
        final gap = sorted[index + 1].x - (sorted[index].x + sorted[index].advance);
        expect(
          gap,
          greaterThan(-0.75),
          reason: 'تراكب داخل مجموعة الدرجة بين '
              '"${sorted[index].text}" و"${sorted[index + 1].text}": '
              'الفجوة $gap نقطة.',
        );
      }
    });

    test('وحدة الدرجة تُطبع كما في النموذج بلا تغيير نصّها', () {
      final document = _document(statement: _shortStatement, marksOverride: 20);
      final blueprint = ExamBlueprint.from(document);
      // العقد القديم (نصّ مسطّح) لا يتغيّر: القاعدة تخطيطية لا بياناتية.
      expect(blueprint.questions.single.title.marks, '(٢٠ درجة)');
      final layout = _layout(document);
      final marksText = <String>[
        for (final line in _titleLines(layout))
          for (final run in line.runs.where(_isMarksRun))
            if (run.text.trim().isNotEmpty) run.text,
      ];
      expect(
        marksText.map((text) => text.replaceAll('\u00A0', ' ')).join(),
        '(٢٠ درجة)',
        reason: 'نصّ الدرجة المتدفّق للرسم يختلف عن النموذج: $marksText',
      );
      // القاعدة تخطيطية: المسافة داخل المجموعة صارت غير كاسرة.
      expect(
        marksText.any((text) => text.contains('\u00A0')),
        isTrue,
        reason: 'فواصل مجموعة الدرجة بقيت كاسرة (مسافة عادية) — '
            'يمكن أن تنقسم بين سطرين.',
      );
    });
  });

  group('سلامة وحدة القياس', () {
    test('هامش العرض الضيق لا يجعل الدرجة صفر المساحة', () {
      final layout = _layout(
        _document(
          statement: _shortStatement,
          marksOverride: 20,
          settings: const PaperSettings(marginMm: 34),
        ),
      );
      final contentWidth = LayoutUnits.a4.width -
          2 * LayoutUnits.mmToPt(34);
      for (final line in _titleLines(layout)) {
        for (final run in line.runs.where(_isMarksRun)) {
          expect(run.advance, greaterThan(0),
              reason: 'جريان درجة بعرض صفر: "${run.text}"');
          expect(run.x, greaterThanOrEqualTo(-0.01));
          expect(run.x + run.advance, lessThanOrEqualTo(contentWidth + 0.5),
              reason: 'الدرجة تتجاوز عرض المحتوى: '
                  '${run.x + run.advance} > $contentWidth');
        }
      }
    });
  });
}
