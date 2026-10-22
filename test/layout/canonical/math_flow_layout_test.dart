// المعادلات في التخطيط القانوني: موضعها وحدودها الفعلية (لا قابلية بحثها —
// المعادلة تُصدَّر صورة، وهذا قيد معلن لا عيب في هذه الدفعة).
//
// المقيس هنا:
//   * المعادلة السطرية تبقى داخل تدفّق الفقرة (سطر النص نفسه).
//   * المعادلة المنفصلة تشغل كتلة/مقطعاً مستقلاً ولا تشارك سطر نص عادي.
//   * لا تراكب بين أي جريان رياضي والجريان المجاور له أفقياً، ولا بين كتلة
//     معادلة منفصلة وأسطر النص.
//   * تنسيق كلمة خارج المعادلة لا يغيّر نمط جريان المعادلة (التنسيق الجزئي
//     داخل المعادلة غير مدعوم لأن وحدتها صورة، وهو موثَّق في
//     docs/p3_editor_preview_export_unification.md §16).
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
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/models/text_format_span.dart';

/// كتلة المعادلة المنفصلة تحمل هذه العلامة في معرّفاتها (layout_engine.dart:957):
/// المحرك يفصلها إلى مقطع مستقل ثم يمنحها فقرة/أسطراً خاصة بها.
bool _isDisplayMathLine(LayoutLine line) => line.id.contains('/block-math/');

