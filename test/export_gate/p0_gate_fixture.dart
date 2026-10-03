// =============================================================================
// تركيبة بوابة P0 — تركيبة واحدة حقيقية تمرّ بالممرّات الأربعة كلها:
//   المعاينة (Preview) · PDF المتجه (PdfEngine) · Word القابل للتحرير (DOCX)
//   · التصدير الدقيق (Exact) — ومسار Exact يبقى **منفصلاً**: لا يُستعمل بديلاً
//   عن اختبار PDF المتجه ولا DOCX القابل للتحرير.
//
// لماذا وسوم ASCII داخل النص العربي؟
//   النص العربي في مطبوع PDF يُحوَّل إلى صور تقديمية (FE70..FEFF) ويُعاد
//   ترتيبه عرضياً (خوارزمية UBA)؛ فمقارنة النص العربي نصاً «كما كُتب» تعطي
//   نتائج زائفة. الوسوم اللاتينية لا تتشكّل ولا تُقلَب داخل الجريان، فتصلح
//   مِسطرةً لقياس: وجود المحتوى، وترتيبه، وصفحته، وموضعه، وتعداد أسطره.
//   أما خصائص العربية (الصور التقديمية، ترتيب الكلمات، الفجوات، الأرقام)
//   فتُقاس هندسياً وبأكواد المحارف مباشرةً — لا بمقارنة نص ولا بجذر RMSE.
//
// لا تُحذف أي ميزة من تركيبة التحقق البصري القائمة
// (test/visual/visual_parity_fixture_test.dart): هذه التركيبة **تضاف** إليها
// وتغطي قائمة P0.1 كاملة، والقطعة القديمة تبقى كما هي لقياس الانحدار البصري.
// =============================================================================
import 'dart:convert';
import 'dart:typed_data';

import 'package:writing_questions_app/layout/blueprint/exam_blueprint.dart';
import 'package:writing_questions_app/models/branch_item.dart';
import 'package:writing_questions_app/models/exam_catalog.dart';
import 'package:writing_questions_app/models/branch_model.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_footer_model.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/floating_element.dart';
import 'package:writing_questions_app/models/paper_divider.dart';
import 'package:writing_questions_app/models/paper_font.dart';
import 'package:writing_questions_app/models/paper_settings.dart';
import 'package:writing_questions_app/models/paper_text_style.dart';
import 'package:writing_questions_app/models/point_kind.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/models/question_option.dart';

/// مسار واحد من مصفوفة الانحدار (P0.7).
enum P0Path {
  /// لقطة المعاينة (Flutter/Skia) — المرجع البصري.
  preview,

  /// PDF المتجه من `PaginatedPdfExamEngine` (نص حقيقي قابل للتحديد).
  vectorPdf,

  /// DOCX القابل للتحرير من `DocxDocumentExportService` (OOXML حقيقي).
  editableDocx,

  /// Exact: صور المعاينة ملفوفة في PDF/DOCX — ممرّ الدقة، لا ممرّ البنية.
  exact,
}

/// حالة الخلية في المصفوفة: لا توجد حالة «تقريباً صحيح».
enum P0Status {
  /// الفحص البنيوي نجح بدليل مقاس.
  pass,

  /// الفحص البنيوي فشل — انحدار يجب إصلاحه.
  fail,

  /// لا معنى للفحص في هذا الممرّ (يُذكر السبب دائماً).
  notApplicable,

  /// انحراف مُثبَت بالكود ولا يُصلح في P0 (يُذكر السبب والدليل).
  deferredToP1,
}

String p0StatusLabel(P0Status status) {
  switch (status) {
    case P0Status.pass:
      return 'PASS';
    case P0Status.fail:
      return 'FAIL';
    case P0Status.notApplicable:
      return 'NOT_APPLICABLE';
    case P0Status.deferredToP1:
      return 'DEFERRED_TO_P1';
  }
}

String p0PathLabel(P0Path path) {
  switch (path) {
    case P0Path.preview:
      return 'Preview';
    case P0Path.vectorPdf:
      return 'VectorPDF';
    case P0Path.editableDocx:
      return 'EditableDOCX';
    case P0Path.exact:
      return 'Exact';
  }
}

/// ميزة من مصفوفة P0.7 (خمس عشرة ميزة × أربعة ممرّات).
class P0Feature {
  const P0Feature({
    required this.key,
    required this.title,
    required this.fixtureEvidence,
  });

