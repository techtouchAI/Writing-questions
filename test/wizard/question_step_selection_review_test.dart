// مراجعة وظيفية مستقلة لمسار «تحديد الكل / نسخ / حذف» في شاشة إعداد
// السؤال — عبر الواجهة كما يستخدمها المدرس، ومن مسار الإنتاج نفسه
// (`ExamWizardScreen`) لا من الشاشة معزولةً فقط.
//
// ما يثبته هذا الملف:
//   * «تحديد الكل» على مقاس هاتف فعلي: يحدد أسئلة النطاق وحدها، ويظهر
//     العدّاد «المحدد ٦ من ٦»، ويحوّل الزر إلى «إلغاء تحديد الكل»، ويُظهر
//     «إنهاء التحديد»، ويُبقي RTL سليماً.
//   * «نسخ» ينشئ نسخاً حقيقية داخل المستند بعد أصولها (لا نصاً في
//     الحافظة): سؤال واحد محدد، ثم جميع الأسئلة، مع هويات جديدة لكل نسخة
//     وفرع ونقطة وخيار ومرفق، وبقاء المحتوى والتنسيق والترتيب.
//   * «حذف» يمس المحدد وحده ويُبقي السؤال المفتوح (بهويته) والباقي بترتيبه،
//     ويُمنع تماماً عند غياب التحديد.
//   * نطاق التحديد الحيّ: معرّف سؤال حُذف من خارج الشاشة (تراجع/حذف آخر)
//     لا يجعل زرّي النسخ/الحذف يبدوان مفعّلين بلا هدف، ولا يبقى في العدّاد.
//   * «إنهاء التحديد» يصفّر التحديد فعلاً: النسخ بعده لا يطال إلا السؤال
//     المفتوح.
//
// كل النقرات على الأزرار/الرقائق أعلاه، والتحقق من المستند نفسه بعدها —
// لا استدعاء دوال المعالجة مباشرة.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:writing_questions_app/models/branch_item.dart';
import 'package:writing_questions_app/models/branch_model.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/floating_element.dart';
import 'package:writing_questions_app/models/paper_divider.dart';
import 'package:writing_questions_app/models/paper_text_style.dart';
import 'package:writing_questions_app/models/point_kind.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/models/question_option.dart';
import 'package:writing_questions_app/providers/exam_wizard_controller.dart';
import 'package:writing_questions_app/views/wizard/exam_wizard_screen.dart';
import 'package:writing_questions_app/views/wizard/question_step_screen.dart';

Widget _app(Widget home) {
  return Directionality(
    textDirection: TextDirection.rtl,
    child: MaterialApp(home: home),
  );
}

/// مستند بفروع ونقاط (عناصر خارج نطاق تحديد هذه الشاشة) حتى يُثبت
/// «تحديد الكل» أنه يعدّ الأسئلة وحدها.
ExamDocument _document({int questionCount = 3}) {
  return ExamDocument(
    name: 'مراجعة التحديد',
    header: ExamHeaderModel.initial(subject: 'اللغة العربية'),
    questions: <QuestionModel>[
      for (var index = 0; index < questionCount; index++)
        QuestionModel(
          id: 'q${index + 1}',
          questionNumber: index + 1,
          statement: 'منطوق ${index + 1}',
          body: 'نص ${index + 1}',
          marksOverride: 5,
          category: 'القواعد',
          items: <BranchItem>[
            BranchItem(id: 'p${index + 1}', text: 'نقطة ${index + 1}'),
          ],
          branches: <BranchModel>[
            BranchModel(
              id: 'b${index + 1}',
              marks: 3,
              content: BranchContent(
                statement: 'فرع ${index + 1}',
                items: <BranchItem>[
                  BranchItem(id: 'bp${index + 1}', text: 'نقطة الفرع ${index + 1}'),
                ],
              ),
            ),
          ],
        ),
    ],
  );
}

