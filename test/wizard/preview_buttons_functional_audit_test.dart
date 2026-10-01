// =============================================================================
// تدقيق وظيفي شامل لأزرار مرحلة المعاينة (WizardStep.preview)
//
// كل اختبار يتحقق من مستوى واحد أو أكثر من المستويات الأربعة
// (1 الحالة/الظهور، 2 صحة الـ callback، 3 الحفظ في النموذج، 4 الظهور النهائي)،
// ونتائج PASS/FAIL في سجلات CI هي الأدلة (gh run view <id> --log-failed).
//
// القاعدة: وجود الشيفرة أو نظافتها أو مظهر الواجهة ليست دليل نجاح —
// النجاح = أثر ملموس على النموذج/الشكل النهائي.
//
// ملاحظة المعمارية الجديدة: «نوع السؤال/الفرع» القديم أصبح **نوع كل نقطة**
// (`BranchItem.kind`)، وخيارات الاختيار من متعدد داخل نقطتها، وحقول الترويسة
// القديمة (تعليمات/عنوان/ملاحظات) حلت محلها حقول النموذج الجديدة
// (اسم المدرسة/نوع الامتحان/العام الدراسي/الدور/المادة/الصف/الوقت).
// =============================================================================
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:writing_questions_app/layout/blueprint/exam_blueprint.dart';
import 'package:writing_questions_app/models/branch_item.dart';
import 'package:writing_questions_app/models/branch_model.dart';
import 'package:writing_questions_app/models/exam_canvas_geometry.dart';
import 'package:writing_questions_app/models/exam_catalog.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_footer_model.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/floating_element.dart';
import 'package:writing_questions_app/models/paper_divider.dart';
import 'package:writing_questions_app/models/paper_font.dart';
import 'package:writing_questions_app/models/paper_text_style.dart';
import 'package:writing_questions_app/models/point_kind.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/models/question_option.dart';
import 'package:writing_questions_app/providers/exam_document_provider.dart';
import 'package:writing_questions_app/providers/exam_wizard_controller.dart';
import 'package:writing_questions_app/views/wizard/exam_preview_screen.dart';
import 'package:writing_questions_app/views/wizard/paper_header_footer_view.dart';
import 'package:writing_questions_app/views/wizard/preview_toolbar.dart';