  final String key;
  final String title;

  /// أين تُغطّى في التركيبة (وسم/حقل)، ليكون كل سطر قابلاً للتتبّع.
  final String fixtureEvidence;
}

/// ميزات مصفوفة P0.7 — أربع عشرة ميزة + [kP0LtrFeature] = خمس عشرة،
/// تُقطع كل منها على الممرّات الأربعة.
///
/// كل ميزة تحمل وسوم التركيبة التي تُقاس بها، فلا خلية في المصفوفة بلا مصدر
/// قابل للتتبّع في [P0GateFixture.rtl] / [P0GateFixture.ltr].
const List<P0Feature> kP0MatrixFeatures = <P0Feature>[
  P0Feature(
    key: 'arabic',
    title: 'عربية RTL (سؤال كامل + التفاف + أقواس التسميات)',
    fixtureEvidence:
        'Q1 `STA1`/`BODY1` (منطوق + متن + قسم)، و`(١)` و`(ب)` كتسميات، '
        'و`BR1`/`BR2` للفروع، و`CAT1` للقسم',
  ),
  P0Feature(
    key: 'latin',
    title: 'لاتينية داخل الورقة العربية',
    fixtureEvidence: 'MIX1، OPT1، OP1A..OP1C، «Set A = {1, 2}» في MATH1',
  ),
  P0Feature(
    key: 'mixed',
    title: 'عربي + إنجليزي في السؤال نفسه',
    fixtureEvidence: 'متن MIX1 نفسه (جملة عربية + عبارة إنجليزية + أرقام)',
  ),
  P0Feature(
    key: 'arabic-numerals',
    title: 'أرقام مشرقية ١- ٢- ٣-',
    fixtureEvidence:
        'تسميات النقاط التلقائية ITM3/ITM5 (١-..٥-)، «س١/» للسؤال، '
        'و(٢٠ درجة) للدرجة',
  ),
  P0Feature(
    key: 'latin-numerals',
    title: 'أرقام لاتينية في RTL (1-، 2026/2027)',
    fixtureEvidence:
        'تسمية يدوية «1-» للنقطة ITM4، «2026/2027» في HDC2 وMIX1، و1990 '
        'في المتن، و«45.5%»',
  ),
  P0Feature(
    key: 'punctuation',
    title: 'الفواصل والأقواس وفاصل الترقيم (، . : — % / ( ) )',
    fixtureEvidence:
        'MIX1: «(20 درجة)»، «(أ) مقابل (ب)»، «%»، «:»، «،»؛ و«/» في '
        'تسميات الأسئلة التلقائية (س١/) والعام الدراسي',
  ),
  P0Feature(
    key: 'math',
    title: 'الرياضيات: \$...\$ في جملة عربية، و\\text{} عربي، وترتيب المعادلات',
    fixtureEvidence:
        'MATH1 (\$x^2+2x+1=0\$)، MATH2 (\$\\frac{a}{b}\$)، TEXTAR1 '
        '(\$\\text{المربع } S\$ / \$\\text{العدد } n\$)',
  ),
  P0Feature(
    key: 'quran',
    title: 'القرآن ﴿…﴾ في كل سطح مطبوع',
    fixtureEvidence:
        'QUR1 (فرع مستقل)، STA1 (داخل منطوق)، QUR2 (متن فرع)، QUR3/QUR4/QUR5 '
        '(خيار)، QUR6 (تسمية سؤال يدوية)، CAT4 (قسم)، FTR1 (تذييل)',
  ),
  P0Feature(
    key: 'options',
    title: 'خيارات الاختيار من متعدد وتسمياتها ( أ ) + خانة صح/خطأ',
    fixtureEvidence:
        'OPT1 + OP1A..OP1C في Q1، وQUR4/QUR5 في Q4، وTF1 '
        '(PointKind.trueFalse ← ExamCatalog.trueFalseSlot)',
  ),
  P0Feature(
    key: 'marks',
    title: 'الدرجات «(٢٠ درجة)» وتجميعها',
    fixtureEvidence:
        'marksOverride=20 لـQ1، ودرجات النقاط (4، 2، 1.5) والفروع (5، 6)',
  ),
  P0Feature(
    key: 'pagination',
    title: 'التقسيم الورقي (أكثر من صفحة) وخطة الأسئلة',
    fixtureEvidence: 'PG5..PG8 (متون طويلة) + فاصل Q2 (`PaperDivider`)',
  ),
  P0Feature(
    key: 'justification',
    title: 'ضبط الفقرة (justify) وقاعدة «لا يُمَدّ سطر واحد»',
    fixtureEvidence: 'bodyAlign=justify لمتن Q1 (MIX1/BODY1) ولفقرات PG5..PG8',
  ),
  P0Feature(
    key: 'floating',
    title: 'العناصر الحرّة FloatingElement (صورة + مربع نص + شكل)',
    fixtureEvidence:
        'FLOAT1 (صورة PNG مملوكة لـQ1)، FLOAT2 (مربع نص عربي مملوك)، '
        'p0free1 (شكل على مستوى الورقة)',
  ),
  P0Feature(
    key: 'header-footer',
    title: 'الترويسة والتذييل (بما فيها القسم)',
    fixtureEvidence:
        'HDRV/HDC1/HDC2/HDG1/HDT1 في الترويسة، FTR1..FTR3 في التذييل، '
        'CAT1/CAT2/CAT4 أسطر أقسام',
  ),
];

