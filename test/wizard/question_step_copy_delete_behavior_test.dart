// الاختبارات السلوكية لزرَّي «نسخ» و«حذف» مع «تحديد الكل» في شريط خطوة
// إعداد السؤال (شاشة «إعداد السؤال الأول»):
//
//   * «نسخ» ينسخ **السؤال المحدد** (أو الأسئلة المحددة) نسخاً حقيقياً داخل
//     المستند — كل نسخة بعد أصلها بمحتواها وإعداداتها وترتيبها — لا نصاً
//     في حافظة النظام، وخارج وضع التحديد يبقى السؤال المفتوح هو الهدف.
//   * «تحديد الكل» يحدد أسئلة هذه الشاشة كلها (لا الفروع ولا النقاط)،
//     ويحدّث العدّاد «المحدد ٥ من ٦» وحالة الأزرار و«إنهاء التحديد».
//   * «حذف» يُطبَّق على المحدد فقط داخل وضع التحديد، ويمنع الحذف غير
//     المقصود عند غياب التحديد (الزر معطَّل ولا شيء يُحذف)، ويبقى سؤال
//     واحد على الأقل، وسلوكه السابق في الوضع العادي سليم كما هو.
//
// كل إثبات هنا عبر الواجهة (نقر الأزرار والرقائق) ثم التحقق من حالة
// المستند والعدّاد — لا مجرد استدعاء دوال المعالجة.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:writing_questions_app/models/branch_item.dart';
import 'package:writing_questions_app/models/branch_model.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/providers/exam_wizard_controller.dart';
import 'package:writing_questions_app/views/wizard/question_step_screen.dart';

Widget _app(Widget home) {
  return Directionality(
    textDirection: TextDirection.rtl,
    child: MaterialApp(home: home),
  );
}