ExamDocument _document() => ExamDocument(
      name: 'تدقيق وظيفي',
      header: ExamHeaderModel.initial(subject: 'اللغة العربية'),
      questions: <QuestionModel>[
        QuestionModel(
          id: 'q1',
          questionNumber: 1,
          statement: 'السؤال الأول',
          items: <BranchItem>[BranchItem(id: 'qi1', text: 'نقطة السؤال الأولى')],
          branches: <BranchModel>[
            BranchModel(
              id: 'b1',
              marks: 5,
              content: BranchContent(statement: 'نص الفرع الأول'),
            ),
            BranchModel(
              id: 'b2',
              marks: 2,
              content: BranchContent(
                statement: 'اختر الإجابة',
                items: <BranchItem>[
                  BranchItem(
                    id: 'bi-mcq',
                    kind: PointKind.multipleChoice,
                    text: 'سؤال الخيارات',
                    options: <QuestionOption>[
                      QuestionOption(text: 'الخيار الأول'),
                      QuestionOption(text: 'الخيار الثاني'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        QuestionModel(
          id: 'q2',
          questionNumber: 2,
          statement: 'السؤال الثاني',
          branches: <BranchModel>[
            BranchModel(
              id: 'b3',
              marks: 3,
              content: BranchContent(
                items: <BranchItem>[
                  BranchItem(id: 'bi1', kind: PointKind.trueFalse, text: 'عبارة أولى'),
                  BranchItem(id: 'bi2', kind: PointKind.trueFalse, text: 'عبارة ثانية'),
                ],
              ),
            ),
          ],
        ),
      ],
    );

Future<void> _pump(
  WidgetTester tester,
  ExamWizardController controller, {
  double width = 1600,
  ExamDocumentProvider? library,
}) async {
  tester.view.physicalSize = Size(width, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider<ExamWizardController>.value(value: controller),
          if (library != null)
            ChangeNotifierProvider<ExamDocumentProvider>.value(value: library),
        ],
        child: ExamPreviewScreen(onBackToQuestions: () {}),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _tool(String tooltip) => find.descendant(
      of: find.byType(PreviewToolbar),
      matching: find.byTooltip(tooltip),
    ).last;

/// يعيد التمرير الأفقي لشريط الأدوات إلى بدايته (كما يسحب المستخدم الشريط
/// إلى أوله) فتُبنى أزرار أوائل الشريط: التراجع والإعادة والقفل.
void _rewindToolbar(WidgetTester tester) {
  final scrollables = find.descendant(
    of: find.byType(PreviewToolbar),
    matching: find.byType(Scrollable),
  );
  if (scrollables.evaluate().isEmpty) {
    return;
  }
  final position = tester.state<ScrollableState>(scrollables.first).position;
  position.jumpTo(0);
}

/// يُمرّر شريط الأدوات حتى يظهر الزر المطلوب قبل النقر (شريط أفقي طويل).
///
/// الشريط يُبني بتقنية lazy بناءً على الموضع؛ فيُمسح من بدايته إلى نهايته
/// (وليس إلى الأمام فقط) كي يُعثر على أزرار أوله — التراجع والإعادة والقفل —
/// حتى لو كان الشريط قد تُرك عند نهايته. وقد يكون الزر غير موجود إطلاقاً،
/// و`.last` يرمي حينها [StateError]، فنعدّ ذلك «غير ظاهر» بدل الانفجار.
Future<void> _revealToolbarButton(WidgetTester tester, Finder finder) async {
  bool visible() {
    try {
      return finder.evaluate().isNotEmpty;
    } on StateError {
      return false;
    }
  }

  if (visible()) {
    return;
  }
  final scrollables = find.descendant(
    of: find.byType(PreviewToolbar),
    matching: find.byType(Scrollable),
  );
  if (scrollables.evaluate().isEmpty) {
    return;
  }
  final scrollable = scrollables.first;
  final position = tester.state<ScrollableState>(scrollable).position;
  // من البداية: أزرار أوائل الشريط (تراجع/إعادة/قفل) لا تُبنى إلا هناك.
  position.jumpTo(0);
  await tester.pumpAndSettle();
  var steps = 0;
  while (!visible() && position.pixels < position.maxScrollExtent && steps < 80) {
    final next = position.pixels + 120;
    position.jumpTo(
      next > position.maxScrollExtent ? position.maxScrollExtent : next,
    );
    await tester.pumpAndSettle();
    steps++;
  }
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _revealToolbarButton(tester, finder);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder _field(String key) => find.descendant(
      of: find.byKey(ValueKey<String>(key)),
      matching: find.byType(TextField),
    );

String _snapshot(ExamWizardController controller) =>
    jsonEncode(controller.document.toMap());

/// أول فرق بين مستندين كنصوص JSON — رسالة فشل قصيرة تصل في تعليقات CI
/// (رسالة expect بالكامل تُقتطع عند القيمة 6KB لتعليق GitHub).
String? _firstDiff(String actual, String baseline) {
  if (actual == baseline) {
    return null;
  }
  final limit =
      actual.length < baseline.length ? actual.length : baseline.length;
  var i = 0;
  while (i < limit && actual.codeUnitAt(i) == baseline.codeUnitAt(i)) {
    i++;
  }
  final from = i > 60 ? i - 60 : 0;
  final aEnd = actual.length < i + 90 ? actual.length : i + 90;
  final bEnd = baseline.length < i + 90 ? baseline.length : i + 90;
  return 'أول فرق عند $i (actual=${actual.length}، baseline=${baseline.length})\n'
      'baseline …${baseline.substring(from, bEnd)}…\n'
      'actual   …${actual.substring(from, aEnd)}…';
}

Future<void> _settleSnackbars(WidgetTester tester) async {
  // رسائل الخطأ SnackBar مؤقت؛ نُفضيها قبل المرة التالية كي لا تتراكم.
  await tester.pumpAndSettle(const Duration(seconds: 5));
}

/// فتح قائمة أداة ثم «مخصص...» ثم إدخال القيمة وتطبيقها.
Future<void> _applyCustomValue(
  WidgetTester tester, {
  required String menuTooltip,
  required String value,
}) async {
  await _tap(tester, _tool(menuTooltip));
  await _tap(tester, find.text('مخصص...').last);
  await tester.enterText(
    find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    ),
    value,
  );
  await _tap(tester, find.text('تطبيق'));
}

void main() {
  setUpAll(() => WidgetController.hitTestWarningShouldBeFatal = true);
  tearDownAll(() => WidgetController.hitTestWarningShouldBeFatal = false);

  // ===========================================================================
  // Undo/Redo matrix — كل عملية موثّقة تُتراجع وتُعاد إلى حالتها الحرفية
  // ===========================================================================
  test('AUD-UR-01: undo/redo matrix — كل عملية تُتراجع وتُعاد بالضبط', () {
    const BranchRef essayRef = BranchRef(questionIndex: 0, branchIndex: 0);
    const BranchRef mcqRef = BranchRef(questionIndex: 0, branchIndex: 1);
    const BranchRef tfRef = BranchRef(questionIndex: 1, branchIndex: 0);
    final PointsOwner questionOwner = PointsOwner.question(0);
    final PointsOwner mcqOwner = PointsOwner.branch(mcqRef);
    final PointsOwner tfOwner = PointsOwner.branch(tfRef);

    void addFreeElement(ExamWizardController c) {
      c.addFloatingElement(FloatingElement(
        id: 'free-1',
        type: FloatingElementType.shape,
        shape: FloatingShapeType.square,
        dx: 140,
        dy: 200,
        width: 80,
        height: 60,
      ));
    }

    void updateHeader(ExamWizardController c, ExamHeaderModel Function(ExamHeaderModel) update) {
      c.updateHeader(update(c.document.header));
    }

    // كل صف: (إعداد اختياري لا يُختبر، العملية نفسها تُراجع وتُعاد).
    final operations = <String,
        (
          void Function(ExamWizardController)?,
          void Function(ExamWizardController)
        )>{
      'تحرير منطوق الفرع':
          (null, (c) => c.updateBranchStatement(essayRef, 'منطوق معدل')),
      'تحرير نص الفرع': (null, (c) => c.updateBranchBody(essayRef, 'نص معدل')),
      'تحرير منطوق السؤال': (null, (c) => c.updateQuestionStatement(0, 'منطوق معدل')),
      'تحرير نص السؤال': (null, (c) => c.updateQuestionBody(0, 'متن معدل')),
      'عريض':
          (null, (c) => c.updateQuestionStyle(0, const PaperTextStyle(bold: true))),
      'محاذاة السؤال': (null,
          (c) => c.updateQuestionStyle(1, const PaperTextStyle(align: PaperAlign.center))),
      'حجم خط الفرع': (null,
          (c) => c.updateBranchStyle(essayRef, const PaperTextStyle(fontSize: 14))),
      'خط الفرع': (null,
          (c) => c.updateBranchStyle(essayRef, const PaperTextStyle(font: PaperFont.tajawal))),
      'لون عنوان السؤال':
          (null, (c) => c.updateQuestionTitleColor(0, 0xFF112233)),
      'محاذاة المتن':
          (null, (c) => c.updateQuestionBodyAlign(0, PaperAlign.left)),
      'محاذاة العنوان':
          (null, (c) => c.updateQuestionTitleAlign(0, PaperAlign.center)),
      'درجة السؤال': (null, (c) => c.updateQuestionMarksOverride(0, 12)),
      'تسمية السؤال': (null, (c) => c.updateQuestionNumberOverride(0, 'س1')),
      'نوع نقطة السؤال':
          (null, (c) => c.updatePointKind(questionOwner, 'qi1', PointKind.trueFalse)),
      'قسم السؤال': (null, (c) => c.updateQuestionCategory(0, 'القسم الأول')),
      'إطار السؤال': (null, (c) => c.toggleQuestionFrame(0)),
      'فاصل بعد السؤال':
          (null, (c) => c.setQuestionDivider(0, const PaperDivider(thickness: 2))),
      'إضافة سؤال': (null, (c) => c.addQuestion()),
      'تكرار سؤال': (null, (c) => c.duplicateQuestion(0)),
      'حذف سؤال': (null, (c) => c.removeQuestion(1)),
      'نقل سؤال': (null, (c) => c.moveQuestion(0, 1)),
      'تباعد الأسئلة': (null, (c) => c.updateQuestionSpacing(0, 40)),
      'إضافة نقطة سؤال': (null, (c) => c.addPoint(questionOwner)),
      'تعديل نقطة سؤال':
          (null, (c) => c.updatePointText(questionOwner, 'qi1', 'نقطة معدّلة')),
      'تسمية نقطة سؤال': (null, (c) => c.updatePointLabel(questionOwner, 'qi1', 'أ')),
      'درجة نقطة سؤال':
          (null, (c) => c.updatePointMarks(questionOwner, 'qi1', 1.5)),
      'حذف نقطة سؤال': (null, (c) => c.removePoint(questionOwner, 'qi1')),
      'إضافة فرع': (null, (c) => c.addBranch(0)),
      'حذف فرع': (
        null,
        (c) => c.removeBranch(const BranchRef(questionIndex: 0, branchIndex: 1)),
      ),
      'تكرار فرع': (null, (c) => c.duplicateBranch(essayRef)),
      'نقل فرع': (null, (c) => c.moveBranch(0, 0, 1)),
      'تبديل محتوى فرعين': (null, (c) => c.swapBranchContent(essayRef, mcqRef)),
      'درجة فرع': (null, (c) => c.updateBranchMarks(essayRef, 7.5)),
      'تسمية فرع': (null, (c) => c.updateBranchLabelOverride(essayRef, 'أولاً')),
      'نوع نقطة فرع':
          (null, (c) => c.updatePointKind(mcqOwner, 'bi-mcq', PointKind.trueFalse)),
      'إضافة خيار': (null, (c) => c.addPointOption(mcqOwner, 'bi-mcq')),
      'نص خيار':
          (null, (c) => c.updatePointOptionText(mcqOwner, 'bi-mcq', 1, 'خيار معدل')),
      'تسمية خيار':
          (null, (c) => c.updatePointOptionLabel(mcqOwner, 'bi-mcq', 0, '-')),
      'إضافة نقطة فرع': (null, (c) => c.addPoint(tfOwner)),
      'تعديل نقطة فرع':
          (null, (c) => c.updatePointText(tfOwner, 'bi1', 'نقطة فرع معدّلة')),
      'تسمية نقطة فرع': (null, (c) => c.updatePointLabel(tfOwner, 'bi1', 'أ')),
      'درجة نقطة فرع': (null, (c) => c.updatePointMarks(tfOwner, 'bi2', 1.5)),
      'حذف نقطة فرع': (null, (c) => c.removePoint(tfOwner, 'bi2')),
      'اسم المدرسة': (
        null,
        (c) => updateHeader(c, (h) => h.copyWith(schoolName: 'مدرسة النجاح')),
      ),
      'نوع الامتحان': (
        null,
        (c) => updateHeader(c, (h) => h.copyWith(examType: 'نهاية السنة')),
      ),
      'الدور الامتحاني': (
        null,
        (c) => updateHeader(c, (h) => h.copyWith(session: ExamSession.second)),
      ),
      'تنسيق الترويسة':
          (null, (c) => c.updateHeaderStyle(const PaperTextStyle(bold: true))),
      'المادة': (null, (c) => c.updateSubject('الرياضيات')),
      'اسم الورقة': (null, (c) => c.updateName('اسم جديد')),
      'إضافة عنصر عائم': (null, addFreeElement),
      'تحديث عنصر عائم': (
        addFreeElement,
        (c) {
          final element = c.document.floatingElementById('free-1')!;
          c.updateFloatingElement(element.copyWith(dx: element.dx + 12));
        },
      ),
      'تدوير عنصر عائم': (
        addFreeElement,
        (c) {
          final element = c.document.floatingElementById('free-1')!;
          c.updateFloatingElement(element.copyWith(rotationDegrees: 45));
        },
      ),
      'حذف عنصر عائم': (
        addFreeElement,
        (c) => c.removeFloatingElement('free-1'),
      ),
    };

    expect(operations.length, greaterThanOrEqualTo(30),
        reason: 'مصفوفة التراجع يجب أن تغطي 30 عملية موثقة على الأقل.');

    for (final MapEntry(:key, :value) in operations.entries) {
      final (setup, operation) = value;
      final controller = ExamWizardController(document: _document());
      setup?.call(controller);
      final baseline = _snapshot(controller);
      operation(controller);
      final applied = _snapshot(controller);
      expect(_firstDiff(applied, baseline), isNotNull,
          reason: 'AUD-UR-01 [$key]: العملية لم تغيّر المستند إطلاقاً.');

      controller.undo();
      expect(_firstDiff(_snapshot(controller), baseline), isNull,
          reason:
              'AUD-UR-01 [$key]: التراجع لم يُرجع المستند كما كان قبل العملية.');

      controller.redo();
      expect(_firstDiff(_snapshot(controller), applied), isNull,
          reason: 'AUD-UR-01 [$key]: الإعادة لم تُعيد نتيجة العملية حرفياً.');
    }
  });

  test('AUD-UR-02: تراجع جديد يمسح تاريخ الإعادة (redo) بالكامل', () {
    final controller = ExamWizardController(document: _document());
    const BranchRef ref = BranchRef(questionIndex: 0, branchIndex: 0);
    controller.updateBranchStatement(ref, 'الأولى');
    controller.updateQuestionStatement(0, 'متن السؤال');
    controller.undo();
    expect(controller.canRedo, isTrue);

    controller.updateQuestionSpacing(1, 33);
    expect(controller.canRedo, isFalse,
        reason: 'AUD-UR-02: تغيير جديد بعد التراجع يجب أن يمسح تاريخ الإعادة.');
    final before = _snapshot(controller);
    controller.redo();
    expect(_snapshot(controller), before,
        reason: 'AUD-UR-02: redo() بعد مسح التاريخ يجب أن يكون بلا أثر.');
  });

  test('AUD-UR-03: دفعة كتابة متصلة تُراجع بخطوة واحدة وcheckpoint يفصلها', () {
    final controller = ExamWizardController(document: _document());
    const BranchRef ref = BranchRef(questionIndex: 0, branchIndex: 0);
    final baseline = _snapshot(controller);

    controller.updateBranchStatement(ref, 'ن');
    controller.updateBranchStatement(ref, 'نص ');
    controller.updateBranchStatement(ref, 'نص جديد');
    expect(_firstDiff(_snapshot(controller), baseline), isNotNull);
    controller.undo();
    expect(_firstDiff(_snapshot(controller), baseline), isNull,
        reason:
            'AUD-UR-03: دفعة الكتابة المتصلة يجب أن تُراجع بخطوة تراجع واحدة.');

    controller.redo();
    expect(_snapshot(controller).contains('نص جديد'), isTrue);

    // checkpoint (فقدان التركيز) يفصل دفعة التالية كخطوة مستقلة.
    controller.checkpoint();
    controller.updateBranchStatement(ref, 'بعد نقطة توقف');
    controller.undo();
    expect(_snapshot(controller).contains('نص جديد'), isTrue,
        reason: 'AUD-UR-03: بعد checkpoint يجب أن يُراجع النص الجديد وحده دون '
            'محو ما قبله.');
  });

  testWidgets(
      'AUD-UR-04: تنسيق تحديد متعدد يُراجع بخطوة تراجع واحدة (سلوك MSO)',
      (tester) async {
    final controller = ExamWizardController(document: _document());
    await _pump(tester, controller);
    await _tap(tester, _tool('تحديد متعدد'));
    await _tap(tester, _field('statement-q1'));
    await _tap(tester, _field('statement-q2'));
    await _tap(tester, _tool('مائل'));
    expect(controller.questions.every((q) => q.style.italic == true), isTrue);

    await _tap(tester, _tool('تراجع'));
    expect(
      controller.questions.every((q) => q.style.italic != true),
      isTrue,
      reason: 'AUD-UR-04: تطبيق تنسيق واحد على تحديد متعدد = إجراء واحد في '
          'Word؛ تراجع واحد يجب أن يُزيل التنسيق عن كل الأهداف.',
    );
  });

  testWidgets(
      'AUD-UR-05: تراجع واحد يُزيل المحاذاة كاملةً (نقرة = خطوة تراجع واحدة)',
      (tester) async {
    final controller = ExamWizardController(document: _document());
    await _pump(tester, controller);
    await _tap(tester, _field('statement-q1'));
    await _tap(tester, _tool('محاذاة لليسار'));
    // «منطوق السؤال» سطر عنوان: محاذاته تُحفظ في titleAlign.
    expect(controller.questions.first.titleAlign, PaperAlign.left);

    await _tap(tester, _tool('تراجع'));
    expect(
      controller.questions.first.titleAlign,
      isNull,
      reason: 'AUD-UR-05: نقرة محاذاة واحدة تُراجَع بخطوة واحدة.',
    );
  });

  testWidgets(
      'AUD-UR-06: بعد تراجع المحاذاة يعود شكل الفرع للافتراضي (لا بقايا خريطة)',
      (tester) async {
    final controller = ExamWizardController(document: _document());
    await _pump(tester, controller);
    await _tap(tester, _field('branch-statement-b1'));
    await _tap(tester, _tool('توسيط'));
    expect(
        controller.questions.first.branches.first.style.align, PaperAlign.center);

    _rewindToolbar(tester);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(PreviewToolbar),
        matching: find.byTooltip('تراجع'),
      ),
      findsOneWidget,
      reason: 'AUD-UR-06: زر التراجع غير موجود بعد إعادة تمرير الشريط إلى أوله.',
    );
    await _tap(tester, _tool('تراجع'));
    expect(controller.questions.first.branches.first.style.align, isNull,
        reason: 'الموديل تراجع — السؤال هنا هو الشكل المعروض.');

    final shown =
        tester.widget<TextField>(_field('branch-statement-b1')).textAlign;
    expect(
      shown,
      TextAlign.start,
      reason: 'AUD-UR-06: بعد التراجع يجب أن يعود شكل الفرع إلى المحاذاة '
          'الافتراضية (قراءة المحاذاة من الموديل لا من خريطة محلية).',
    );
  });

  // ===========================================================================
  // المحاذاة: حفظ في الموديل + شكل نهائي
  // ===========================================================================
  testWidgets('AUD-ALIGN-OPT-01: محاذاة خيار MCQ تُحفظ في الموديل والتصدير',
      (tester) async {
    final controller = ExamWizardController(document: _document());
    await _pump(tester, controller);
    await _tap(tester, _field('option-bi-mcq-0'));
    await _tap(tester, _tool('توسيط'));
    final shown =
        tester.widget<TextField>(_field('option-bi-mcq-0')).textAlign;
    expect(shown, TextAlign.center, reason: 'الشاشة: الخيار يبدو منسّقاً.');

    // ما يقرأه المصدّران (PDF/Word) هو محاذاة الخيار في الموديل.
    final exported = controller
        .document
        .branchAt(const BranchRef(questionIndex: 0, branchIndex: 1))
        .content
        .items
        .single
        .options
        .first
        .align;
    expect(
      exported,
      PaperAlign.center,
      reason: 'AUD-ALIGN-OPT-01: محاذاة الخيار لم تُحفظ في خيار الموديل — '
          'فيفقدها التصدير وإعادة الفتح.',
    );
  });

  testWidgets('AUD-ALIGN-HDR-01: محاذاة الترويسة تُحفظ في الموديل', (tester) async {
    final controller = ExamWizardController(document: _document());
    await _pump(tester, controller);
    await _tap(tester, find.byType(PaperHeaderView));
    await _tap(tester, _tool('توسيط'));
    expect(
      controller.document.header.style.align,
      PaperAlign.center,
      reason: 'AUD-ALIGN-HDR-01: محاذاة الترويسة تصل إلى ExamHeaderModel '
          'وتظهر في PDF/Word.',
    );
  });

  testWidgets(
      'AUD-ALIGN-02: المحاذاة الأربع تُوجّه تخطيط الحقل مع نص مختلط وأرقام (RTL)',
      (tester) async {
    final controller = ExamWizardController(document: _document());
    await _pump(tester, controller);
    await tester.enterText(
      _field('branch-statement-b1'),
      'Mixed English نص مختلط 123.45، وترقيم (1) - نص.',
    );
    await tester.pumpAndSettle();
    await _tap(tester, _field('branch-statement-b1'));

    for (final entry in <String, TextAlign>{
      'محاذاة لليمين': TextAlign.right,
      'توسيط': TextAlign.center,
      'محاذاة لليسار': TextAlign.left,
      'ضبط': TextAlign.justify,
    }.entries) {
      await _tap(tester, _tool(entry.key));
      expect(
        tester.widget<TextField>(_field('branch-statement-b1')).textAlign,
        entry.value,
        reason: 'AUD-ALIGN-02: زر ${entry.key} لم يُوجّه تخطيط النص المختلط.',
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'AUD-JUSTIFY-01: ضبط سطر واحد لا يمدّده (Word لا تشدّ آخر سطر)',
      (tester) async {
    final controller = ExamWizardController(document: _document());
    await _pump(tester, controller);
    await tester.enterText(_field('branch-statement-b1'), 'نص قصير جداً');
    await tester.pumpAndSettle();
    await _tap(tester, _field('branch-statement-b1'));
    await _tap(tester, _tool('ضبط'));

    final style =
        tester.widget<TextField>(_field('branch-statement-b1')).style;
    final wordSpacing = style?.wordSpacing ?? 0;
    expect(
      wordSpacing,
      0.0,
      reason: 'AUD-JUSTIFY-01: أضاف وضع «ضبط» wordSpacing=$wordSpacing لسطر '
          'واحد، ومحرك PDF لا يمدّد السطر الأخير — الشاشة وحدها تنشئ انحرافاً.',
    );
  });

  // ===========================================================================
  // القفل — يمنع التحريك وحده ولا يعطّل الكتابة/التنسيق/الحفظ
  // ===========================================================================
  testWidgets('AUD-LOCK-01: القفل يمنع السحب ويسمح بالكتابة والتنسيق والحفظ',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final library = ExamDocumentProvider();
    final controller = ExamWizardController(document: _document());
    controller.addQuestionAttachment(
      FloatingElement(
        id: 'lock-shape',
        type: FloatingElementType.shape,
        shape: FloatingShapeType.square,
        dx: 120,
        dy: 300,
        width: 70,
        height: 70,
      ),
      questionIndex: 0,
    );
    await _pump(tester, controller, library: library);

    Future<void> dragElement() async {
      final target = find.byKey(const ValueKey('page-element-lock-shape'));
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(tester.getCenter(target));
      await tester.pump();
      await gesture.moveBy(const Offset(24, 10));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
    }

    FloatingElement element() => controller.document.floatingElementById('lock-shape')!;
    final startX = element().dx;
    await dragElement();
    expect(element().dx, isNot(startX),
        reason: 'قبل القفل: السحب المباشر يجب أن يحرّك الشكل.');

    await _tap(tester, _tool('قفل التحريك'));
    final lockedX = element().dx;
    final lockedY = element().dy;
    await dragElement();
    expect(element().dx, lockedX,
        reason: 'AUD-LOCK-01: الشكل تحرّك أثناء القفل — القفل يجب أن يمنع '
            'التحريك فقط لا كل شيء.');
    expect(element().dy, lockedY);

    // الكتابة والتنسيق والحفظ تعمل مقفلة (القفل للمتحرك لا للتحرير).
    await tester.enterText(_field('branch-statement-b1'), 'نص أثناء القفل');
    await tester.pumpAndSettle();
    expect(controller.questions.first.branches.first.content.statement,
        'نص أثناء القفل');
    await _tap(tester, _tool('عريض'));
    expect(controller.questions.first.branches.first.style.bold, isTrue);

    await _tap(tester, _tool('حفظ'));
    expect(
      library.documents.single.questions.first.branches.first.content.statement,
      'نص أثناء القفل',
      reason: 'AUD-LOCK-01: الحفظ أثناء القفل يجب أن يعمل.',
    );

    // زر فتح القفل في مطلع الشريط؛ نعيد الشريط إلى بدايته فيُبنى الزر أولاً.
    _rewindToolbar(tester);
    await tester.pumpAndSettle();
    await _tap(tester, _tool('فتح القفل (السماح بالتحريك)'));
    final unlockX = element().dx;
    await dragElement();
    expect(element().dx, isNot(unlockX));
    expect(tester.takeException(), isNull);
  });

  // ===========================================================================
  // العمليات بلا أثر جانبي (viewport/مراجعات)
  // ===========================================================================
  testWidgets('AUD-NOFX-01: التكبير/الملاءمة/التوسيط/زر 100% يؤثر في العرض فقط',
      (tester) async {
    final controller = ExamWizardController(document: _document());
    await _pump(tester, controller);
    final before = _snapshot(controller);
    final undoBefore = controller.canUndo;
    final redoBefore = controller.canRedo;

    await _tap(tester, _tool('تكبير'));
    await _tap(tester, _tool('تصغير'));
    await _tap(tester, _tool('ملاءمة الورقة للشاشة'));
    await _tap(tester, _tool('توسيط الورقة'));
    await _tap(tester, _tool('نسبة التكبير — انقر للعودة إلى 100%'));

    expect(_snapshot(controller), before,
        reason: 'AUD-NOFX-01: أزرار التكبير غيّرت المستند — المفروض العرض فقط.');
    expect(controller.canUndo, undoBefore);
    expect(controller.canRedo, redoBefore);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'AUD-NOFX-02: المراجعات وشريط الصيغ وإعدادات(إلغاء) بلا أثر على المستند',
      (tester) async {
    final controller = ExamWizardController(document: _document());
    await _pump(tester, controller);
    final before = _snapshot(controller);
    final undoBefore = controller.canUndo;

    // لا وجود لأي زر يبدّل إلى «نموذج الإجابة» — التطبيق لكتابة الأسئلة.
    expect(find.byTooltip('عرض نموذج الإجابة'), findsNothing);
    expect(find.byTooltip('عرض ورقة الطالب'), findsNothing);
    await _tap(tester, _tool('شريط الصيغ والوسائط'));
    await _tap(tester, _tool('شريط الصيغ والوسائط'));
    await _tap(tester, _tool('مراجعة وتصدير PDF'));
    expect(find.text('مراجعة الورقة'), findsOneWidget);
    await _tap(tester, find.text('رجوع'));
    await _tap(tester, _tool('مراجعة وتصدير Word'));
    expect(find.text('مراجعة الورقة'), findsOneWidget);
    await _tap(tester, find.text('رجوع'));
    await _tap(tester, find.byTooltip('إعدادات الورقة'));
    await _tap(tester, find.text('إلغاء'));

    expect(_snapshot(controller), before,
        reason: 'AUD-NOFX-02: عمليات عرض/معاينة عدّلت المستند.');
    expect(controller.canUndo, undoBefore,
        reason: 'AUD-NOFX-02: فتح المراجعات/الإعدادات(إلغاء) خلقت خطوة تراجع.');
    expect(tester.takeException(), isNull);
  });

  // ===========================================================================
  // العناصر العائمة: التدوير والمحاذاة ونسبة الأبعاد
  // ===========================================================================
  testWidgets('AUD-ROT-01: 8 نقرات تدوير تعبر 45°…315° ثم العودة لـ0 داخل الجلسة',
      (tester) async {
    final controller = ExamWizardController(document: _document());
    controller.addQuestionAttachment(
      FloatingElement(
        id: 'rot-shape',
        type: FloatingElementType.shape,
        shape: FloatingShapeType.circle,
        dx: 200,
        dy: 340,
        width: 60,
        height: 60,
      ),
      questionIndex: 0,
    );
    await _pump(tester, controller);
    await _tap(tester, find.byKey(const ValueKey('page-element-rot-shape')));

    final seen = <double>[];
    for (var i = 0; i < 8; i++) {
      await _tap(tester, find.byKey(const ValueKey('rotate-element-rot-shape')));
      seen.add(controller.document.floatingElementById('rot-shape')!.rotationDegrees);
    }
    expect(seen, <double>[45, 90, 135, 180, 225, 270, 315, 0],
        reason: 'AUD-ROT-01: دورة التدوير داخل الجلسة يجب أن تمر كل زوايا 45°.');
    expect(tester.takeException(), isNull);
  });

  test('AUD-ROT-02: زاوية 225°/270°/315° تبقى كما هي بعد الحفظ وإعادة الفتح', () {
    final drifted = <String>[];
    for (final angle in <double>[45, 90, 135, 180, 225, 270, 315, -45, -90]) {
      final document = ExamDocument(
        name: 'تدوير',
        header: ExamHeaderModel.initial(subject: 'اللغة العربية'),
        floatingElements: <FloatingElement>[
          FloatingElement(
            id: 'r',
            type: FloatingElementType.shape,
            shape: FloatingShapeType.square,
            dx: 100,
            dy: 100,
            width: 60,
            height: 60,
            rotationDegrees: angle,
          ),
        ],
      );
      final restored = ExamDocument.fromMap(
        jsonDecode(jsonEncode(document.toMap())) as Map<String, dynamic>,
      );
      final restoredAngle = restored.floatingElements.single.rotationDegrees;
      if (restoredAngle != angle) {
        drifted.add('$angle° → $restoredAngle°');
      }
    }
    expect(
      drifted,
      isEmpty,
      reason: 'AUD-ROT-02: زوايا الدوران تغيرت بعد حفظ/إعادة فتح: '
          '${drifted.join('، ')}.',
    );
  });

  testWidgets(
      'AUD-ELEM-01: محاذاة العنصر داخل الهامش ونسبة الصورة ثابتة مع التكبير',
      (tester) async {
    final controller = ExamWizardController(document: _document());
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
    );
    controller.addFloatingElement(FloatingElement(
      id: 'img-1',
      type: FloatingElementType.image,
      bytes: Uint8List.fromList(bytes),
      dx: 300,
      dy: 400,
      width: 160,
      height: 80,
    ));
    await _pump(tester, controller);
    await _tap(tester, find.byKey(const ValueKey('page-element-img-1')));

    await _tap(tester, find.byTooltip('محاذاة لليمين').last);
    expect(
      controller.document.floatingElements.single.dx,
      closeTo(ExamCanvasGeometry.margin, 0.01),
      reason: 'AUD-ELEM-01: في RTL يجب أن تحاذي «لليمين» العنصر مع هامش '
          'الطباعة لا مع حافة اللوحة.',
    );
    await _tap(tester, find.byTooltip('محاذاة لليسار').last);
    expect(
      controller.document.floatingElements.single.dx,
      closeTo(
        ExamCanvasGeometry.width -
            ExamCanvasGeometry.margin -
            controller.document.floatingElements.single.width,
        0.01,
      ),
    );
    await _tap(tester, find.byTooltip('محاذاة للأعلى').last);
    expect(
      controller.document.floatingElements.single.dy,
      closeTo(ExamCanvasGeometry.margin, 0.01),
    );

    final before = controller.document.floatingElements.single;
    final ratioBefore = before.width / before.height;
    await _tap(tester, find.byTooltip('تكبير العنصر'));
    await _tap(tester, find.byTooltip('تكبير العنصر'));
    final after = controller.document.floatingElements.single;
    expect(after.width, closeTo(before.width * 1.1 * 1.1, 0.01));
    expect(after.width / after.height, closeTo(ratioBefore, 1e-9),
        reason: 'AUD-ELEM-01: تكبير الصورة يجب أن يحافظ على نسبة الأبعاد.');
    expect(tester.takeException(), isNull);
  });

  // ===========================================================================
  // تكرار الأسئلة/الفروع — استقلالية التحرير
  // ===========================================================================
  test('AUD-DUP-01: تكرار السؤال نسخة مستقلة — تعديل النسخة لا يمس الأصل', () {
    final controller = ExamWizardController(document: _document());
    final originalBefore =
        jsonEncode(controller.document.questions.first.toMap());
    controller.duplicateQuestion(0);
    expect(controller.questions.length, 3);

    const copy = 1;
    final copyPointId =
        controller.pointsOf(const PointsOwner.question(copy)).single.id;
    controller.updateQuestionStatement(copy, 'متن النسخة');
    controller.updateQuestionStyle(copy, const PaperTextStyle(bold: true));
    controller.updateQuestionNumberOverride(copy, 'ن1');
    controller.updateBranchStatement(
        const BranchRef(questionIndex: copy, branchIndex: 0), 'فرع النسخة');
    controller.updateBranchLabelOverride(
        const BranchRef(questionIndex: copy, branchIndex: 0), 'أ');
    controller.updatePointText(
        const PointsOwner.question(copy), copyPointId, 'نقطة النسخة');

    expect(jsonEncode(controller.document.questions.first.toMap()),
        originalBefore,
        reason: 'AUD-DUP-01: تعديل نسخة السؤال غيّر الأصل — النسخة غير مستقلة.');

    controller.updateQuestionStatement(0, 'متن الأصل');
    expect(controller.questions[copy].statement, 'متن النسخة');
    expect(
      controller.document.questions[0].id,
      isNot(controller.document.questions[copy].id),
    );
    expect(
      controller.document.questions[0].branches[0].id,
      isNot(controller.document.questions[copy].branches[0].id),
      reason: 'AUD-DUP-01: الفروع داخل النسخة يجب أن تحمل معرّفات جديدة.',
    );
  });

  test('AUD-DUP-02: تكرار الفرع نسخة مستقلة والتسمية اليدوية تنتقل معها', () {
    final controller = ExamWizardController(document: _document());
    const ref = BranchRef(questionIndex: 0, branchIndex: 0);
    controller.updateBranchLabelOverride(ref, 'أولاً');
    controller.updateBranchStatement(ref, 'نص الأصل');
    final originalBefore = jsonEncode(controller.document.branchAt(ref).toMap());

    controller.duplicateBranch(ref);
    expect(controller.questions.first.branches.length, 3);

    const copyRef = BranchRef(questionIndex: 0, branchIndex: 1);
    controller.updateBranchStatement(copyRef, 'نص النسخة');
    controller.updateBranchMarks(copyRef, 9);
    expect(jsonEncode(controller.document.branchAt(ref).toMap()), originalBefore,
        reason: 'AUD-DUP-02: تعديل الفرع المكرر غيّر الأصل.');
    expect(controller.document.branchAt(copyRef).labelOverride, 'أولاً',
        reason: 'AUD-DUP-02: التسمية اليدوية تنتقل مع النسخة.');
  });

  test('AUD-DUP-03: العنصر الحر مستندي مشترك — حذف السؤال لا يحذفه', () {
    final controller = ExamWizardController(document: _document());
    controller.addQuestionAttachment(
      FloatingElement(
        id: 'global-shape',
        type: FloatingElementType.shape,
        shape: FloatingShapeType.square,
        dx: 100,
        dy: 700,
        width: 60,
        height: 60,
      ),
      questionIndex: 0,
    );
    final elementCount = controller.document.floatingElements.length;
    expect(elementCount, 1);

    controller.duplicateQuestion(0);
    expect(controller.document.floatingElements.length, elementCount,
        reason: 'AUD-DUP-03: تكرار السؤال لا يضاعف العنصر الحر المستندي.');
    expect(controller.document.questions[1].attachments, isEmpty,
        reason: 'مرآة المرفق القديمة لا تُنسخ لتصبح مالكاً ثانياً للعنصر الحر.');

    controller.removeQuestion(0);
    expect(controller.document.floatingElements.length, elementCount,
        reason: 'AUD-DUP-03: حذف السؤال يجب ألّا يحذف العنصر الحر.');
    expect(controller.document.floatingElementById('global-shape'), isNotNull);
  });

  // ===========================================================================
  // أنواع النقاط، الخيارات، النقاط، الفواصل، الترويسة
  // ===========================================================================
  test('AUD-TYPE-01: نوع النقطة يقرر طريقة الطباعة ولا يمس النص المخزَّن', () {
    final controller = ExamWizardController(document: _document());
    final owner = PointsOwner.branch(const BranchRef(questionIndex: 0, branchIndex: 1));
    final pointId = controller.pointsOf(owner).single.id;
    expect(controller.pointsOf(owner).single.options, hasLength(2));

    // تحويل النقطة إلى صح/خطأ: النص والخيارات تبقى مخزَّنة، والخيارات
    // تختفي من المخطط المطبوع (تُطبع لـ«اختيار من متعدد» وحده).
    controller.updatePointKind(owner, pointId, PointKind.trueFalse);
    final converted = controller.pointsOf(owner).single;
    expect(converted.text, 'سؤال الخيارات',
        reason: 'AUD-TYPE-01: نص النقطة يبقى كما هو عند تغيير النوع.');
    expect(converted.options, hasLength(2),
        reason: 'AUD-TYPE-01: الخيارات مخزَّنة مع النقطة لا تُحذف صامتة.');
    final blueprint = ExamBlueprint.from(controller.document);
    final printed = blueprint.questions.first.branches[1].points.single;
    expect(printed.item.kind, PointKind.trueFalse);
    expect(printed.options, isEmpty,
        reason: 'AUD-TYPE-01: لا تُطبع خيارات لغير «اختيار من متعدد».');

    // العودة إلى اختيار من متعدد تُعيد طباعة الخيارات نفسها.
    controller.updatePointKind(owner, pointId, PointKind.multipleChoice);
    expect(controller.pointsOf(owner).single.options, hasLength(2));
    final reprinted = ExamBlueprint.from(controller.document)
        .questions
        .first
        .branches[1]
        .points
        .single;
    expect(reprinted.options, hasLength(2));
    expect(reprinted.options.every((option) => option.label.isNotEmpty), isTrue);
  });

  testWidgets('AUD-TYPE-02: أنواع النقاط تعرض محتواها وبلا أي إجابة',
      (tester) async {
    final controller = ExamWizardController(document: _document());
    await _pump(tester, controller);

    // خيارات MCQ ظاهرة، وبلا أي سطح إجابة (نموذجية أو صح/خطأ أو خيار صحيح).
    expect(find.byKey(const ValueKey<String>('option-bi-mcq-0')), findsOneWidget,
        reason: 'MCQ: خانات الخيارات تظهر على الورقة.');
    expect(find.byKey(const ValueKey<String>('item-bi1')), findsOneWidget,
        reason: 'نقاط صح/خطأ تظهر كنقاط عادية.');
    expect(find.text('صح'), findsNothing,
        reason: 'لا تُكتب كلمة «صح» على الورقة في أي وضع.');
    expect(find.byTooltip('عرض نموذج الإجابة'), findsNothing);

    // التحول إلى صح/خطأ يُخفي خانات الخيارات من الورقة.
    final owner = PointsOwner.branch(const BranchRef(questionIndex: 0, branchIndex: 1));
    controller.updatePointKind(owner, 'bi-mcq', PointKind.trueFalse);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('option-bi-mcq-0')), findsNothing,
        reason: 'بعد التحول تختفي خيارات MCQ من الورقة (تُطبع للمتعدد وحده).');
    expect(tester.takeException(), isNull);
  });

  test('AUD-MCQ-01: دورة حياة الخيارات — إضافة/تعديل/إخفاء تسمية/حذف', () {
    final controller = ExamWizardController(document: _document());
    final owner = PointsOwner.branch(const BranchRef(questionIndex: 0, branchIndex: 1));
    expect(controller.pointsOf(owner).single.options, hasLength(2));

    controller.addPointOption(owner, 'bi-mcq');
    expect(controller.pointsOf(owner).single.options, hasLength(3));
    controller.updatePointOptionText(owner, 'bi-mcq', 2, 'خيار ثالث');
    expect(controller.pointsOf(owner).single.options[2].text, 'خيار ثالث');

    controller.updatePointOptionLabel(owner, 'bi-mcq', 1, '-');
    expect(
      controller.pointsOf(owner).single.options[1].labelOverride,
      '',
      reason: 'AUD-MCQ-01: علامة - تحفظ كإخفاء تام (\'\') لسمية الخيار دون حذفه.',
    );

    controller.removePointOption(owner, 'bi-mcq', 0);
    expect(controller.pointsOf(owner).single.options, hasLength(2));
  });

  test('AUD-PTS-01: النقاط تُعاد ترقيمها آلياً بعد الحذف مع بقاء التسميات المخصصة',
      () {
    final controller = ExamWizardController(document: _document());
    const ref = BranchRef(questionIndex: 1, branchIndex: 0);
    final owner = PointsOwner.branch(ref);
    controller.setPointCount(owner, 3);
    final ids = <String>[for (final point in controller.pointsOf(owner)) point.id];
    controller.updatePointText(owner, ids[0], 'الأولى');
    controller.updatePointText(owner, ids[1], 'الثانية');
    controller.updatePointText(owner, ids[2], 'الثالثة');
    controller.updatePointLabel(owner, ids[1], 'مخصص');

    controller.removePoint(owner, ids[0]);
    final items = controller.document.branchAt(ref).content.items;
    expect(items, hasLength(2));
    expect(
      controller.document.displayItemLabel(items[0], 0),
      'مخصص',
      reason: 'AUD-PTS-01: التسمية المخصصة تبقى على نقطتها ولا تُعاد ترقيمها.',
    );
    expect(
      controller.document.displayItemLabel(items[1], 1),
      controller.document.autoItemLabel(1),
      reason: 'بعد الحذف تعود التسمية التلقائية حسب الموقع الجديد.',
    );
  });

  testWidgets('AUD-DIV-01: الفاصل يُضاف ويتراجع ويعاد بالقياسات نفسها',
      (tester) async {
    final controller = ExamWizardController(document: _document());
    await _pump(tester, controller);
    expect(controller.document.questions.first.dividerAfter, isNull);

    await _tap(tester, _tool('إضافة فاصل'));
    final added = controller.document.questions.first.dividerAfter;
    expect(added, isNotNull);
    expect(added!.thickness, greaterThan(0));

    await _tap(tester, _tool('تراجع'));
    expect(controller.document.questions.first.dividerAfter, isNull,
        reason: 'AUD-DIV-01: التراجع يزيل الفاصل.');

    await _tap(tester, _tool('إعادة'));
    final redone = controller.document.questions.first.dividerAfter;
    expect(redone, isNotNull,
        reason: 'AUD-DIV-01: الإعادة تعيد الفاصل.');
    expect(redone!.thickness, added.thickness);
    expect(redone.widthFraction, added.widthFraction);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'AUD-HDR-01: حقول الترويسة الجديدة وتنسيقها تُحفظ بعد إعادة الفتح',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final library = ExamDocumentProvider();
    final controller = ExamWizardController(document: _document());
    await _pump(tester, controller, library: library);

    controller.updateHeader(
      controller.document.header.copyWith(
        schoolName: 'مدرسة النجاح',
        examType: 'نهاية السنة',
        session: ExamSession.third,
        grade: 'الثالث المتوسط',
        time: 'ساعتان',
      ),
    );
    await _tap(tester, find.byType(PaperHeaderView));
    await _tap(tester, _tool('نوع الخط'));
    await _tap(tester, find.textContaining(PaperFont.tajawal.arabicLabel).last);
    await _tap(tester, _tool('حفظ'));

    final reloaded = ExamDocumentProvider();
    await reloaded.loadDocuments();
    final doc = reloaded.documents.single;
    expect(doc.header.schoolName, 'مدرسة النجاح');
    expect(doc.header.examType, 'نهاية السنة');
    expect(doc.header.session, ExamSession.third);
    expect(doc.header.grade, 'الثالث المتوسط');
    expect(doc.header.time, 'ساعتان');
    expect(doc.header.style.font, PaperFont.tajawal,
        reason: 'AUD-HDR-01: تنسيق الترويسة (خط) يجب أن يبقى بعد الحفظ '
            'وإعادة الفتح، لا على الشاشة وحدها.');
    expect(tester.takeException(), isNull);
  });

  // ===========================================================================
  // المدخلات غير الصالحة
  // ===========================================================================
  testWidgets(
      'AUD-INVALID-01: قيم خارج النطاق تُreject برسالة خطأ ولا تغيّر الموديل',
      (tester) async {
    final controller = ExamWizardController(document: _document());
    const essayRef = BranchRef(questionIndex: 0, branchIndex: 0);
    await _pump(tester, controller);

    await _tap(tester, _field('branch-statement-b1'));
    await _applyCustomValue(tester, menuTooltip: 'حجم الخط', value: '0');
    expect(find.text('أدخل حجماً بين 6 و 32.'), findsOneWidget,
        reason: 'AUD-INVALID-01: حجم 0 يجب أن يُ rejected برسالة واضحة.');
    expect(controller.document.branchAt(essayRef).style.fontSize, isNull);
    await _settleSnackbars(tester);

    await _applyCustomValue(tester, menuTooltip: 'حجم الخط', value: '100');
    expect(find.text('أدخل حجماً بين 6 و 32.'), findsOneWidget);
    expect(controller.document.branchAt(essayRef).style.fontSize, isNull);
    await _settleSnackbars(tester);

    await _applyCustomValue(tester, menuTooltip: 'تباعد الأسطر', value: '10');
    expect(find.text('أدخل تباعداً بين 0.5 و 4.0.'), findsOneWidget);
    expect(controller.document.branchAt(essayRef).style.lineHeight, isNull);
    await _settleSnackbars(tester);

    await _applyCustomValue(
        tester, menuTooltip: 'المسافة بين الفقرات', value: '99');
    expect(find.text('أدخل مسافة بين 0 و 40 بكسل.'), findsOneWidget);
    expect(controller.document.branchAt(essayRef).style.paragraphSpacing, isNull);
    await _settleSnackbars(tester);

    // HEX غير صالح (حوار نصي بلا مانع إدخال).
    await _tap(tester, _tool('لون النص'));
    await _tap(tester, find.text('مخصص...').last);
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'XYZ123',
    );
    await _tap(tester, find.text('تطبيق'));
    expect(find.text('أدخل لون HEX صحيحاً (6 خانات مثل 1E3A8A).'), findsOneWidget,
        reason: 'AUD-INVALID-01: HEX غير صالح يجب أن يُ rejected.');
    expect(controller.document.branchAt(essayRef).style.color, isNull);
    await _settleSnackbars(tester);

    // مسافة أسئلة خارج النطاق.
    await _tap(tester, _field('statement-q1'));
    await _tap(tester, _tool('المسافة بين الأسئلة'));
    await _tap(tester, find.text('قيمة مخصصة...').last);
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      '999',
    );
    await _tap(tester, find.text('تطبيق'));
    expect(find.text('المسافة يجب أن تكون بين 0 و200 بكسل.'), findsOneWidget);
    expect(controller.questions.first.spacingAfter, 10,
        reason: 'AUD-INVALID-01: مسافة 999 يجب ألّا تُحفظ.');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'AUD-INVALID-02: درجة سالبة لا تُحفظ من حوار الدرجة الرقمي',
      (tester) async {
    final controller = ExamWizardController(document: _document());
    await _pump(tester, controller);

    // درجة الفرع b1 = 5 → «(٥ درجة)»؛ النقر عليها يفتح حوار الرقم الخام.
    await _tap(tester, find.text('(٥ درجة)'));
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      '-5',
    );
    await _tap(tester, find.text('تطبيق'));
    expect(
      controller.document
          .branchAt(const BranchRef(questionIndex: 0, branchIndex: 0))
          .marks,
      5,
      reason: 'AUD-INVALID-02: درجة سالبة لا تُطبَّق على الموديل.',
    );
    expect(find.text('أدخل الدرجة رقماً صحيحاً فقط (مثال: 5).'), findsOneWidget,
        reason: 'AUD-INVALID-02: إدخال غير صالح يُرفض برسالة واضحة.');
    await _settleSnackbars(tester);
    expect(tester.takeException(), isNull);
  });

  // ===========================================================================
  // الحفظ: دورة المستند الكاملة عبر JSON
  // ===========================================================================
  test('AUD-PERSIST-01: مستند مكتمل يعود مطابقاً حرفياً بعد حفظ/إعادة فتح', () {
    final document = ExamDocument(
      name: 'حفظ شامل',
      header: ExamHeaderModel.initial(subject: 'اللغة العربية').copyWith(
        schoolName: 'مدرسة النجاح',
        examType: 'نصف السنة',
        session: ExamSession.second,
        grade: 'الثالث المتوسط',
        time: 'ساعتان',
        style: const PaperTextStyle(
          font: PaperFont.tajawal,
          fontSize: 11,
          bold: true,
          underline: true,
          align: PaperAlign.center,
          lineHeight: 1.6,
          paragraphSpacing: 6,
          color: 0xFF1E3A8A,
        ),
      ),
      footer: const ExamFooterModel(
        closingPhrase: 'تمنياتنا لكم بالنجاح والتوفيق',
        primary: SignatureModel(title: SignatureTitle.lecturer, name: 'المدرس الأول'),
        secondary: SignatureModel(title: SignatureTitle.educator, name: 'المدرس الثاني'),
      ),
      questions: <QuestionModel>[
        QuestionModel(
          id: 'q1',
          questionNumber: 1,
          statement: 'منطوق السؤال',
          body: 'متن السؤال',
          bodyAlign: PaperAlign.right,
          titleAlign: PaperAlign.center,
          numberOverride: 'س1',
          marksOverride: 15,
          spacingAfter: 45,
          category: 'القسم الأول',
          style: const PaperTextStyle(
            font: PaperFont.amiri,
            fontSize: 13,
            italic: true,
            align: PaperAlign.left,
            lineHeight: 2.2,
            paragraphSpacing: 12,
            color: 0xFF15803D,
          ),
          showFrame: true,
          dividerAfter: const PaperDivider(thickness: 2, widthFraction: 0.5),
          items: <BranchItem>[
            BranchItem(
              id: 'i1',
              text: 'نقطة بدرجة',
              marks: 2,
              labelOverride: 'أ-',
              align: PaperAlign.center,
            ),
          ],
          branches: <BranchModel>[
            BranchModel(
              id: 'b1',
              marks: 4,
              labelOverride: 'أولاً',
              content: BranchContent(
                statement: 'اختر',
                body: 'نص الفرع',
                items: <BranchItem>[
                  BranchItem(
                    id: 'bi1',
                    kind: PointKind.multipleChoice,
                    text: 'سؤال الخيارات',
                    options: <QuestionOption>[
                      QuestionOption(text: 'صحيح', labelOverride: 'أ'),
                      QuestionOption(text: 'بديل', labelOverride: '-'),
                    ],
                  ),
                  BranchItem(id: 'bi2', kind: PointKind.trueFalse, text: 'عبارة'),
                ],
              ),
            ),
          ],
        ),
      ],
      floatingElements: <FloatingElement>[
        FloatingElement(
          id: 'img',
          type: FloatingElementType.image,
          bytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
          dx: 100.5,
          dy: 200.25,
          width: 150,
          height: 90,
          rotationDegrees: 90,
        ),
        FloatingElement(
          id: 'box',
          type: FloatingElementType.shape,
          shape: FloatingShapeType.textBox,
          dx: 300,
          dy: 400,
          width: 200,
          height: 100,
          rotationDegrees: -90,
          textStyle: const PaperTextStyle(
            font: PaperFont.rakkas,
            fontSize: 16,
            bold: true,
            align: PaperAlign.center,
            lineHeight: 1.3,
            paragraphSpacing: 4,
            color: 0xFFB91C1C,
          ),
        ),
      ],
    );

    final encoded = jsonEncode(document.toMap());
    final restored = ExamDocument.fromMap(
      jsonDecode(encoded) as Map<String, dynamic>,
    );
    expect(
      jsonEncode(restored.toMap()),
      encoded,
      reason: 'AUD-PERSIST-01: دورة حفظ/إعادة فتح كاملة غير محايدة — أحد '
          'الحقول (تنسيق/مسافات/عناصر/تسميات) يتغير أو يضيع.',
    );
  });

  // ===========================================================================
  // حالات فارغة واستقلالية الكيانات
  // ===========================================================================
  testWidgets('AUD-EMPTY-01: أنسجة فارغة تعرض تلميحات الكتابة بلا انهيار',
      (tester) async {
    final document = ExamDocument(
      name: 'فارغة',
      header: ExamHeaderModel.initial(subject: 'اللغة العربية'),
      questions: <QuestionModel>[
        QuestionModel(
          id: 'q1',
          questionNumber: 1,
          branches: <BranchModel>[
            BranchModel(id: 'b1', content: BranchContent.empty()),
          ],
        ),
      ],
    );
    final controller = ExamWizardController(document: document);
    await _pump(tester, controller);

    expect(find.text('اكتب منطوق الفرع هنا...'), findsOneWidget,
        reason: 'فرع فارغ يعرض تلميح الكتابة (لا شاشة بيضاء).');
    expect(find.byKey(const ValueKey<String>('branch-statement-b1')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('AUD-INDEP-01: تعديل كيان لا يمسّ كياناً آخر (أسئلة/فروع/عناصر)', () {
    final controller = ExamWizardController(document: _document());
    final q2Before = jsonEncode(controller.document.questions[1].toMap());
    final b2Before = jsonEncode(
      controller.document
          .branchAt(const BranchRef(questionIndex: 0, branchIndex: 1))
          .toMap(),
    );

    controller.updateQuestionStatement(0, 'متن معدّل');
    controller.updateQuestionStyle(0, const PaperTextStyle(fontSize: 18));
    controller.updateBranchStatement(
        const BranchRef(questionIndex: 0, branchIndex: 0), 'فرع معدّل');
    controller.addFloatingElement(FloatingElement(
      id: 'f1',
      type: FloatingElementType.shape,
      shape: FloatingShapeType.triangle,
      dx: 10,
      dy: 10,
      width: 50,
      height: 50,
    ));
    controller.addFloatingElement(FloatingElement(
      id: 'f2',
      type: FloatingElementType.shape,
      shape: FloatingShapeType.circle,
      dx: 60,
      dy: 60,
      width: 50,
      height: 50,
    ));
    final f1 = controller.document.floatingElementById('f1')!;
    controller.updateFloatingElement(f1.copyWith(dx: 999));

    expect(jsonEncode(controller.document.questions[1].toMap()), q2Before,
        reason: 'AUD-INDEP-01: تعديل السؤال الأول غيّر الثاني.');
    expect(
      jsonEncode(controller.document
          .branchAt(const BranchRef(questionIndex: 0, branchIndex: 1))
          .toMap()),
      b2Before,
      reason: 'AUD-INDEP-01: تعديل الفرع الأول غيّر فرع MCQ المجاور.',
    );
    expect(controller.document.floatingElementById('f2')!.dx, 60,
        reason: 'AUD-INDEP-01: تحريك عنصر عائم غيّر عنصراً آخر.');
  });
}
