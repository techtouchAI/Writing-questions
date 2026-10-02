// عقد Layout/Rendering الواحد: الحجم والتباعد والإزاحة والمحتوى تُقرأ من هنا
// في المعاينة وPDF وWord — فلا رقم مكتوب في راسم، ولا جدول ثانٍ ينحرف.
import 'package:flutter_test/flutter_test.dart';

import 'package:writing_questions_app/layout/paper_metrics.dart';
import 'package:writing_questions_app/layout/visual/visual_content.dart';
import 'package:writing_questions_app/layout/visual/visual_metrics.dart';
import 'package:writing_questions_app/layout/visual/visual_style.dart';
import 'package:writing_questions_app/layout/visual/visual_typography.dart';
import 'package:writing_questions_app/models/paper_font.dart';
import 'package:writing_questions_app/models/paper_settings.dart';
import 'package:writing_questions_app/models/paper_text_style.dart';
import 'package:writing_questions_app/models/subject_layout.dart';

VisualTextStyle _resolve(
  VisualRole role, {
  PaperSettings settings = const PaperSettings(),
  SubjectLayoutTemplate layout = SubjectLayoutTemplate.generic,
  PaperTextStyle? override,
}) =>
    ExamTypography.resolve(
      role,
      settings: settings,
      layout: layout,
      override: override,
    );

