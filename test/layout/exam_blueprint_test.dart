import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/layout/blueprint/exam_blueprint.dart';
import 'package:writing_questions_app/models/branch_item.dart';
import 'package:writing_questions_app/models/branch_model.dart';
import 'package:writing_questions_app/models/exam_catalog.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_footer_model.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/paper_settings.dart';
import 'package:writing_questions_app/models/point_kind.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/models/question_option.dart';

ExamDocument _document({
  ExamHeaderModel? header,
  ExamFooterModel? footer,
  PaperSettings? settings,
  List<QuestionModel>? questions,
}) {
  return ExamDocument(
    name: 'ورقة',
    header: header ?? ExamHeaderModel.initial(now: DateTime(2026, 10, 1)),
    footer: footer,
    settings: settings,
    questions: questions ?? <QuestionModel>[QuestionModel(questionNumber: 1, statement: 'س')],
  );
}

ExamBlueprint _blueprint(ExamDocument document) => ExamBlueprint.from(document);

void main() {
  group('header blueprint', () {
    test('prints the three columns exactly as specified', () {
      final header = ExamHeaderModel(
        schoolName: 'متوسطة حليف القرآن',
        examType: 'نصف السنة',
        academicYear: '2026/2027',
        subject: 'الرياضيات',
        grade: 'الثالث المتوسط',
        time: 'ساعتان',
      );
      final data = _blueprint(_document(header: header)).header;

      expect(data.rightLines, <String>['ادارة', 'متوسطة حليف القرآن', 'للبنين']);
      expect(data.centerLines, <String>[
        'اسئلة امتحان نصف السنة',
        'للعام الدراسي ٢٠٢٦/٢٠٢٧',
        'الدور الأول',
      ]);
      expect(data.leftLines, <String>[
        'المادة: الرياضيات',
        'الصف: الثالث المتوسط',
        'الوقت: ساعتان',
        'اسم الطالب: ....................',
      ]);
      expect(data.showBismillah, isTrue);
      expect(data.bismillah, 'بسم الله الرحمن الرحيم');
    });

    test('the exam session sits directly under the academic year', () {
      final data = _blueprint(
        _document(
          header: ExamHeaderModel(
            academicYear: '2026/2027',
            session: ExamSession.second,
          ),
        ),
      ).header;
      final yearIndex = data.centerLines.indexWhere((line) => line.startsWith('للعام الدراسي'));
      expect(yearIndex, 1);
      expect(data.centerLines[yearIndex + 1], 'الدور الثاني');
    });

    test('blank subject, grade and time print their label with a dotted line', () {
      final data = _blueprint(_document(header: ExamHeaderModel())).header;
      expect(data.leftLines[0], 'المادة: ${ExamCatalog.blankLine}');
      expect(data.leftLines[1], 'الصف: ${ExamCatalog.blankLine}');
      expect(data.leftLines[2], 'الوقت: ${ExamCatalog.blankLine}');
      expect(data.leftLines[3], 'اسم الطالب: ${ExamCatalog.blankLine}');
      expect(ExamCatalog.blankLine, '....................');
    });

    test('a student name is always dotted, whatever the other fields hold', () {
      final data = _blueprint(
        _document(header: ExamHeaderModel(subject: 'اللغة العربية', grade: 'x', time: 'y')),
      ).header;
      expect(data.leftLines.last, 'اسم الطالب: ....................');
    });

    test('optional lines disappear: no school name, no gender, no session', () {
      final data = _blueprint(
        _document(
          header: ExamHeaderModel(
            schoolGender: SchoolGender.none,
            session: ExamSession.none,
            showBismillah: false,
          ),
        ),
      ).header;
      expect(data.rightLines, <String>['ادارة']);
      expect(data.centerLines, <String>['اسئلة امتحان', 'للعام الدراسي']);
      expect(data.showBismillah, isFalse);
    });

    test('girls and the third session are printed verbatim', () {
      final data = _blueprint(
        _document(
          header: ExamHeaderModel(
            schoolName: 'ثانوية الزهراء',
            schoolGender: SchoolGender.girls,
            session: ExamSession.third,
          ),
        ),
      ).header;
      expect(data.rightLines, <String>['ادارة', 'ثانوية الزهراء', 'للبنات']);
      expect(data.centerLines.last, 'الدور الثالث');
    });

    test('digits follow the paper numerals setting whatever the teacher typed', () {
      final header = ExamHeaderModel(academicYear: '٢٠٢٦/٢٠٢٧', time: '90 دقيقة');
      final indic = _blueprint(_document(header: header)).header;
      expect(indic.centerLines[1], 'للعام الدراسي ٢٠٢٦/٢٠٢٧');
      expect(indic.leftLines[2], 'الوقت: ٩٠ دقيقة');

      final latin = _blueprint(
        _document(
          header: header,
          settings: const PaperSettings(numerals: PaperNumerals.latin),
        ),
      ).header;
      expect(latin.centerLines[1], 'للعام الدراسي 2026/2027');
      expect(latin.leftLines[2], 'الوقت: 90 دقيقة');
    });

    test('the header box follows the existing header-border setting', () {
      expect(_blueprint(_document()).header.framed, isTrue);
      expect(
        _blueprint(_document(settings: const PaperSettings(headerBorder: false))).header.framed,
        isFalse,
      );
    });
  });

  group('footer blueprint', () {
    test('has a closing phrase and a single primary signature by default', () {
      final footer = _blueprint(_document()).footer;
      expect(footer.closingPhrase, ExamCatalog.defaultClosingPhrase);
      expect(footer.primary.title, 'مدرس المادة');
      expect(footer.primary.nameLine, ExamCatalog.blankLine);
      expect(footer.secondary, isNull);
    });

    test('shows the typed name and the second teacher only when added', () {
      final footer = _blueprint(
        _document(
          footer: const ExamFooterModel(
            closingPhrase: 'انتهت الأسئلة',
            primary: SignatureModel(title: SignatureTitle.educatorFemale, name: ' سارة علي '),
            secondary: SignatureModel(title: SignatureTitle.lecturer, name: 'أحمد'),
          ),
        ),
      ).footer;
      expect(footer.closingPhrase, 'انتهت الأسئلة');
      expect(footer.primary.title, 'معلمة المادة');
      expect(footer.primary.nameLine, 'سارة علي');
      expect(footer.secondary!.title, 'مدرس المادة');
      expect(footer.secondary!.nameLine, 'أحمد');
    });

    test('a blank closing phrase hides the line', () {
      final footer = _blueprint(
        _document(footer: const ExamFooterModel(closingPhrase: '  ')),
      ).footer;
      expect(footer.closingPhrase, isNull);
    });
  });

  group('question blueprint', () {
    test('auto numbers follow the label style and end with a slash', () {
      final ordinal = _blueprint(
        _document(
          questions: <QuestionModel>[
            QuestionModel(questionNumber: 1),
            QuestionModel(questionNumber: 2),
          ],
        ),
      );
      expect(ordinal.questions[0].title.number, 'السؤال الأول/');
      expect(ordinal.questions[1].title.number, 'السؤال الثاني/');

      final compact = _blueprint(
        _document(
          settings: const PaperSettings(questionLabelStyle: QuestionLabelStyle.compact),
          questions: <QuestionModel>[QuestionModel(questionNumber: 1)],
        ),
      );
      expect(compact.questions.single.title.number, 'س١/');
    });

    test('the number typed by the teacher is printed verbatim', () {
      final data = _blueprint(
        _document(
          questions: <QuestionModel>[
            QuestionModel(questionNumber: 1, numberOverride: 'س١/'),
            QuestionModel(questionNumber: 2, numberOverride: 'السؤال الاول/'),
            QuestionModel(questionNumber: 3, numberOverride: 'أولاً'),
          ],
        ),
      );
      expect(data.questions.map((question) => question.title.number), <String>[
        'س١/',
        'السؤال الاول/',
        'أولاً',
      ]);
    });

    test('marks: a raw number prints as (٢٠ درجة) on the title line', () {
      final data = _blueprint(
        _document(
          questions: <QuestionModel>[
            QuestionModel(
              questionNumber: 1,
              statement: 'اختر الإجابة الصحيحة',
              marksOverride: 20,
            ),
          ],
        ),
      ).questions.single;
      expect(data.title.marks, '(٢٠ درجة)');
      expect(data.title.statement, 'اختر الإجابة الصحيحة');
      expect(data.title.line, 'السؤال الأول/ اختر الإجابة الصحيحة (٢٠ درجة)');
    });

    test('marks follow the show-question-marks setting and hide zero', () {
      final hidden = _blueprint(
        _document(
          settings: const PaperSettings(showQuestionMarks: false),
          questions: <QuestionModel>[QuestionModel(questionNumber: 1, marksOverride: 20)],
        ),
      );
      expect(hidden.questions.single.title.marks, isNull);

      final zero = _blueprint(
        _document(questions: <QuestionModel>[QuestionModel(questionNumber: 1)]),
      );
      expect(zero.questions.single.title.marks, isNull);
    });

    test('marks default to the sum of branch and point marks', () {
      final data = _blueprint(
        _document(
          questions: <QuestionModel>[
            QuestionModel(
              questionNumber: 1,
              items: <BranchItem>[BranchItem(text: 'ن', marks: 2)],
              branches: <BranchModel>[BranchModel(marks: 3), BranchModel(marks: 5)],
            ),
          ],
        ),
      ).questions.single;
      expect(data.title.marks, '(١٠ درجة)');
    });

    test('marks respect the Latin numerals setting and LTR papers', () {
      final latin = _blueprint(
        _document(
          settings: const PaperSettings(numerals: PaperNumerals.latin),
          questions: <QuestionModel>[QuestionModel(questionNumber: 1, marksOverride: 20)],
        ),
      );
      expect(latin.questions.single.title.marks, '(20 درجة)');

      final english = _blueprint(
        _document(
          header: ExamHeaderModel(subject: 'اللغة الإنجليزية'),
          questions: <QuestionModel>[QuestionModel(questionNumber: 1, marksOverride: 5)],
        ),
      );
      expect(english.questions.single.title.number, 'Q1.');
      expect(english.questions.single.title.marks, '(5 marks)');
    });

    test('a blank question text is removed entirely', () {
      final data = _blueprint(
        _document(
          questions: <QuestionModel>[
            QuestionModel(questionNumber: 1, statement: 'س', body: '   \n '),
            QuestionModel(questionNumber: 2, statement: 'س', body: ' نص السؤال '),
          ],
        ),
      );
      expect(data.questions[0].body, isNull);
      expect(data.questions[1].body, 'نص السؤال');
    });

    test('the section heading is optional', () {
      final data = _blueprint(
        _document(
          questions: <QuestionModel>[
            QuestionModel(questionNumber: 1, category: ' القواعد '),
            QuestionModel(questionNumber: 2),
          ],
        ),
      );
      expect(data.questions[0].section, 'القواعد');
      expect(data.questions[1].section, isNull);
    });

    test('printable follows the existing exportability rule', () {
      final data = _blueprint(
        _document(
          questions: <QuestionModel>[
            QuestionModel(questionNumber: 1),
            QuestionModel(questionNumber: 2, statement: 'س'),
            QuestionModel(questionNumber: 3, body: 'نص'),
          ],
        ),
      );
      expect(data.questions.map((question) => question.isPrintable()), <bool>[false, true, true]);
    });
  });

  group('points blueprint', () {
    PointBlueprint pointAt(ExamDocument document, int index) =>
        _blueprint(document).questions.single.points[index];

    ExamDocument withPoints(List<BranchItem> items, {PaperSettings? settings}) => _document(
          settings: settings,
          questions: <QuestionModel>[QuestionModel(questionNumber: 1, items: items)],
        );

    test('numbering is one continuous sequence whatever the kinds', () {
      final document = withPoints(<BranchItem>[
        BranchItem(kind: PointKind.trueFalse, text: 'عبارة'),
        BranchItem(kind: PointKind.fillBlank, text: 'جملة'),
        BranchItem(kind: PointKind.multipleChoice, text: 'سؤال'),
        BranchItem(text: 'حر'),
      ]);
      final labels = _blueprint(document).questions.single.points.map((point) => point.label);
      expect(labels, <String>['١-', '٢-', '٣-', '٤-']);

      final latin = withPoints(
        <BranchItem>[BranchItem(text: 'أ'), BranchItem(text: 'ب')],
        settings: const PaperSettings(numerals: PaperNumerals.latin),
      );
      expect(
        _blueprint(latin).questions.single.points.map((point) => point.label),
        <String>['1-', '2-'],
      );
    });

    test('a custom label is literal and an empty one hides the number', () {
      final document = withPoints(<BranchItem>[
        BranchItem(text: 'أ', labelOverride: 'أ)'),
        BranchItem(text: 'ب', labelOverride: ''),
        BranchItem(text: 'ج'),
      ]);
      final points = _blueprint(document).questions.single.points;
      expect(points[0].line, 'أ) أ');
      expect(points[1].line, 'ب');
      // الترقيم التلقائي يستمر بالفهرس: النقطة الثالثة تبقى «٣-».
      expect(points[2].label, '٣-');
    });

    test('true/false statements get empty answer brackets', () {
      final point = pointAt(
        withPoints(<BranchItem>[BranchItem(kind: PointKind.trueFalse, text: 'الأرض كروية')]),
        0,
      );
      expect(point.trailer, ExamCatalog.trueFalseSlot);
      expect(point.line, '١- الأرض كروية ${ExamCatalog.trueFalseSlot}');
    });

    test('fill-in sentences get a dotted blank unless the teacher wrote one', () {
      final auto = pointAt(
        withPoints(<BranchItem>[BranchItem(kind: PointKind.fillBlank, text: 'عاصمة العراق هي')]),
        0,
      );
      expect(auto.trailer, ExamCatalog.fillBlank);
      expect(auto.line, '١- عاصمة العراق هي ${ExamCatalog.fillBlank}');

      for (final typed in <String>['عاصمة العراق ___', 'عاصمة ...... العراق', 'عاصمة … العراق']) {
        final point = pointAt(
          withPoints(<BranchItem>[BranchItem(kind: PointKind.fillBlank, text: typed)]),
          0,
        );
        expect(point.trailer, isNull, reason: typed);
        expect(point.line, '١- $typed');
      }
    });

    test('plain and multiple-choice stems carry no trailer', () {
      final document = withPoints(<BranchItem>[
        BranchItem(text: 'حر'),
        BranchItem(kind: PointKind.multipleChoice, text: 'سؤال'),
      ]);
      final points = _blueprint(document).questions.single.points;
      expect(points[0].trailer, isNull);
      expect(points[1].trailer, isNull);
    });

    test('multiple choice lists only written options with their original labels', () {
      final point = pointAt(
        withPoints(<BranchItem>[
          BranchItem(
            kind: PointKind.multipleChoice,
            text: 'عاصمة العراق',
            options: <QuestionOption>[
              QuestionOption(text: 'بغداد'),
              QuestionOption(text: ''),
              QuestionOption(text: 'أربيل'),
              QuestionOption(text: 'الموصل', labelOverride: 'د.'),
            ],
          ),
        ]),
        0,
      );
      expect(point.line, '١- عاصمة العراق');
      expect(point.options.map((option) => option.line), <String>[
        '( أ ) بغداد',
        '( ج ) أربيل',
        'د. الموصل',
      ]);
      expect(
        point.optionsLine,
        '( أ ) بغداد\u00A0\u00A0\u00A0\u00A0\u00A0( ج ) أربيل\u00A0\u00A0\u00A0\u00A0\u00A0د. الموصل',
      );
    });

    test('options of non multiple-choice points are never printed', () {
      final point = pointAt(
        withPoints(<BranchItem>[
          BranchItem(text: 'نص', options: <QuestionOption>[QuestionOption(text: 'خيار')]),
        ]),
        0,
      );
      expect(point.options, isEmpty);
      expect(point.optionsLine, isEmpty);
    });

    test('point marks print as (n درجة) and obey the marks setting', () {
      final shown = pointAt(withPoints(<BranchItem>[BranchItem(text: 'نص', marks: 2)]), 0);
      expect(shown.marks, '(٢ درجة)');
      expect(shown.line, '١- نص (٢ درجة)');

      final hidden = pointAt(
        withPoints(
          <BranchItem>[BranchItem(text: 'نص', marks: 2)],
          settings: const PaperSettings(showQuestionMarks: false),
        ),
        0,
      );
      expect(hidden.marks, isNull);
    });

    test('empty points are not printable', () {
      final points = _blueprint(
        withPoints(<BranchItem>[BranchItem(), BranchItem(text: 'ن')]),
      ).questions.single.points;
      expect(points.map((point) => point.isPrintable), <bool>[false, true]);
    });
  });

  group('branch blueprint', () {
    test('has the same structure as a question: number, statement, marks, text, points', () {
      final data = _blueprint(
        _document(
          questions: <QuestionModel>[
            QuestionModel(
              questionNumber: 1,
              branches: <BranchModel>[
                BranchModel(
                  marks: 5,
                  content: BranchContent(
                    statement: 'عرّف الفاعل',
                    body: ' نص الفرع ',
                    items: <BranchItem>[BranchItem(text: 'مثال')],
                  ),
                ),
                BranchModel(),
              ],
            ),
          ],
        ),
      ).questions.single;

      final first = data.branches[0];
      expect(first.title.number, 'أ)');
      expect(first.title.statement, 'عرّف الفاعل');
      expect(first.title.marks, '(٥ درجة)');
      expect(first.title.line, 'أ) عرّف الفاعل (٥ درجة)');
      expect(first.body, 'نص الفرع');
      expect(first.points.single.line, '١- مثال');
      expect(first.isPrintable(), isTrue);

      expect(data.branches[1].title.number, 'ب)');
      expect(data.branches[1].body, isNull);
      expect(data.branches[1].isPrintable(), isFalse);
    });

    test('a custom branch number replaces the letter and keeps the bracket', () {
      final data = _blueprint(
        _document(
          questions: <QuestionModel>[
            QuestionModel(
              questionNumber: 1,
              branches: <BranchModel>[BranchModel(labelOverride: 'أولاً')],
            ),
          ],
        ),
      ).questions.single;
      expect(data.branches.single.title.number, 'أولاً)');
    });
  });

  group('forbidden texts', () {
    test('the catalog never contains the banned phrase or page-number wording', () {
      final texts = <String>[
        ExamCatalog.bismillah,
        ExamCatalog.administrationLabel,
        ExamCatalog.examTitlePrefix,
        ExamCatalog.academicYearPrefix,
        ExamCatalog.subjectLabel,
        ExamCatalog.gradeLabel,
        ExamCatalog.timeLabel,
        ExamCatalog.studentNameLabel,
        ...ExamCatalog.closingPhrases,
        ...ExamCatalog.examTypeSuggestions,
        ...ExamCatalog.timeSuggestions,
        ...SchoolGender.values.map((value) => value.menuLabel),
        ...ExamSession.values.map((value) => value.menuLabel),
        ...SignatureTitle.values.map((value) => value.label),
        ...QuestionLabelStyle.values.map((value) => value.arabicLabel),
      ];
      for (final text in texts) {
        expect(text.contains('وزار'), isFalse, reason: text);
        expect(text.contains('صفحة'), isFalse, reason: text);
      }
    });

    test('a full blueprint prints no page-number text anywhere', () {
      final data = _blueprint(_document());
      final printed = <String>[
        ...data.header.rightLines,
        ...data.header.centerLines,
        ...data.header.leftLines,
        data.footer.closingPhrase ?? '',
        data.footer.primary.title,
        data.footer.primary.nameLine,
        for (final question in data.questions) question.title.line,
      ].join(' ');
      expect(printed.contains('صفحة'), isFalse);
      expect(printed.toLowerCase().contains('page'), isFalse);
    });
  });
}
