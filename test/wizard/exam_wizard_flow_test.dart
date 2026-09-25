import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:writing_questions_app/layout/pagination_engine.dart';
import 'package:writing_questions_app/layout/paper_metrics.dart';
import 'package:writing_questions_app/models/branch_model.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_font.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/models/question_option.dart';
import 'package:writing_questions_app/models/question_type.dart';
import 'package:writing_questions_app/providers/exam_wizard_controller.dart';
import 'package:writing_questions_app/views/widgets/tex_text.dart';
import 'package:writing_questions_app/views/wizard/exam_preview_screen.dart';
import 'package:writing_questions_app/views/wizard/exam_wizard_screen.dart';

Widget _app(Widget home) {
  return Directionality(
    textDirection: TextDirection.rtl,
    child: MaterialApp(home: home),
  );
}

ExamDocument _previewDocument({int questionCount = 2, List<int>? branchesPerQuestion}) {
  return ExamDocument(
    name: 'معاينة',
    header: ExamHeaderModel.ministerialDefault(subject: 'اللغة العربية'),
    questions: <QuestionModel>[
      for (var q = 0; q < questionCount; q++)
        QuestionModel(
          id: 'q${q + 1}',
          questionNumber: q + 1,
          branches: <BranchModel>[
            for (var b = 0; b < (branchesPerQuestion?[q] ?? 2); b++)
              BranchModel(
                id: 'q${q + 1}${b == 0 ? 'a' : b == 1 ? 'b' : 'x$b'}',
                content: BranchContent(
                  type: QuestionType.essay,
                  text: 'محتوى س${q + 1} ${b == 0 ? 'أ' : b == 1 ? 'ب' : 'فرع ${b + 1}'}',
                ),
                marks: b == 0 ? q + 1.0 : 1,
              ),
          ],
        ),
    ],
  );
}

/// يجمع كل امتدادات النص ([TextSpan]) داخل شجرة [span] مهما تعمّقت.
///
/// لازمة لأن `Text.rich` يلفّ الامتداد المُمرَّر داخل جذر يحمل النمط العام،
/// فجمع الأبناء المباشرين وحده لا يصل إلى مقطع الآية.
List<TextSpan> _collectTextSpans(InlineSpan span) {
  final collected = <TextSpan>[];
  void visit(InlineSpan current) {
    if (current is! TextSpan) {
      return;
    }
    collected.add(current);
    for (final child in current.children ?? const <InlineSpan>[]) {
      visit(child);
    }
  }

  visit(span);
  return collected;
}

/// يتحقق أن كل سؤال معروض على صفحة واحدة فقط مع **كل** فروعه (لا فصل).
void _expectQuestionsUnsplit(ExamWizardController controller) {
  final pages = controller.pagination.pages;
  for (final question in controller.questions) {
    final pageIndex = controller.pagination.pageIndexOf(question.id);
    expect(pageIndex, isNotNull, reason: 'كل سؤال يجب أن يُسند إلى صفحة');
    final owners = pages.where((page) => page.blockIds.contains(question.id));
    expect(owners, hasLength(1), reason: 'السؤال ${question.id} يظهر في صفحة واحدة فقط');
    final page = find.byKey(ValueKey<String>('a4-page-$pageIndex'));
    expect(page, findsOneWidget);
    for (final branch in question.branches) {
      expect(
        find.descendant(of: page, matching: find.text(branch.content.text)),
        findsOneWidget,
        reason: 'فرع ${branch.id} يجب أن يكون على صفحة سؤاله ($pageIndex)',
      );
    }
  }
  // لا صفحة تتجاوز الارتفاع المتاح إلا إذا كانت كتلة منفردة أطول من الصفحة.
  for (final page in pages) {
    if (!page.overflows) {
      expect(page.usedHeight, lessThanOrEqualTo(PaperMetrics.pageContentHeightPx + 0.01));
    }
  }
}

Widget _preview(ExamWizardController controller) {
  return _app(
    ChangeNotifierProvider<ExamWizardController>.value(
      value: controller,
      child: ExamPreviewScreen(onBackToQuestions: () {}),
    ),
  );
}

