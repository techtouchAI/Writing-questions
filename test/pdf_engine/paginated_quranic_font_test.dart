import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/models/branch_model.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/models/question_type.dart';
import 'package:writing_questions_app/pdf_engine/exam_fonts.dart';
import 'package:writing_questions_app/pdf_engine/paginated_pdf_exam_engine.dart';

import 'pdf_content_probe.dart';

/// حزمة أصول تحاكي تطبيقاً لم يُضمَّن فيه الخط القرآني (شرط «إن توفّرت»).
class _BundleWithoutQuranic extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) {
    if (key == ExamFonts.quranicAsset) {
      throw Exception('asset not bundled: $key');
    }
    return rootBundle.load(key);
  }
}

ExamDocument _islamicDocument({required String verse}) {
  return ExamDocument(
    name: 'تربية إسلامية',
    header: ExamHeaderModel.ministerialDefault(subject: 'التربية الإسلامية'),
    questions: <QuestionModel>[
      QuestionModel(
        id: 'q1',
        questionNumber: 1,
        category: 'أحكام التلاوة',
        branches: <BranchModel>[
          BranchModel(
            id: 'q1a',
            content: BranchContent(
              type: QuestionType.essay,
              text: verse,
              modelAnswer: 'تلاوة صحيحة مع مراعاة أحكام التجويد',
            ),
            marks: 5,
          ),
        ],
      ),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Quranic font', () {
    test('is loaded from the bundled assets', () async {
      final fonts = await ExamFonts.load();
      expect(fonts.hasQuranic, isTrue);
      expect(ExamFonts.quranicAsset, 'assets/fonts/Amiri-Regular.ttf');
    });

    test('falls back gracefully when the asset is missing', () async {
      final fonts = await ExamFonts.load(bundle: _BundleWithoutQuranic());
      expect(fonts.hasQuranic, isFalse);
      expect(fonts.regular, isNotNull);
      expect(fonts.bold, isNotNull);
    });
  });

  group('PaginatedPdfExamEngine — Quranic verses', () {
    const verse = '﴿ إنا أعطيناك الكوثر ﴾';

    test('draws the verse with the Quranic font and the rest with Noto Naskh', () async {
      final bytes = await const PaginatedPdfExamEngine().generate(
        document: _islamicDocument(verse: verse),
      );
      final probe = PdfContentProbe.fromBytes(bytes);

      bool hasFont(String needle) => probe.lines.any(
            (line) => line.words.any(
              (word) => word.baseFont.toLowerCase().contains(needle),
            ),
          );

      expect(hasFont('amiri'), isTrue, reason: 'الآية يجب أن تُرسم بالخط القرآني');
      expect(hasFont('noto'), isTrue, reason: 'بقية الورقة تبقى بخط Noto Naskh');

      final quranicWords = <ProbedWord>[
        for (final line in probe.lines)
          for (final word in line.words)
            if (word.baseFont.toLowerCase().contains('amiri')) word,
      ];
      expect(quranicWords, isNotEmpty);
      for (final word in quranicWords) {
        // لا محارف مفقودة (0xFFFD): الخط يغطي أشكال العرض العربية كلها
        // التي يستبدلها محرك التشكيل في هذا المشروع.
        expect(
          word.text.contains('\uFFFD'),
          isFalse,
          reason: 'محرف غير مغطى في الخط القرآني: ${word.text}',
        );
      }
    });

    test('still renders the verse when no Quranic font is available', () async {
      final fonts = await ExamFonts.load(bundle: _BundleWithoutQuranic());
      final bytes = await const PaginatedPdfExamEngine().generate(
        document: _islamicDocument(verse: verse),
        fonts: fonts,
      );
      final probe = PdfContentProbe.fromBytes(bytes);

      expect(probe.lines, isNotEmpty);
      expect(
        probe.lines
            .expand((line) => line.words)
            .any((word) => word.baseFont.toLowerCase().contains('amiri')),
        isFalse,
        reason: 'بلا خط قرآني تُرسم الآية بخط الورقة الأساسي بلا فقدان للنص',
      );
      expect(
        probe.lines.expand((line) => line.words).any((word) => word.text.isNotEmpty),
        isTrue,
      );
    });
  });
}