void main() {
  group('جدول الأدوار — نفس أرقام المعاينة قبل التوحيد', () {
    test('الترويسة والتذييل', () {
      expect(_resolve(VisualRole.headerTitle).fontSizePt, 15);
      expect(_resolve(VisualRole.headerTitle).lineHeight, 1.6);
      expect(_resolve(VisualRole.headerTitle).bold, isTrue);
      expect(_resolve(VisualRole.headerBody).fontSizePt, 10);
      expect(_resolve(VisualRole.headerBody).lineHeight, 1.6);
      // نص التذييل الصغير دوره `footer` (8.5/1.45)، أما سطور التوقيع
      // والعبارة الختامية فتستعمل `headerBody` نفسه (10/1.6) — وهذا نص
      // العقد صراحةً حتى لا ينحرف التذييل في أي راسم.
      expect(_resolve(VisualRole.footer).fontSizePt, 8.5);
      expect(_resolve(VisualRole.footer).lineHeight, 1.45);
    });

    test('البسملة والقسم والعنوان والنص', () {
      final bismillah = _resolve(VisualRole.bismillah);
      expect(bismillah.fontSizePt, 17);
      expect(bismillah.lineHeight, 1.5);
      expect(bismillah.font, PaperFont.amiri);

      final category = _resolve(VisualRole.category);
      expect(category.fontSizePt, 12.5);
      expect(category.lineHeight, 1.45);
      expect(category.bold, isTrue);

      final title = _resolve(VisualRole.questionTitle);
      expect(title.fontSizePt, 11);
      expect(title.lineHeight, 1.7);
      expect(title.bold, isTrue);

      expect(_resolve(VisualRole.questionBody).fontSizePt, 11);
      expect(_resolve(VisualRole.questionBody).lineHeight, 1.7);
    });

    test('النقطة والخيار', () {
      expect(_resolve(VisualRole.point).fontSizePt, 10.5);
      expect(_resolve(VisualRole.point).lineHeight, 1.5);
      expect(_resolve(VisualRole.option).fontSizePt, 10.5);
      expect(_resolve(VisualRole.option).lineHeight, 1.4);
    });

    test('الآية: خط مصحفي وارتفاع أعلى قليلاً', () {
      final verse = _resolve(
        VisualRole.verse,
        layout: SubjectLayoutTemplate.arabic,
      );
      expect(verse.fontSizePt, 12);
      expect(verse.font, PaperFont.amiri);
      expect(
        verse.lineHeight,
        closeTo(SubjectLayoutTemplate.arabic.lineHeightFactor + 0.2, 1e-9),
      );
    });

    test('المتن يتبع قالب المادة', () {
      for (final layout in SubjectLayoutTemplate.values) {
        expect(
          _resolve(VisualRole.branchBody, layout: layout).lineHeight,
          closeTo(layout.lineHeightFactor, 1e-9),
        );
      }
    });

    test('الملاحظات بلون واحد من العقد (لا رمادي مكتوب في ثلاثة أماكن)', () {
      expect(_resolve(VisualRole.small).color, ExamTypography.mutedColor);
      expect(_resolve(VisualRole.note).color, ExamTypography.mutedColor);
    });
  });

  group('معامل الورقة يُطبَّق مرة واحدة', () {
    const scaled = PaperSettings(baseFontSize: 12.6, lineSpacing: 2.0);
    final fontScale = 12.6 / PaperSettings.referenceFontSize;
    final heightScale = 2.0 / PaperSettings.referenceLineSpacing;

    test('الحجم والارتفاع مضروبان بالمعامل مرة واحدة لا مرتين', () {
      final title = _resolve(VisualRole.questionTitle, settings: scaled);
      expect(title.fontSizePt, closeTo(11 * fontScale, 1e-9));
      expect(title.lineHeight, closeTo(1.7 * heightScale, 1e-9));
      // لو ضُرب مرتين لصار 11 × 1.2 × 1.2.
      expect(
        title.fontSizePt,
        isNot(closeTo(11 * fontScale * fontScale, 1e-6)),
      );
    });

    test('التنسيق المخصص المطلق للعنصر لا يتأثر بالمعامل العام', () {
      final custom = _resolve(
        VisualRole.questionBody,
        settings: scaled,
        override: const PaperTextStyle(fontSize: 9, lineHeight: 1.1),
      );
      expect(custom.fontSizePt, 9);
      expect(custom.lineHeight, 1.1);
    });

    test('تحويلات Word: أنصاف النقاط وارتفاع السطر بالتويب', () {
      expect(_resolve(VisualRole.questionTitle).halfPoints, 22); // 11pt
      expect(_resolve(VisualRole.questionTitle).lineTwips, 408); // 1.7
      expect(_resolve(VisualRole.point).halfPoints, 21); // 10.5pt
      expect(
        _resolve(VisualRole.questionTitle, settings: scaled).halfPoints,
        (11 * fontScale * 2).round(),
      );
    });
  });

  group('المسافات والإزاحات (VisualMetrics)', () {
    test('التحويل الموحّد بكسل ← نقطة ← تويب', () {
      expect(PaperMetrics.twips(VisualMetrics.pointIndentPx), 540); // 36px
      expect(PaperMetrics.twips(VisualMetrics.branchIndentPx), 390); // 26px
      expect(PaperMetrics.twips(VisualMetrics.optionIndentPx), 300); // 20px
      // معامل واحد: النقاط من البكسل وبالعكس بلا فقد.
      expect(
        PaperMetrics.px(PaperMetrics.pt(VisualMetrics.pointIndentPx)),
        closeTo(VisualMetrics.pointIndentPx, 1e-9),
      );
    });

    test('الفجوات المشتركة مشتقة من PaperMetrics لا مكررة', () {
      expect(VisualMetrics.elementGapPx, PaperMetrics.elementGapPx);
      expect(VisualMetrics.itemGapPx, PaperMetrics.itemGapPx);
      expect(VisualMetrics.branchGapPx, PaperMetrics.branchGapPx);
      expect(VisualMetrics.blockSpacingPx, PaperMetrics.blockSpacingPx);
    });

    test('أرقام البنية كلها في العقد (لا ثابت في راسم)', () {
      expect(VisualMetrics.branchIndentPx, 26);
      expect(VisualMetrics.pointIndentPx, 36);
      expect(VisualMetrics.optionIndentPx, 20);
      expect(VisualMetrics.optionLabelGapPx, 6);
      expect(VisualMetrics.optionBoxWidthPx, 190);
      expect(VisualMetrics.titleGapPx, 4);
      expect(VisualMetrics.questionFramePaddingPx, 5);
    });
  });

  group('المحتوى مقاطع لا نصاً واحداً', () {
    test('يفصل النص عن الصيغة والآية بترتيب الظهور', () {
      final content = RichContent.parse(r'قبل $$x^2$$ بين ﴿آية﴾ بعد');
      expect(content.hasMath, isTrue);
      expect(content.hasQuran, isTrue);
      expect(content.runs.map((run) => run.kind), <VisualRunKind>[
        VisualRunKind.text,
        VisualRunKind.math,
        VisualRunKind.text,
        VisualRunKind.quran,
        VisualRunKind.text,
      ]);
      // `plainText` نصّ المحتوى: زخرفة الآية تبقى (هي التي تعرّفه للراسم)،
      // وعلامات الصيغة `$$` تُنزع لأن مقطع الرياضيات يحمل المحتوى وحده.
      expect(content.plainText, 'قبل x^2 بين ﴿آية﴾ بعد');
      // مقطع الرياضيات يحمل المحتوى وحده (العلامات `$` ليست جزءاً من LaTeX).
      expect(content.runs[1].text, 'x^2');
      expect(content.runs.every((run) => run.text.isNotEmpty), isTrue);
    });

    test('النص العادي مقطع واحد', () {
      final content = RichContent.parse('نص عادي');
      expect(content.runs, hasLength(1));
      expect(content.runs.single.isText, isTrue);
      expect(content.hasMath, isFalse);
      expect(content.hasQuran, isFalse);
    });

    test('نص فارغ = بلا مقاطع (لا يُرسم شيء)', () {
      expect(RichContent.parse('').isEmpty, isTrue);
    });
  });
}
