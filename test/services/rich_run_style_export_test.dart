// عقد تقطيع المقاطع الغنية: [RichContent.parse] يقطع النص إلى مقاطع معلنة
// (نص/قرآن/صيغة سطرية/صيغة كتلية) تقرؤها المعاينة وPDF النصي بالقواعد نفسها،
// فما يراه المدرس على الشاشة هو ما يُطبع في الملف.
//
// (حُذفت في C5 مع Word القابل للتحرير: كتابة المقاطع بتنسيقها في XML واختبار
// مربع النص الحر `w:szCs` — Word اليوم صور صفحات المعاينة لا بنية قابلة
// للتحرير، فيغطيها Exact.)
import 'package:flutter_test/flutter_test.dart';

import 'package:writing_questions_app/layout/visual/visual_content.dart';
import 'package:writing_questions_app/models/paper_font.dart';

/// آية موسومة بقوسَي المصحف (تُكتب رموزاً تهريبية فلا تنعكس بصرياً في المصدر).
const String _verse = '\uFD3Fآية\uFD3E';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('العقد: قطع واحد للمقاطع الغنية', () {
    test(r'الصيغة تُقطَع أولاً: أقواس المصحف داخل $...$ تبقى رياضيات', () {
      final content = RichContent.parse('\$y \uFD3Fث\uFD3E\$');
      expect(content.runs, hasLength(1));
      expect(content.runs.single.isMath, isTrue);
      expect(content.hasQuran, isFalse,
          reason: 'قوس المصحف داخل صيغة ليس مقطعاً قرآنياً.');
    });

    test('الآية تحمل قوسيها كاملين وخطها المعلن في المقطع نفسه', () {
      final content = RichContent.parse('قال $_verse ثم');
      expect(content.runs.map((run) => run.kind), <VisualRunKind>[
        VisualRunKind.text,
        VisualRunKind.quran,
        VisualRunKind.text,
      ]);
      final quran = content.runs[1];
      expect(quran.text, _verse, reason: 'القوسان جزء من نص المقطع.');
      expect(quran.style?.font, PaperFont.amiri);
      expect(quran.isBlockMath, isFalse);
    });

    test('الصيغة المنفصلة تُعلَن كتلة والسطرية تُعلَن سطرية', () {
      final block = RichContent.parse(r'$$\int_0^1 x\,dx$$');
      expect(block.runs.single.isMath, isTrue);
      expect(block.runs.single.isBlockMath, isTrue);
      final inline = RichContent.parse(r'$x^2$');
      expect(inline.runs.single.isMath, isTrue);
      expect(inline.runs.single.isBlockMath, isFalse);
    });

    test(r'الدولار المهروب `\$` نص عادي بلا شرطة مائلة', () {
      final content = RichContent.parse(r'سعر $5 ثم \$10');
      expect(content.plainText, isNot(contains(r'\$')));
      expect(content.plainText, contains(r'$10'));
    });

    test('`withStyle` يدمج ولا يمحو ما أُعلن سابقاً', () {
      final quran = RichContent.parse(_verse).runs.single;
      final merged = quran.withStyle(const VisualRunStyle(bold: true));
      expect(merged.style?.font, PaperFont.amiri);
      expect(merged.style?.bold, isTrue);
      expect(merged.text, quran.text);
    });
  });
}