ExamDocument _document({List<TextFormatSpan> formats = const <TextFormatSpan>[]}) =>
    ExamDocument(
      name: 'تدفق المعادلات',
      header: ExamHeaderModel.initial(subject: 'الرياضيات'),
      questions: <QuestionModel>[
        QuestionModel(
          id: 'q1',
          questionNumber: 1,
          statement: r'احسب $x^2 + \frac{1}{2}$ ثم اكتب الناتج',
          body: r'قبل $a+b$ بعد',
          bodyFormats: formats,
        ),
        QuestionModel(
          id: 'q2',
          questionNumber: 2,
          statement: 'سؤال ثانٍ',
          body: r'مقدمة ثم معادلة منفصلة $$\sqrt{x+1} = 3$$ ثم خاتمة',
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

/// الكتل التي يظهر فيها النص المميّز (يُختار بالمحتوى لا بمعرّف مُفترض، حتى
/// لا يصير القياس «عينات صفرية» لو تغيّر تكوين المعرّفات).
List<LayoutBlock> _blocksWith(LayoutDocument layout, String needle) => <LayoutBlock>[
      for (final page in layout.pages)
        for (final block in page.blocks)
          if (block.allLines.any(
            (line) => line.runs.any((run) => run.text.contains(needle)),
          ))
            block,
    ];

List<LayoutLine> _lines(LayoutDocument layout, String needle) => <LayoutLine>[
      for (final block in _blocksWith(layout, needle)) ...block.allLines,
    ];

List<LayoutRun> _runs(LayoutDocument layout, String needle) => <LayoutRun>[
      for (final line in _lines(layout, needle)) ...line.runs,
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await FlutterTextMetrics.ensureFontsLoaded();
  });

  test('المعادلة السطرية داخل تدفّق السطر، ولا تراكب مع جيرانها', () {
    final layout = _layout(_document());
    final statementRuns = _runs(layout, 'احسب');
    final mathRuns = statementRuns.where((run) => run.isMath).toList();
    expect(mathRuns, isNotEmpty,
        reason: 'لا جريان رياضي في نص السؤال — القياس بلا عيّنة.');

    final lineOfMath = _lines(layout, 'احسب')
        .firstWhere((line) => line.runs.any((run) => run.isMath));
    final lineRuns = lineOfMath.runs.toList()
      ..sort((a, b) => a.x.compareTo(b.x));
    // نصّ ورياضيات على خط أساس واحد: السطر يحتوي الاثنين.
    expect(lineRuns.any((run) => !run.isMath && run.text.trim().isNotEmpty),
        isTrue,
        reason: 'المعادلة السطرية أُخرجت من تدفّق النص إلى سطر مستقل: '
            '${lineRuns.map((run) => run.text).toList()}');
    // تشخيص مقروء في سجلّ CI: أي جريان وأي حدود.
    // ignore: avoid_print
    print('[math] سطر المعادلة: '
        '${lineRuns.map((run) => '"${run.text}":x=${run.x.toStringAsFixed(2)}'
            '+adv=${run.advance.toStringAsFixed(2)}'
            'w=${run.width.toStringAsFixed(2)}'
            '${run.isMath ? ' [math]' : ''}').join(' | ')}');
    for (var index = 0; index + 1 < lineRuns.length; index++) {
      final left = lineRuns[index];
      final right = lineRuns[index + 1];
      expect(left.x + left.advance, lessThanOrEqualTo(right.x + 0.5),
          reason: 'تراكب أفقي بين «${left.text}» (ينتهي عند '
              '${(left.x + left.advance).toStringAsFixed(2)}) و«${right.text}» '
              '(يبدأ عند ${right.x.toStringAsFixed(2)}).');
    }
    // الجريان الرياضي يحمل قياساً حقيقياً (لا تقدير صفري).
    for (final run in mathRuns) {
      expect(run.width, greaterThan(0),
          reason: 'جريان رياضي بعرض صفر: ${run.text}');
      expect(run.width.isFinite, isTrue);
    }
  });

  test('المعادلة المنفصلة تشغل كتلة مستقلة ولا تشارك سطراً نصياً', () {
    final layout = _layout(_document());
    final bodyLines = _lines(layout, 'مقدمة');
    expect(bodyLines.length, greaterThanOrEqualTo(2),
        reason: 'المعادلة المنفصلة لم تفصل الفقرة إلى مقاطع: '
            '${bodyLines.length} سطر.');

    final displayLines = bodyLines
        .where((line) => line.runs.any((run) => run.isMath && _isDisplayMathLine(line)))
        .toList();
    expect(displayLines, isNotEmpty,
        reason: 'لا سطر يحمل معادلة منفصلة: القياس بلا عيّنة.');
    for (final line in displayLines) {
      final textRuns =
          line.runs.where((run) => !run.isMath && run.text.trim().isNotEmpty);
      expect(textRuns, isEmpty,
          reason: 'سطر المعادلة المنفصلة يحمل نصاً عادياً معه: '
              '${textRuns.map((run) => run.text).toList()}');
    }

    // لا تداخل رأسياً بين كتلة المعادلة وأسطر النص المجاورة.
    final displayRects = <LayoutRect>[
      for (final page in layout.pages)
        for (final block in page.blocks)
          for (final line in block.allLines)
            if (line.runs.any((run) => run.isMath && _isDisplayMathLine(line)))
              line.rect,
    ];
    final textRects = <LayoutRect>[
      for (final line in bodyLines)
        if (line.runs.any((run) => !run.isMath && run.text.trim().isNotEmpty))
          line.rect,
    ];
    for (final mathRect in displayRects) {
      for (final textRect in textRects) {
        final overlaps = mathRect.top < textRect.bottom &&
            textRect.top < mathRect.bottom &&
            mathRect.left < textRect.right &&
            textRect.left < mathRect.right;
        expect(overlaps, isFalse,
            reason: 'تراكب بين كتلة معادلة منفصلة ($mathRect) وسطر نص '
                '($textRect).');
      }
    }
  });

  test('تنسيق نصّ خارج المعادلة لا يمسّ جريان المعادلة', () {
    final plain = _layout(_document());
    // تنسيق أول كلمة في المتن («قبل») فقط.
    final formatted = _layout(
      _document(
        formats: const <TextFormatSpan>[
          TextFormatSpan(start: 0, end: 3, bold: true, color: 0xFFB91C1C),
        ],
      ),
    );
    String mathStyles(LayoutDocument layout) => <String>[
          for (final run in _runs(layout, 'قبل'))
            if (run.isMath)
              '${run.text}:${run.style.bold}:${run.style.colorArgb}:'
                  '${run.width.toStringAsFixed(2)}',
        ].join('|');
    expect(mathStyles(formatted), mathStyles(plain),
        reason: 'تنسيق نصّ عادي غيّر نمط أو قياس جريان المعادلة.');
    // والنص المنسّق نفسه تغيّر (فالبوابة ليست عمياء).
    // ignore: avoid_print
    print('[math] جريانات «قبل» في النسخة المنسّقة: '
        '${_runs(formatted, 'قبل').map((run) => run.isMath ? '<math:${run.text}>' : '"${run.text}"${run.style.bold ? '*' : ''}').toList()}');
    // ignore: avoid_print
    print('[math] كل الجريانات العريضة: '
        '${[for (final page in formatted.pages) for (final block in page.blocks) for (final line in block.allLines) ...line.runs.where((run) => run.style.bold).map((run) => '"${run.text}"@${run.semanticNodeId}')].toList()}');
    final formattedText = _runs(formatted, 'قبل')
        .where((run) => !run.isMath && run.style.bold)
        .toList();
    expect(formattedText, isNotEmpty,
        reason: 'التنسيق لم يصل إلى النص خارج المعادلة.');
    for (final run in formattedText) {
      expect(run.text.trim(), 'قبل',
          reason: 'التنسيق تسرّب إلى «${run.text}» خارج الكلمة المحدَّدة.');
    }
  });
}