/// ورقة LTR المستقلة تُقاس كخلايا مستقلة لكل ممرّ على الميزات نفسها، وتُجمع
/// مع `arabic`… في عمود خاص بها في [P0GateFixture.ltr].
const P0Feature kP0LtrFeature = P0Feature(
  key: 'ltr-document',
  title: 'ورقة LTR كاملة لا تنكسر بإصلاحات RTL',
  fixtureEvidence: 'كل وثيقة P0GateFixture.ltr() (وسوم LTR*)',
);

/// الميزات الخمس عشرة: [kP0MatrixFeatures] + [kP0LtrFeature].
const List<P0Feature> kP0Features = <P0Feature>[...kP0MatrixFeatures, kP0LtrFeature];

/// ما يُقاس في كل خلية من خلايا المعاينة (تُملأ من اختبار البوابة).
abstract final class P0GateFixture {
  /// مجلد قطع البوابة (يُرفع من CI).
  static const String artifactDir = 'build/export_gate';

  /// PNG 1×1 حقيقية لعنصر الصورة الحر (المحتوى يُنتَج، لا يُموَّه).
  static Uint8List tinyPng() => base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8'
        'z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
      );

  /// فقرة طويلة مكرَّرة: تضمن التفافاً وأكبر من صفحة.
  static String longParagraph(String marker) =>
      'نصّ طويل تابع لقياس التدفّق والتفاف الأسطر في الممرّات الأربعة معاً، '
      'يجب أن تتساوى عدد الأسطر ومواضع الكلمات بلا أي كسر للصفحة داخل السؤال '
      'ولا أي فقدان لعلامة \$marker من علامات المحتوى. '
      'وفيه كلمات متعددة الفواصل والأقواس لقياس التبرير وسعة السطر '
      '\u066b\u066c والأرقام (٢٠ درجة) أيضاً. '
      'نصّ طويل تابع لقياس التدفّق والتفاف الأسطر في الممرّات الأربعة معاً، '
      'يجب أن تتساوى عدد الأسطر ومواضع الكلمات بلا أي كسر للصفحة داخل السؤال '
      'ولا أي فقدان لعلامة \$marker من علامات المحتوى. '
      'وفي آخره سطرٌ رابع وخامس لضمان أن تتعدى الورقة صفحة واحدة في كل ممرّ، '
      'وأن يكون التقسيم محكوماً بالارتفاع المقاس لا بعدّ الأسئلة. '
      'نصّ طويل تابع لقياس التدفّق والتفاف الأسطر في الممرّات الأربعة معاً، '
      'يجب أن تتساوى عدد الأسطر ومواضع الكلمات بلا أي كسر للصفحة داخل السؤال '
      'ولا أي فقدان لعلامة \$marker من علامات المحتوى.';

  /// الوثيقة العربية RTL — كل ميزات P0.1 ما عدا الورقة المستقلة LTR.
  static ExamDocument rtl() {
    return ExamDocument(
      name: 'بوابة P0 — عربية',
      header: ExamHeaderModel.initial(
        subject: 'التربية الإسلامية',
        schoolName: 'ثانوية النهوضHDRV',
        examType: 'نصف السنةHDC1',
      ).copyWith(
        academicYear: 'HDC2 2026/2027',
        grade: 'الثالث المتوسطHDG1',
        time: '90HDT1 دقيقة',
        showBismillah: true,
      ),
      footer: const ExamFooterModel(
        // آية في التذييل: لا يراعيها الفحص الجزئي القائم لـ needsQuranicFont.
        closingPhrase: 'انتهت الأسئلة مع التوفيق FTR1 ﴿وَقُل رَّبِّ زِدْنِي عِلْمًا﴾',
        primary: SignatureModel(
          title: SignatureTitle.lecturer,
          name: 'أ. محمد FTR2',
        ),
        secondary: SignatureModel(
          title: SignatureTitle.educator,
          name: 'د. علي FTR3',
        ),
      ),
      settings: const PaperSettings(
        // auto ← قالب التربية الإسلامية: أرقام مشرقية + فاصل «/».
        numerals: PaperNumerals.auto,
        questionLabelStyle: QuestionLabelStyle.compact,
        autoNumberQuestions: true,
        autoLetterBranches: true,
        showQuestionMarks: true,
        headerBorder: true,
        defaultFont: PaperFont.naskh,
        baseFontSize: 11,
        lineSpacing: 1.7,
        marginMm: 15,
      ),
      questions: <QuestionModel>[
        // (1) عربية RTL: قسم + آية في المنطوق + متن مختلط + كل أنماط التسميات.
        QuestionModel(
          id: 'p0q1',
          questionNumber: 1,
          category: 'النصوص والأدب CAT1',
          statement: 'اقرأ النص ثم أجب: ﴿وَقُل رَّبِّ زِدْنِي عِلْمًا﴾ STA1',
          marksOverride: 20,
          bodyAlign: PaperAlign.justify,
          body: 'يناقش الكاتب ظاهرة أدبية عند الجاحظ MIX1 بين عامي 1990 '
              'و2026/2027 بنسبة 45.5%، ثم يذكر 3 أمثلة؛ وفي المتن قوسان '
              '(20 درجة) وعبارة (أ) مقابل (ب) — ولا يجوز أن تُقلب الأرقام '
              'ولا أن تُبدَّل مواضع الفواصل في أي ممرّ من ممرات التصدير BODY1.',
          items: <BranchItem>[
            BranchItem(
              id: 'p0q1i1',
              kind: PointKind.multipleChoice,
              text: 'اختر الإجابة الصحيحة OPT1',
              marks: 4,
              options: <QuestionOption>[
                QuestionOption(text: 'الإظهار OP1A'),
                QuestionOption(text: 'الإدغام OP1B'),
                QuestionOption(text: 'الإقلاب OP1C'),
              ],
            ),
            BranchItem(
              id: 'p0q1i2',
              kind: PointKind.trueFalse,
              text: 'الجاحظ من علماء البصرة TF1',
              marks: 2,
            ),
            BranchItem(
              id: 'p0q1i3',
              kind: PointKind.fillBlank,
              // تسمية يدوية بين قوسين برقم مشرقي: (١)
              labelOverride: '(١)',
              text: 'أكمل: مؤلف كتاب الحيوان ITM3 ......',
            ),
            BranchItem(
              id: 'p0q1i4',
              kind: PointKind.plain,
              // أرقام لاتينية داخل RTL تُطبع حرفياً (1-)
              labelOverride: '1-',
              text: 'اكتب خلاصة في سطرين ITM4',
              marks: 1.5,
            ),
            BranchItem(
              id: 'p0q1i5',
              kind: PointKind.plain,
              text: 'علّل بقاء الأثر ITM5',
            ),
          ],
          branches: <BranchModel>[
            BranchModel(
              id: 'p0q1b1',
              marks: 5,
              content: BranchContent(
                statement: 'فرع أول: استخرج الفاعل BR1',
                body: 'نص الفرع الأول الطويل قليلاً ليُجبر على الالتفاف '
                    'داخل الفقرة نفسها BR1B.',
                items: <BranchItem>[
                  BranchItem(id: 'p0q1b1i1', text: 'بند الفرع BR1I', marks: 1),
                ],
              ),
            ),
            BranchModel(
              id: 'p0q1b2',
              // تسمية فرع يدوية بين قوسين.
              labelOverride: '(ب)',
              content: BranchContent(
                statement: 'فرع بتسمية بين قوسين BR2',
              ),
            ),
          ],
          attachments: <FloatingElement>[
            FloatingElement(
              id: 'p0q1float1',
              type: FloatingElementType.image,
              bytes: tinyPng(),
              ownerQuestionId: 'p0q1',
              dx: 520,
              dy: 240,
              width: 96,
              height: 64,
            ),
            FloatingElement(
              id: 'p0q1float2',
              type: FloatingElementType.shape,
              shape: FloatingShapeType.textBox,
              label: 'ملاحظة: راجع الشكل FLOAT2',
              ownerQuestionId: 'p0q1',
              dx: 120,
              dy: 300,
              width: 220,
              height: 70,
              framed: true,
              textStyle: const PaperTextStyle(align: PaperAlign.center),
            ),
          ],
        ),
        // (2) رياضيات داخل العربية: صيغة سطرية + \text{} عربي + فاصل.
        QuestionModel(
          id: 'p0q2',
          questionNumber: 2,
          category: 'الجبر CAT2',
          statement: 'احسب جذور المعادلة \$x^2+2x+1=0\$ MATH1 ثم قارن '
              'بالمجموعة Set A = {1, 2}',
          body: 'اكتب الإجابة داخل \$\\text{المربع } S\$ ثم بيّن '
              '\$\\text{العدد } n\$ TEXTAR1',
          marksOverride: 8,
          dividerAfter: const PaperDivider(),
          items: <BranchItem>[
            BranchItem(
              id: 'p0q2i1',
              kind: PointKind.plain,
              text: r'أكمل $\frac{a}{b}$ MATH2',
              marks: 3,
            ),
          ],
        ),
        // (3) الفرع بآية قائمة بذاتها (دور verse) + آية في القسم (fix C).
        QuestionModel(
          id: 'p0q3',
          questionNumber: 3,
          // آية داخل سطر القسم وحده: لا يراها الفحص الجزئي القائم.
          category: 'أحكام التلاوة CAT4 ﴿وَاتَّقُوا يَوْمًا تُرْجَعُونَ فِيهِ﴾',
          statement: 'بيّن حكم التلاوة في ما يأتي QUR0',
          marksOverride: 6,
          branches: <BranchModel>[
            BranchModel(
              id: 'p0q3b1',
              marks: 6,
              content: BranchContent(
                // آية قائمة بذاتها (سطر مستقل) → دور verse.
                statement: '﴿إِنَّا أَعْطَيْنَاكَ الْكَوْثَرَ﴾ QUR1',
                body: 'اذكر الحكم وعلّله مع ذكر أمثلة من النص QUR2.',
              ),
            ),
          ],
        ),
        // (4) آية داخل خيار من متعدد: سطح آخر لا يغطيه الفحص الجزئي.
        QuestionModel(
          id: 'p0q4',
          questionNumber: 4,
          statement: 'اختر الحكم الوارد في الآية QUR3',
          marksOverride: 4,
          // متن من سطر واحد بمحاذاة مضبوطة: إن مُدّ سطرٌ وحيد ظهر الانحدار
          // في vector.pdf (امتداد السطر إلى عرض المحتوى) وفي المعاينة
          // (wordSpacing غير صفري) — وهو بالضبط قرار P0.5-F.
          bodyAlign: PaperAlign.justify,
          body: 'سطران فقط JUSTS1',
          // تسمية سؤال يدوية تحوي آية: سطح ثالث (fix C).
          numberOverride: 'السؤال الرابع QUR6',
          items: <BranchItem>[
            BranchItem(
              id: 'p0q4i1',
              kind: PointKind.multipleChoice,
              text: 'الحكم في قوله تعالى هو:',
              options: <QuestionOption>[
                QuestionOption(text: 'الإظهار ﴿عِلْمًا﴾ QUR4'),
                QuestionOption(text: 'الإخفاء QUR5'),
              ],
            ),
          ],
        ),
        // (5) نص طويل يضمن أكثر من صفحة + ضبط السطر في فقرة بلا رياضيات.
        for (var index = 5; index <= 8; index++)
          QuestionModel(
            id: 'p0q$index',
            questionNumber: index,
            statement: 'سؤال التدفّق رقم $index PG$index',
            body: longParagraph('PG$index'),
            marksOverride: 5,
            style: const PaperTextStyle(align: PaperAlign.justify),
          ),
      ],
      floatingElements: <FloatingElement>[
        FloatingElement(
          id: 'p0free1',
          type: FloatingElementType.shape,
          shape: FloatingShapeType.square,
          dx: 600,
          dy: 120,
          width: 90,
          height: 90,
          pageIndex: 0,
          framed: true,
        ),
      ],
    );
  }

  /// الوثيقة الإنجليزية LTR — يجب ألا تمسّها إصلاحات RTL ولا أن تنكسر بها.
  static ExamDocument ltr() {
    return ExamDocument(
      name: 'بوابة P0 — English',
      header: ExamHeaderModel.initial(
        subject: 'English',
        schoolName: 'Al-Nahda School LTRV',
        examType: 'Midyear LTRC1',
      ).copyWith(
        academicYear: 'LTRC2 2026/2027',
        grade: 'Form Three LTRG1',
        time: '90 LTRT1 minutes',
        showBismillah: false,
      ),
      footer: const ExamFooterModel(
        closingPhrase: 'End of questions LTRF1',
        primary: SignatureModel(
          title: SignatureTitle.lecturer,
          name: 'Mr. Ali LTRF2',
        ),
      ),
      settings: const PaperSettings(
        numerals: PaperNumerals.auto,
        questionLabelStyle: QuestionLabelStyle.compact,
        showQuestionMarks: true,
        headerBorder: true,
        baseFontSize: 11,
        lineSpacing: 1.7,
        marginMm: 15,
      ),
      questions: <QuestionModel>[
        QuestionModel(
          id: 'p0lq1',
          questionNumber: 1,
          category: 'Vocabulary LTRCAT1',
          statement: 'Choose the correct answer LTRSTA1',
          marksOverride: 20,
          bodyAlign: PaperAlign.justify,
          body: 'The passage below is long enough to wrap on more than one '
              'line, and it carries digits 1990, 45.5% and the marks note '
              '(20 marks) with brackets (A) against (B) so that ordering is '
              'measurable in every export path LTROBJ1.',
          items: <BranchItem>[
            BranchItem(
              id: 'p0lq1i1',
              kind: PointKind.multipleChoice,
              text: 'Pick the correct option LTROPT1',
              marks: 4,
              options: <QuestionOption>[
                QuestionOption(text: 'go LTRP1A'),
                QuestionOption(text: 'goes LTRP1B'),
                QuestionOption(text: 'going LTRP1C'),
              ],
            ),
            BranchItem(
              id: 'p0lq1i2',
              kind: PointKind.trueFalse,
              text: 'He goes to school every day LTRTF1',
            ),
            BranchItem(
              id: 'p0lq1i3',
              kind: PointKind.plain,
              labelOverride: '(1)',
              text: 'Write a short answer LTRITM3',
            ),
          ],
          branches: <BranchModel>[
            BranchModel(
              id: 'p0lq1b1',
              marks: 5,
              content: BranchContent(
                statement: 'Answer the first part LTRBR1',
                body: 'A branch body that wraps because it is long enough '
                    'to need two lines in the content box LTRBR1B.',
              ),
            ),
          ],
        ),
        QuestionModel(
          id: 'p0lq2',
          questionNumber: 2,
          statement: r'Solve $x^2+2x+1=0$ LTRMATH1 and write the set.',
          marksOverride: 5,
          bodyAlign: PaperAlign.justify,
          body: 'A single justified line JUSTL1',
          dividerAfter: const PaperDivider(),
        ),
        QuestionModel(
          id: 'p0lq3',
          questionNumber: 3,
          statement: 'Flow question LTRPG1',
          body: longParagraph('LTRPG1'),
          marksOverride: 5,
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // توقعات الترتيب (P0.3/P0.4)
  //
  // الترويسة والتذييل والعناصر الحرة تُستثنى من مقارنة التسلسل لأنها تُرسم في
  // طبقة/موضع مختلف (ترويسة في أعلى كل صفحة، تذييل في أسفل آخر صفحة، عناصر
  // حرة في طبقة علوية بعد المتن)، فتُفحص وحدها بالوجود والموضع.
  //
  // ترتيب الوسوم المتوقع لا يُكتب يدوياً: يُشتق من `ExamBlueprint` نفسه — وهو
  // العقد الذي يستهلكه الراسمان — فالاختبار يقارن **الراسم** بالعقد، لا
  // بقائمة صيانة بشرية تنفصل عنه.
  // ---------------------------------------------------------------------------

  /// كل وسوم المتن (بلا الترويسة والتذييل والعناصر الحرة) — مجموعة مغلقة:
  /// أي وسم يضيع في ممرّ يظهر هنا كانقصان، وأي وسم غريب يظهر كانحدار.
  static const Set<String> rtlBodyMarkers = <String>{
    'CAT1',
    'STA1',
    'MIX1',
    'BODY1',
    'OPT1',
    'OP1A',
    'OP1B',
    'OP1C',
    'TF1',
    'ITM3',
    'ITM4',
    'ITM5',
    'BR1',
    'BR1B',
    'BR1I',
    'BR2',
    'CAT2',
    'MATH1',
    'TEXTAR1',
    'MATH2',
    'CAT4',
    'QUR0',
    'QUR1',
    'QUR2',
    'QUR3',
    'QUR6',
    'QUR4',
    'QUR5',
    'PG5',
    'JUSTS1',
    'PG6',
    'PG7',
    'PG8',
  };

  /// وسوم المتن في الوثيقة الإنجليزية LTR.
  static const Set<String> ltrBodyMarkers = <String>{
    'LTRCAT1',
    'LTRSTA1',
    'LTROBJ1',
    'LTROPT1',
    'LTRP1A',
    'LTRP1B',
    'LTRP1C',
    'LTRTF1',
    'LTRITM3',
    'LTRBR1',
    'LTRBR1B',
    'LTRMATH1',
    'JUSTL1',
    'LTRPG1',
  };

  /// تسلسل وسوم المتن كما يولّده العقد (ترتيب الكتلة المنطقية نفسها).
  static List<String> bodyMarkerSequence(ExamDocument document) {
    final known = document.layout.isLtr ? ltrBodyMarkers : rtlBodyMarkers;
    final blueprint = ExamBlueprint.from(document);
    final sequence = <String>[];

    void scan(String? source) {
      if (source == null || source.isEmpty) {
        return;
      }
      for (final match in _markerPattern.allMatches(source)) {
        final marker = match.group(1)!;
        if (known.contains(marker)) {
          sequence.add(marker);
        }
      }
    }

    for (final question in blueprint.questions) {
      scan(question.section);
      scan(question.title.number);
      scan(question.title.statement);
      scan(question.title.marks);
      scan(question.body);
      for (final point in question.points) {
        if (!point.isPrintable) {
          continue;
        }
        scan(point.label);
        scan(point.text);
        scan(point.trailer);
        scan(point.marks);
        for (final option in point.options) {
          scan(option.label);
          scan(option.text);
        }
      }
      for (final branch in question.branches) {
        if (!branch.isPrintable()) {
          continue;
        }
        scan(branch.title.number);
        scan(branch.title.statement);
        scan(branch.title.marks);
        scan(branch.body);
        for (final point in branch.points) {
          if (!point.isPrintable) {
            continue;
          }
          scan(point.label);
          scan(point.text);
          scan(point.trailer);
          scan(point.marks);
          for (final option in point.options) {
            scan(option.label);
            scan(option.text);
          }
        }
      }
    }
    // تتابع الوسوم داخل الكتلة الواحدة لا يُكرَّر: ما يُقارَن هو **تتابع
    // البلوكات**، والفقرات قد تحمل وسمين (منطوق + متن) أو أكثر.
    final collapsed = <String>[];
    for (final marker in sequence) {
      if (collapsed.isEmpty || collapsed.last != marker) {
        collapsed.add(marker);
      }
    }
    return collapsed;
  }

  /// الوسم داخل نص: حروف لاتينية وأرقام، مسبوقة بحدّ حرفي ومتبوعة بحدّ حرفي.
  static final RegExp _markerPattern = RegExp(r'(?<![A-Za-z0-9])([A-Z][A-Z0-9]{2,})(?![A-Za-z0-9])');

  /// وسوم الترويسة (كل صفحة في PDF، و`word/header*.xml` في DOCX).
  static const List<String> headerMarkers = <String>[
    'HDRV',
    'HDC1',
    'HDC2',
    'HDG1',
    'HDT1',
  ];

  /// وسوم التذييل (سطر التذييل في PDF، جدول التذييل في المتن لـ DOCX).
  static const List<String> footerMarkers = <String>[
    'FTR1',
    'FTR2',
    'FTR3',
  ];

  /// وسوم العناصر الحرة (لا تدخل مقارنة التسلسل).
  static const List<String> floatingMarkers = <String>['FLOAT2'];

  /// عدد الأسئلة في كل وثيقة (يُستعمل لربط خطة الترقيم بالصفحات).
  static const int rtlQuestionCount = 8;
  static const int ltrQuestionCount = 3;
}
