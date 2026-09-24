import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:writing_questions_app/models/exam.dart';
import 'package:writing_questions_app/models/exam_header.dart';
import 'package:writing_questions_app/models/main_question.dart';
import 'package:writing_questions_app/models/question_branch.dart';
import 'package:writing_questions_app/models/question_option.dart';
import 'package:writing_questions_app/models/question_type.dart';
import 'package:writing_questions_app/pdf_engine/pdf_engine.dart';

Exam _buildExam({required int questionCount, String subject = 'اللغة العربية'}) {
  final questions = <MainQuestion>[
    for (var index = 0; index < questionCount; index++)
      MainQuestion(
        title: 'السؤال رقم ${index + 1}: ما الذي يليه مما سبق يوافق القاعدة النحوية '
            'المعتمدة في الكتاب المدرسي مع نص إضافي لاختبار الالتفاف والحجم؟',
        type: index.isEven ? QuestionType.multipleChoice : QuestionType.essay,
        branches: <QuestionBranch>[
          QuestionBranch(text: '', marks: index.isEven ? 2 : 5),
        ],
        category: index.isEven ? 'القواعد' : 'الأدب',
        options: index.isEven
            ? <QuestionOption>[
                QuestionOption(text: 'الخيار الأول الصحيح', isCorrect: true),
                QuestionOption(text: 'خيار ب'),
                QuestionOption(text: 'خيار ج'),
                QuestionOption(text: 'خيار د'),
              ]
            : const <QuestionOption>[],
        modelAnswer: 'عناصر الإجابة النموذجية بنص طويل لضمان وجود محتوى كافٍ.',
        explanation: 'ملاحظة المعلم للتوضيح.',
      ),
  ];

  return Exam(
    name: 'اختبار تجريبي',
    header: ExamHeader(
      subject: subject,
      gradeStage: 'الثالث المتوسط',
      directorate: 'مديرية تربية ذي قار',
      section: 'شعبة 2',
      examType: 'اختبار نصف السنة',
      instructor: 'أ. مصطفى',
      duration: '',
      examDate: DateTime(2026, 2, 10),
    ),
    mainQuestions: questions,
  );
}

int _countPages(List<int> bytes) {
  final source = String.fromCharCodes(bytes);
  return RegExp(r'/Type\s*/Page(?![s\w])').allMatches(source).length;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PdfExamEngine', () {
    test('produces a valid single-page A4 document', () async {
      final bytes = await const PdfExamEngine()
          .generate(exam: _buildExam(questionCount: 8), isTeacherVersion: false);

      final source = String.fromCharCodes(bytes);
      expect(bytes.length, greaterThan(5 * 1024), reason: 'خطوط PDF مضمّنة');
      expect(source, startsWith('%PDF-'));
      expect(_countPages(bytes), 1, reason: 'ورقة الامتحان صفحة واحدة تماماً');
      expect(RegExp(r'/MediaBox\s*\[\s*0\s+0\s+595').hasMatch(source), isTrue);
      expect(RegExp(r'\s841(\.89|\.\d+)?\s*\]').hasMatch(source), isTrue);
    });

    test('keeps even a very long exam on a single page (auto-fit)', () async {
      final bytes = await const PdfExamEngine()
          .generate(exam: _buildExam(questionCount: 60), isTeacherVersion: false);

      expect(_countPages(bytes), 1);
    });

    test('teacher version also stays on one page', () async {
      final bytes = await const PdfExamEngine()
          .generate(exam: _buildExam(questionCount: 40), isTeacherVersion: true);

      expect(_countPages(bytes), 1);
      expect(String.fromCharCodes(bytes), startsWith('%PDF-'));
    });

    test('renders an empty exam without crashing', () async {
      final exam = Exam(name: 'فارغ', mainQuestions: const <MainQuestion>[]);
      final bytes = await const PdfExamEngine().generate(
        exam: exam,
        isTeacherVersion: false,
      );

      expect(_countPages(bytes), 1);
    });

    test('uses strategy override when provided', () async {
      final bytes = await const PdfExamEngine().generate(
        exam: _buildExam(questionCount: 3, subject: 'علوم'),
        isTeacherVersion: false,
        strategy: const EnglishExamStrategy(),
      );

      expect(_countPages(bytes), 1);
    });

    test('content width matches A4 minus the 15mm margins', () {
      // 210مم عرضاً ناقص 15مم من كل جهة = 180مم متاحة لمنطقة الأسئلة.
      const expected = 180 * PdfPageFormat.mm;
      expect(PdfExamEngine.contentWidth, closeTo(expected, 0.01));
    });
  });
}