/// سؤال غني بكل إعدادات النسخ: نص/منطوق/قسم/درجة/تباعد/خط/ألوان/إطار/
/// فاصل/محاذاة/نقاط وخيارات/فرع بكل حقوله/مرفقات. النسخة يجب أن تحملها
/// كلها بهويات جديدة.
ExamDocument _richDocument() {
  final questionAttachment = FloatingElement(
    id: 'f1',
    type: FloatingElementType.shape,
    shape: FloatingShapeType.square,
    dx: 12,
    dy: 9,
    width: 34,
    height: 26,
    label: 'مربع',
    framed: true,
    strokeWidth: 2.5,
    rotationDegrees: 12,
    textStyle: const PaperTextStyle(fontSize: 11, bold: true),
  );
  final branchAttachment = FloatingElement(
    id: 'f2',
    type: FloatingElementType.shape,
    shape: FloatingShapeType.circle,
    dx: 3,
    dy: 4,
    width: 10,
    height: 10,
  );
  return ExamDocument(
    name: 'نسخ كامل',
    header: ExamHeaderModel.initial(subject: 'اللغة العربية'),
    questions: <QuestionModel>[
      QuestionModel(
        id: 'q1',
        questionNumber: 1,
        statement: 'منطوق السؤال',
        body: 'نص السؤال',
        category: 'القواعد',
        marksOverride: 12.5,
        spacingAfter: 21.5,
        items: <BranchItem>[
          BranchItem(
            id: 'i1',
            text: 'نقطة مباشرة',
            kind: PointKind.multipleChoice,
            marks: 2.5,
            labelOverride: 'م',
            align: PaperAlign.end,
            options: <QuestionOption>[
              QuestionOption(
                id: 'o1',
                text: 'خيار أول',
                labelOverride: '١',
                align: PaperAlign.start,
              ),
              QuestionOption(id: 'o2', text: 'خيار ثانٍ'),
            ],
          ),
        ],
        branches: <BranchModel>[
          BranchModel(
            id: 'b1',
            marks: 3.5,
            labelOverride: 'ج',
            style: const PaperTextStyle(
              fontSize: 13,
              italic: true,
              align: PaperAlign.left,
            ),
            showFrame: true,
            dividerAfter: const PaperDivider(
              thickness: 2.4,
              widthFraction: 0.7,
              spacingBefore: 4,
              spacingAfter: 8,
            ),
            attachments: <FloatingElement>[branchAttachment],
            content: BranchContent(
              statement: 'منطوق الفرع',
              body: 'نص الفرع',
              items: <BranchItem>[
                BranchItem(
                  id: 'bi1',
                  text: 'نقطة فرع',
                  marks: 1.5,
                  labelOverride: 'ف',
                  align: PaperAlign.center,
                  options: <QuestionOption>[
                    QuestionOption(id: 'bo1', text: 'خيار فرع'),
                  ],
                ),
              ],
            ),
          ),
        ],
        attachments: <FloatingElement>[questionAttachment],
        style: const PaperTextStyle(
          fontSize: 15,
          bold: true,
          italic: true,
          underline: true,
          align: PaperAlign.center,
          lineHeight: 1.4,
          paragraphSpacing: 3,
          color: 0xFF112233,
        ),
        titleColor: 0xFF445566,
        showFrame: true,
        dividerAfter: const PaperDivider(
          thickness: 1.8,
          widthFraction: 0.9,
          spacingBefore: 5,
          spacingAfter: 7,
        ),
        titleAlign: PaperAlign.right,
        bodyAlign: PaperAlign.left,
        categoryAlign: PaperAlign.center,
      ),
      QuestionModel(id: 'q2', questionNumber: 2, statement: 'منطوق ٢'),
    ],
  );
}

final Finder _selectAll =
    find.byKey(const ValueKey<String>('select-all-questions'));
final Finder _exitSelection =
    find.byKey(const ValueKey<String>('exit-selection-mode'));
final Finder _selectionCount =
    find.byKey(const ValueKey<String>('question-selection-count'));
final Finder _copyButton =
    find.byKey(const ValueKey<String>('question-copy-action'));
final Finder _deleteButton =
    find.byKey(const ValueKey<String>('question-delete-action'));

Finder _chip(String id) => find.byKey(ValueKey<String>('question-chip-$id'));

bool _buttonEnabled(WidgetTester tester, Finder finder) =>
    tester.widget<IconButton>(finder).onPressed != null;

String _countText(ExamDocument document, int selected, int total) =>
    'المحدد ${document.formatNumber(selected)} '
    'من ${document.formatNumber(total)}';

List<String> _statements(ExamWizardController controller) =>
    <String>[for (final question in controller.questions) question.statement];

