// التخطيط الجديد لورقة الأسئلة في ملف PDF الناتج فعلياً: الترويسة بثلاثة
// أعمدة، التذييل في آخر صفحة وحدها، ولا ترقيم للصفحات، والإطار.
//
// المنهج: لا نفحص الشيفرة الداخلية، بل نقرأ ملف PDF الناتج عبر
// [PdfContentProbe]. طبقة النص العربية مخزَّنة مشكّلة (أشكال عرض)، لذلك
// تُحسب الصيغة المشكّلة لكل كلمة بترسيمها منفردة بنفس الخط ثم تُطابَق.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:writing_questions_app/models/branch_item.dart';
import 'package:writing_questions_app/models/branch_model.dart';
import 'package:writing_questions_app/models/exam_catalog.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_footer_model.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/paper_settings.dart';
import 'package:writing_questions_app/models/point_kind.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/pdf_engine/pdf_engine.dart';

import 'pdf_content_probe.dart';

/// صورة PNG شفافة بحجم 1×1 (تكفي لاختبار تضمين صورة الإطار).
final Uint8List _framePng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

ExamDocument _document({
  ExamHeaderModel? header,
  ExamFooterModel? footer,
  PaperSettings? settings,
  List<QuestionModel>? questions,
}) {
  return ExamDocument(
    name: 'اختبار التخطيط',
    header: header ??
        ExamHeaderModel(
          schoolName: 'متوسطة حليف القرآن',
          examType: 'نصف السنة',
          academicYear: '2026/2027',
          subject: 'الرياضيات',
          grade: 'الثالث',
          time: 'ساعتان',
          showBismillah: false,
        ),
    footer: footer ?? const ExamFooterModel(closingPhrase: 'انتهت الأسئلة'),
    settings: settings,
    questions: questions ??
        <QuestionModel>[
          QuestionModel(id: 'q1', questionNumber: 1, statement: 'اختر الإجابة الصحيحة'),
        ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ExamFonts fonts;

  setUpAll(() async {
    fonts = await ExamFonts.load();
  });

  /// الكلمات المشكّلة كما ستظهر في ملف PDF (نص منفرد بنفس خط الورقة).
  Future<List<String>> shaped(String text) async {
    final document = pw.Document();
    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
        build: (context) => pw.Text(text),
      ),
    );
    return PdfContentProbe.fromBytes(await document.save()).words.map((word) => word.text).toList();
  }

  Future<String> firstShaped(String word) async => (await shaped(word)).first;

  Future<Uint8List> generate(ExamDocument document, {List<List<String>>? pages, Uint8List? frame}) {
    return PaginatedPdfExamEngine().generate(
      document: document,
      fonts: fonts,
      pageAssignments: pages,
      frameImage: frame,
    );
  }

  ProbedWord word(PdfContentProbe probe, String shapedWord) {
    return probe.words.firstWhere(
      (candidate) => candidate.text == shapedWord,
      orElse: () => throw StateError('الكلمة المشكّلة غير مرسومة: $shapedWord'),
    );
  }

  group('الترويسة', () {
    test('ثلاثة أعمدة فيزيائية: المدرسة يميناً والامتحان وسطاً والمادة يساراً', () async {
      final probe = PdfContentProbe.fromBytes(await generate(_document()), pageIndex: 0);

      final right = word(probe, await firstShaped('ادارة'));
      final center = word(probe, await firstShaped('اسئلة'));
      // The punctuation colon is a separate semantic run in canonical layout.
      final left = word(probe, await firstShaped('المادة'));

      expect(right.x, greaterThan(center.x));
      expect(center.x, greaterThan(left.x));
      // الأعمدة الثلاثة في أعلى الصفحة (إحداثي y عالٍ).
      expect(right.y, greaterThan(PdfPageFormat.a4.height * 0.8));
      expect(left.y, greaterThan(PdfPageFormat.a4.height * 0.8));
    });

    test('الحقول الفارغة تُطبع خطاً منقطاً (المادة/الصف/الوقت + اسم الطالب)', () async {
      // توقيع مسمّى كي لا يُحسب خط التوقيع المنقط ضمن العدّ.
      const footer = ExamFooterModel(
        closingPhrase: '',
        primary: SignatureModel(name: 'أحمد'),
      );
      final blank = _document(
        header: ExamHeaderModel(showBismillah: false),
        footer: footer,
      );
      final blankWords = PdfContentProbe.fromBytes(await generate(blank)).words;
      final dotted = blankWords.where((word) => RegExp(r'^\.+$').hasMatch(word.text)).toList();
      expect(dotted, hasLength(4));

      final filled = PdfContentProbe.fromBytes(
        await generate(_document(footer: footer)),
      ).words;
      final dottedFilled = filled.where((word) => RegExp(r'^\.+$').hasMatch(word.text));
      // لم يبقَ إلا خط اسم الطالب.
      expect(dottedFilled, hasLength(1));
    });

    test('البسملة بخط Amiri عند تفعيلها فقط', () async {
      final withBismillah = _document(
        header: ExamHeaderModel(subject: 'الرياضيات'),
      );
      final on = PdfContentProbe.fromBytes(await generate(withBismillah)).words;
      expect(on.any((word) => word.baseFont.toLowerCase().contains('amiri')), isTrue);

      final without = _document(
        header: ExamHeaderModel(subject: 'الرياضيات', showBismillah: false),
      );
      final off = PdfContentProbe.fromBytes(await generate(without)).words;
      expect(off.any((word) => word.baseFont.toLowerCase().contains('amiri')), isFalse);
    });

    test('الدور الامتحاني يُطبع تحت العام الدراسي مباشرة', () async {
      final document = _document(
        header: ExamHeaderModel(
          examType: 'نصف السنة',
          academicYear: '2026/2027',
          session: ExamSession.second,
          showBismillah: false,
        ),
      );
      final probe = PdfContentProbe.fromBytes(await generate(document));
      final year = word(probe, await firstShaped('للعام'));
      final session = word(probe, await firstShaped('الثاني'));
      // y الأصغر = أسفل في الصفحة: الدور تحت العام.
      expect(session.y, lessThan(year.y));
    });
  });

  group('التذييل', () {
    ExamDocument twoPages({ExamFooterModel? footer}) => _document(
          footer: footer,
          questions: <QuestionModel>[
            QuestionModel(id: 'q1', questionNumber: 1, statement: 'السؤال الأول'),
            QuestionModel(id: 'q2', questionNumber: 2, statement: 'السؤال الثاني'),
          ],
        );

    test('يُطبع في آخر صفحة فقط ولا يتكرر في غيرها', () async {
      final bytes = await generate(
        twoPages(),
        pages: const <List<String>>[
          <String>['q1'],
          <String>['q2'],
        ],
      );
      expect(PdfContentProbe.pageCountOf(bytes), 2);
      final phrase = await firstShaped('انتهت');

      final first = PdfContentProbe.fromBytes(bytes, pageIndex: 0).words.map((w) => w.text);
      final last = PdfContentProbe.fromBytes(bytes, pageIndex: 1).words.map((w) => w.text);
      expect(first, isNot(contains(phrase)));
      expect(last, contains(phrase));
    });

    test('ملتصق بأسفل الصفحة وتحت آخر سؤال', () async {
      final bytes = await generate(twoPages());
      final probe = PdfContentProbe.fromBytes(bytes);
      final phrase = word(probe, await firstShaped('انتهت'));
      final question = word(probe, await firstShaped('الثاني'));

      // قرب أسفل صندوق المحتوى (هامش 15 مم) لا بعد آخر سؤال مباشرة.
      expect(phrase.y, lessThan(15 * PdfPageFormat.mm + 80));
      expect(phrase.y, lessThan(question.y));
    });

    test('التوقيع الأساسي يساراً والثاني يميناً، والثاني يظهر عند إضافته فقط', () async {
      final single = _document(
        footer: const ExamFooterModel(
          closingPhrase: '',
          primary: SignatureModel(name: 'أحمد'),
        ),
      );
      final singleProbe = PdfContentProbe.fromBytes(await generate(single));
      final titleWord = await firstShaped('مدرس');
      expect(singleProbe.words.where((w) => w.text == titleWord), hasLength(1));

      final both = _document(
        footer: const ExamFooterModel(
          closingPhrase: '',
          primary: SignatureModel(name: 'أحمد'),
          secondary: SignatureModel(title: SignatureTitle.educator, name: 'علي'),
        ),
      );
      final probe = PdfContentProbe.fromBytes(await generate(both));
      final primary = word(probe, await firstShaped('أحمد'));
      final secondary = word(probe, await firstShaped('علي'));
      expect(primary.x, lessThan(secondary.x));
      expect(probe.words.where((w) => w.text == titleWord), hasLength(1));
      expect(probe.words.where((w) => w.text == titleWord), isNotEmpty);
    });

    test('التوقيع بلا اسم يُطبع خطاً منقطاً', () async {
      final probe = PdfContentProbe.fromBytes(await generate(_document()));
      final dotted = probe.words.where((w) => RegExp(r'^\.+$').hasMatch(w.text));
      // المادة/الصف/الوقت معبّأة: خط اسم الطالب + خط التوقيع.
      expect(dotted, hasLength(2));
    });
  });

  group('لا ترقيم للصفحات', () {
    test('لا كلمة «صفحة» في أي صفحة ولا حقل ترقيم في الملف', () async {
      final bytes = await generate(
        _document(
          questions: <QuestionModel>[
            for (var i = 1; i <= 3; i++)
              QuestionModel(id: 'q$i', questionNumber: i, statement: 'سؤال $i'),
          ],
        ),
        pages: const <List<String>>[
          <String>['q1'],
          <String>['q2'],
          <String>['q3'],
        ],
      );
      final pageWord = await firstShaped('صفحة');
      final count = PdfContentProbe.pageCountOf(bytes);
      expect(count, 3);
      for (var page = 0; page < count; page++) {
        final words = PdfContentProbe.fromBytes(bytes, pageIndex: page).words.map((w) => w.text);
        expect(words, isNot(contains(pageWord)), reason: 'الصفحة ${page + 1}');
        expect(words.where((w) => w == 'of' || w == 'Page'), isEmpty);
      }
    });
  });

  group('الإطار', () {
    bool hasImage(Uint8List bytes) =>
        RegExp(r'/Subtype\s*/Image').hasMatch(String.fromCharCodes(bytes));

    test('صورة PNG تُدمج خلف المحتوى عند تفعيل الإطار فقط', () async {
      final on = await generate(
        _document(settings: const PaperSettings(pageBorder: true)),
        frame: _framePng,
      );
      expect(hasImage(on), isTrue);

      final off = await generate(_document(), frame: _framePng);
      expect(hasImage(off), isFalse);
    });

    test('بلا صورة يُرسم الإطار المتجه ولا تُدمج صورة', () async {
      final vector = await generate(
        _document(settings: const PaperSettings(pageBorder: true)),
      );
      expect(hasImage(vector), isFalse);
      expect(String.fromCharCodes(vector), startsWith('%PDF-'));
    });

    test('صورة تالفة ترتد إلى الإطار المتجه بدل إسقاط التصدير', () async {
      final bytes = await generate(
        _document(settings: const PaperSettings(pageBorder: true)),
        frame: Uint8List.fromList(<int>[1, 2, 3, 4]),
      );
      expect(String.fromCharCodes(bytes), startsWith('%PDF-'));
      expect(hasImage(bytes), isFalse);
    });

    test('الهامش يحدد صندوق المحتوى: هامش أكبر يدفع الترويسة للداخل', () async {
      Future<ProbedWord> rightmost(double marginMm) async {
        final probe = PdfContentProbe.fromBytes(
          await generate(
            _document(settings: PaperSettings(pageBorder: true, marginMm: marginMm)),
          ),
        );
        return word(probe, await firstShaped('ادارة'));
      }

      final small = await rightmost(8);
      final large = await rightmost(25);
      expect(large.x, lessThan(small.x));
      expect(large.y, lessThan(small.y));
    });
  });

  group('الأرقام والنصوص المحظورة', () {
    test('الدرجة تُطبع «(٢٠ درجة)» في سطر العنوان', () async {
      final document = _document(
        questions: <QuestionModel>[
          QuestionModel(
            id: 'q1',
            questionNumber: 1,
            statement: 'اختر',
            marksOverride: 20,
            items: <BranchItem>[
              BranchItem(kind: PointKind.trueFalse, text: 'الأرض كروية'),
            ],
            branches: <BranchModel>[BranchModel(marks: 5, content: BranchContent(statement: 'فرع'))],
          ),
        ],
      );
      final probe = PdfContentProbe.fromBytes(await generate(document));
      final texts = probe.words.map((w) => w.text).toList();
      // الأقواس تلتصق بالرقم داخل الكلمة نفسها: «(٢٠» و«(٥».
      expect(texts.any((text) => text.contains('٢٠')), isTrue);
      expect(texts.any((text) => text.contains('٥')), isTrue);
      expect(texts.any((text) => text.contains('20')), isFalse);
    });

    test('لا تظهر العبارة المحظورة في أي كلمة مرسومة', () async {
      final probe = PdfContentProbe.fromBytes(await generate(_document()));
      final banned = await shaped('الوزارية');
      final texts = probe.words.map((w) => w.text).toList();
      for (final token in banned) {
        expect(texts, isNot(contains(token)));
      }
    });
  });
}
