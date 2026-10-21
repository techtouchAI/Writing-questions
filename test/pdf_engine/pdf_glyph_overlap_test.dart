// بوابة: لا يتداخل حبر كلمتين متجاورتين في PDF، والنص المرسوم كامل.
//
// البلاغ يُظهر في PDF: «اللارحمن» بدل «الله الرحمن»، و«٢٠٢٧/» بدل
// «٢٠٢٦/٢٠٢٧»، ودرجة السؤال ناقصة قوسًا، والمعادلة فوق الرقم. كل هذه أعراض
// **تراكب حبر** أو **ضياع كلمة**، لا فرقًا في محتوى النموذج.
//
// هذا الاختبار يقيس ما هو مكتوب فعلاً في مجرى صفحة PDF: مواضع الكلمات
// (`Td`) وتقدّمها من مصفوفة `/W` داخل الملف نفسه، فلا يعتمد على أي ثابت في
// الاختبار ولا على صورة مرجعية.
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/models/branch_item.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/paper_settings.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/pdf_engine/exam_fonts.dart';
import 'package:writing_questions_app/pdf_engine/paginated_pdf_exam_engine.dart';

import 'pdf_content_probe.dart';

const String _year = '2026/2027';

ExamDocument _document() => ExamDocument(
      name: 'بوابة تراكب الحبر',
      header: ExamHeaderModel(
        schoolName: 'متوسطة حليف القرآن للبنين',
        examType: 'نصف السنة',
        academicYear: _year,
        subject: 'الرياضيات',
        grade: 'الأول المتوسط',
        time: 'ساعة ونصف',
        showBismillah: true,
      ),
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Uint8List bytes;
  late PdfContentProbe probe;

  setUpAll(() async {
    final fonts = await ExamFonts.load();
    bytes = await PaginatedPdfExamEngine().generate(
      document: _document(),
      fonts: fonts,
    );
    probe = PdfContentProbe.fromBytes(bytes, pageIndex: 0);
  });

  test('لا تراكب بين كلمتين متجاورتين من المقطع نفسه في أي سطر', () {
    final violations = <String>[];
    for (final line in probe.lines) {
      for (final index in line.adjacencyIndices) {
        final gap = line.gapAfter(index);
        if (gap >= -0.75) continue;
        final right = line.words[index];
        final left = line.words[index + 1];
        violations.add(
          '"${right.text}"@${right.x.toStringAsFixed(2)}'
          '+${right.advanceWidth.toStringAsFixed(2)} (${right.baseFont}) فوق '
          '"${left.text}"@${left.x.toStringAsFixed(2)}'
          '+${left.advanceWidth.toStringAsFixed(2)} (${left.baseFont}) '
          'الفجوة=${gap.toStringAsFixed(2)}pt',
        );
      }
    }
    for (final line in probe.lines) {
      debugPrint('PDF-LINE ${line.describe()}');
    }
    expect(
      violations,
      isEmpty,
      reason: 'تراكب حبر بين كلمات متجاورة (${violations.length}):\n'
          '${violations.join('\n')}',
    );
  });

  test('حبر الكلمة لا يتجاوز موضعها: العرض المرسوم يطابق التقدّم', () {
    // كل كلمة تُرسم من `x` بتقدّم `advanceWidth`؛ إن كان الحبر أوسع من التقدّم
    // دخل على الجارة. نقيس هنا الحالة الأكثر ظهورًا في البلاغ: السطر الذي يحمل
    // العام الدراسي رقمًا وشرطة (جزيرة LTR داخل سياق RTL).
    const arabicDigits = <String>['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    String localize(String latin) => latin
        .split('')
        .map((char) {
          final index = '0123456789'.indexOf(char);
          return index >= 0 ? arabicDigits[index] : char;
        })
        .join();
    final parts = _year.split('/');
    final first = localize(parts.first);
    final second = localize(parts.last);

    final yearLines = probe.lines
        .where((line) =>
            line.words.any((word) => word.text == first) &&
            line.words.any((word) => word.text == second))
        .toList();
    expect(yearLines, hasLength(1),
        reason: 'العام الدراسي (${parts.first}/${parts.last}) ليس على سطر واحد '
            'في PDF. الكلمات المرسومة: '
            '${probe.words.map((word) => word.text).toList()}');

    final line = yearLines.single;
    final firstWord = line.words.firstWhere((word) => word.text == first);
    final secondWord = line.words.firstWhere((word) => word.text == second);
    final slashes = line.words.where((word) => word.text == '/').toList();
    expect(slashes, isNotEmpty, reason: 'شرطة العام الدراسي غير مرسومة.');

    final separator = slashes.firstWhere(
      (word) =>
          word.x >= firstWord.x &&
          word.x + word.advanceWidth <= secondWord.x + 0.5,
      orElse: () => slashes.first,
    );
    // جزيرة LTR: الأرقام والشرطة تتقدّم يسارًا إلى يمين بلا تراكب.
    expect(separator.x, greaterThanOrEqualTo(firstWord.x - 0.5),
        reason: 'الشرطة قبل الرقم الأول: ${line.describe()}');
    expect(secondWord.x, greaterThanOrEqualTo(separator.x - 0.5),
        reason: 'الرقم الثاني قبل الشرطة: ${line.describe()}');
    expect(
      line.gaps.where((gap) => gap < -0.75),
      isEmpty,
      reason: 'تداخل داخل سطر العام الدراسي: ${line.describe()}',
    );
  });

}
