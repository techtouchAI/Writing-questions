// بوابة فجوة المعادلة المستقلة: مشتقّة من قياس الصندوق، لا رقم ثابت.
//
// ما يُقاس هنا:
//   * الدالة المشتركة نفسها (`VisualMetrics.displayMathGapPx`): الأرضية،
//     النمو مع ارتفاع الصندوق، وسلامة القيم غير الصالحة.
//   * المحرك القانوني يستهلك القاعدة فعلاً: الفجوة المقيسة بين المعادلة
//     المنفصلة والسطر الذي قبلها تساوي الصيغة المحسوبة من الارتفاعات المقيسة
//     نفسها، فلا تُحتسب مرة في المحرك ومرة في الراسم.
//   * مصدر واحد: لا تبقى حشوة 4px ثابتة في `TexText`، ولا `pxToPt(4)` في
//     المحرك.
//
// التفاوت: 0.75pt (نفس تفاوت بوابة هندسة الحقل)، وهو أكبر من تقريب px↔pt.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:writing_questions_app/layout/blueprint/exam_blueprint.dart';
import 'package:writing_questions_app/layout/canonical/exam_document_layout_adapter.dart';
import 'package:writing_questions_app/layout/canonical/flutter_text_metrics.dart';
import 'package:writing_questions_app/layout/canonical/layout_document.dart';
import 'package:writing_questions_app/layout/canonical/layout_engine.dart';
import 'package:writing_questions_app/layout/document_ir.dart';
import 'package:writing_questions_app/layout/visual/visual_metrics.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/question_model.dart';

/// التفاوت الموثَّق (pt) بين الفجوة المقيسة والصيغة المحسوبة.
const double _kTolerancePt = 0.75;

/// الأرضية بالنقاط: 4px على لوحة 96dpi = 3pt.
const double _kFloorPt = 3.0;

