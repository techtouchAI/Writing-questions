import 'package:flutter_test/flutter_test.dart';

import 'package:writing_questions_app/layout/canonical/canonical_layout_service.dart';
import 'package:writing_questions_app/layout/canonical/canonical_page_plan.dart';
import 'package:writing_questions_app/layout/canonical/flutter_text_metrics.dart';
import 'package:writing_questions_app/layout/canonical/layout_document.dart';
import 'package:writing_questions_app/layout/canonical/layout_units.dart';
import 'package:writing_questions_app/models/branch_model.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/floating_element.dart';
import 'package:writing_questions_app/models/paper_divider.dart';
import 'package:writing_questions_app/models/paper_settings.dart';
import 'package:writing_questions_app/models/question_model.dart';

ExamDocument _document({double? floatTopPx, bool longTitle = false}) => ExamDocument(
  name: 'Whole source windows',
  header: ExamHeaderModel.initial(subject: 'الرياضيات'),
  questions: <QuestionModel>[
    QuestionModel(
      id: 'whole-q', questionNumber: 1, showFrame: true,
      statement: List.filled(longTitle ? 90 : 1,
          'عنوان السؤال الذي يختبر عدم فقد الأسطر').join(' '),
      body: List.generate(140, (i) =>
          'W$i فقرة عربية تقيس حدود الصفحة ومحتوى السؤال الكامل.').join(' '),
      dividerAfter: const PaperDivider(),
      attachments: <FloatingElement>[
        if (floatTopPx != null) FloatingElement(
          id: 'whole-float', type: FloatingElementType.shape,
          shape: FloatingShapeType.rectangle, ownerQuestionId: 'whole-q',
          dx: 4, dy: floatTopPx, width: 60, height: 80,
        ),
      ],
      branches: <BranchModel>[
        BranchModel(id: 'whole-b', showFrame: true,
          content: BranchContent(statement: 'آخر فرع ZEND'),
          dividerAfter: const PaperDivider()),
      ],
    ),
  ],
);

Future<LayoutDocument> _layout(ExamDocument document, {bool tall = false}) =>
    CanonicalLayoutService.resolve(document: document,
      pageSize: tall ? const LayoutSize(width: 210 * 72 / 25.4, height: 20000) : null);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(FlutterTextMetrics.ensureFontsLoaded);

  for (final longTitle in <bool>[false, true]) {
    test('full source coverage and exact line inventory; longTitle=$longTitle', () async {
      final source = _document(longTitle: longTitle);
      final layout = await _layout(source);
      final reference = await _layout(source, tall: true);
      final plan = CanonicalPagePlan.fromLayout(layout);
      final fragments = plan.fragmentsOfQuestion('whole-q');
      expect(fragments.length, greaterThan(1));
      var end = 0.0;
      for (final fragment in fragments) {
        expect(fragment.sourceTopPt, closeTo(end, 1e-6));
        end += fragment.heightPt;
        final page = plan.pages[fragment.pageIndex];
        expect(fragment.topPt + fragment.heightPt,
            lessThanOrEqualTo(page.bodyBounds.bottom + 1e-6));
      }
      final original = reference.allBlocks.singleWhere((b) => b.id == 'whole-q');
      expect(end, closeTo(original.rect.height, 1e-6));
      final referenceLines = original.allLines.map((l) => l.id).toList()..sort();
      final actual = layout.pages.expand((p) => p.blocks)
          .where((b) => b.kind == LayoutBlockKind.question)
          .expand((b) => b.allLines).map((l) => l.id).toList()..sort();
      expect(actual, referenceLines, reason: 'Compare against UNSPLIT input, '
          'not against a second projection of already-sliced output.');
      final rules = layout.allBlocks.where((b) => b.kind == LayoutBlockKind.divider);
      expect(rules.map((b) => b.id).toSet(),
          reference.allBlocks.where((b) => b.kind == LayoutBlockKind.divider)
              .map((b) => b.id).toSet());
      expect(rules.length, 2);
    });
  }

  test('fractional spacing keeps the unframed terminal line exactly once', () async {
    final source = ExamDocument(
      name: 'Fractional terminal line',
      header: ExamHeaderModel.initial(subject: 'الرياضيات'),
      settings: const PaperSettings(baseFontSize: 11, lineSpacing: 1.7, marginMm: 15),
      questions: <QuestionModel>[
        QuestionModel(id: 'terminal-q', questionNumber: 1,
          statement: 'السؤال الثاني',
          body: '${List.filled(46, 'فقرة عربية تقيس امتداد السؤال عبر الصفحات في سطح المعاينة وتصدير PDF، وتحمل كلمات متعددة وأرقاماً ٢٠ و2026 وفواصل، حتى يبلغ النصّ حدّ الصفحة ويقرّر المحرك موضع الفصل بين الأسطر.').join(' ')} ZEND2'),
      ],
    );
    final reference = await _layout(source, tall: true);
    final layout = await _layout(source);
    final original = reference.allBlocks.singleWhere((b) => b.id == 'terminal-q');
    final wanted = original.allLines.map((line) => line.id).toList()..sort();
    final actual = layout.allLines.where((line) => line.semanticNodeId.startsWith('terminal-q/'))
        .map((line) => line.id).toList()..sort();
    expect(actual, wanted, reason: 'Unsplit final line: '
        '${original.allLines.last.rect.top}..${original.allLines.last.rect.bottom}; '
        'question bottom=${original.rect.bottom}');
    for (final block in reference.allBlocks) {
      for (final line in block.allLines) {
        expect(line.rect.bottom, lessThanOrEqualTo(block.rect.bottom + 1e-6),
            reason: '${block.id} must contain measured line ${line.id}.');
      }
    }
    final marker = layout.allLines.where((line) => line.runs.any((run) => run.text.contains('ZEND2')));
    expect(marker, hasLength(1));
  });

  test('an owned attachment crossing a prospective seam stays whole on its page', () async {
    final initial = CanonicalPagePlan.fromLayout(await _layout(_document()));
    final seam = initial.fragmentsOfQuestion('whole-q').first.heightPt;
    final layout = await _layout(_document(floatTopPx: LayoutUnits.ptToPx(seam) - 20));
    final placement = layout.pages.expand((p) => p.floatingElements).single;
    final page = layout.pages[placement.pageIndex];
    expect(placement.pageIndex, greaterThan(0));
    expect(placement.rect.top, greaterThanOrEqualTo(page.bodyBounds.top - 1e-6));
    expect(placement.rect.bottom, lessThanOrEqualTo(page.bodyBounds.bottom + 1e-6));
    expect(placement.rect.height, closeTo(LayoutUnits.pxToPt(80), 1e-6));
  });
}
