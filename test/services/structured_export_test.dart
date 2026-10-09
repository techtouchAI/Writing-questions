// البنية لا النص المدموج: الخيارات في PDF **صناديق ثابتة العرض** تتشارك
// السطر وتلتفّ كما في المعاينة (لا نصاً واحداً يفصل بينه بمسافات NBSP)،
// والقيم (العرض والفجوة) هي قيم العقد نفسه.
//
// (حُذفت في C5 مع Word القابل للتحرير: جريانات `<w:r>` المستقلة لكل جزء
// وقيم `w:ind/w:sz/w:line` من العقد — Word اليوم صور لا بنية.)
import 'package:flutter_test/flutter_test.dart';

import 'package:writing_questions_app/layout/paper_metrics.dart';
import 'package:writing_questions_app/layout/visual/visual_metrics.dart';
import 'package:writing_questions_app/models/branch_item.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/paper_settings.dart';
import 'package:writing_questions_app/models/point_kind.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/models/question_option.dart';
import 'package:writing_questions_app/pdf_engine/paginated_pdf_exam_engine.dart';

import '../pdf_engine/pdf_content_probe.dart';

ExamDocument _document() => ExamDocument(
      name: 'بنية',
      header: ExamHeaderModel.initial(subject: 'اللغة العربية'),
      // أرقام لاتينية وتسميات صريحة: تُقرأ صريحةً من PDF أيضاً.
      settings: const PaperSettings(numerals: PaperNumerals.latin),
      questions: <QuestionModel>[
        QuestionModel(
          id: 'q1',
          questionNumber: 1,
          category: 'Cat',
          statement: 'Stmt',
          marksOverride: 12,
          items: <BranchItem>[
            BranchItem(
              id: 'p1',
              kind: PointKind.multipleChoice,
              text: 'PointOne',
              marks: 3,
              options: <QuestionOption>[
                QuestionOption(text: 'OptA', labelOverride: 'A)'),
                QuestionOption(text: 'OptB', labelOverride: 'B)'),
                QuestionOption(text: 'OptC', labelOverride: 'C)'),
                QuestionOption(text: 'OptD', labelOverride: 'D)'),
              ],
            ),
          ],
        ),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PDF: الخيارات صناديق ثابتة العرض في سطر واحد', () {
    test('ثلاثة خيارات تشترك السطر والرابع يلتفّ، والعرض عرض العقد', () async {
      final bytes = await PaginatedPdfExamEngine().generate(
        document: _document(),
      );
      final probe = PdfContentProbe.fromBytes(bytes);

      ProbedWord option(String text) => probe.words.firstWhere(
            (word) => word.text.contains(text),
            orElse: () => fail('كلمة الخيار «$text» لم تُرسم في PDF.'),
          );

      final a = option('OptA');
      final b = option('OptB');
      final c = option('OptC');
      final d = option('OptD');

      expect(a.y, closeTo(b.y, 0.5), reason: 'الخياران الأول والثاني في سطر واحد.');
      expect(b.y, closeTo(c.y, 0.5), reason: 'ثلاثة خيارات تتشارك السطر كما في المعاينة.');
      expect(d.y, lessThan(a.y),
          reason: 'الخيار الرابع يلتفّ إلى صف جديد (Wrap) كما في المعاينة.');

      // الترتيب من اليمين إلى اليسار: الأول يميناً ثم التالي يساراً.
      expect(a.x, greaterThan(b.x));
      expect(b.x, greaterThan(c.x));

      // المسافة بين صندوقين متجاورين = عرض الصندوق + الفجوة (من العقد).
      // تُقاس من **تسميتي** الخيارين (وكلتاهما في أول صندوقها) فلا يتداخل
      // عرض التسمية مع نص الخيار في القياس.
      // The canonical semantic tree keeps punctuation in its own stable run,
      // so the word probe sees the alphanumeric label separately from `)`.
      final labelA = probe.words.firstWhere((word) => word.text.trim() == 'A');
      final labelB = probe.words.firstWhere((word) => word.text.trim() == 'B');
      final step = PaperMetrics.pt(
        VisualMetrics.optionBoxWidthPx + VisualMetrics.optionWrapSpacingPx,
      );
      expect((labelA.x - labelB.x).abs(), closeTo(step, 1.0),
          reason: 'عرض صندوق الخيار وفجوته من العقد لا من قياس النص الحر.');
      expect(
        probe.words.any((word) => word.text.contains('PointOne')),
        isTrue,
        reason: 'نص النقطة مرسوم ككلمة مستقلة عن تسميتها.',
      );
      final pointLine = probe.lines.firstWhere(
        (line) => line.words.any((word) => word.text.trim() == 'PointOne'),
      );
      final pointLabelParts = pointLine.words
          .map((word) => word.text.trim())
          .where((text) => text == '1' || text == '-')
          .toSet();
      expect(
        pointLabelParts,
        containsAll(<String>{'1', '-'}),
        reason: 'رقم النقطة وفاصلها يُرسمان كتسمية مستقلة عن نصها.',
      );
    });
  });
}