void main() {
  group('Wizard step flow', () {
    testWidgets('walks header → first question → second question → preview', (tester) async {
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_app(const ExamWizardScreen()));

      // الخطوة 1: الترويسة بأعمدتها الثلاثة.
      expect(find.text('الخطوة 1: ترويسة النموذج الوزاري'), findsOneWidget);
      expect(find.text('العمود الأيمن'), findsOneWidget);
      expect(find.text('العمود الأوسط'), findsOneWidget);
      expect(find.text('العمود الأيسر'), findsOneWidget);

      await tester.ensureVisible(find.text('التالي: إعداد السؤال الأول'));
      await tester.tap(find.text('التالي: إعداد السؤال الأول'));
      await tester.pumpAndSettle();

      // الخطوة 2: العنوان ديناميكي ويبدأ بالفرع (أ).
      expect(find.text('إعداد السؤال الأول'), findsOneWidget);
      expect(find.text('الفرع (أ)'), findsOneWidget);

      // إضافة فرع جديد يضيف (ب) بنفس الأدوات.
      await tester.ensureVisible(find.textContaining('إضافة فرع جديد'));
      await tester.tap(find.textContaining('إضافة فرع جديد'));
      await tester.pumpAndSettle();
      expect(find.text('الفرع (ب)'), findsOneWidget);

      // بدون محتوى لا يُسمح بالمتابعة.
      await tester.tap(find.text('التالي: سؤال جديد'));
      await tester.pumpAndSettle();
      expect(find.text('إعداد السؤال الأول'), findsOneWidget);

      // كتابة محتوى ودرجة ثم [التالي] يفتح «إعداد السؤال الثاني».
      await tester.enterText(find.widgetWithText(TextFormField, 'نص الفرع').first, 'عرّف الفاعل');
      await tester.enterText(find.widgetWithText(TextFormField, 'الدرجة').first, '5');
      await tester.pumpAndSettle();
      await tester.tap(find.text('التالي: سؤال جديد'));
      await tester.pumpAndSettle();
      expect(find.text('إعداد السؤال الثاني'), findsOneWidget);
      expect(find.text('الفرع (أ)'), findsOneWidget);
      expect(find.text('الفرع (ب)'), findsNothing);

      // إنهاء وعرض النموذج من سؤال فارغ مرفوض، ومن السؤال الأول مقبول.
      await tester.tap(find.text('السؤال الأول'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('إنهاء وعرض النموذج'));
      await tester.pumpAndSettle();

      expect(find.textContaining('الخطوة 3: معاينة A4'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('a4-page-0')), findsOneWidget);
      expect(find.text('السؤال الأول: [٥ درجة]'), findsOneWidget);
    });
  });

  group('ExamPreviewScreen', () {
    testWidgets('measures blocks and paginates whole questions onto pages', (tester) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = ExamWizardController(document: _previewDocument(questionCount: 3));
      await tester.pumpWidget(_preview(controller));
      await tester.pump();
      await tester.pump();

      // كل الكتل قيست ديناميكياً عبر MeasureSize.
      expect(controller.isFullyMeasured, isTrue);
      expect(controller.blockHeight(PaperMetrics.headerBlockId), greaterThan(0));
      expect(controller.blockHeight('q1'), greaterThan(0));

      // التوزيع المعروض مطابق لما يحسبه محرك التقسيم من الارتفاعات نفسها.
      final expected = PaginationEngine.paginate(
        blocks: <PageBlock>[
          PageBlock(
            id: PaperMetrics.headerBlockId,
            height: controller.blockHeight(PaperMetrics.headerBlockId)!,
          ),
          for (final question in controller.questions)
            PageBlock(id: question.id, height: controller.blockHeight(question.id)!),
        ],
        pageHeight: PaperMetrics.pageContentHeightPx,
        spacing: PaperMetrics.blockSpacingPx,
      );
      expect(controller.pagination.pageCount, expected.pageCount);
      expect(find.byKey(const ValueKey<String>('a4-page-0')), findsOneWidget);
      expect(find.text('السؤال الأول: [٢ درجة]'), findsOneWidget);
      expect(find.text('السؤال الثالث: [٤ درجة]'), findsOneWidget);
      _expectQuestionsUnsplit(controller);
    });

    testWidgets('moves a question that no longer fits to the next page as a whole', (tester) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // سؤال قصير ثم سؤالان طويلان (8 فروع مقالية لكلٍّ منهما) — لا يتّسعان معاً.
      final controller = ExamWizardController(
        document: _previewDocument(questionCount: 3, branchesPerQuestion: <int>[2, 8, 8]),
      );
      await tester.pumpWidget(_preview(controller));
      await tester.pump();
      await tester.pump();
      // قد تُعاد القياسات بعد انتقال كتلة إلى صفحة جديدة؛ نستقر على النتيجة.
      await tester.pump();
      await tester.pump();

      expect(controller.isFullyMeasured, isTrue);
      final pagination = controller.pagination;
      expect(pagination.pageCount, greaterThanOrEqualTo(2));
      expect(pagination.pageIndexOf('q1'), 0);

      // أول كتلة في كل صفحة تالية لم تكن لتتسع في الصفحة السابقة — أي أنها
      // نُقلت كاملة بدل أن تُقسَّم.
      for (var index = 1; index < pagination.pageCount; index++) {
        final previous = pagination.pages[index - 1];
        final movedId = pagination.pages[index].blockIds.first;
        final movedHeight = controller.blockHeight(movedId)!;
        expect(
          previous.usedHeight + PaperMetrics.blockSpacingPx + movedHeight,
          greaterThan(PaperMetrics.pageContentHeightPx),
          reason: 'الكتلة $movedId نُقلت رغم أنها كانت تتسع في الصفحة ${index - 1}',
        );
      }
      _expectQuestionsUnsplit(controller);
    });

    testWidgets('in-place editing updates the model without leaving the sheet', (tester) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = ExamWizardController(document: _previewDocument(questionCount: 1));
      await tester.pumpWidget(_preview(controller));
      await tester.pump();

      await tester.enterText(find.text('محتوى س1 أ'), 'نص معدّل مباشرة');
      await tester.pump();

      expect(
        controller.document.branchAt(const BranchRef(questionIndex: 0, branchIndex: 0)).content.text,
        'نص معدّل مباشرة',
      );
    });

    testWidgets('drag & drop swaps branch content while headings stay in place', (tester) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = ExamWizardController(document: _previewDocument(questionCount: 2));
      await tester.pumpWidget(_preview(controller));
      await tester.pump();
      await tester.pump();

      final source = find.byKey(const ValueKey<String>('branch-target-q1a'));
      final target = find.byKey(const ValueKey<String>('branch-target-q2b'));
      expect(source, findsOneWidget);
      expect(target, findsOneWidget);

      // سحب بالضغط المطوّل من مقبض (السؤال الأول - أ) إلى (السؤال الثاني - ب).
      final handle = find.descendant(of: source, matching: find.byIcon(Icons.drag_indicator));
      expect(handle, findsOneWidget);
      final gesture = await tester.startGesture(tester.getCenter(handle));
      await tester.pump();
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
      final destination = tester.getCenter(target);
      await gesture.moveBy(const Offset(0, 10));
      await tester.pump();
      await gesture.moveTo(destination);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      const q1a = BranchRef(questionIndex: 0, branchIndex: 0);
      const q2b = BranchRef(questionIndex: 1, branchIndex: 1);
      expect(controller.document.branchAt(q1a).content.text, 'محتوى س2 ب');
      expect(controller.document.branchAt(q1a).marks, 1);
      expect(controller.document.branchAt(q2b).content.text, 'محتوى س1 أ');
      expect(controller.document.branchAt(q2b).marks, 1);
      expect(controller.document.branchAt(q1a).id, 'q1a');
      expect(controller.document.branchAt(q2b).id, 'q2b');

      // العناوين لم تتحرك، والحقول على الورقة تعكس المحتوى الجديد.
      expect(find.text('السؤال الأول: [٢ درجة]'), findsOneWidget);
      expect(find.text('السؤال الثاني: [٣ درجة]'), findsOneWidget);
      final firstField = tester.widget<TextField>(
        find.descendant(of: source, matching: find.byType(TextField)).first,
      );
      expect(firstField.controller!.text, 'محتوى س2 ب');
    });

    testWidgets('edits multiple-choice options and the ministry category in place', (tester) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = ExamWizardController(
        document: ExamDocument(
          name: 'خيارات',
          header: ExamHeaderModel.ministerialDefault(subject: 'التربية الإسلامية'),
          questions: <QuestionModel>[
            QuestionModel(
              id: 'q1',
              questionNumber: 1,
              category: 'أحكام التلاوة',
              branches: <BranchModel>[
                BranchModel(
                  id: 'q1a',
                  content: BranchContent(
                    type: QuestionType.multipleChoice,
                    text: 'اختر الإجابة الصحيحة',
                    options: <QuestionOption>[
                      QuestionOption(text: 'الخيار الأول', isCorrect: true),
                      QuestionOption(text: 'الخيار الثاني'),
                    ],
                  ),
                  marks: 2,
                ),
              ],
            ),
          ],
        ),
      );
      await tester.pumpWidget(_preview(controller));
      await tester.pump();

      // عنوان القسم الوزاري ونصوص الخيارات: نصوص قابلة للتحرير في مكانها.
      await tester.enterText(find.byKey(const ValueKey<String>('category-q1')), 'الحفظ');
      await tester.pump();
      expect(controller.document.questions.single.category, 'الحفظ');

      await tester.enterText(
        find.byKey(const ValueKey<String>('option-q1a-1')),
        'الخيار الثاني المعدّل',
      );
      await tester.pump();

      final options = controller.document
          .branchAt(const BranchRef(questionIndex: 0, branchIndex: 0))
          .content
          .options;
      expect(options[1].text, 'الخيار الثاني المعدّل');
      // علامة الإجابة الصحيحة لا تتغيّر بتحرير نص الخيار.
      expect(options[0].isCorrect, isTrue);
      expect(options[1].isCorrect, isFalse);
    });

    testWidgets('hides teacher answers in the student sheet and edits them in the answer view',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = ExamWizardController(document: _previewDocument(questionCount: 1));
      await tester.pumpWidget(_preview(controller));
      await tester.pump();

      const answerKey = ValueKey<String>('answer-q1a');
      expect(find.byKey(answerKey), findsNothing, reason: 'ورقة الطالب لا تُظهر الإجابة النموذجية');

      await tester.tap(find.byTooltip('عرض نموذج الإجابة'));
      await tester.pump();
      expect(find.byKey(answerKey), findsOneWidget);

      await tester.enterText(find.byKey(answerKey), 'إجابة نموذجية مفصّلة');
      await tester.pump();
      expect(
        controller.document
            .branchAt(const BranchRef(questionIndex: 0, branchIndex: 0))
            .content
            .modelAnswer,
        'إجابة نموذجية مفصّلة',
      );

      await tester.tap(find.byTooltip('عرض ورقة الطالب'));
      await tester.pump();
      expect(find.byKey(answerKey), findsNothing);
    });

    testWidgets('renders a Quranic verse with the Quranic font and centering', (tester) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = ExamWizardController(
        document: ExamDocument(
          name: 'تربية إسلامية',
          header: ExamHeaderModel.ministerialDefault(subject: 'التربية الإسلامية'),
          questions: <QuestionModel>[
            QuestionModel(
              id: 'q1',
              questionNumber: 1,
              branches: <BranchModel>[
                BranchModel(
                  id: 'q1a',
                  content: BranchContent(
                    type: QuestionType.essay,
                    text: '\uFD3F إنا أعطيناك الكوثر \uFD3E',
                  ),
                  marks: 3,
                ),
              ],
            ),
          ],
        ),
      );
      await tester.pumpWidget(_preview(controller));
      await tester.pump();

      final verseText = tester.widget<TexText>(find.byType(TexText));
      expect(verseText.textAlign, TextAlign.center, reason: 'الآية القائمة بذاتها تُوسَّط');
      expect(verseText.quranStyle?.fontFamily, ExamFont.quranicFamily);

      // المقطع القرآني المرسوم فعلاً يلبس الخط القرآني.
      final renderedSpans = <TextSpan>[
        for (final richText in tester.widgetList<RichText>(
          find.descendant(of: find.byType(TexText), matching: find.byType(RichText)),
        ))
          ..._collectTextSpans(richText.text),
      ];
      final verseSpans = renderedSpans
          .where((span) => span.text?.contains('\uFD3F') ?? false)
          .toList(growable: false);
      expect(verseSpans, isNotEmpty, reason: 'الآية تُعرض عرضاً منسّقاً على الورقة');
      for (final span in verseSpans) {
        expect(span.style?.fontFamily, ExamFont.quranicFamily);
      }
    });

    testWidgets('keeps the Quranic face in every template but centres only where preferred',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // قالب غير إسلامي (اللغة العربية): يُلبس الخط القرآني النصَّ الموسوم،
      // لكن «أسلوب المصحف» (التوسيط والتكبير) يبقى لقالب التربية الإسلامية.
      final controller = ExamWizardController(
        document: ExamDocument(
          name: 'لغة عربية',
          header: ExamHeaderModel.ministerialDefault(subject: 'اللغة العربية'),
          questions: <QuestionModel>[
            QuestionModel(
              id: 'q1',
              questionNumber: 1,
              branches: <BranchModel>[
                BranchModel(
                  id: 'q1a',
                  content: BranchContent(
                    type: QuestionType.essay,
                    text: '\uFD3F إنا أعطيناك الكوثر \uFD3E',
                  ),
                  marks: 3,
                ),
              ],
            ),
          ],
        ),
      );
      await tester.pumpWidget(_preview(controller));
      await tester.pump();

      final verseText = tester.widget<TexText>(find.byType(TexText));
      expect(verseText.textAlign, TextAlign.start,
          reason: 'قالب لا يفضّل الخط القرآني: بلا توسيط مصحفي');
      expect(verseText.quranStyle?.fontFamily, ExamFont.quranicFamily,
          reason: 'الخط القرآني يُلبس المقاطع الموسومة في كل القوالب');

      final renderedSpans = <TextSpan>[
        for (final richText in tester.widgetList<RichText>(
          find.descendant(of: find.byType(TexText), matching: find.byType(RichText)),
        ))
          ..._collectTextSpans(richText.text),
      ];
      final verseSpans = renderedSpans
          .where((span) => span.text?.contains('\uFD3F') ?? false)
          .toList(growable: false);
      expect(verseSpans, isNotEmpty, reason: 'الآية تُعرض عرضاً منسّقاً على الورقة');
      for (final span in verseSpans) {
        expect(span.style?.fontFamily, ExamFont.quranicFamily);
      }
    });

    testWidgets('exposes the floating tools toolbar above the pages', (tester) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = ExamWizardController(document: _previewDocument(questionCount: 1));
      await tester.pumpWidget(_preview(controller));
      await tester.pump();

      expect(find.text('وسائط'), findsOneWidget);
      expect(find.text('رياضيات'), findsOneWidget);

      // إضافة شكل بلا فرع محدد تُرشد المستخدم؛ وبعد التحديد يُثبَّت فوق الفرع.
      await tester.tap(find.text('وسائط'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('مربع'));
      await tester.pump();
      expect(find.textContaining('انقر على فرع داخل الورقة'), findsOneWidget);

      controller.selectBranch(const BranchRef(questionIndex: 0, branchIndex: 0));
      await tester.pump();
      await tester.tap(find.text('مربع'));
      await tester.pump();
      expect(
        controller.document
            .branchAt(const BranchRef(questionIndex: 0, branchIndex: 0))
            .attachments,
        hasLength(1),
      );
      expect(find.byType(CustomPaint), findsWidgets);
    });
  });
}
