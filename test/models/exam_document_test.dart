import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/models/branch_model.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/floating_element.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/models/question_option.dart';
import 'package:writing_questions_app/models/question_type.dart';
import 'package:writing_questions_app/models/subject_layout.dart';

ExamDocument _twoQuestionDocument() {
  return ExamDocument(
    name: 'نموذج',
    header: ExamHeaderModel.ministerialDefault(subject: 'اللغة العربية'),
    questions: <QuestionModel>[
      QuestionModel(
        id: 'q1',
        questionNumber: 1,
        branches: <BranchModel>[
          BranchModel(
            id: 'q1a',
            content: BranchContent(type: QuestionType.essay, text: 'أعرب ما تحته خط'),
            marks: 5,
          ),
          BranchModel(
            id: 'q1b',
            content: BranchContent(type: QuestionType.fillInTheBlank, text: 'أكمل: _____'),
            marks: 3,
          ),
        ],
      ),
      QuestionModel(
        id: 'q2',
        questionNumber: 2,
        branches: <BranchModel>[
          BranchModel(
            id: 'q2a',
            content: BranchContent(
              type: QuestionType.multipleChoice,
              text: 'اختر الصحيح',
              options: <QuestionOption>[
                QuestionOption(text: 'بغداد', isCorrect: true),
                QuestionOption(text: 'البصرة'),
              ],
            ),
            marks: 2,
          ),
          BranchModel(
            id: 'q2b',
            content: BranchContent(type: QuestionType.trueFalse, text: 'الأرض كروية'),
            marks: 1,
            attachments: <FloatingElement>[
              FloatingElement(
                id: 'shape-1',
                type: FloatingElementType.shape,
                shape: FloatingShapeType.circle,
                dx: 10,
                dy: 20,
                width: 60,
                height: 60,
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

void main() {
  group('ExamHeaderModel', () {
    test('holds exactly three lines per column and round-trips through JSON', () {
      final header = ExamHeaderModel(
        subject: 'الرياضيات',
        right: HeaderColumn(<String>['التاريخ', 'المادة']),
        center: HeaderColumn(<String>['وزارة التربية', 'المدرسة', 'الدور الأول', 'زائد']),
        left: HeaderColumn(<String>['الوقت', 'الاسم', 'الرقم الامتحاني']),
      );

      expect(header.right.lines, <String>['التاريخ', 'المادة', '']);
      expect(header.center.lines, hasLength(HeaderColumn.lineCount));
      expect(header.layoutTemplate, SubjectLayoutTemplate.scientific);

      final restored = ExamHeaderModel.fromMap(header.toMap());
      expect(restored.left.lines, header.left.lines);
      expect(restored.center.lines.last, 'الدور الأول');
      expect(restored.layoutTemplate, SubjectLayoutTemplate.scientific);
    });

    test('changing the subject re-selects the layout template', () {
      final header = ExamHeaderModel.ministerialDefault(subject: 'اللغة العربية');
      expect(header.layoutTemplate, SubjectLayoutTemplate.arabic);

      final english = header.copyWith(subject: 'اللغة الإنجليزية');
      expect(english.layoutTemplate, SubjectLayoutTemplate.english);
      expect(english.layoutTemplate.isLtr, isTrue);
    });

    test('withLine edits a single header cell in place', () {
      final header = ExamHeaderModel.ministerialDefault();
      final edited = header.withLine(HeaderSlot.left, 1, 'الاسم: علي');

      expect(edited.left.lines[1], 'الاسم: علي');
      expect(edited.left.lines[0], header.left.lines[0]);
      expect(edited.right, header.right);
    });

    test('rejects a header without a subject', () {
      expect(
        () => ExamHeaderModel.fromMap(const <String, dynamic>{'right': <String>[]}),
        throwsFormatException,
      );
    });
  });

  group('QuestionModel / BranchModel', () {
    test('a question always has at least one branch and rolls up marks', () {
      final question = QuestionModel(questionNumber: 1);
      expect(question.branches, hasLength(1));
      expect(question.marks, 0);

      final grown = question
          .withBranchAdded(BranchModel(marks: 2))
          .withBranchAdded(BranchModel(marks: 1.5));
      expect(grown.branches, hasLength(3));
      expect(grown.marks, 3.5);
      expect(grown.withBranchRemoved(0).branches, hasLength(2));
      expect(QuestionModel(questionNumber: 1).withBranchRemoved(0).branches, hasLength(1));
    });

    test('changing the content type resets options to the type defaults', () {
      final essay = BranchContent.empty();
      final mcq = essay.copyWith(type: QuestionType.multipleChoice);
      expect(mcq.options, hasLength(4));
      expect(mcq.options.first.isCorrect, isTrue);

      final trueFalse = mcq.withTrueFalseAnswer(false);
      expect(trueFalse.type, QuestionType.trueFalse);
      expect(trueFalse.trueFalseAnswer, isFalse);
    });

    test('rejects negative marks and unknown types strictly', () {
      expect(() => BranchModel(marks: -1), throwsArgumentError);
      expect(
        () => BranchContent.fromMap(const <String, dynamic>{'type': 'riddle'}),
        throwsFormatException,
      );
      expect(
        () => BranchModel.fromMap(const <String, dynamic>{
          'content': <String, dynamic>{'type': 'essay'},
          'marks': 'abc',
        }),
        throwsFormatException,
      );
    });
  });

  group('ExamDocument', () {
    test('renumbers questions sequentially after removal', () {
      final document = _twoQuestionDocument().withQuestionAdded();
      expect(document.questions.map((q) => q.questionNumber), <int>[1, 2, 3]);

      final removed = document.withQuestionRemoved(0);
      expect(removed.questions.map((q) => q.questionNumber), <int>[1, 2]);
      expect(removed.questions.first.id, 'q2');
    });

    test('swapBranchContent exchanges content and marks only (golden rule)', () {
      final document = _twoQuestionDocument();
      const from = BranchRef(questionIndex: 0, branchIndex: 0); // السؤال الأول - أ
      const to = BranchRef(questionIndex: 1, branchIndex: 1); // السؤال الثاني - ب

      final swapped = document.swapBranchContent(from, to);

      // الهيكل الرقمي ثابت: السؤال الأول يبقى أولاً والمعرفات لا تتحرك.
      expect(swapped.questions[0].questionNumber, 1);
      expect(swapped.questions[1].questionNumber, 2);
      expect(swapped.questions[0].branches[0].id, 'q1a');
      expect(swapped.questions[1].branches[1].id, 'q2b');

      // المحتوى والدرجة تبدّلا.
      expect(swapped.branchAt(from).content.text, 'الأرض كروية');
      expect(swapped.branchAt(from).content.type, QuestionType.trueFalse);
      expect(swapped.branchAt(from).marks, 1);
      expect(swapped.branchAt(to).content.text, 'أعرب ما تحته خط');
      expect(swapped.branchAt(to).content.type, QuestionType.essay);
      expect(swapped.branchAt(to).marks, 5);

      // المرفقات مثبّتة على الخانة لا على المحتوى.
      expect(swapped.branchAt(to).attachments, hasLength(1));
      expect(swapped.branchAt(from).attachments, isEmpty);

      // بقية الفروع لم تُمس، والمجموع الكلي ثابت.
      expect(swapped.branchAt(const BranchRef(questionIndex: 0, branchIndex: 1)).marks, 3);
      expect(swapped.totalMarks, document.totalMarks);
    });

    test('swapBranchContent ignores identical or invalid references', () {
      final document = _twoQuestionDocument();
      const ref = BranchRef(questionIndex: 0, branchIndex: 0);
      expect(identical(document.swapBranchContent(ref, ref), document), isTrue);
      expect(
        identical(
          document.swapBranchContent(ref, const BranchRef(questionIndex: 5, branchIndex: 0)),
          document,
        ),
        isTrue,
      );
    });

    test('round-trips the full tree (header, questions, branches, attachments)', () {
      final document = _twoQuestionDocument();
      final restored = ExamDocument.fromJson(document.toJson());

      expect(restored.id, document.id);
      expect(restored.header.subject, 'اللغة العربية');
      expect(restored.questions, hasLength(2));
      expect(restored.questions[1].branches[0].content.options, hasLength(2));
      expect(restored.questions[1].branches[1].attachments.single.shape, FloatingShapeType.circle);
      expect(restored.totalMarks, 11);
    });

    test('isolates a corrupt question through FormatException', () {
      final map = _twoQuestionDocument().toMap();
      map['questions'] = <Object?>['ليس خريطة', ...(map['questions'] as List).skip(1)];
      expect(() => ExamDocument.fromMap(map), throwsFormatException);

      final badBranch = _twoQuestionDocument().toMap();
      final question = Map<String, dynamic>.from((badBranch['questions'] as List).first as Map);
      question['branches'] = <Object?>[42];
      badBranch['questions'] = <Object?>[question];
      expect(() => ExamDocument.fromMap(badBranch), throwsFormatException);
    });

  });
}
