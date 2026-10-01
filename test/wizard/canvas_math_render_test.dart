// اختبار «اللوحة تعرض المعادلة لا نصها»: كل حقل يقبل إدراج الصيغ يعرض
// المعادلة المُصيَّرة النهائية **في مكانه** (Math من flutter_math_fork — نفس
// محرك عرض المعادلات)، بنفس منطق التقطيع الذي يطبعه محرك الـ PDF. الحقل
// الذكي (PaperField) يُظهر المصدر الخام للتحرير وحده عند التركيز/النقر،
// وإلا العرض النهائي — بلا معاينة منفصلة فوق الحقل ولا تكرار للمصدر.
//
// يُتحقق عددياً: لكل مقطع `$...$`/`$$...$$` واحدٍ من Math بالضبط في الشجرة،
// وبغياب الصيغ لا شيء — أي أن العرض مشروط بالمحتوى لا أنه نسخة ثابتة.
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart' show Math;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:writing_questions_app/models/branch_item.dart';
import 'package:writing_questions_app/models/branch_model.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/models/question_option.dart';
import 'package:writing_questions_app/providers/exam_wizard_controller.dart';
import 'package:writing_questions_app/views/widgets/mixed_content_editor.dart';
import 'package:writing_questions_app/views/widgets/paper_field.dart';
import 'package:writing_questions_app/views/wizard/exam_preview_screen.dart';

ExamDocument _mathDoc() {
  return ExamDocument(
    name: 'لوحة',
    header: ExamHeaderModel(
      subject: 'الرياضيات',
      title: r'عنوان $\frac{5}{8}$',
      right: HeaderColumn(<String>[r'سطر $\sqrt{4}$', '', '']),
    ),
    questions: <QuestionModel>[
      QuestionModel(
        id: 'q1',
        questionNumber: 1,
        prompt: r'احسب $\frac{5}{8}$',
        branches: <BranchModel>[
          BranchModel(
            content: BranchContent(
              type: QuestionType.multipleChoice,
              text: r'اختر الأنسب $\frac{1}{2}$',
              items: <BranchItem>[
                BranchItem(text: r'نقطة $\times$'),
              ],
              options: <QuestionOption>[
                QuestionOption(text: r'أول $x^{2}$'),
                QuestionOption(text: r'ثانٍ $y_{3}$'),
              ],
            ),
            marks: 2,
          ),
          // فرع فراغات: نصه هو ما يُطبع — بلا أي إجابة.
          BranchModel(
            content: BranchContent(
              type: QuestionType.fillInTheBlank,
              text: 'أكمل الجمل التالية',
            ),
            marks: 1,
          ),
        ],
      ),
    ],
  );
}

Widget _preview(ExamWizardController controller) {
  return Directionality(
    textDirection: TextDirection.rtl,
    child: MaterialApp(
      home: ChangeNotifierProvider<ExamWizardController>.value(
        value: controller,
        child: ExamPreviewScreen(onBackToQuestions: () {}),
      ),
    ),
  );
}