/// مستند أغنى من اللازم عمداً: فروع ونقاط (عناصر خارج نطاق تحديد هذه
/// الشاشة) حتى يُثبت «تحديد الكل» أنه يعدّ الأسئلة وحدها.
ExamDocument _document({int questionCount = 3}) {
  return ExamDocument(
    name: 'نسخ وحذف',
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
  WidgetTester tester, {
  int questionCount = 3,
}) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final controller =
      ExamWizardController(document: _document(questionCount: questionCount));
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

void main() {
  testWidgets('«نسخ» في الوضع العادي يكرر السؤال المفتوح نسخاً حقيقياً بعد الأصل',
      (tester) async {
    final controller = await _pumpScreen(tester);

    // فتح السؤال الثاني بالضغمة العادية (لا وضع تحديد).
    await tester.tap(_chip('q2'));
    await tester.pumpAndSettle();
    expect(controller.currentQuestionIndex, 1);

    await tester.tap(_copyButton);
    await tester.pumpAndSettle();

    expect(
      _statements(controller),
      <String>['منطوق 1', 'منطوق 2', 'منطوق 2', 'منطوق 3'],
      reason: 'النسخة تُدرج بعد الأصل مباشرة مع بقاء ترتيب بقية الأسئلة.',
    );
    final source = controller.questions[1];
    final copy = controller.questions[2];
    expect(copy.id, isNot(source.id), reason: 'النسخة هوية جديدة.');
    expect(copy.statement, source.statement);
    expect(copy.body, source.body);
    expect(copy.marksOverride, source.marksOverride);
    expect(copy.category, source.category);
    expect(copy.style.toMap(), source.style.toMap());
    expect(copy.items.single.text, source.items.single.text);
    expect(copy.items.single.id, isNot(source.items.single.id));
    expect(copy.branches.single.content.statement,
        source.branches.single.content.statement);
    expect(copy.branches.single.marks, source.branches.single.marks);
    expect(copy.branches.single.id, isNot(source.branches.single.id));
    // السؤال المفتوح يبقى هو الأصل (لا يقفز إلى النسخة).
    expect(controller.currentQuestionIndex, 1);
  });

  testWidgets('«نسخ» ينسخ الأسئلة المحددة فقط — كل نسخة بعد أصلها بالترتيب',
      (tester) async {
    final controller = await _pumpScreen(tester);
    final document = controller.document;

    // تحديد الأول والثالث (الثاني غير محدد).
    await tester.longPress(_chip('q1'));
    await tester.pumpAndSettle();
    await tester.tap(_chip('q3'));
    await tester.pumpAndSettle();

    await tester.tap(_copyButton);
    await tester.pumpAndSettle();

    expect(
      _statements(controller),
      <String>[
        'منطوق 1',
        'منطوق 1',
        'منطوق 2',
        'منطوق 3',
        'منطوق 3',
      ],
      reason: 'النُّسخ من المحدد وحده، وكل نسخة بعد أصلها، والترتيب محفوظ.',
    );
    // الأسئلة غير المحددة لم تُنسخ ولم تُمس.
    expect(controller.questions[2].statement, 'منطوق 2');
    expect(
      controller.questions.where((question) => question.statement == 'منطوق 2'),
      hasLength(1),
    );
    // النسخ محتوى مستقل: تعديل النسخة (الموضع 1) لا يمس الأصل (الموضع 0).
    controller.updateQuestionStatement(1, 'منطوق النسخة');
    expect(controller.questions[0].statement, 'منطوق 1');
    // العدّاد يتبع المحددة من الإجمالي الجديد.
    expect(find.text(_countText(document, 2, 5)), findsOneWidget);
  });

  testWidgets('«تحديد الكل» ثم «نسخ» يكرر كل أسئلة النطاق نسخاً حقيقياً',
      (tester) async {
    final controller = await _pumpScreen(tester);
    final document = controller.document;

    await tester.tap(_selectAll);
    await tester.pumpAndSettle();
    expect(find.text(_countText(document, 3, 3)), findsOneWidget);

    await tester.tap(_copyButton);
    await tester.pumpAndSettle();

    expect(
      _statements(controller),
      <String>[
        'منطوق 1',
        'منطوق 1',
        'منطوق 2',
        'منطوق 2',
        'منطوق 3',
        'منطوق 3',
      ],
    );
    // كل زوج أصل+نسخة بمعرّفات مختلفة، والمحتوى مطابق.
    for (var pair = 0; pair < 3; pair++) {
      final source = controller.questions[pair * 2];
      final copy = controller.questions[pair * 2 + 1];
      expect(copy.id, isNot(source.id));
      expect(copy.statement, source.statement);
      expect(copy.branches.single.id, isNot(source.branches.single.id));
    }
    // التحديد بقي على الأصول بعد النسخ.
    expect(find.text(_countText(document, 3, 6)), findsOneWidget);
  });

  testWidgets('«نسخ» في وضع التحديد بلا تحديد = لا شيء، والزر معطَّل',
      (tester) async {
    final controller = await _pumpScreen(tester);

    // وضع تحديد ثم إفراغ التحديد (ضغطتان على الرقاقة نفسها).
    await tester.longPress(_chip('q1'));
    await tester.pumpAndSettle();
    await tester.tap(_chip('q1'));
    await tester.pumpAndSettle();

    expect(_buttonEnabled(tester, _copyButton), isFalse);
    expect(_buttonEnabled(tester, _deleteButton), isFalse);

    final before = _statements(controller);
    await tester.tap(_copyButton);
    await tester.tap(_deleteButton);
    await tester.pumpAndSettle();
    expect(_statements(controller), before,
        reason: 'غياب التحديد لا ينسخ شيئاً ولا يحذف شيئاً.');
  });

  testWidgets('«حذف» في الوضع العادي يحذف السؤال المفتوح وحده (السلوك السابق)',
      (tester) async {
    final controller = await _pumpScreen(tester);

    await tester.tap(_chip('q2'));
    await tester.pumpAndSettle();
    await tester.tap(_deleteButton);
    await tester.pumpAndSettle();

    expect(_statements(controller), <String>['منطوق 1', 'منطوق 3']);
    // مؤشر السؤال المفتوح يُقفل على الباقي بلا عطل.
    expect(controller.currentQuestionIndex, lessThan(controller.questions.length));
  });

  testWidgets('«حذف» يُطبَّق على العناصر المحددة فقط', (tester) async {
    final controller = await _pumpScreen(tester);

    await tester.longPress(_chip('q1'));
    await tester.pumpAndSettle();
    await tester.tap(_chip('q2'));
    await tester.pumpAndSettle();

    await tester.tap(_deleteButton);
    await tester.pumpAndSettle();

    expect(_statements(controller), <String>['منطوق 3'],
        reason: 'حُذف المحدد (الأول والثاني) وبقي غير المحدد وحده.');
    expect(_selectionCount, findsNothing,
        reason: 'الحذف في وضع التحديد يُنهي الوضع بعد التنفيذ.');
  });

  testWidgets('«تحديد الكل» ثم «حذف»: يبقى سؤال واحد على الأقل',
      (tester) async {
    final controller = await _pumpScreen(tester);
    final document = controller.document;

    await tester.tap(_selectAll);
    await tester.pumpAndSettle();
    expect(find.text(_countText(document, 3, 3)), findsOneWidget);

    await tester.tap(_deleteButton);
    await tester.pumpAndSettle();

    expect(controller.questions, hasLength(1),
        reason: 'الحد الأدنى: سؤال واحد لا يُحذف أبداً.');
    expect(controller.questions.single.statement, 'منطوق 1',
        reason: 'عند شمول التحديد للجميع يبقى الأول.');
  });

  testWidgets('«تحديد الكل» يحدّث العدّاد وحالة الأزرار ويظهر «إنهاء التحديد»',
      (tester) async {
    final controller = await _pumpScreen(tester, questionCount: 6);
    final document = controller.document;

    expect(_selectionCount, findsNothing);
    expect(_exitSelection, findsNothing);

    await tester.tap(_selectAll);
    await tester.pumpAndSettle();

    expect(find.text(_countText(document, 6, 6)), findsOneWidget);
    expect(find.text('إلغاء تحديد الكل'), findsOneWidget);
    expect(_exitSelection, findsOneWidget);
    expect(_buttonEnabled(tester, _copyButton), isTrue);
    expect(_buttonEnabled(tester, _deleteButton), isTrue);
    for (final question in controller.questions) {
      expect(
        tester.widget<ChoiceChip>(_chip(question.id)).selected,
        isTrue,
        reason: 'كل أسئلة النطاق محددة.',
      );
    }

    // «إنهاء التحديد» ينقل إلى الوضع العادي ويصفّر التحديد.
    await tester.tap(_exitSelection);
    await tester.pumpAndSettle();
    expect(_selectionCount, findsNothing);
    expect(_exitSelection, findsNothing);
    expect(find.text('تحديد الكل'), findsOneWidget);
    expect(_buttonEnabled(tester, _copyButton), isTrue,
        reason: 'خارج وضع التحديد يعمل الزر على السؤال المفتوح.');
    expect(_buttonEnabled(tester, _deleteButton), isTrue);
    expect(controller.currentQuestionIndex, 0);
  });

  testWidgets('لا تُختار عناصر خارج النطاق: الفروع والنقاط ليست ضمن العدّاد',
      (tester) async {
    // لكل سؤال فرع ونقطة — عناصر كثيرة خارج نطاق هذه الشاشة.
    final controller = await _pumpScreen(tester, questionCount: 2);
    final document = controller.document;
    expect(document.totalBranches, 2);
    expect(controller.questions.first.items, hasLength(1));

    await tester.tap(_selectAll);
    await tester.pumpAndSettle();

    expect(
      find.text(_countText(document, 2, 2)),
      findsOneWidget,
      reason: 'الإجمالي عدد الأسئلة وحدها — لا فروع ولا نقاط.',
    );
    expect(controller.questions.every((q) => q.branches.length == 1), isTrue);
  });

  testWidgets('التراجع عن التحديد: «إلغاء تحديد الكل» وتحديد يدوي بعد «تحديد الكل»',
      (tester) async {
    final controller = await _pumpScreen(tester, questionCount: 6);
    final document = controller.document;

    await tester.tap(_selectAll);
    await tester.pumpAndSettle();
    expect(find.text(_countText(document, 6, 6)), findsOneWidget);

    // الضغط الثاني على الزر نفسه («إلغاء تحديد الكل»): صفر محدد، الأزرار
    // معطّلة، والوضع باقٍ.
    await tester.tap(_selectAll);
    await tester.pumpAndSettle();
    expect(find.text(_countText(document, 0, 6)), findsOneWidget);
    expect(_buttonEnabled(tester, _copyButton), isFalse);
    expect(_buttonEnabled(tester, _deleteButton), isFalse);
    expect(_selectionCount, findsOneWidget);

    // إعادة التحديد من الوضع الفارغ تعمل أيضاً.
    await tester.tap(_selectAll);
    await tester.pumpAndSettle();
    expect(find.text(_countText(document, 6, 6)), findsOneWidget);
    expect(_buttonEnabled(tester, _deleteButton), isTrue);

    // التراجع اليدوي بعد «تحديد الكل»: إسقاط سؤال واحد يعيد الزر إلى
    // «تحديد الكل» ويحدّث العدّاد. الرقاقة الأخيرة قد تخرج عن حافة الشريط
    // الأفقي فتُسحب إلى الظهور أولاً كما يفعل المستخدم.
    await tester.ensureVisible(_chip('q6'));
    await tester.pumpAndSettle();
    await tester.tap(_chip('q6'));
    await tester.pumpAndSettle();
    expect(find.text(_countText(document, 5, 6)), findsOneWidget);
    expect(find.text('تحديد الكل'), findsOneWidget);
  });

  testWidgets('الحذف المتعدد يزيل المحدد وحده ويُبقي ترتيب الباقي', (tester) async {
    final controller = await _pumpScreen(tester, questionCount: 4);

    // تحديد الثاني والرابع.
    await tester.longPress(_chip('q2'));
    await tester.pumpAndSettle();
    await tester.tap(_chip('q4'));
    await tester.pumpAndSettle();

    await tester.tap(_deleteButton);
    await tester.pumpAndSettle();

    expect(_statements(controller), <String>['منطوق 1', 'منطوق 3'],
        reason: 'المحدد يُحذف وحده، وترتيب الباقي محفوظ.');
  });

  testWidgets('حالة حدية: سؤال واحد — «تحديد الكل» و«نسخ» يعملان ولا حذف',
      (tester) async {
    final controller = await _pumpScreen(tester, questionCount: 1);
    final document = controller.document;

    expect(_deleteButton, findsNothing,
        reason: 'السؤال الوحيد لا يُحذف — الزر غير معروض أصلاً.');

    await tester.tap(_selectAll);
    await tester.pumpAndSettle();
    expect(find.text(_countText(document, 1, 1)), findsOneWidget);

    await tester.tap(_copyButton);
    await tester.pumpAndSettle();
    expect(_statements(controller), <String>['منطوق 1', 'منطوق 1']);
    expect(find.text(_countText(document, 1, 2)), findsOneWidget,
        reason: 'التحديد بقي على الأصل والإجمالي صار اثنين.');
  });
}
