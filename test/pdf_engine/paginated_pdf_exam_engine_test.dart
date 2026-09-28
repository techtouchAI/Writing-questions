import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:writing_questions_app/models/branch_model.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/floating_element.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/models/question_option.dart';
import 'package:writing_questions_app/models/question_type.dart';
import 'package:writing_questions_app/pdf_engine/pdf_engine.dart';

int _countPages(List<int> bytes) {
  final source = String.fromCharCodes(bytes);
  return RegExp(r'/Type\s*/Page(?![s\w])').allMatches(source).length;
}

ExamDocument _document({
  required int questionCount,
  int branchesPerQuestion = 3,
  String subject = 'اللغة العربية',
  QuestionType type = QuestionType.essay,
}) {
  return ExamDocument(
    name: 'نموذج تجريبي',
    header: ExamHeaderModel.ministerialDefault(subject: subject),
    questions: <QuestionModel>[
      for (var q = 0; q < questionCount; q++)
        QuestionModel(
          id: 'q${q + 1}',
          questionNumber: q + 1,
          branches: <BranchModel>[
            for (var b = 0; b < branchesPerQuestion; b++)
              BranchModel(
                content: BranchContent(
                  type: type,
                  text: 'نص الفرع رقم ${b + 1} من السؤال ${q + 1} مع كلمات إضافية '
                      'لاختبار الالتفاف داخل عرض الورقة المتاح بالكامل.',
                  options: type == QuestionType.multipleChoice
                      ? <QuestionOption>[
                          QuestionOption(text: 'خيار أول', isCorrect: true),
                          QuestionOption(text: 'خيار ثانٍ'),
                          QuestionOption(text: 'خيار ثالث'),
                        ]
                      : const <QuestionOption>[],
                  modelAnswer: 'إجابة نموذجية',
                ),
                marks: 2,
              ),
          ],
        ),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PaginatedPdfExamEngine', () {
    test('renders a single-page A4 document for a short exam', () async {
      final bytes = await PaginatedPdfExamEngine().generate(
        document: _document(questionCount: 2, branchesPerQuestion: 1),
      );
      final source = String.fromCharCodes(bytes);

      expect(source, startsWith('%PDF-'));
      expect(_countPages(bytes), 1);
      expect(RegExp(r'/MediaBox\s*\[\s*0\s+0\s+595').hasMatch(source), isTrue);
    });

    test('spreads a long exam over multiple pages without splitting a question', () async {
      // 12 أسئلة مقالية × 3 فروع × 4 أسطر إجابة ≈ أطول من صفحة واحدة بكثير.
      final bytes = await PaginatedPdfExamEngine().generate(
        document: _document(questionCount: 12),
      );

      expect(_countPages(bytes), greaterThan(1));
    });

    test('excludes non-printable placeholders from student and teacher pagination', () async {
      final document = ExamDocument(
        name: 'ترقيم الطباعة',
        header: ExamHeaderModel.ministerialDefault(subject: 'الرياضيات'),
        questions: <QuestionModel>[
          QuestionModel(id: 'blank', questionNumber: 1),
          QuestionModel(id: 'student', questionNumber: 2, prompt: 'سؤال ظاهر للطالب'),
          QuestionModel(
            id: 'teacher-answer',
            questionNumber: 3,
            branches: <BranchModel>[
              BranchModel(
                content: BranchContent(
                  type: QuestionType.essay,
                  modelAnswer: 'إجابة تظهر للمعلم فقط',
                ),
              ),
            ],
          ),
        ],
      );
      final engine = PaginatedPdfExamEngine();
      final studentPages = await engine.resolveQuestionPages(document: document);
      final teacherPages = await engine.resolveQuestionPages(
        document: document,
        isTeacherVersion: true,
      );

      expect(studentPages.expand((page) => page), <String>['student']);
      expect(
        teacherPages.expand((page) => page),
        <String>['student', 'teacher-answer'],
      );
      // توزيع قديم يتضمن السؤال الفارغ يُعاد حسابه، لا يُطبع كصفحة أو فراغ.
      final bytes = await engine.generate(
        document: document,
        pageAssignments: const <List<String>>[
          <String>['blank', 'student', 'teacher-answer'],
        ],
      );
      expect(_countPages(bytes), 1);

      final globalMirror = FloatingElement(
        id: 'global-only-mirror',
        type: FloatingElementType.shape,
        shape: FloatingShapeType.square,
        width: 24,
        height: 24,
      );
      final mirrorDocument = ExamDocument(
        name: 'مرآة عنصر حر',
        header: ExamHeaderModel.ministerialDefault(subject: 'الرياضيات'),
        questions: <QuestionModel>[
          QuestionModel(
            id: 'mirror-owner',
            questionNumber: 1,
            branches: <BranchModel>[
              BranchModel(
                content: BranchContent.empty(),
                attachments: <FloatingElement>[globalMirror],
              ),
            ],
          ),
        ],
        floatingElements: <FloatingElement>[globalMirror],
      );
      final mirrorPages = await engine.resolveQuestionPages(document: mirrorDocument);
      expect(mirrorPages.expand((page) => page), isEmpty);
    });

    test('honours the on-screen page assignments exactly', () async {
      final document = _document(questionCount: 4, branchesPerQuestion: 1);
      final bytes = await PaginatedPdfExamEngine().generate(
        document: document,
        pageAssignments: const <List<String>>[
          <String>['q1'],
          <String>['q2', 'q3'],
          <String>['q4'],
        ],
      );

      expect(_countPages(bytes), 3);
    });

    test('falls back to its own measurement when assignments are incomplete', () async {
      final document = _document(questionCount: 2, branchesPerQuestion: 1);
      final bytes = await PaginatedPdfExamEngine().generate(
        document: document,
        pageAssignments: const <List<String>>[
          <String>['q1'],
        ],
      );

      expect(_countPages(bytes), 1);
    });

    test('renders the English (LTR) layout and the teacher version', () async {
      final english = _document(
        questionCount: 3,
        subject: 'اللغة الإنجليزية',
        type: QuestionType.multipleChoice,
      );
      expect(english.layout.isLtr, isTrue);

      final student = await PaginatedPdfExamEngine().generate(document: english);
      final teacher = await PaginatedPdfExamEngine().generate(
        document: english,
        isTeacherVersion: true,
      );

      expect(String.fromCharCodes(student), startsWith('%PDF-'));
      expect(_countPages(student), greaterThanOrEqualTo(1));
      expect(_countPages(teacher), greaterThanOrEqualTo(1));
    });

    test('renders document-level floating elements without any question owner', () async {
      final document = ExamDocument(
        name: 'ورقة بلا أسئلة',
        header: ExamHeaderModel.ministerialDefault(subject: 'الرياضيات'),
        floatingElements: <FloatingElement>[
          FloatingElement(
            id: 'free-shape',
            type: FloatingElementType.shape,
            shape: FloatingShapeType.circle,
            dx: 280,
            dy: 360,
            width: 90,
            height: 90,
          ),
        ],
      );

      final bytes = await PaginatedPdfExamEngine().generate(document: document);

      expect(_countPages(bytes), 1);
      expect(String.fromCharCodes(bytes), startsWith('%PDF-'));
    });

    test('embeds branch attachments (shapes) anchored to their branch', () async {
      final document = ExamDocument(
        name: 'مرفقات',
        header: ExamHeaderModel.ministerialDefault(subject: 'الرياضيات'),
        questions: <QuestionModel>[
          QuestionModel(
            questionNumber: 1,
            branches: <BranchModel>[
              BranchModel(
                content: BranchContent(type: QuestionType.essay, text: r'أوجد $\sqrt{x}$'),
                marks: 5,
                attachments: <FloatingElement>[
                  FloatingElement(
                    type: FloatingElementType.shape,
                    shape: FloatingShapeType.triangle,
                    dx: 20,
                    dy: 10,
                    width: 90,
                    height: 70,
                  ),
                ],
              ),
            ],
          ),
        ],
      );

      final bytes = await PaginatedPdfExamEngine().generate(document: document);
      expect(_countPages(bytes), 1);
      expect(String.fromCharCodes(bytes), startsWith('%PDF-'));
    });

    test('content geometry matches the A4 sheet minus 15mm margins', () {
      expect(PaginatedPdfExamEngine.contentWidth, closeTo(180 * PdfPageFormat.mm, 0.01));
      expect(
        PaginatedPdfExamEngine.pageContentHeight,
        lessThan(PdfPageFormat.a4.height - 30 * PdfPageFormat.mm),
      );
    });
  });
}
