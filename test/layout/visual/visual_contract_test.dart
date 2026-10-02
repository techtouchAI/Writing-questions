// عقد التخطيط البصري الواحد (Visual Layout Contract):
//   * جدول الطباعة واحد لكل الأدوار (لا ثلاثة جداول في ثلاثة راسمين)،
//   * معامل القياس العام (fontScale/heightScale) يُطبَّق **مرة واحدة**،
//   * تنسيق العنصر المخصص مطلق لا يتأثر بالمعامل العام،
//   * المسافات والإزاحات من VisualMetrics لا من أرقام محلية،
//   * والمحتوى مقاطع (نص/رياضيات/قرآن) لا نصاً واحداً.
import 'package:flutter_test/flutter_test.dart';

import 'package:writing_questions_app/layout/paper_metrics.dart';
import 'package:writing_questions_app/layout/visual/visual_content.dart';
import 'package:writing_questions_app/layout/visual/visual_document.dart';
import 'package:writing_questions_app/layout/visual/visual_metrics.dart';
import 'package:writing_questions_app/layout/visual/visual_style.dart';
import 'package:writing_questions_app/layout/visual/visual_typography.dart';
import 'package:writing_questions_app/models/branch_item.dart';
import 'package:writing_questions_app/models/branch_model.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/paper_font.dart';
import 'package:writing_questions_app/models/paper_settings.dart';
import 'package:writing_questions_app/models/paper_text_style.dart';
import 'package:writing_questions_app/models/point_kind.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/models/question_option.dart';
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
  group('جدول الطباعة الواحد', () {
    test('مقاسات الأدوار بالنقاط مطابقة لما ترسمه المعاينة وPDF وWord', () {
      // القيم التاريخية نفسها التي كانت مكررة في ثلاثة أماكن.
      expect(_resolve(VisualRole.headerBody).fontSizePt, 10);
      expect(_resolve(VisualRole.category).fontSizePt, 12.5);
      expect(_resolve(VisualRole.questionTitle).fontSizePt, 11);
      expect(_resolve(VisualRole.questionBody).fontSizePt, 11);
      expect(_resolve(VisualRole.point).fontSizePt, 10.5);
      expect(_resolve(VisualRole.option).fontSizePt, 10.5);
      expect(_resolve(VisualRole.bismillah).fontSizePt, 17);
      expect(_resolve(VisualRole.verse).fontSizePt, 12);
      expect(_resolve(VisualRole.footer).fontSizePt, 8.5);
    });

    test('ارتفاعات الأسطر من الدور والقالب (والآية تزيد على القالب)', () {
      expect(_resolve(VisualRole.questionTitle).lineHeight, 1.7);
      expect(_resolve(VisualRole.point).lineHeight, 1.5);
      expect(_resolve(VisualRole.headerBody).lineHeight, 1.6);
      expect(_resolve(VisualRole.branchBody).lineHeight, 1.45);
      expect(
        _resolve(VisualRole.branchBody, layout: SubjectLayoutTemplate.scientific)
            .lineHeight,
        1.8,
      );
      expect(
        _resolve(VisualRole.verse, layout: SubjectLayoutTemplate.islamic).lineHeight,
        closeTo(1.65, 1e-9),
      );
    });

    test('الأوزان والخطوط: العنوان غامق والبسملة بخط أميري', () {
      expect(_resolve(VisualRole.questionTitle).bold, isTrue);
      expect(_resolve(VisualRole.questionBody).bold, isFalse);
      expect(_resolve(VisualRole.category).bold, isTrue);
      expect(_resolve(VisualRole.bismillah).font, PaperFont.amiri);
    });
  });

  group('معامل القياس يُطبَّق مرة واحدة', () {
    test('fontScale يضرب المرجع مرة واحدة، ولا يضاعفه أي مُلحِق', () {
      final scaled = _resolve(
        VisualRole.questionTitle,
        settings: const PaperSettings(baseFontSize: 10.5 * 1.2),
      );
      // 11 × 1.2 = 13.2 — لا 11 × 1.44.
      expect(scaled.fontSizePt, closeTo(13.2, 1e-9));
    });

    test('heightScale يضرب مرجع الدور مرة واحدة', () {
      final scaled = _resolve(
        VisualRole.questionTitle,
        settings: const PaperSettings(lineSpacing: 1.45 * 1.2),
      );
      expect(scaled.lineHeight, closeTo(1.7 * 1.2, 1e-9));
    });

    test('تنسيق العنصر المخصص مطلق: لا يتأثر بالمعامل العام', () {
      final scaled = _resolve(
        VisualRole.questionBody,
        settings: const PaperSettings(baseFontSize: 12.6, lineSpacing: 2.0),
        override: const PaperTextStyle(fontSize: 9, lineHeight: 1.1),
      );
      expect(scaled.fontSizePt, 9);
      expect(scaled.lineHeight, 1.1);
    });

    test('تحويلات Word: أنصاف النقاط وارتفاع السطر بالتويب', () {
      final title = _resolve(VisualRole.questionTitle);
      // 11pt → 22 نصف نقطة (نفس w:sz في الملف)، و1.7 → 408 = 240×1.7.
      expect(title.halfPoints, 22);
      expect(title.lineTwips, 408);
      final scaled = _resolve(
        VisualRole.questionTitle,
        settings: const PaperSettings(baseFontSize: 13.125), // fontScale 1.25
      );
      expect(scaled.halfPoints, 28); // round(11×1.25×2)
    });
  });

  group('المسافات والإزاحات (VisualMetrics)', () {
    test('التحويل الموحّد بكسل ← نقطة ← تويب', () {
      expect(PaperMetrics.twips(VisualMetrics.pointIndentPx), 540); // 36px→27pt
      expect(PaperMetrics.twips(VisualMetrics.branchIndentPx), 390); // 26px
      expect(PaperMetrics.twips(VisualMetrics.optionIndentPx), 300); // 20px
      expect(PaperMetrics.pt(VisualMetrics.pointIndentPx), closeTo(27, 1e-9));
      expect(PaperMetrics.pt(VisualMetrics.branchIndentPx), closeTo(19.5, 1e-9));
    });

    test('الفجوات المشتركة مشتقة من PaperMetrics لا مكررة', () {
      expect(VisualMetrics.elementGapPx, PaperMetrics.elementGapPx);
      expect(VisualMetrics.itemGapPx, PaperMetrics.itemGapPx);
      expect(VisualMetrics.branchGapPx, PaperMetrics.branchGapPx);
      expect(VisualMetrics.blockSpacingPx, PaperMetrics.blockSpacingPx);
    });
  });

  group('المحتوى مقاطع لا نصاً واحداً', () {
    test('يفصل النص عن الصيغة والآية بترتيب الظهور', () {
      final content = RichContent.parse('قبل \$\$x^2\$\$ بين ﴿آية﴾ بعد');
      expect(content.hasMath, isTrue);
      expect(content.hasQuran, isTrue);
      expect(content.runs.map((run) => run.kind), <VisualRunKind>[
        VisualRunKind.text,
        VisualRunKind.math,
        VisualRunKind.text,
        VisualRunKind.quran,
        VisualRunKind.text,
      ]);
      expect(content.plainText, 'قبل x^2 بين آية بعد');
    });

    test('النص العادي بلا صيغ مقطع واحد', () {
      final content = RichContent.parse('نص عادي');
      expect(content.runs, hasLength(1));
      expect(content.runs.single.isText, isTrue);
      expect(content.hasMath, isFalse);
    });
  });

  group('المستند البصري: البنية والإزاحات والمحاذاة', () {
    ExamDocument buildDocument() => ExamDocument(
          name: 'عقد',
          header: ExamHeaderModel.initial(subject: 'اللغة العربية'),
          questions: <QuestionModel>[
            QuestionModel(
              id: 'q1',
              questionNumber: 1,
              // قسم بمحاذاة خاصة + سؤال بنص ونقطة وخيارات وفرع بنقاط.
              category: 'القواعد',
              categoryAlign: PaperAlign.center,
              statement: 'منطوق السؤال',
              body: 'نص السؤال',
              bodyAlign: PaperAlign.end,
              items: <BranchItem>[
                BranchItem(
                  id: 'p1',
                  kind: PointKind.multipleChoice,
                  text: 'نقطة السؤال',
                  options: <QuestionOption>[
                    QuestionOption(text: 'خيار أول'),
                    QuestionOption(text: 'خيار ثانٍ'),
                  ],
                ),
              ],
              branches: <BranchModel>[
                BranchModel(
                  id: 'b1',
                  content: BranchContent(
                    statement: 'عنوان الفرع',
                    items: <BranchItem>[BranchItem(id: 'bp1', text: 'نقطة الفرع')],
                  ),
                ),
              ],
            ),
          ],
        );

    test('ترتيب العناصر: قسم ← عنوان ← نص ← نقاط ← فرع ← نقطة الفرع', () {
      final document = VisualLayoutEngine.build(buildDocument());
      final block = document.questionBlock('q1');
      expect(block, isNotNull);
      final kinds = block!.elements.map((element) => element.kind).toList();
      expect(kinds, <VisualElementKind>[
        VisualElementKind.category,
        VisualElementKind.title,
        VisualElementKind.body,
        VisualElementKind.point,
        VisualElementKind.title, // عنوان الفرع
        VisualElementKind.point, // نقطة الفرع
      ]);
      final roles = block.elements.map((element) => element.role).toList();
      expect(roles[0], VisualRole.category);
      expect(roles[1], VisualRole.questionTitle);
      expect(roles[2], VisualRole.questionBody);
      expect(roles[3], VisualRole.point);
      expect(roles[4], VisualRole.branchTitle);
      expect(roles[5], VisualRole.point);
    });

    test('الإزاحات من العقد: الفرع 26، نقطة السؤال 36، نقطة الفرع 62', () {
      final document = VisualLayoutEngine.build(buildDocument());
      final elements = document.questionBlock('q1')!.elements;
      expect(elements[0].indentPx, VisualMetrics.blockStartIndentPx);
      expect(elements[3].indentPx, VisualMetrics.pointIndentPx);
      expect(elements[4].indentPx, VisualMetrics.branchIndentPx);
      expect(
        elements[5].indentPx,
        VisualMetrics.branchIndentPx + VisualMetrics.pointIndentPx,
      );
    });

    test('محاذاة القسم والنص من النموذج (categoryAlign/bodyAlign)', () {
      final document = VisualLayoutEngine.build(buildDocument());
      final elements = document.questionBlock('q1')!.elements;
      expect(elements[0].align, PaperAlign.center);
      expect(elements[2].align, PaperAlign.end);
    });

    test('النقاط والخيارات تحمل محتواها مقاطعَ وأجزاءها كاملة', () {
      final document = VisualLayoutEngine.build(buildDocument());
      final point = document
          .questionBlock('q1')!
          .elements
          .firstWhere((element) => element.kind == VisualElementKind.point);
      expect(point.point, isNotNull);
      expect(point.point!.number.isNotEmpty, isTrue);
      expect(point.point!.content.plainText, 'نقطة السؤال');
      expect(point.point!.options, hasLength(2));
      expect(point.point!.options.first.content.plainText, 'خيار أول');
    });

    test('الترويسة والتذييل كتلتان بصريتان بأدوارهما', () {
      final document = VisualLayoutEngine.build(buildDocument());
      expect(document.header.isHeader, isTrue);
      expect(document.footer.isFooter, isTrue);
      expect(
        document.header.elements.first.role,
        anyOf(VisualRole.bismillah, VisualRole.headerBody),
      );
      expect(
        document.footer.elements.every((element) => element.role == VisualRole.headerBody),
        isTrue,
      );
    });
  });
}