Future<ExamWizardController> _pumpScreen(
  WidgetTester tester,
  ExamDocument document,
) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final controller = ExamWizardController(document: document);
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    _app(
      ChangeNotifierProvider<ExamWizardController>.value(
        value: controller,
        child: QuestionStepScreen(onFinish: () {}, onBack: () {}),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

/// مسار الإنتاج الكامل بمقاس هاتف: `ExamWizardScreen` نفسه بمزوّده
/// ومبدّل خطواته، لا الشاشة معزولة.
Future<void> _pumpProductionPhone(
  WidgetTester tester,
  ExamDocument document,
) async {
  tester.view.physicalSize = const Size(412, 915);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(useMaterial3: true),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: ExamWizardScreen(
          existingDocument: document,
          initialStep: WizardStep.questions,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'مسار الإنتاج على مقاس هاتف: تحديد الكل ٦ من ٦ ← نسخ ← حذف المحدد فقط',
      (tester) async {
    final document = _document(questionCount: 6);
    await _pumpProductionPhone(tester, document);

    expect(find.text('إعداد السؤال الأول'), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNWidgets(6));
    expect(find.text('تحديد الكل'), findsOneWidget);
    expect(_selectionCount, findsNothing);
    expect(
      Directionality.of(tester.element(_selectAll)),
      TextDirection.rtl,
      reason: 'الواجهة عربية RTL كما هي، لا تغيير في الاتجاه.',
    );

    await tester.tap(_selectAll);
    await tester.pumpAndSettle();

    expect(find.text(_countText(document, 6, 6)), findsOneWidget);
    expect(find.text('إلغاء تحديد الكل'), findsOneWidget);
    expect(find.text('تحديد الكل'), findsNothing);
    expect(_exitSelection, findsOneWidget);
    expect(_buttonEnabled(tester, _copyButton), isTrue);
    expect(_buttonEnabled(tester, _deleteButton), isTrue);
    expect(find.byTooltip('نسخ الأسئلة المحددة'), findsOneWidget);
    expect(find.byTooltip('حذف الأسئلة المحددة'), findsOneWidget);
    for (var index = 1; index <= 6; index++) {
      expect(
        tester.widget<ChoiceChip>(_chip('q$index')).selected,
        isTrue,
        reason: 'كل أسئلة النطاق محددة — لا الفروع ولا النقاط.',
      );
    }

    // «نسخ» من الشريط العلوي: ست نسخ حقيقية بعد أصولها.
    await tester.tap(_copyButton);
    await tester.pumpAndSettle();
    expect(find.byType(ChoiceChip), findsNWidgets(12));
    expect(find.text(_countText(document, 6, 12)), findsOneWidget);
    // التحديد بقي على الأصول الستة، لا على النسخ.
    for (var index = 1; index <= 6; index++) {
      expect(tester.widget<ChoiceChip>(_chip('q$index')).selected, isTrue);
    }

    // «حذف» من الشريط العلوي: يحذف المحدد (ستة أصول) وحده، فتبقى النسخ
    // الست غير المحددة كما هي ← ٦ أسئلة.
    await tester.tap(_deleteButton);
    await tester.pumpAndSettle();
    expect(find.byType(ChoiceChip), findsNWidgets(6));
    expect(_selectionCount, findsNothing);
    expect(_exitSelection, findsNothing);
    expect(find.byTooltip('نسخ السؤال'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'نسخ سؤال واحد محدد داخل وضع التحديد — النسخة بعد أصله لا بعد المفتوح',
      (tester) async {
    final controller = await _pumpScreen(tester, _document());

    // فتح الثالث ثم تحديد الثاني (الفتح لا يغيّر التحديد).
    await tester.tap(_chip('q3'));
    await tester.pumpAndSettle();
    expect(controller.currentQuestionIndex, 2);

    await tester.longPress(_chip('q2'));
    await tester.pumpAndSettle();
    expect(find.text(_countText(controller.document, 1, 3)), findsOneWidget);

    await tester.tap(_copyButton);
    await tester.pumpAndSettle();

    expect(
      _statements(controller),
      <String>['منطوق 1', 'منطوق 2', 'منطوق 2', 'منطوق 3'],
      reason: 'النسخة تُدرج بعد أصلها المحدد (الثاني) لا بعد السؤال المفتوح.',
    );
    final source = controller.questions[1];
    final copy = controller.questions[2];
    expect(copy.id, isNot(source.id));
    expect(copy.body, source.body);
    expect(copy.marksOverride, source.marksOverride);
    expect(copy.items.single.id, isNot(source.items.single.id));
    expect(copy.branches.single.id, isNot(source.branches.single.id));
    // السؤال المفتوح (الثالث) بقي هو نفسه، وأزاحته النسخة المُدرجة قبله
    // بمقدار واحد (من 2 إلى 3) بدل أن يقفز إلى النسخة.
    expect(controller.currentQuestionIndex, 3);
    expect(controller.currentQuestion.statement, 'منطوق 3');
    // التحديد بقي على الأصل، والعدّاد يتبع الإجمالي الجديد.
    expect(find.text(_countText(controller.document, 1, 4)), findsOneWidget);
    expect(_buttonEnabled(tester, _copyButton), isTrue);
  });

  testWidgets(
      'نسخ الأسئلة المحددة يحفظ المحتوى والتنسيق والإعدادات بهويات جديدة',
      (tester) async {
    final controller = await _pumpScreen(tester, _richDocument());
    final source = controller.questions.first;

    await tester.longPress(_chip('q1'));
    await tester.pumpAndSettle();
    await tester.tap(_copyButton);
    await tester.pumpAndSettle();

    expect(controller.questions, hasLength(3));
    final copy = controller.questions[1];
    expect(copy.id, isNot(source.id));
    expect(controller.questions[0].id, 'q1', reason: 'الأصل لم يُمس.');
    expect(controller.questions[2].statement, 'منطوق ٢');

    // بيانات السؤال كاملة.
    expect(copy.statement, source.statement);
    expect(copy.body, source.body);
    expect(copy.category, source.category);
    expect(copy.marksOverride, source.marksOverride);
    expect(copy.spacingAfter, source.spacingAfter);
    expect(copy.style.toMap(), source.style.toMap());
    expect(copy.titleColor, source.titleColor);
    expect(copy.showFrame, source.showFrame);
    expect(copy.dividerAfter, source.dividerAfter);
    expect(copy.titleAlign, source.titleAlign);
    expect(copy.bodyAlign, source.bodyAlign);
    expect(copy.categoryAlign, source.categoryAlign);

    // النقاط والخيارات: محتوى كما هو، هويات جديدة.
    final sourceItem = source.items.single;
    final copyItem = copy.items.single;
    expect(copyItem.id, isNot(sourceItem.id));
    expect(copyItem.text, sourceItem.text);
    expect(copyItem.kind, sourceItem.kind);
    expect(copyItem.marks, sourceItem.marks);
    expect(copyItem.labelOverride, sourceItem.labelOverride);
    expect(copyItem.align, sourceItem.align);
    expect(copyItem.options, hasLength(2));
    for (var index = 0; index < sourceItem.options.length; index++) {
      final originalOption = sourceItem.options[index];
      final copiedOption = copyItem.options[index];
      expect(copiedOption.id, isNot(originalOption.id));
      expect(copiedOption.text, originalOption.text);
      expect(copiedOption.labelOverride, originalOption.labelOverride);
      expect(copiedOption.align, originalOption.align);
    }

    // الفرع: كل الحقول + هوية جديدة.
    final sourceBranch = source.branches.single;
    final copyBranch = copy.branches.single;
    expect(copyBranch.id, isNot(sourceBranch.id));
    expect(copyBranch.marks, sourceBranch.marks);
    expect(copyBranch.labelOverride, sourceBranch.labelOverride);
    expect(copyBranch.style.toMap(), sourceBranch.style.toMap());
    expect(copyBranch.showFrame, sourceBranch.showFrame);
    expect(copyBranch.dividerAfter, sourceBranch.dividerAfter);
    expect(copyBranch.content.statement, sourceBranch.content.statement);
    expect(copyBranch.content.body, sourceBranch.content.body);
    expect(
      copyBranch.content.items.single.id,
      isNot(sourceBranch.content.items.single.id),
    );
    expect(
      copyBranch.content.items.single.text,
      sourceBranch.content.items.single.text,
    );
    expect(
      copyBranch.content.items.single.options.single.text,
      sourceBranch.content.items.single.options.single.text,
    );

    // المرفقات: محتوى وهندسة كما هي، هوية جديدة، والأصل محفوظ.
    final sourceAttachment = source.attachments.single;
    final copyAttachment = copy.attachments.single;
    expect(copyAttachment.id, isNot(sourceAttachment.id));
    expect(copyAttachment.type, sourceAttachment.type);
    expect(copyAttachment.shape, sourceAttachment.shape);
    expect(copyAttachment.dx, sourceAttachment.dx);
    expect(copyAttachment.dy, sourceAttachment.dy);
    expect(copyAttachment.width, sourceAttachment.width);
    expect(copyAttachment.height, sourceAttachment.height);
    expect(copyAttachment.label, sourceAttachment.label);
    expect(copyAttachment.framed, sourceAttachment.framed);
    expect(copyAttachment.strokeWidth, sourceAttachment.strokeWidth);
    expect(copyAttachment.rotationDegrees, sourceAttachment.rotationDegrees);
    expect(copyAttachment.textStyle.toMap(), sourceAttachment.textStyle.toMap());
    expect(sourceAttachment.id, 'f1');
    expect(copy.branches.single.attachments.single.id, isNot('f2'));
    expect(copy.branches.single.attachments.single.width, 10);

    // الترتيب والعدّاد.
    expect(
      _statements(controller),
      <String>['منطوق السؤال', 'منطوق السؤال', 'منطوق ٢'],
    );
    expect(find.text(_countText(controller.document, 1, 3)), findsOneWidget);
  });

  testWidgets(
      'حذف المحدد وحده يُبقي السؤال المفتوح بهويته والباقي بترتيبه',
      (tester) async {
    final controller = await _pumpScreen(tester, _document(questionCount: 4));

    await tester.tap(_chip('q3'));
    await tester.pumpAndSettle();
    final openId = controller.currentQuestion.id;

    await tester.longPress(_chip('q2'));
    await tester.pumpAndSettle();
    await tester.tap(_chip('q4'));
    await tester.pumpAndSettle();
    expect(find.text(_countText(controller.document, 2, 4)), findsOneWidget);

    await tester.tap(_deleteButton);
    await tester.pumpAndSettle();

    expect(_statements(controller), <String>['منطوق 1', 'منطوق 3'],
        reason: 'حُذف المحدد (الثاني والرابع) وحده، وترتيب الباقي محفوظ.');
    expect(controller.currentQuestion.id, openId,
        reason: 'السؤال المفتوح بقي هو نفسه (الثالث) بعد إعادة الترقيم.');
    expect(controller.currentQuestionIndex, 1);
    expect(_selectionCount, findsNothing);
    expect(controller.currentQuestion.statement, 'منطوق 3');
    // خارج وضع التحديد يحذف زر الحذف السؤال المفتوح (السلوك السابق محفوظ).
    expect(_buttonEnabled(tester, _deleteButton), isTrue);
    expect(_buttonEnabled(tester, _copyButton), isTrue);
  });

  testWidgets(
      'إنهاء التحديد يصفّر التحديد: النسخ بعده لا يطال إلا السؤال المفتوح',
      (tester) async {
    final controller = await _pumpScreen(tester, _document());

    await tester.longPress(_chip('q2'));
    await tester.pumpAndSettle();
    await tester.tap(_chip('q3'));
    await tester.pumpAndSettle();
    expect(find.text(_countText(controller.document, 2, 3)), findsOneWidget);

    await tester.tap(_exitSelection);
    await tester.pumpAndSettle();
    expect(_selectionCount, findsNothing);
    expect(find.text('تحديد الكل'), findsOneWidget);

    await tester.tap(_copyButton);
    await tester.pumpAndSettle();
    expect(
      _statements(controller),
      <String>['منطوق 1', 'منطوق 1', 'منطوق 2', 'منطوق 3'],
      reason: 'التحديد المصفَّر لا يتسرّب إلى عملية النسخ التالية.',
    );
    expect(controller.questions[1].id, isNot(controller.questions[0].id));
    expect(controller.currentQuestionIndex, 0);
  });

  testWidgets(
      'تحديد قديم بعد حذف خارجي: العدّاد والأزرار تتبع النطاق الحيّ لا المعرّفات الباقية',
      (tester) async {
    final controller = await _pumpScreen(tester, _document());

    await tester.longPress(_chip('q1'));
    await tester.pumpAndSettle();
    expect(find.text(_countText(controller.document, 1, 3)), findsOneWidget);

    // حذف السؤال المحدد من خارج الشاشة (كما يفعل التراجع/شاشة أخرى).
    controller.removeQuestion(0);
    await tester.pumpAndSettle();

    expect(controller.questions.map((question) => question.id),
        <String>['q2', 'q3']);
    expect(_selectionCount, findsOneWidget,
        reason: 'وضع التحديد نفسه باقٍ — لا يُغلق بسبب تغيّر خارجي.');
    expect(
      find.text(_countText(controller.document, 0, 2)),
      findsOneWidget,
      reason: 'المعرّف المحذوف لا يُحتسب في العدّاد.',
    );
    expect(_buttonEnabled(tester, _copyButton), isFalse);
    expect(_buttonEnabled(tester, _deleteButton), isFalse);

    // إعادة التحديد من الزر نفسه تعمل على النطاق الحيّ وتُنظّف المعرّف القديم.
    await tester.tap(_selectAll);
    await tester.pumpAndSettle();
    expect(find.text(_countText(controller.document, 2, 2)), findsOneWidget);
    expect(_buttonEnabled(tester, _copyButton), isTrue);
    expect(_buttonEnabled(tester, _deleteButton), isTrue);

    // نسخ الاثنين فعلاً: أربعة أسئلة بعد العملية.
    await tester.tap(_copyButton);
    await tester.pumpAndSettle();
    expect(controller.questions, hasLength(4));
    expect(find.text(_countText(controller.document, 2, 4)), findsOneWidget);
  });
}
