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
import 'package:writing_questions_app/layout/canonical/layout_document.dart';
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
  late LayoutDocument layout;

  setUpAll(() async {
    final fonts = await ExamFonts.load();
    final engine = PaginatedPdfExamEngine();
    final document = _document();
    layout = await engine.resolveLayoutDocument(
      document: document,
      fonts: fonts,
    );
    bytes = await engine.generate(document: document, fonts: fonts);
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

  test('هندسة الكلمات في PDF تطابق هندستها في التخطيط القانوني', () {
    // المصدر الوحيد للحقيقة: `LayoutDocument` نفسه الذي يرسمه Preview وPDF.
    // كل كلمة في التخطيط (نصًّا وموضعًا وعرض حبر) يجب أن تُرسم في الملف
    // بالموضع نفسه. أي انزياح = حبر يغطي جارته، وهو عطل «اللارحمن».
    final canonical =
        <String, List<({String text, double x, double advance})>>{};
    for (final line in layout.allLines) {
      for (final run in line.runs) {
        for (final word in run.words) {
          canonical
              .putIfAbsent(
                word.text.trim(),
                () => <({String text, double x, double advance})>[],
              )
              .add((
            text: word.text,
            x: word.x,
            advance: word.textAdvance,
          ));
        }
      }
    }
    final probed = <String, List<ProbedWord>>{};
    for (final word in probe.words) {
      probed.putIfAbsent(word.text, () => <ProbedWord>[]).add(word);
    }

    final mismatches = <String>[];
    var compared = 0;
    for (final entry in canonical.entries) {
      final drawn = probed[entry.key];
      if (drawn == null) continue; // غياب الكلمة تقيسه بوابة أخرى.
      for (final word in entry.value) {
        // أقرب كلمة مرسومة بنفس النص.
        ProbedWord? closest;
        var best = double.infinity;
        for (final candidate in drawn) {
          final distance = (candidate.x - word.x).abs();
          if (distance < best) {
            best = distance;
            closest = candidate;
          }
        }
        if (closest == null) continue;
        compared++;
        final dx = closest.x - word.x;
        final dAdvance = closest.advanceWidth - word.advance;
        if (dx.abs() > 0.75 || dAdvance.abs() > 0.75) {
          mismatches.add(
            '"${word.text}": التخطيط x=${word.x.toStringAsFixed(2)} '
            'عرض=${word.advance.toStringAsFixed(2)} | '
            'PDF x=${closest.x.toStringAsFixed(2)} '
            'عرض=${closest.advanceWidth.toStringAsFixed(2)} '
            '(Δx=${dx.toStringAsFixed(2)}، Δعرض=${dAdvance.toStringAsFixed(2)})',
          );
        }
      }
    }
    expect(compared, greaterThan(10),
        reason: 'لم تُقارن كلمات كافية ($compared) — الاختبار لم يقس شيئًا.');
    expect(
      mismatches,
      isEmpty,
      reason: 'كلمات رُسمت في غير موضعها من التخطيط (${mismatches.length}):\n'
          '${mismatches.take(25).join('\n')}',
    );
  });
}