ExamDocument _document(String body) => ExamDocument(
      name: 'فجوة المعادلة',
      header: ExamHeaderModel.initial(subject: 'الرياضيات'),
      questions: <QuestionModel>[
        QuestionModel(
          id: 'q1',
          questionNumber: 1,
          statement: 'سؤال أول',
          body: body,
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

bool _isDisplayMathLine(LayoutLine line) => line.id.contains('/block-math/');

/// كل الأسطر بترتيب الصفحات كما يرسمها الـPDF.
List<LayoutLine> _allLines(LayoutDocument layout) => <LayoutLine>[
      for (final page in layout.pages)
        for (final block in page.blocks) ...block.allLines,
    ];

void main() {
  group('قاعدة الفجوة المشتقة', () {
    test('الأرضية 3pt حين يكون الصندوق بارتفاع السطر أو أقصر', () {
      expect(
        VisualMetrics.displayMathGapPx(mathHeightPx: 18, lineHeightPx: 18),
        VisualMetrics.displayMathMinGapPx,
      );
      expect(
        VisualMetrics.displayMathGapPx(mathHeightPx: 12, lineHeightPx: 18),
        VisualMetrics.displayMathMinGapPx,
      );
      // 4px = 3pt على لوحة 96dpi.
      expect(
        VisualMetrics.displayMathMinGapPx,
        closeTo(_kFloorPt * 96.0 / 72.0, 1e-9),
      );
    });

    test('تنمو بنصف الزيادة على ارتفاع السطر', () {
      // صندوق 26px داخل سطر 18px: (26−18)/2 = 4px > الأرضية.
      expect(
        VisualMetrics.displayMathGapPx(mathHeightPx: 26, lineHeightPx: 18),
        closeTo(4.0, 1e-9),
      );
      // صندوق 40px: (40−18)/2 = 11px.
      expect(
        VisualMetrics.displayMathGapPx(mathHeightPx: 40, lineHeightPx: 18),
        closeTo(11.0, 1e-9),
      );
    });

    test('القيم غير الصالحة تُعيد الأرضية وحدها', () {
      for (final pair in <List<double>>[
        <double>[double.nan, 18],
        <double>[26, double.nan],
        <double>[double.infinity, 18],
        <double>[0, 18],
        <double>[26, 0],
        <double>[-5, 18],
        <double>[26, -1],
      ]) {
        expect(
          VisualMetrics.displayMathGapPx(
            mathHeightPx: pair[0],
            lineHeightPx: pair[1],
          ),
          VisualMetrics.displayMathMinGapPx,
          reason: 'قيمة غير صالحة أنتجت فجوة غير الأرضية: $pair',
        );
      }
    });
  });

  group('المحرك يستهلك القاعدة من الارتفاعات المقيسة', () {
    for (final body in <String>[
      r'مقدمة قصيرة $$x=1$$ ثم خاتمة',
      r'مقدمة قصيرة $$\frac{a}{b}=\sqrt{x^{2}+1}$$ ثم خاتمة',
      r'مقدمة قصيرة $$\int_{0}^{1} x\,dx=\frac{1}{2}$$ ثم خاتمة',
    ]) {
      test('فجوة منفصلة = max(3pt, (h−line)/2) لـ"$body"', () {
        final lines = _allLines(_layout(_document(body)));
        final index = lines.indexWhere(_isDisplayMathLine);
        expect(index, greaterThan(0),
            reason: 'لا سطر معادلة منفصلة في المخطط: القياس بلا عيّنة.');
        final math = lines[index];
        final previous = lines[index - 1];
        final gap = math.rect.top - previous.rect.bottom;
        final lineHeight = previous.rect.height;
        final expected = math.rect.height.isFinite && lineHeight > 0
            ? (math.rect.height - lineHeight) / 2
            : _kFloorPt;
        final floorOrDerived = expected > _kFloorPt ? expected : _kFloorPt;
        expect(gap, greaterThanOrEqualTo(_kFloorPt - 1e-6),
            reason: 'الفجوة أقل من الأرضية: $gap');
        expect(gap, closeTo(floorOrDerived, _kTolerancePt),
            reason: 'الفجوة $gap لا تطابق الصيغة $floorOrDerived '
                '(ارتفاع الصندوق ${math.rect.height}، ارتفاع السطر $lineHeight)');
      });
    }

    test('الفجوة تتبع ارتفاع الصندوق لا رقمًا ثابتًا', () {
      final lines = _allLines(_layout(
        _document(r'مقدمة $$x=1$$ وسط $$\frac{a}{b}=\sqrt{x^{2}+1}$$ خاتمة'),
      ));
      final mathLines =
          lines.where(_isDisplayMathLine).toList(growable: false);
      expect(mathLines.length, greaterThanOrEqualTo(2),
          reason: 'المعادلتان لم تصيرا سطرين منفصلين: القياس بلا عيّنة.');
      for (final line in mathLines) {
        final index = lines.indexOf(line);
        final previous = lines[index - 1];
        final derived = (line.rect.height - previous.rect.height) / 2;
        final expected = derived > _kFloorPt ? derived : _kFloorPt;
        expect(
          line.rect.top - previous.rect.bottom,
          closeTo(expected, _kTolerancePt),
          reason: 'سطر ${line.id} لا يتبع الصيغة المشتقة.',
        );
      }
    });
  });

  group('مصدر واحد للفجوة', () {
    test('لا تبقى حشوة ثابتة في TexText ولا رقم ثابت في المحرك', () {
      final texText =
          File('lib/views/widgets/tex_text.dart').readAsStringSync();
      expect(texText.contains('VisualMetrics.displayMathGapPx'), isTrue,
          reason: 'المعاينة لم تعد تستهلك القاعدة المشتركة.');
      expect(texText.contains('EdgeInsets.symmetric(vertical: 4)'), isFalse,
          reason: 'عادت الحشوة الثابتة إلى TexText.');

      final engine =
          File('lib/layout/canonical/layout_engine.dart').readAsStringSync();
      expect(engine.contains('_displayMathGapPt'), isTrue,
          reason: 'المحرك لم يعد يستهلك القاعدة المشتقة.');
      expect(engine.contains('before: isBlockMath ? LayoutUnits.pxToPt(4)'),
          isFalse,
          reason: 'عاد الرقم الثابت إلى فجوة المحرك.');
    });

    test('القاعدة معرَّفة مرة واحدة في VisualMetrics', () {
      final metrics =
          File('lib/layout/visual/visual_metrics.dart').readAsStringSync();
      expect(
        RegExp(r'double displayMathGapPx\(').allMatches(metrics).length,
        1,
      );
      final engine =
          File('lib/layout/canonical/layout_engine.dart').readAsStringSync();
      final texText =
          File('lib/views/widgets/tex_text.dart').readAsStringSync();
      for (final source in <String>[engine, texText]) {
        expect(source.contains('displayMathGapPx('), isTrue);
        // لا صيغة ثانية مكرّرة داخل الراسم أو المحرك: النسخة المكرّرة
        // تُعرف بخشم القسمة على ارتفاع السطر، وهو ما لا وجود له إلا في
        // VisualMetrics.
        expect(
          RegExp(r'lineHeight(Px|Pt)?\)\s*/\s*2').hasMatch(source),
          isFalse,
          reason: 'صيغة الفجوة مكرّرة خارج VisualMetrics.',
        );
      }
    });
  });
}
