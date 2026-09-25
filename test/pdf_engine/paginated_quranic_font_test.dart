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

ExamDocument _islamicDocument({required String verse, String subject = 'التربية الإسلامية'}) {
  return ExamDocument(
    name: subject,
    header: ExamHeaderModel.ministerialDefault(subject: subject),
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
    const verse = '\uFD3F إنا أعطيناك الكوثر \uFD3E';

    test('draws the verse with the Quranic font and the rest with Noto Naskh', () async {
      final doc = _islamicDocument(verse: verse);
      final needsQ = PaginatedPdfExamEngine.needsQuranicFont(doc);
      final loaded = await ExamFonts.load(loadQuranic: needsQ);
      final bytes = await PaginatedPdfExamEngine().generate(document: doc);
      final probe = PdfContentProbe.fromBytes(bytes);
      final seenFonts = <String>{
        for (final line in probe.lines) for (final word in line.words) word.baseFont,
      };

      bool hasFont(String needle) => probe.lines.any(
            (line) => line.words.any(
              (word) => word.baseFont.toLowerCase().contains(needle),
            ),
          );

      expect(
        hasFont('amiri'),
        isTrue,
        reason: 'DIAG needsQuranic=$needsQ quranicLoaded=${loaded.quranic != null} '
            'seenFonts=$seenFonts',
      );
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

    test('applies the Quranic face in non-Islamic templates too (no mushaf centering)', () async {
      final bytes = await PaginatedPdfExamEngine().generate(
        document: _islamicDocument(verse: verse, subject: 'اللغة العربية'),
      );
      final probe = PdfContentProbe.fromBytes(bytes);

      final words = <ProbedWord>[
        for (final line in probe.lines) ...line.words,
      ];
      expect(words, isNotEmpty);
      // القوسان المزخرفان يُرسمان (الآية موجودة نصاً) وبالخط القرآني.
      expect(
        words.any((word) => word.text.contains('\uFD3F') || word.text.contains('\uFD3E')),
        isTrue,
        reason: 'وسم الآية يُرسم كما كتبه المعلم',
      );
      expect(
        words.any((word) => word.baseFont.toLowerCase().contains('amiri')),
        isTrue,
        reason: 'الخط القرآني يُلبس المقاطع الموسومة في كل القوالب',
      );
    });

    test('skips the Quranic face for sheets with no Quranic text', () async {
      final withVerse = _islamicDocument(verse: verse);
      final withoutVerse = _islamicDocument(verse: 'اشرح مفهوم التلاوة الصحيحة');

      expect(PaginatedPdfExamEngine.needsQuranicFont(withVerse), isTrue);
      expect(PaginatedPdfExamEngine.needsQuranicFont(withoutVerse), isFalse);

      final fonts = await ExamFonts.load(loadQuranic: false);
      expect(fonts.hasQuranic, isFalse, reason: 'لا يُحمَّل الخط القرآني بلا حاجة');
      expect(fonts.regular, isNotNull);

      // ورقة بلا وسْم قرآني تُولَّد طبيعية (بقية الخطوط كما هي).
      final bytes = await PaginatedPdfExamEngine().generate(
        document: withoutVerse,
        fonts: fonts,
      );
      expect(PdfContentProbe.fromBytes(bytes).lines, isNotEmpty);
    });

    test('still renders the verse when no Quranic font is available', () async {
      final fonts = await ExamFonts.load(bundle: _BundleWithoutQuranic());
      final bytes = await PaginatedPdfExamEngine().generate(
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
