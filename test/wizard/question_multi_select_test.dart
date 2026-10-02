// التحديد المتعدد في قائمة الأسئلة (شريط الأسئلة في خطوة إعداد السؤال):
//   * ضغط مطوّل على سؤال ← دخول وضع التحديد مع تحديد السؤال المضغوط،
//   * ضغمة على سؤال ثانٍ ← تحديد سؤالين، وعلى محدد ← إلغاء تحديده،
//   * «تحديد الكل» ← تحديد الجميع، ومرة أخرى ← إلغاء تحديد الجميع،
//   * «إنهاء التحديد» ← خروج من الوضع،
//   * والضغمة العادية خارج الوضع تفتح السؤال للتحرير كما كانت دائماً،
//   * بلا أي تغيير في الأسئلة أو محتواها أو ترتيبها.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
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

ExamDocument _document({int questionCount = 3}) {
  return ExamDocument(
    name: 'تحديد متعدد',
    header: ExamHeaderModel.initial(subject: 'اللغة العربية'),
    questions: <QuestionModel>[
      for (var index = 0; index < questionCount; index++)
        QuestionModel(
          id: 'q${index + 1}',
          questionNumber: index + 1,
          statement: 'منطوق السؤال ${index + 1}',
        ),
    ],
  );
}

Finder _chip(String id) => find.byKey(ValueKey<String>('question-chip-$id'));
final Finder _selectAll =
    find.byKey(const ValueKey<String>('select-all-questions'));
final Finder _exitSelection =
    find.byKey(const ValueKey<String>('exit-selection-mode'));
final Finder _selectionCount =
    find.byKey(const ValueKey<String>('question-selection-count'));

bool _chipSelected(WidgetTester tester, String id) =>
    tester.widget<ChoiceChip>(_chip(id)).selected;

/// نص العدّاد كما يبنيه الشاشة من ترقيم المستند نفسه.
String _countText(ExamDocument document, int selected, int total) =>
    'المحدد ${document.formatNumber(selected)} '
    'من ${document.formatNumber(total)}';

