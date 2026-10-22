// استخراج نصّ PDF: هل يقرأ القارئ من الملف **الكلمات التي كتبها المدرس**؟
//
// هذه بوابة سلوكية لا بنيوية: تبني مستندًا حقيقيًا بمحرك PDF القانوني، ثم تقرأ
// من الملف نفسه ما يقرؤه أي قارئ PDF (سلسلة CID عبر `/ToUnicode` لكل كلمة
// مرسومة كما تُستخرج في القصاصة/النسخ)، وتقارنه بالنصّ المنطقي.
//
// ما تقيسه:
//   1. صفر أشكال عرض عربية (U+FB50..FDFF / U+FE70..FEFF) في النصّ المستخرَج —
//      أشكال العرض تجعل «الرحمن» غير موجود في البحث.
//   2. كل كلمة عربية من السؤال تُستخرج كاملةً بحروفها المعجمية؛ والمقارنة
//      بعكس محارف الكلمة المنطقية مكتوبة في الاختبار بقواعد الحروف لا عبر
//      الشارح، فحرف ضائع من رابطة لام-ألف يُفشلها.
//   3. الأرقام والأقواس تبقى كما كُتبت (لا تُقلَب ولا تُفقد).
//   4. لا CID بلا مدخل `/ToUnicode` (المحرف البديل U+FFFD يعني فشل الاستخراج).
//
// ما لا تقيسه هنا: ترتيب الكلمات في الجملة (قرار القارئ وبيديه) — ترتيب السطر
// تقيسه P0-GATE-03 على الهندسة، والرسم يُقاس في rtl_to_unicode_test.dart.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart' show isArabicPresentationForm;
import 'package:writing_questions_app/models/branch_item.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_footer_model.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/paper_settings.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/pdf_engine/exam_fonts.dart';
import 'package:writing_questions_app/pdf_engine/paginated_pdf_exam_engine.dart';

import 'pdf_content_probe.dart';

/// الشكل البصري لكلمة عربية خالصة: عكس محارف الكلمة المنطقية.
///
/// مكتوب بقواعد الحروف مباشرةً (لا عبر شارح المحرك) كي تكون المقارنة مستقلة:
/// لو فقد الاستخراج حرفًا من رابطة لام-ألف لاختلف النصّان.
String _visualOrder(String logical) =>
    String.fromCharCodes(logical.runes.toList().reversed);

ExamDocument _document() {
  return ExamDocument(
    name: 'استخراج نص PDF',
    header: ExamHeaderModel(
      schoolName: 'متوسطة حليف القرآن',
      examType: 'نصف السنة',
      academicYear: '2026/2027',
      subject: 'الرياضيات',
      grade: 'الأول المتوسط',
      time: 'ساعة ونصف',
      showBismillah: true,
    ),
    footer: const ExamFooterModel(closingPhrase: 'انتهت الأسئلة'),
    settings: const PaperSettings(headerBorder: true),
    questions: <QuestionModel>[
      QuestionModel(
        id: 'q1',
        questionNumber: 1,
        statement: 'حل المعادلات التالية',
        marksOverride: 20,
        items: <BranchItem>[
          BranchItem(id: 'i1', text: 'أجب عن السؤال (٢٠ درجة)'),
        ],
      ),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Uint8List pdfBytes;

  setUpAll(() async {
    final fonts = await ExamFonts.load();
    pdfBytes = await PaginatedPdfExamEngine().generate(
      document: _document(),
      fonts: fonts,
    );
  });

  test('الصفحة الأولى: صفر أشكال عرض، وكل كلمة عربية كاملة الحروف', () {
    final probe = PdfContentProbe.fromBytes(pdfBytes, pageIndex: 0);
    expect(probe.words, isNotEmpty,
        reason: 'لم تُستخرج أي كلمة من الصفحة — القياس بلا عيّنة.');
    final drawn = probe.words.map((word) => word.text).toList();

    // (1) لا شكل عرض في أي كلمة مستخرَجة.
    for (final word in drawn) {
      for (final rune in word.runes) {
        expect(isArabicPresentationForm(rune), isFalse,
            reason: 'النصّ المستخرَج «$word» يحمل شكل العرض '
                '${rune.toRadixString(16)} — البحث عنه بالحروف العادية يفشل.');
      }
    }

    // (4) لا CID بلا مدخل ToUnicode (المحرف البديل يعني خريطة ناقصة).
    expect(drawn.join(' ').contains('\uFFFD'), isFalse,
        reason: 'CID بلا /ToUnicode — استخراج ناقص: $drawn');

    // (2) كل كلمة من السؤال موجودة بحروفها المعجمية كاملة.
    for (final word in const <String>[
      'حل',
      'المعادلات',
      'التالية',
      'أجب',
      'عن',
      'السؤال',
      'درجة',
    ]) {
      expect(drawn, contains(_visualOrder(word)),
          reason: 'كلمة السؤال «$word» لم تُستخرج كاملةً. المتوقع '
              '«${_visualOrder(word)}».\nالمستخرَج: $drawn');
    }

    // (2ب) حدود الكلمات: كل كلمة تُكتب إرسالًا مستقلًا، فالنصّ المرسوم يحوي
    // الكلمات الثلاث متتابعةً لا مدموجة. أما مسافة الاستخراج فيستنتجها القارئ
    // من الفجوة بين الإرسالين، وهذا حدّ معلن في تقرير الحدود.
    // الترتيب المنطقي والترتيب البصري كلاهما مقبول كترتيب إرسال (المهم ألا
    // تُدمج الكلمات ولا تُفقد)، فالمقارنة تقبل أحد التسلسلين المتتاليين.
    final logicalOrder = <String>['حل', 'المعادلات', 'التالية']
        .map(_visualOrder)
        .toList();
    final joined = drawn.join(' ');
    expect(
      joined.contains(logicalOrder.join(' ')) ||
          joined.contains(logicalOrder.reversed.join(' ')),
      isTrue,
      reason: 'كلمات السؤال ليست إرسالات مستقلة متتابعة (كلمة مدموجة أو '
          'ناقصة): $drawn',
    );

    // (3) الأرقام والأقواس: «٢٠» رقم وليس صورة، والقوس محرف منطقي.
    expect(drawn.any((word) => word.contains('٢٠')), isTrue,
        reason: 'الرقم «٢٠» لم يُستخرج في أي كلمة: $drawn');
    expect(
      drawn.where((word) => word.contains('(') || word.contains(')')),
      isNotEmpty,
      reason: 'قوسا «(٢٠ درجة)» لم يُستخرجا: $drawn',
    );
  });

  test('البسملة تُستخرَج أربع كلمات معجمية متمايزة', () {
    final probe = PdfContentProbe.fromBytes(pdfBytes, pageIndex: 0);
    final drawn = probe.words.map((word) => word.text).toList();
    final expected = <String>[
      for (final word in const <String>['بسم', 'الله', 'الرحمن', 'الرحيم'])
        _visualOrder(word),
    ];
    for (final token in expected) {
      expect(drawn, contains(token),
          reason: 'كلمة البسملة «$token» غير مستخرَجة. المستخرَج: $drawn');
    }
    expect(expected.toSet(), hasLength(4),
        reason: 'بصمات كلمات البسملة يجب أن تكون متمايزة.');
  });
}
