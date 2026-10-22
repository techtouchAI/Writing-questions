// =============================================================================
// بوابة انحدار مفقودة: هل ما يُرسم في PDF هو **نفس** كلمات التخطيط القانوني؟
//
// بوابة التحقق البصري القائمة تقارن راسم المعاينة القانوني بـPDF، فتنجح حتى
// لو كان كلاهما يعرض النص تالفًا. هذا الاختبار يقيس النص **المرسوم فعلاً** في
// الملف (Td/TJ من مجرى الصفحة نفسه) ويقارنه بعقد الكلمات في `LayoutDocument`:
//
//   1. لا تراكب: كلمتان متجاورتان من المقطع نفسه لا يجوز أن يتداخلا حبرهما.
//      (هذا هو عطل «اللارحمن» و«٢٠٢٧/» الظاهر في صور البلاغ: الكلمة تُرسم أوسع
//      من موضعها فتغطي جارتها ويقصّ clip الكلمةُ حبرَ نفسها.)
//   2. لا ضياع: كل كلمة من سطر البسملة موجودة مرسومة داخل السطر نفسه؛ والعام
//      الدراسي (أرقامه وشرطته) مرسوم متصلًا على سطر واحد وبترتيب LTR — أي أن
//      الأرقام لا تُقطع ولا تُعاد ترتيبها ولا تُفصل عن شرطتها.
//   3. لا كلمات زائدة: عدد الكلمات المرسومة في الصفحة لا يزيد على عدد كلمات
//      التخطيط (كلمة مكرّرة أو مقطوعة تعني انحراف إسقاط).
//
// كل الأرقام تأتي من الخطوط المضمّنة في الملف نفسه، لا من ثوابت في الاختبار.
// =============================================================================
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:writing_questions_app/layout/canonical/layout_document.dart';
import 'package:writing_questions_app/models/branch_item.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_footer_model.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/paper_settings.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/pdf_engine/exam_fonts.dart';
import 'package:writing_questions_app/pdf_engine/paginated_pdf_exam_engine.dart';

import 'pdf_content_probe.dart';