/// لقطة محتوى الأسئلة وترتيبها — يجب ألا يمسها وضع التحديد.
List<String> _questionsSnapshot(ExamWizardController controller) => <String>[
      for (final question in controller.questions)
        '${question.id}|${question.statement}|${question.marks}',
    ];

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
  testWidgets('وضع عادي: لا عدّاد ولا خروج، وزر «تحديد الكل» حاضر',
      (tester) async {
    await _pumpScreen(tester);

    expect(_selectionCount, findsNothing);
    expect(_exitSelection, findsNothing);
    expect(_selectAll, findsOneWidget);
    expect(find.text('تحديد الكل'), findsOneWidget);
    // الرقاقة الحالية (السؤال المفتوح) محددة بتنقّل المعتاد.
    expect(_chipSelected(tester, 'q1'), isTrue);
    expect(_chipSelected(tester, 'q2'), isFalse);
  });

  testWidgets('ضغط مطوّل ← وضع تحديد والسؤال المضغوط محدد وحده',
      (tester) async {
    final controller = await _pumpScreen(tester);
    final document = controller.document;

    await tester.longPress(_chip('q2'));
    await tester.pumpAndSettle();

    expect(_selectionCount, findsOneWidget);
    expect(_exitSelection, findsOneWidget);
    expect(find.text(_countText(document, 1, 3)), findsOneWidget);
    expect(_chipSelected(tester, 'q2'), isTrue);
    expect(_chipSelected(tester, 'q1'), isFalse);
    expect(_chipSelected(tester, 'q3'), isFalse);
    // الضغط المطوّل لا يفتح السؤال ولا يغيّر السؤال الحالي.
    expect(controller.currentQuestionIndex, 0);
  });

  testWidgets('ضغمة على ثانٍ ← اثنان، وعلى محدد ← إلغاء تحديده',
      (tester) async {
    final controller = await _pumpScreen(tester);
    final document = controller.document;

    await tester.longPress(_chip('q1'));
    await tester.pumpAndSettle();

    // تحديد سؤال ثانٍ بضغمة.
    await tester.tap(_chip('q2'));
    await tester.pumpAndSettle();
    expect(_chipSelected(tester, 'q1'), isTrue);
    expect(_chipSelected(tester, 'q2'), isTrue);
    expect(find.text(_countText(document, 2, 3)), findsOneWidget);

    // ضغمة على سؤال محدد تلغي تحديده وحده.
    await tester.tap(_chip('q2'));
    await tester.pumpAndSettle();
    expect(_chipSelected(tester, 'q2'), isFalse);
    expect(_chipSelected(tester, 'q1'), isTrue);
    expect(find.text(_countText(document, 1, 3)), findsOneWidget);
    // الوضع ما زال قائماً.
    expect(_selectionCount, findsOneWidget);
  });

  testWidgets('«تحديد الكل» يحدد الجميع ثم يلغي تحديد الجميع',
      (tester) async {
    final controller = await _pumpScreen(tester);
    final document = controller.document;

    await tester.longPress(_chip('q1'));
    await tester.pumpAndSettle();

    await tester.tap(_selectAll);
    await tester.pumpAndSettle();
    expect(_chipSelected(tester, 'q1'), isTrue);
    expect(_chipSelected(tester, 'q2'), isTrue);
    expect(_chipSelected(tester, 'q3'), isTrue);
    expect(find.text(_countText(document, 3, 3)), findsOneWidget);
    // الزر نفسه صار «إلغاء تحديد الكل».
    expect(find.text('إلغاء تحديد الكل'), findsOneWidget);
    expect(find.text('تحديد الكل'), findsNothing);

    await tester.tap(_selectAll);
    await tester.pumpAndSettle();
    expect(_chipSelected(tester, 'q1'), isFalse);
    expect(_chipSelected(tester, 'q2'), isFalse);
    expect(_chipSelected(tester, 'q3'), isFalse);
    expect(find.text(_countText(document, 0, 3)), findsOneWidget);
    expect(find.text('تحديد الكل'), findsOneWidget);
    // إلغاء تحديد الكل لا يخرج من الوضع (الخروج زرّه الخاص).
    expect(_selectionCount, findsOneWidget);
  });

  testWidgets('«تحديد الكل» من الوضع العادي يدخل وضع التحديد محدداً الجميع',
      (tester) async {
    final controller = await _pumpScreen(tester);
    final document = controller.document;

    await tester.tap(_selectAll);
    await tester.pumpAndSettle();

    expect(_selectionCount, findsOneWidget);
    expect(find.text(_countText(document, 3, 3)), findsOneWidget);
    for (final id in <String>['q1', 'q2', 'q3']) {
      expect(_chipSelected(tester, id), isTrue);
    }
  });

  testWidgets('سؤال واحد: تحديد الكل يعمل عليه وحده', (tester) async {
    final controller = await _pumpScreen(tester, questionCount: 1);
    final document = controller.document;

    await tester.tap(_selectAll);
    await tester.pumpAndSettle();
    expect(find.text(_countText(document, 1, 1)), findsOneWidget);
    expect(_chipSelected(tester, 'q1'), isTrue);

    await tester.tap(_selectAll);
    await tester.pumpAndSettle();
    expect(find.text(_countText(document, 0, 1)), findsOneWidget);
    expect(_chipSelected(tester, 'q1'), isFalse);
  });

  testWidgets('«إنهاء التحديد» يخرج من الوضع ويصفّر التحديد',
      (tester) async {
    final controller = await _pumpScreen(tester);

    await tester.longPress(_chip('q2'));
    await tester.pumpAndSettle();
    await tester.tap(_selectAll);
    await tester.pumpAndSettle();

    await tester.tap(_exitSelection);
    await tester.pumpAndSettle();

    expect(_selectionCount, findsNothing);
    expect(_exitSelection, findsNothing);
    expect(find.text('تحديد الكل'), findsOneWidget);
    // الرقائق تعود إلى دلالتها العادية: السؤال المفتوح وحده «محدد».
    expect(_chipSelected(tester, 'q1'), isTrue);
    expect(_chipSelected(tester, 'q2'), isFalse);
    expect(_chipSelected(tester, 'q3'), isFalse);
    expect(controller.currentQuestionIndex, 0);
  });

  testWidgets('ضغمة عادية خارج الوضع تفتح السؤال (لم تنكسر الإيماءة الأصلية)',
      (tester) async {
    final controller = await _pumpScreen(tester);

    await tester.tap(_chip('q3'));
    await tester.pumpAndSettle();

    expect(controller.currentQuestionIndex, 2);
    expect(_selectionCount, findsNothing,
        reason: 'الضغمة العادية لا تدخل وضع التحديد.');
    expect(_chipSelected(tester, 'q3'), isTrue);
    expect(_chipSelected(tester, 'q1'), isFalse);
  });

  testWidgets('وضع التحديد لا يمس الأسئلة: لا محتوى ولا ترتيب ولا تخزين',
      (tester) async {
    final controller = await _pumpScreen(tester);
    final before = _questionsSnapshot(controller);
    final documentBefore = controller.document.toMap();

    await tester.longPress(_chip('q2'));
    await tester.pumpAndSettle();
    await tester.tap(_chip('q3'));
    await tester.pumpAndSettle();
    await tester.tap(_selectAll);
    await tester.pumpAndSettle();
    await tester.tap(_selectAll);
    await tester.pumpAndSettle();
    await tester.tap(_exitSelection);
    await tester.pumpAndSettle();

    expect(_questionsSnapshot(controller), before);
    expect(controller.document.toMap(), documentBefore);
    expect(controller.currentQuestionIndex, 0);
  });

  testWidgets('تحديد سؤالين لا يترك الثالث متأثراً', (tester) async {
    final controller = await _pumpScreen(tester);

    await tester.longPress(_chip('q1'));
    await tester.pumpAndSettle();
    await tester.tap(_chip('q3'));
    await tester.pumpAndSettle();

    expect(_chipSelected(tester, 'q1'), isTrue);
    expect(_chipSelected(tester, 'q3'), isTrue);
    expect(_chipSelected(tester, 'q2'), isFalse,
        reason: 'السؤال غير المحدد يبقى خارج التحديد.');
    // فتح سؤال بالضغط المطوّل لم يحدث: الحالي ما زال الأول.
    expect(controller.currentQuestionIndex, 0);
  });
}