Future<void> _pumpPreview(WidgetTester tester, ExamWizardController controller) async {
  tester.view.physicalSize = const Size(1000, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(_preview(controller));
  await tester.pump();
  await tester.pump();
}

double _scrollPixels(WidgetTester tester, String scrollerKey) {
  final scrollable = find
      .descendant(
        of: find.byKey(ValueKey<String>(scrollerKey)),
        matching: find.byType(Scrollable),
      )
      .first;
  return tester.state<ScrollableState>(scrollable).position.pixels;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('رسم المعادلات المرئي على لوحة العرض (A4)', () {
    testWidgets('كل حقل يقبل الصيغ يعرض المعادلة المُصيَّرة في مكانه (Math واحد لكل مقطع)', (tester) async {
      final controller = ExamWizardController(document: _mathDoc());
      await _pumpPreview(tester, controller);

      // عنوان الترويسة + سطر الترويسة + نص السؤال + نص الفرع + النقطة
      // + خياران = 7 معادلات مرسومة، ولا شيء غيرها (لا إجابة مطبوعة).
      expect(find.byType(Math), findsNWidgets(7));
    });

    testWidgets('بلا صيغ — لا معاينة ولا Math أصلاً (العرض مشروط بالمحتوى)', (tester) async {
      final controller = ExamWizardController(
        document: ExamDocument(
          name: 'عادي',
          header: ExamHeaderModel(subject: 'الرياضيات', title: 'عنوان عادي'),
          questions: <QuestionModel>[
            QuestionModel(
              questionNumber: 1,
              prompt: 'سؤال بلا رياضيات',
              branches: <BranchModel>[
                BranchModel(
                  content: BranchContent(type: QuestionType.essay, text: 'فرع عادي'),
                ),
              ],
            ),
          ],
        ),
      );
      await _pumpPreview(tester, controller);
      expect(find.byType(Math), findsNothing);
    });

    testWidgets('لا كود خام على الورقة: النقر يفتح محرر النص والمعادلات المرئي',
        (tester) async {
      final controller = ExamWizardController(document: _mathDoc());
      await _pumpPreview(tester, controller);

      const key = ValueKey<String>('prompt-q1');
      // غير مركّز: العرض النهائي المُصيَّر وحده — لا حقل نصي ظاهر على الورقة.
      expect(
        find.descendant(of: find.byKey(key), matching: find.byType(EditableText)),
        findsNothing,
      );
      // المصدر المخزَّن يبقى بصيغته القابلة للتحرير (نص + $معادلة$).
      expect(tester.widget<PaperField>(find.byKey(key)).controller.text,
          r'احسب $\frac{5}{8}$');

      // النقر على العرض النهائي يفتح محرر المحتوى المختلط: نص حقولاً
      // والمعادلة مرسومةً مرئية — لا كود LaTeX.
      await tester.tap(find.byKey(key));
      await tester.pump();
      await tester.pump();
      expect(find.text('تحرير المحتوى'), findsOneWidget);
      expect(find.text('إضافة معادلة'), findsOneWidget);
      expect(find.text('حفظ المحتوى'), findsOneWidget);
      // النص والمعادلة معروضان في المحرر (المعادلة مرسومة لا مكتوبة ككود).
      expect(
        find.descendant(
          of: find.byType(MixedContentEditor),
          matching: find.byType(Math),
        ),
        findsOneWidget,
      );

      // إلغاء: لا يتغير المصدر.
      await tester.tap(find.text('إلغاء'));
      await tester.pump();
      await tester.pump();
      expect(controller.questions.single.prompt, r'احسب $\frac{5}{8}$');
    });

    testWidgets('الحقول الاختيارية الفارغة لا تُبنى أصلاً (صفر بكسل لا إخفاء)', (tester) async {
      final controller = ExamWizardController(
        document: ExamDocument(
          name: 'فارغ',
          header: ExamHeaderModel(subject: 'الرياضيات'),
          questions: <QuestionModel>[QuestionModel(questionNumber: 1)],
        ),
      );
      await _pumpPreview(tester, controller);

      // عنوان فارغ وغير محدد → لا TextField ولا تلميح ولا عمود فراغ:
      // الحقل غير موجود في الشجرة إطلاقاً (ليس opacity:0 ولا visibility).
      expect(find.text('عنوان الامتحان...'), findsNothing);
      expect(find.text('ملاحظات إضافية (وقت/درجة/...)...'), findsNothing);
      // وفرع مفقود لا يترك شيئاً: السؤال الجديد starts بلا فروع.
      expect(controller.questions.single.branches, isEmpty);
      expect(find.text('أ)'), findsNothing);
    });

    testWidgets('توسيط اللوحة عند 144% يحفظ الزوم ويعيد التمرير فقط', (tester) async {
      final controller = ExamWizardController(document: _mathDoc());
      await _pumpPreview(tester, controller);

      await tester.tap(find.byTooltip('تكبير'));
      await tester.pump();
      await tester.tap(find.byTooltip('تكبير'));
      await tester.pump();
      expect(find.text('144%'), findsOneWidget);

      // تمرير يدوي بعيداً، ثم توسيط: الأفقي يعود لمنتصف مجال overflow
      // والعمودي إلى الصفر — وقيمة الزوم لا تلمَس إطلاقاً.
      await tester.drag(
        find.byKey(const ValueKey<String>('paper-v-scroll')),
        const Offset(0, -200),
      );
      await tester.pump();

      expect(_scrollPixels(tester, 'paper-v-scroll'), greaterThan(0));

      await tester.tap(find.byTooltip('توسيط الورقة'));
      await tester.pump();
      await tester.pump();

      expect(find.text('144%'), findsOneWidget);
      expect(_scrollPixels(tester, 'paper-v-scroll'), 0);
      // 794 × 1.44 = 1143.4 + 24 حشو مقابل منفذ 1000 ⇒ maxScrollExtent
      // أفقي ≈ 167.4، ومنتصفه ≈ 83.7 هو توسيط الورقة هندسياً.
      expect(_scrollPixels(tester, 'paper-h-scroll'), closeTo(83.7, 1.5));
    });
  });
}
