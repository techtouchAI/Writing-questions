import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/models/branch_item.dart';
import 'package:writing_questions_app/models/branch_model.dart';
import 'package:writing_questions_app/models/exam_catalog.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_footer_model.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/floating_element.dart';
import 'package:writing_questions_app/models/paper_text_style.dart';
import 'package:writing_questions_app/models/point_kind.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/models/question_option.dart';
import 'package:writing_questions_app/models/subject_layout.dart';

ExamDocument _twoQuestionDocument() {
  return ExamDocument(
    name: 'نموذج',
    header: ExamHeaderModel.initial(subject: 'اللغة العربية'),
    questions: <QuestionModel>[
      QuestionModel(
        id: 'q1',
        questionNumber: 1,
        statement: 'أجب عما يأتي',
        branches: <BranchModel>[
          BranchModel(
            id: 'q1a',
            content: BranchContent(statement: 'أعرب ما تحته خط'),
            marks: 5,
          ),
          BranchModel(
            id: 'q1b',
            content: BranchContent(
              statement: 'أكمل',
              items: <BranchItem>[
                BranchItem(kind: PointKind.fillBlank, text: 'عاصمة العراق ___'),
              ],
            ),
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
              statement: 'اختر الصحيح',
              items: <BranchItem>[
                BranchItem(
                  id: 'mc',
                  kind: PointKind.multipleChoice,
                  text: 'عاصمة العراق',
                  options: <QuestionOption>[
                    QuestionOption(text: 'بغداد'),
                    QuestionOption(text: 'البصرة'),
                  ],
                ),
              ],
            ),
            marks: 2,
          ),
          BranchModel(
            id: 'q2b',
            content: BranchContent(statement: 'الأرض كروية'),
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
    test('initial uses the current academic year and round-trips through JSON', () {
      final header = ExamHeaderModel.initial(
        subject: 'الرياضيات',
        schoolName: 'متوسطة حليف القرآن',
        now: DateTime(2026, 10, 1),
      );

      expect(header.academicYear, '2026/2027');
      expect(header.examType, 'نصف السنة');
      expect(header.session, ExamSession.first);
      expect(header.schoolGender, SchoolGender.boys);
      expect(header.showBismillah, isTrue);
      expect(header.layoutTemplate, SubjectLayoutTemplate.scientific);

      final restored = ExamHeaderModel.fromMap(header.toMap());
      expect(restored.schoolName, 'متوسطة حليف القرآن');
      expect(restored.academicYear, '2026/2027');
      expect(restored.session, ExamSession.first);
      expect(restored.subject, 'الرياضيات');
    });

    test('the academic year starts in September', () {
      expect(AcademicYear.current(DateTime(2026, 8, 31)), '2025/2026');
      expect(AcademicYear.current(DateTime(2026, 9, 1)), '2026/2027');
      expect(
        AcademicYear.suggestions(DateTime(2026, 10, 1)),
        <String>['2025/2026', '2026/2027', '2027/2028'],
      );
    });

    test('changing the subject re-selects the layout template', () {
      final header = ExamHeaderModel.initial(subject: 'اللغة العربية');
      expect(header.layoutTemplate, SubjectLayoutTemplate.arabic);

      final english = header.copyWith(subject: 'اللغة الإنجليزية');
      expect(english.layoutTemplate, SubjectLayoutTemplate.english);
      expect(english.layoutTemplate.isLtr, isTrue);
    });

    test('every field is optional: a blank subject is allowed and fromMap is tolerant', () {
      final blank = ExamHeaderModel.fromMap(const <String, dynamic>{});
      expect(blank.subject, isEmpty);
      expect(blank.layoutTemplate, SubjectLayoutTemplate.generic);
      expect(blank.session, ExamSession.first);
      expect(blank.schoolGender, SchoolGender.boys);
      expect(blank.showBismillah, isTrue);

      final partial = ExamHeaderModel.fromMap(const <String, dynamic>{
        'schoolName': 'مدرسة',
        'showBismillah': false,
        'session': 'third',
        'schoolGender': 'none',
        'unknownKey': 1,
      });
      expect(partial.schoolName, 'مدرسة');
      expect(partial.showBismillah, isFalse);
      expect(partial.session, ExamSession.third);
      expect(partial.schoolGender, SchoolGender.none);
    });

    test('catalog labels are the verbatim printed texts', () {
      expect(ExamCatalog.administrationLabel, 'ادارة');
      expect(ExamCatalog.examTitlePrefix, 'اسئلة امتحان');
      expect(ExamCatalog.academicYearPrefix, 'للعام الدراسي');
      expect(ExamCatalog.bismillah, 'بسم الله الرحمن الرحيم');
      expect(
        ExamSession.values.map((session) => session.label),
        <String>['', 'الدور الأول', 'الدور الثاني', 'الدور الثالث'],
      );
      expect(SchoolGender.boys.label, 'للبنين');
      expect(
        SignatureTitle.values.map((title) => title.label),
        <String>['مدرس المادة', 'معلم المادة', 'مدرسة المادة', 'معلمة المادة'],
      );
      expect(ExamCatalog.closingPhrases, hasLength(10));
      expect(ExamCatalog.closingPhrases.toSet(), hasLength(10));
    });
  });

  group('ExamFooterModel', () {
    test('has a default phrase and a single primary signature', () {
      const footer = ExamFooterModel();
      expect(footer.closingPhrase, ExamCatalog.defaultClosingPhrase);
      expect(footer.primary.title, SignatureTitle.lecturer);
      expect(footer.hasSecondary, isFalse);
    });

    test('the second signature exists only when explicitly added', () {
      const footer = ExamFooterModel(
        primary: SignatureModel(title: SignatureTitle.educatorFemale, name: 'سارة'),
      );
      final added = footer.withSecondaryAdded();

      expect(added.hasSecondary, isTrue);
      // التوقيع الثاني مطابق للأول في اللقب ويبدأ بلا اسم.
      expect(added.secondary!.title, SignatureTitle.educatorFemale);
      expect(added.secondary!.name, isEmpty);
      expect(identical(added.withSecondaryAdded(), added), isTrue);
      expect(added.withSecondaryRemoved().hasSecondary, isFalse);
    });

    test('round-trips through JSON and tolerates a missing or corrupt value', () {
      const footer = ExamFooterModel(
        closingPhrase: 'انتهت الأسئلة',
        primary: SignatureModel(name: 'أحمد'),
        secondary: SignatureModel(title: SignatureTitle.educator, name: 'علي'),
      );
      final restored = ExamFooterModel.fromValue(footer.toMap());

      expect(restored, footer);
      expect(restored.secondary!.name, 'علي');
      expect(ExamFooterModel.fromValue(null), const ExamFooterModel());
      expect(ExamFooterModel.fromValue('تالف'), const ExamFooterModel());
      expect(
        ExamFooterModel.fromValue(const <String, dynamic>{'closingPhrase': ''})
            .closingPhrase,
        isEmpty,
      );
    });
  });

  group('QuestionModel / BranchModel', () {
    test('a question starts branchless and rolls up marks', () {
      final question = QuestionModel(questionNumber: 1);
      expect(question.branches, isEmpty);
      expect(question.marks, 0);

      final grown = question
          .withBranchAdded(BranchModel(marks: 2))
          .withBranchAdded(BranchModel(marks: 1.5));
      expect(grown.branches, hasLength(2));
      expect(grown.marks, 3.5);
      expect(grown.withBranchRemoved(0).branches, hasLength(1));
      // حذف الفرع الأخير مسموح: يبقى السؤال بلا فروع.
      expect(grown.withBranchRemoved(0).withBranchRemoved(0).branches, isEmpty);
    });

    test('question title color is stored separately and reads legacy style colors', () {
      const color = 0xFF1E3A8A;
      final question = QuestionModel(
        questionNumber: 1,
        titleColor: color,
      );
      final restored = QuestionModel.fromMap(question.toMap());

      expect(restored.titleColor, color);
      expect(restored.effectiveTitleColor, color);
      expect(restored.style.color, isNull);

      final legacy = QuestionModel.fromMap(const <String, dynamic>{
        'questionNumber': 1,
        'branches': <Object?>[],
        'style': <String, dynamic>{'color': '#B91C1C'},
      });
      expect(legacy.titleColor, isNull);
      expect(legacy.effectiveTitleColor, 0xFFB91C1C);
      expect(legacy.copyWith(titleColor: () => null).effectiveTitleColor, 0xFFB91C1C);
      expect(
        const PaperTextStyle(color: 0xFFB91C1C)
            .copyWith(color: () => null)
            .color,
        isNull,
      );
    });

    test('question exportability includes intended attachments and excludes blanks', () {
      final empty = QuestionModel(questionNumber: 1);
      expect(empty.hasExportableContent(), isFalse);

      final attachedOnly = QuestionModel(
        questionNumber: 2,
        branches: <BranchModel>[
          BranchModel(
            content: BranchContent.empty(),
            attachments: <FloatingElement>[
              FloatingElement(
                type: FloatingElementType.shape,
                shape: FloatingShapeType.circle,
                dx: 0,
                dy: 0,
                width: 20,
                height: 20,
              ),
            ],
          ),
        ],
      );
      expect(attachedOnly.hasExportableContent(), isTrue);

      final globalMirror = QuestionModel(
        questionNumber: 3,
        branches: <BranchModel>[
          BranchModel(
            content: BranchContent.empty(),
            attachments: <FloatingElement>[
              FloatingElement(
                id: 'global-mirror',
                type: FloatingElementType.shape,
                shape: FloatingShapeType.circle,
                dx: 0,
                dy: 0,
                width: 20,
                height: 20,
              ),
            ],
          ),
        ],
      );
      expect(globalMirror.hasExportableContent(), isTrue);
      expect(
        globalMirror.hasExportableContent(
          ignoredAttachmentIds: const <String>{'global-mirror'},
        ),
        isFalse,
      );
    });

    test('shows custom item and option labels literally (no renumbering)', () {
      final document = _twoQuestionDocument();
      final point = document.questions[1].branches[0].content.items.single;
      final option = point.options[0];
      expect(document.displayOptionLabel(option, 0), '( أ )');

      final customOption = option.copyWith(labelOverride: () => 'A.');
      expect(document.displayOptionLabel(customOption, 0), 'A.');
      final hiddenOption = option.copyWith(labelOverride: () => '');
      expect(document.displayOptionLabel(hiddenOption, 0), '');

      final item = BranchItem(text: 'عبارة');
      expect(document.displayItemLabel(item, 2), document.autoItemLabel(2));
      expect(
        document.displayItemLabel(item.copyWith(labelOverride: () => 'ثالثاً:'), 2),
        'ثالثاً:',
      );
    });

    test('detects branches with no exportable content', () {
      expect(BranchContent(statement: '  ').hasExportableContent, isFalse);
      expect(BranchContent(statement: 'منطوق').hasExportableContent, isTrue);
      expect(BranchContent(body: 'نص').hasExportableContent, isTrue);
      // فرع فارغ تماماً لا يُظهر شيئاً.
      expect(BranchContent.empty().hasExportableContent, isFalse);
      // نقطة صح/خطأ بلا نص لا تُظهر شيئاً.
      final blankTrueFalse = BranchContent(
        items: <BranchItem>[BranchItem(kind: PointKind.trueFalse)],
      );
      expect(blankTrueFalse.hasExportableContent, isFalse);
      // العبارة المكتوبة وحدها هي ما يُطبع.
      final trueFalseWithText = BranchContent(
        items: <BranchItem>[BranchItem(kind: PointKind.trueFalse, text: 'الأرض كروية')],
      );
      expect(trueFalseWithText.hasExportableContent, isTrue);
      // خيار مكتوب في نقطة اختيار من متعدد يكفي لإظهارها.
      final choicesOnly = BranchContent(
        items: <BranchItem>[
          BranchItem(
            kind: PointKind.multipleChoice,
            options: <QuestionOption>[QuestionOption(text: 'بغداد')],
          ),
        ],
      );
      expect(choicesOnly.hasExportableContent, isTrue);
      // الخيارات لا تُطبع لغير نوع «اختيار من متعدد».
      final hiddenChoices = BranchContent(
        items: <BranchItem>[
          BranchItem(options: <QuestionOption>[QuestionOption(text: 'لا يظهر')]),
        ],
      );
      expect(hiddenChoices.items.single.hasVisibleOptions, isFalse);
    });

    test('a multiple-choice point starts with four blank options; other kinds none', () {
      final plain = BranchItem(text: 'نص');
      expect(plain.options, isEmpty);

      final mcq = plain.copyWith(kind: PointKind.multipleChoice);
      expect(mcq.options, hasLength(BranchItem.defaultOptionCount));
      // لا تمييز لخيار صحيح: الخيارات نصّية فقط.
      expect(mcq.options.map((option) => option.text), everyElement(isEmpty));
      expect(mcq.isEmpty, isFalse); // النص موجود
      expect(BranchItem(kind: PointKind.multipleChoice).isEmpty, isTrue);

      final trueFalse = BranchItem(kind: PointKind.trueFalse, text: 'عبارة');
      expect(trueFalse.options, isEmpty);
    });

    test('kinds mix freely in one group and survive a JSON round trip', () {
      final content = BranchContent(
        statement: 'ضع علامة',
        items: <BranchItem>[
          BranchItem(kind: PointKind.trueFalse, text: 'الأرض كروية'),
          BranchItem(kind: PointKind.fillBlank, text: 'عاصمة العراق ____'),
          BranchItem(
            kind: PointKind.multipleChoice,
            text: 'أكبر محافظة',
            options: <QuestionOption>[
              QuestionOption(text: 'نينوى'),
              QuestionOption(text: 'الأنبار'),
            ],
          ),
          BranchItem(text: 'عرّف الفقه'),
        ],
      );
      final restored = BranchContent.fromMap(content.toMap());

      expect(
        restored.items.map((item) => item.kind),
        <PointKind>[
          PointKind.trueFalse,
          PointKind.fillBlank,
          PointKind.multipleChoice,
          PointKind.plain,
        ],
      );
      expect(restored.items[2].options.map((option) => option.text), <String>['نينوى', 'الأنبار']);
      // النقطة النصية الحرة لا تحمل مفتاح نوع ولا خيارات في JSON.
      expect(content.items[3].toMap().containsKey('kind'), isFalse);
      expect(content.items[3].toMap().containsKey('options'), isFalse);
    });

    test('rejects negative marks strictly and tolerates corrupt points', () {
      expect(() => BranchModel(marks: -1), throwsArgumentError);
      expect(
        () => BranchModel.fromMap(const <String, dynamic>{
          'content': <String, dynamic>{'statement': 'س'},
          'marks': 'abc',
        }),
        throwsFormatException,
      );
      final tolerant = BranchContent.fromMap(const <String, dynamic>{
        'statement': 'س',
        'items': <Object?>[
          'ليست خريطة',
          <String, dynamic>{'text': 'سليمة', 'kind': 'unknown-kind', 'marks': -3},
        ],
      });
      expect(tolerant.items, hasLength(1));
      expect(tolerant.items.single.kind, PointKind.plain);
      expect(tolerant.items.single.marks, 0);
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
      expect(swapped.branchAt(from).content.statement, 'الأرض كروية');
      expect(swapped.branchAt(from).marks, 1);
      expect(swapped.branchAt(to).content.statement, 'أعرب ما تحته خط');
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

    test('question duplication preserves the custom spacing after a question', () {
      final document = ExamDocument(
        name: 'مسافات مخصصة',
        header: ExamHeaderModel.initial(),
        questions: <QuestionModel>[
          QuestionModel(questionNumber: 1, spacingAfter: 37.5),
        ],
      );

      expect(document.withQuestionDuplicated(0).questions[1].spacingAfter, 37.5);
      expect(document.duplicated().questions.single.spacingAfter, 37.5);
    });

    test('round-trips document-level floating elements and their page index', () {
      final element = FloatingElement(
        id: 'document-free-element',
        type: FloatingElementType.shape,
        shape: FloatingShapeType.circle,
        dx: 24,
        dy: 48,
        pageIndex: 3,
        width: 72,
        height: 72,
      );
      final document = ExamDocument(
        name: 'ورقة بلا أسئلة',
        header: ExamHeaderModel.initial(),
        floatingElements: <FloatingElement>[element],
      );

      final restored = ExamDocument.fromJson(document.toJson());

      expect(restored.questions, isEmpty);
      expect(restored.floatingElements.single.id, element.id);
      expect(restored.floatingElements.single.pageIndex, 3);
      expect(restored.floatingElements.single.dx, 24);
    });

    test('resolves floating elements by stable id in legacy owner attachments', () {
      final global = FloatingElement(
        id: 'global-float',
        type: FloatingElementType.shape,
        shape: FloatingShapeType.circle,
        dx: 0,
        dy: 0,
        width: 10,
        height: 10,
      );
      final questionFloat = FloatingElement(
        id: 'question-float',
        type: FloatingElementType.shape,
        shape: FloatingShapeType.square,
        dx: 0,
        dy: 0,
        width: 10,
        height: 10,
      );
      final branchFloat = FloatingElement(
        id: 'branch-float',
        type: FloatingElementType.shape,
        shape: FloatingShapeType.triangle,
        dx: 0,
        dy: 0,
        width: 10,
        height: 10,
      );
      final document = ExamDocument(
        name: 'مرفقات قديمة',
        header: ExamHeaderModel.initial(),
        floatingElements: <FloatingElement>[global],
        questions: <QuestionModel>[
          QuestionModel(
            id: 'q-floats',
            questionNumber: 1,
            attachments: <FloatingElement>[questionFloat],
            branches: <BranchModel>[
              BranchModel(
                id: 'b-floats',
                attachments: <FloatingElement>[branchFloat],
              ),
            ],
          ),
        ],
      );

      expect(document.floatingElementById(global.id), same(global));
      expect(document.floatingElementById(questionFloat.id), same(questionFloat));
      expect(document.floatingElementById(branchFloat.id), same(branchFloat));
      expect(document.floatingElementById('missing-float'), isNull);
    });

    test('deleting an owner does not delete a document-level floating element', () {
      final element = FloatingElement(
        id: 'survives-question-removal',
        type: FloatingElementType.shape,
        shape: FloatingShapeType.circle,
        dx: 30,
        dy: 40,
        width: 20,
        height: 20,
      );
      final document = ExamDocument(
        name: 'عنصر حر',
        header: ExamHeaderModel.initial(),
        questions: <QuestionModel>[
          QuestionModel(
            questionNumber: 1,
            attachments: <FloatingElement>[element],
          ),
        ],
        floatingElements: <FloatingElement>[element],
      );

      final removed = document.withQuestionRemoved(0);
      expect(removed.questions, isEmpty);
      expect(removed.floatingElements.single.id, element.id);
    });

    test('document duplication copies each free element once and keeps legacy mirrors linked', () {
      final element = FloatingElement(
        id: 'free-circle',
        type: FloatingElementType.shape,
        shape: FloatingShapeType.circle,
        dx: 42,
        dy: 180,
        pageIndex: 2,
        width: 60,
        height: 60,
      );
      final document = ExamDocument(
        name: 'أصل',
        header: ExamHeaderModel.initial(),
        questions: <QuestionModel>[
          QuestionModel(
            questionNumber: 1,
            attachments: <FloatingElement>[element],
          ),
        ],
        floatingElements: <FloatingElement>[element],
      );

      final duplicate = document.duplicated();
      final rootCopy = duplicate.floatingElements.single;
      final mirrorCopy = duplicate.questions.single.attachments.single;

      expect(rootCopy.id, isNot(element.id));
      expect(mirrorCopy.id, rootCopy.id);
      expect(identical(rootCopy, mirrorCopy), isTrue);
      expect(rootCopy.pageIndex, 2);
    });

    test('duplicating an owner does not clone a document-level floating element', () {
      final element = FloatingElement(
        id: 'shared-element',
        type: FloatingElementType.shape,
        shape: FloatingShapeType.square,
        dx: 12,
        dy: 24,
        width: 40,
        height: 40,
      );
      final document = ExamDocument(
        name: 'مستند',
        header: ExamHeaderModel.initial(),
        floatingElements: <FloatingElement>[element],
        questions: <QuestionModel>[
          QuestionModel(
            questionNumber: 1,
            attachments: <FloatingElement>[element],
            branches: <BranchModel>[
              BranchModel(
                content: BranchContent.empty(),
                attachments: <FloatingElement>[element],
              ),
            ],
          ),
        ],
      );

      final duplicatedQuestion = document.withQuestionDuplicated(0);
      expect(duplicatedQuestion.floatingElements, hasLength(1));
      expect(duplicatedQuestion.questions[1].attachments, isEmpty);
      expect(duplicatedQuestion.questions[1].branches.single.attachments, isEmpty);

      final duplicatedBranch = document.withBranchDuplicated(
        const BranchRef(questionIndex: 0, branchIndex: 0),
      );
      expect(duplicatedBranch.floatingElements, hasLength(1));
      expect(duplicatedBranch.questions.single.branches[1].attachments, isEmpty);
    });

    test('round-trips the full tree (header, questions, branches, attachments)', () {
      final document = _twoQuestionDocument();
      final restored = ExamDocument.fromJson(document.toJson());

      expect(restored.id, document.id);
      expect(restored.header.subject, 'اللغة العربية');
      expect(restored.questions, hasLength(2));
      expect(restored.questions[1].branches[0].content.items.single.options, hasLength(2));
      expect(restored.footer, document.footer);
      expect(restored.header.academicYear, document.header.academicYear);
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


    test('showsInExport: النص أو الدرجة أو التسمية تُظهر النقطة، والفارغة لا', () {
      final withText = BranchItem(id: 'a', text: '١');
      final emptyItem = BranchItem(id: 'c');
      final withMarks = BranchItem(id: 'd', marks: 1);
      final labeledOnly = BranchItem(id: 'e', labelOverride: 'أ-');

      // النص يكفي لعرض النقطة (في المعاينة وPDF وWord على السواء).
      expect(withText.showsInExport, isTrue);
      // الفارغة تماماً تُحجب.
      expect(emptyItem.showsInExport, isFalse);
      // الدرجة والتسمية المخصصة محتوى مقصود.
      expect(withMarks.showsInExport, isTrue);
      expect(labeledOnly.showsInExport, isTrue);
    });

  });
}
