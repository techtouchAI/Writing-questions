// تشخيص مؤقّت (يُحذف بعد تحديد السبب): هندسة العام الدراسي في التخطيط.
import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/paper_settings.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/pdf_engine/exam_fonts.dart';
import 'package:writing_questions_app/pdf_engine/paginated_pdf_exam_engine.dart';

ExamDocument _document() => ExamDocument(
      name: 'تشخيص العام',
      header: ExamHeaderModel(
        schoolName: 'متوسطة حليف القرآن للبنين',
        examType: 'نصف السنة',
        academicYear: '2026/2027',
        subject: 'الرياضيات',
        grade: 'الأول المتوسط',
        time: 'ساعة ونصف',
        showBismillah: true,
      ),
      settings: const PaperSettings(headerBorder: true),
      questions: const <QuestionModel>[],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('DIAG year geometry', () async {
    final fonts = await ExamFonts.load();
    final layout = await PaginatedPdfExamEngine().resolveLayoutDocument(
      document: _document(),
      fonts: fonts,
    );
    final buffer = StringBuffer();
    for (final line in layout.allLines) {
      final hasYear = line.runs.any(
        (run) => run.text.contains('٢٠٢٦') || run.text.contains('2026'),
      );
      if (!hasYear) continue;
      buffer.writeln('LINE ${line.id} baseline=${line.baseline} '
          'rect=${line.rect.left}..${line.rect.right}');
      for (final run in line.runs) {
        buffer.writeln('  RUN ${run.id} dir=${run.direction.name} '
            'x=${run.x.toStringAsFixed(2)} adv=${run.advance.toStringAsFixed(2)} '
            'text="${run.text}"');
        for (final word in run.words) {
          buffer.writeln('    WORD "${word.text}" x=${word.x.toStringAsFixed(2)} '
              'adv=${word.advance.toStringAsFixed(2)} '
              'textAdv=${word.textAdvance.toStringAsFixed(2)}');
        }
      }
    }
    fail(buffer.toString());
  });
}