/// ورقة بالشكل الذي تُظهره صور البلاغ: بسملة (خط قرآني)، ترويسة بعام دراسي
/// عريض، سؤال بدرجة عشرين ونقطة تحتوي معادلة سطرية.
ExamDocument _document() {
  return ExamDocument(
    name: 'بوابة نص PDF',
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
          BranchItem(id: 'i1', text: r'أجب عن المعادلات: $5+\sqrt{10}$'),
        ],
      ),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ExamFonts fonts;
  late Uint8List pdfBytes;
  late LayoutDocument layout;

  setUpAll(() async {
    fonts = await ExamFonts.load();
    final engine = PaginatedPdfExamEngine();
    final document = _document();
    layout = await engine.resolveLayoutDocument(document: document, fonts: fonts);
    pdfBytes = await engine.generate(document: document, fonts: fonts);
  });

  /// الكلمة كما يكتبها المحرك في قناة `/ToUnicode`: حروف معجمية بترتيب بصري.
  /// هذا ما يقرؤه القارئ منها (وليس الشكل المشكَّل) بعد إصلاح قناة الاستخراج.
  String shaped(String text) => shapeRtlRun(text).toUnicodeText;

  group('نصّ PDF مطابق لعقد الكلمات في التخطيط', () {
    test('لا كلمتان متجاورتان تتراكبان في أي سطر من أي صفحة', () {
      final pageCount = PdfContentProbe.pageCountOf(pdfBytes);
      expect(pageCount, greaterThan(0));

      var measuredPairs = 0;
      for (var pageIndex = 0; pageIndex < pageCount; pageIndex++) {
        final probe = PdfContentProbe.fromBytes(pdfBytes, pageIndex: pageIndex);
        for (final line in probe.lines) {
          for (final index in line.adjacencyIndices) {
            measuredPairs++;
            final gap = line.gapAfter(index);
            expect(
              gap,
              greaterThan(-0.75),
              reason: 'تراكب كلمتين في الصفحة $pageIndex بين '
                  '"${line.words[index].text}" و'
                  '"${line.words[index + 1].text}" (فجوة $gap نقطة).\n'
                  'السطر المرسوم: ${line.describe()}\n'
                  'هذا هو نمط «اللارحمن» و«٢٠٢٧/»: الكلمة تُرسم أوسع من '
                  'موضعها القانوني فتغطي جارتها.',
            );
          }
        }
      }
      expect(measuredPairs, greaterThan(10),
          reason: 'لم تُقس أي فجوة ($measuredPairs): البوابة صامتة.');
    });

    test('البسملة تُرسم أربع كلمات في السطر نفسه لا كلمتين مدموجتين',
        () async {
      final probe = PdfContentProbe.fromBytes(pdfBytes, pageIndex: 0);
      final tokens = <String>[
        shaped('بسم'),
        shaped('الله'),
        shaped('الرحمن'),
        shaped('الرحيم'),
      ];
      final line = probe.lineWithWord(tokens.first);
      expect(line, isNotNull,
          reason: 'سطر البسملة غير موجود. كل الكلمات المرسومة: '
              '${probe.words.map((word) => word.text).toList()}');
      final drawn = line!.words.map((word) => word.text).toList();
      for (final token in tokens) {
        expect(
          drawn,
          contains(token),
          reason: 'كلمة البسملة "$token" غير مرسومة في سطرها: $drawn\n'
              'الكلمات المدموجة تعني أن إحداهما غطّت الأخرى.',
        );
      }
      final bismillahWords =
          drawn.where((word) => tokens.contains(word)).toList();
      expect(bismillahWords.length, 4,
          reason: 'سطر البسملة يحمل ${bismillahWords.length} كلمة من أربع: '
              '$drawn');
    });

    test('العام الدراسي رمز واحد متصل بترتيبه المنطقي (لا يُقطع ولا يتراكب)',
        () {
      // «٢٠٢٦/٢٠٢٧» لا حرف عربي فيه وفاصله داخلي بين رقمين، فهو بحكم UAX #9
      // جزيرة LTR واحدة؛ تُقاس قطعةً واحدة وتُكتب في PDF رمزًا واحدًا، فلا
      // تنقسم مجموعتاه ولا تُرسم إحداهما فوق الأخرى ولا تُعاد الشرطة للطرف.
      final year = _document().header.academicYear;
      final localized = _arabicIndic(year);
      final probe = PdfContentProbe.fromBytes(pdfBytes, pageIndex: 0);
      final tokens = probe.words.where((word) => word.text == localized).toList();
      expect(
        tokens,
        hasLength(1),
        reason: 'العام الدراسي «$localized» يجب أن يُرسم مرة واحدة رمزًا واحدًا.\n'
            'الكلمات المرسومة: ${probe.words.map((word) => word.text).toList()}',
      );
      final token = tokens.single;
      // ترتيبه المنطقي هو نفسه المرئي (LTR) فلا يُعكس ولا تُقطع شرطته.
      expect(token.text, localized);
      // ومرة واحدة: لا نسخة مقطوعة إضافية من أي مجموعة أرقام.
      final first = _arabicIndic(year.split('/').first);
      final second = _arabicIndic(year.split('/').last);
      expect(
        probe.words.where((word) => word.text == first || word.text == second),
        isEmpty,
        reason: 'مجموعة أرقام من العام رُسمت منفصلة عن شرطتها (انقسام).',
      );
      // ولا تراكب مع الجارة على السطر نفسه.
      final line = probe.lines.firstWhere((line) => line.words.contains(token));
      final ordered = <ProbedWord>[...line.words]
        ..sort((a, b) => a.x.compareTo(b.x));
      for (var index = 0; index + 1 < ordered.length; index++) {
        final current = ordered[index];
        final next = ordered[index + 1];
        if (!identical(current, token) && !identical(next, token)) continue;
        expect(
          current.x + current.advanceWidth,
          lessThanOrEqualTo(next.x + 0.75),
          reason: 'تراكب بين «${current.text}» و«${next.text}» في سطر العام: '
              '${line.describe()}',
        );
      }
    });

    test('عدد الكلمات المرسومة لا يزيد على كلمات التخطيط', () {
      final expected = _canonicalWordCount(layout);
      var drawn = 0;
      for (var pageIndex = 0;
          pageIndex < PdfContentProbe.pageCountOf(pdfBytes);
          pageIndex++) {
        drawn += PdfContentProbe.fromBytes(pdfBytes, pageIndex: pageIndex)
            .words
            .where((word) => word.text.trim().isNotEmpty)
            .length;
      }
      expect(drawn, lessThanOrEqualTo(expected + 2),
          reason: 'كلمات مرسومة أكثر من كلمات التخطيط: $drawn > $expected — '
              'إسقاط مكرّر أو تفكيك لكلمة واحدة.');
      expect(drawn, greaterThanOrEqualTo(expected - 2),
          reason: 'كلمات مرسومة أقل من كلمات التخطيط: $drawn < $expected — '
              'كلمات ضاعت في الإسقاط (العام الدراسي مثلًا).');
    });
  });
}

String _arabicIndic(String latin) {
  const digits = '٠١٢٣٤٥٦٧٨٩';
  final buffer = StringBuffer();
  for (final codeUnit in latin.codeUnits) {
    final char = String.fromCharCode(codeUnit);
    final index = '0123456789'.indexOf(char);
    buffer.write(index >= 0 ? digits[index] : char);
  }
  return buffer.toString();
}

/// كلمات التخطيط القابلة للرسم: غير المصوَّرة وغير الفراغية.
int _canonicalWordCount(LayoutDocument layout) {
  var count = 0;
  for (final line in layout.allLines) {
    for (final run in line.runs) {
      if (run.isMath) continue;
      if (run.text.trim().isEmpty) continue;
      final words = run.words;
      count += words.isEmpty ? 1 : words.length;
    }
  }
  return count;
}

