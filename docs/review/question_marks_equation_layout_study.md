# دراسة هندسية: موضع الدرجة والمسافة حول المعادلة المستقلة

**النطاق:** دراسة وتشخيص فقط — **لا تعديل على كود الإنتاج** في هذه المرحلة.
**الفرع:** `arena/c08372c2-writing-questions` · **خط الإنتاج المجمَّد:** `c45655c`

> **قيد وارد أولًا (بصراحة):** الصورتان المرفقتان في الطلب **لم تُوصَل إلى بيئة
> التنفيذ** (وصل وصفهما لا ملفّاهما). لذلك لم أستخرج «الهيئة المطلوبة» من صورة
> بل من **النموذج المرجعي داخل المشروع نفسه**: عقد العنوان في
> `lib/layout/visual/visual_document.dart`، وقواعد `LayoutEngine._titleBlock`،
> وسجل العقد `lib/layout/visual/export_contract_audit.dart`
> («سطر العنوان: الرقم ← المنطوق ← الدرجة»)، ثم قِيس الفرق على مخرجات حقيقية.
> كل ما يلي قابل للتحقق بالأمر الواحد المذكور في §8.

---

## 1. العرض الأولي (المرجع المطبوع)

| الطبقة | الملف | المسؤول |
|---|---|---|
| الخطة | `lib/views/wizard/canonical_preview_plan_controller.dart` | يطلب الحسم المتزامن مع المستند ويحفظ `CanonicalPagePlan` |
| المحرّك | `lib/layout/canonical/layout_engine.dart` | `_titleBlock` (873) · `_contentBlock` (930) · `_paragraphBlock` (1006) |
| القياس | `lib/layout/canonical/flutter_text_metrics.dart` | `layoutParagraph` — `TextPainter` + `WidgetSpan` بمقاس `mathBox` |
| قياس الرياضيات | `lib/layout/canonical/layout_math_metrics_resolver.dart` | لقطات `MathSnapshotRenderer` → `LayoutMathBox` بالسنتيمتر/النقطة |
| الرسم | `lib/layout/canonical/canonical_layout_preview.dart` | `CanonicalLayoutPreviewPage` — يرسم إحداثيات `LayoutDocument` كما هي |
| الصفحات | `lib/layout/canonical/canonical_page_plan.dart` | `CanonicalPagePlan`, `CanonicalPagePlanFragment`, `titleHeightPtOf` |

**كيف يحدد موضع الدرجة هنا؟** الدرجة **ليست عنصرًا مستقلًا**: `_titleBlock`
يبنيها كـ`MetricSpan` داخل فقرة سطر العنوان نفسها:

```
label  ⟶ separator ⟶ 4px فجوة ⟶ statement ⟶ NBSP ⟶ marks
```
(`layout_engine.dart:880-916`، والفجوة قبل الدرجة `_nonBreakingGap` تُنفَّذ كحرف
U+00A0 مقيس بخط السطر نفسه، تعليق السطور 903-913).

النتيجة الهندسية: **الدرجة تتبع آخر سطر من المنطوق**، لا حافة الصف، ولا يمكن أن
تنفصل عنه لأن U+00A0 يحمل صنف UAX #14 = GL.

---

## 2. واجهة العرض والتعديل (سطح الإنتاج)

**هذا هو السطح الذي يراه المدرس فعلًا**، وهو ليس السطح القانوني:

```dart
// lib/views/wizard/exam_wizard_screen.dart:160
return ExamPreviewScreen(
  key: const ValueKey<WizardStep>(WizardStep.preview),
  onBackToQuestions: () => _goTo(WizardStep.questions),
);
```
بلا `canonicalLayoutResolver` ولا `canonicalPreviewAssetLoader`، وبهما فقط:

```dart
// lib/views/wizard/exam_preview_screen.dart:618
bool get _useCanonicalSurface =>
    widget.canonicalLayoutResolver != null &&
    widget.canonicalPreviewAssetLoader != null;
```

إذن في الإنتاج `_useCanonicalSurface == false`، ويُرسم
`_buildPaperZoomedPage` → `_buildPage` → `_buildQuestionBlock` (ودجات Flutter).

| المسؤولية | الملف:السطر | الطريقة |
|---|---|---|
| صف العنوان | `exam_preview_screen.dart:5912` `_titleRow` | `Row[ dragHandle, label(≤34%), gap 4px, **Expanded(statement)**, marks(≤26%), actions ]` |
| الدرجة | `exam_preview_screen.dart:6292` `_marksTarget` | ودجة مستقلة في نهاية الـ`Row`؛ وعند غيابها تُطبع «+ درجة» رمادية 10px |
| المنطوق | `_paperField` → `lib/views/widgets/paper_field.dart:317-370` | `TextField` حقيقي أثناء التحرير، و`TexText` حين يُترك |
| المعادلة المستقلة | `lib/views/widgets/tex_text.dart:110-133` | `Text.rich` مستقل + `Padding(vertical: 4)` + `TextAlign.center` |
| الترقيم والصفحات | `_buildPage:4879` · `_planRowHeight:5950` · `_buildQuestionFragmentSlice:5967` | من الخطة: ارتفاع سطر العنوان، نافذة المقطع، فجوة الترويسة |
| ارتفاع عنوان الفرع | `plan?.branchTitleHeightPtOf(...)` (6563) | من الخطة |

**الخلاصة البنيوية:** السطح التفاعلي يأخذ من الخطة **ثلاثة أشياء فقط**: حدود
الصفحات/المقاطع، ارتفاع صف العنوان، وفجوة الترويسة. أما **مواضع العناصر داخل
السطر** فتقرّرها `Row`/`Expanded`/`TextField` — أي محرّك تخطيط ثانٍ.

---

## 3. PDF

| الطبقة | الملف | المسؤول |
|---|---|---|
| الواجهة | `lib/pdf_engine/paginated_pdf_exam_engine.dart:52-100` | `generate` — `layoutDocument ?? CanonicalLayoutService.resolve(...)` ثم `painter.paintPage` |
| الرسم | `lib/pdf_engine/canonical_layout_pdf_painter.dart:226-300` | يرسم كل `LayoutRun` في `x` و`baseline` من المستند، والمعادلات كصور لا نصًا |
| الرياضيات | `lib/pdf_engine/pdf_math_rasters.dart` + `lib/services/math_snapshot_renderer.dart` | لقطة `SafeMathTex` نفسها التي تعرضها اللوحة (لا محرك رياضيات ثانٍ) |
| التصدير الفعلي | `lib/services/pdf_export_service.dart:55-70` | `exportDocumentToPdf` **لا يمرّر** `layoutDocument` → `resolve` جديدة |

PDF لا يعيد حساب أي موضع: يرسم إحداثيات `LayoutDocument` حرفيًا. أي أن **مرجع
الموضع هو المحرّك**، وPDF طابع مطيع له.

---

## 4. جدول مقارنة القواعد

| القاعدة | العرض القانوني (المرجع) | واجهة العرض والتعديل | PDF |
|---|---|---|---|
| موضع الدرجة | جريان نصي داخل فقرة العنوان بعد المنطوق (`_titleBlock:903-916`) | ودجة في نهاية `Row` بعد `Expanded` (`_titleRow:5912`) | من `LayoutRun` — مطابق للمرجع |
| انفصال الدرجة عن المنطوق | مستحيل (U+00A0 يمنع كسر السطر) | **ممكن**: تبقى على السطر الأول بينما المنطوق يلتفّ | مستحيل |
| درجة بلا قيمة | لا شيء يُطبع | «+ درجة» رمادية (أداة تحرير لا تُطبع) | لا شيء |
| عرض المنطوق | عمود كامل ناقص التسمية | ناقص عرض صندوق الدرجة (`maxWidth: 26%`) | كالمرجع |
| التعريف «مستقلة» للمعادلة | `TexContent._blockPattern` = `$$…$$` (`tex_content.dart:6`) | **نفس المصدر**: `RichContent.parse` ← `TexContent.split` | **نفس المصدر** |
| فراغ قبل/بعد المعادلة المستقلة | `LayoutUnits.pxToPt(4)` = 3pt (`layout_engine.dart:998`) | `EdgeInsets.symmetric(vertical: 4)` = 4px = 3pt على المقياس نفسه | 3pt من المرجع |
| محاذاة المعادلة | `PaperAlign.center` مفروضة | `TextAlign.center` | من المرجع |
| ارتفاع المعادلة | `mathBox` من اللقطة، وإلا `fontSizePt` (احتياط) | الودجة الحقيقية (ارتفاع الحبر والهبوط) | ارتفاع اللقطة |
| أثناء التحرير | — | نص LaTeX خام داخل `TextField` → يختفي الفصل الرأسي | لا يوجد «تحرير» |
| ترتيب/التفاف النص | `TextPainter` بإحداثيات PT | `TextField` بوحدات px مع `_CaretGutter` | من المرجع |
| RTL/BiDi | `DocumentDirection` من المصدر | يرث اتجاه اللوحة + `Directionality` | نفس المصدر |
| القياسات | نقطة (pt) | بكسل منطقي (px) بتحويل 96/72 | نقطة (pt) |

---

## 5. موضع الدرجة الصحيح وفق المرجع

وفق عقد المشروع نفسه:

* `visual_document.dart:16-22` — «سطر عنوان (رقم ← منطوق ← درجة)».
* `export_contract_audit.dart:156` — «سطر العنوان: الرقم ← المنطوق ← الدرجة».
* `branch_model.dart:14` — «الرقم ← [statement] ← الدرجة».
* `layout_engine.dart:903-913` — الفجوة قبل الدرجة NBSP مقيس، لا `SizedBox`.

**إذن الموضع الصحيح:** نفس سطر العنوان، **ملتصقة بنهاية المنطوق** بفجوة حرف
واحد غير قابلة للكسر، وتظهر على يسار المنطوق في RTL لأنها آخر ما في السطر
منطقيًا — **لا** على حافة الصف، ولا في صندوق مستقل، ولا كزر «+ درجة» داخل الورقة.

الدرجة **مرتبطة بالسؤال كلّه** لا بكل فقرة: `QuestionModel.marks`
(`question_model.dart:141-144`) = `marksOverride` أو مجموع درجات الفروع والنقاط؛
والفروع والنقاط لها درجاتها المستقلة (`BranchModel.marks`, `BranchItem.marks`)،
وكلها تُطبع في سطر عنوان صاحبها. فالبنية ثلاثية المستويات، لا ثنائية.

---

## 6. المعادلة المستقلة: المسافة والمحاذاة المطلوبة

**قبل الإصلاح المزعوم، هذه هي القاعدة القائمة فعلًا:**

* تُعرَّف ب`$$…$$` (`tex_content.dart:6`)، وتصل إلى المحرك كـ`MetricSpan.isBlockMath`.
* المحرك يفصلها عن النص إلى فقرة مستقلة (`_contentBlock:960-1005`)، يفرض عليها
  `PaperAlign.center`، ويضع قبلها وبعدها `LayoutUnits.pxToPt(4)` = **3pt**.
* السطح التفاعلي يفعل الشيء نفسه بالضبط: بلوك `Text.rich` مستقل + `4px` رأسي =
  **3pt** على مقياس الورقة.

**إذن الفجوة المطلوبة هي 3pt قبل و3pt بعد**، وهي اليوم **ثابتة لا تتعلّق
بارتفاع المعادلة**. هذا هو جوهر الملاحظة: معادلة بكسر/جذر (ارتفاعها ضعف سطر
النص) تحصل على فراغ سطر عادي، فتبدو ملتصقة بالنص فوقها وتحت. القاعدة الصحيحة
ليست «padding عشوائي» بل **فجوة مشتقة من هندسة الصندوق**:

```
gapBefore = max(3pt, (mathBox.heightPt - lineHeightPt) / 2)
```
أي نصف الفارق بين ارتفاع الصندوق الرياضي وارتفاع سطر النص، بأرضية 3pt — وهذا
يعني أن المعادلة الطويلة تدفع النص تلقائيًا، والقاعدة تُشتق من `mathBox` الذي
يُحسب أصلًا في `LayoutMathMetricsResolver` ولا يستهلكه المحرك في الفراغ.

---

## 7. السبب الجذري لكل اختلاف

| # | الاختلاف | السبب الجذري | الدليل |
|---|---|---|---|
| 1 | الدرجة على حافة الصف بدل نهاية المنطوق | `Expanded(statement)` يدفع `marks` إلى نهاية `Row` | `exam_preview_screen.dart:5925-5940` |
| 2 | الدرجة تنفصل عن المنطوق عند التفاف السطر | الدرجة خارج فقرة النص، فلا يشاركها محرك الكسر | مقارنة §4 + القياس في §8 |
| 3 | «+ درجة» تظهر داخل الورقة | `_marksTarget` يرسم بديلًا تحريريًا داخل الصف | `exam_preview_screen.dart:6313-6325` |
| 4 | عرض المنطوق أقل من الطباعة | صندوق الدرجة محجوز مسبقًا (≤26%) | `_titleRow:5935-5941` |
| 5 | الدرجة تتحرك عند تنشيط نقطة | أدوات النقطة تُدرج **بعد** الدرجة في `Row` | `_pointRow:6739-6760` |
| 6 | المعادلة تفقد فصلها في التحرير | `TextField` يعرض LaTeX خامًا بلا بنية بلوك | `paper_field.dart:320-370` |
| 7 | فراغ المعادلة لا يكبر مع ارتفاعها | 3pt ثابتة | `layout_engine.dart:998` · `tex_text.dart:120` |
| 8 | احتمال قياس رياضيات مختلف | احتياط `heightPt = fontSizePt` عند غياب اللقطات | `flutter_text_metrics.dart:245-256` |
| 9 | ارتفاع سطر العنوان مفروض من الخطة على ودجات قد تكون أطول | `_planRowHeight` `SizedBox` | `exam_preview_screen.dart:5950-5956` |

**ما هو منفي بالأدلة:** ليس اختلافًا في نموذج البيانات (الدرجة واحدة،
`question_model.dart:141`)، ولا في ترتيب العناصر في `DocumentIR`
(`document_ir.dart` يبني العنوان من المصدر نفسه)، ولا في RTL/BiDi (كلاهما من
`DocumentDirection`)، ولا تعريف المعادلة المستقل (مصدر واحد: `TexContent.split`).

---

## 8. إعادة الإنتاج والقياس

MEASUREMENTS_SECTION

---

## 9. تشخيص المستوى

**الخلل في Renderer لا في البيانات ولا في Recognition:**
نموذج البيانات سليم، و`DocumentIR` سليم، و`LayoutEngine` ينتج الموضع الصحيح
(الدرجة في نهاية المنطوق). الذي يختلف هو **الراسم**: سطح الإنتاج يرسم صفًا
مبنيًا بـ`Row` بدل أن يرسم `LayoutRun`، فيفقد العلاقة بين الدرجة والمنطوق.
والمسافة حول المعادلة: المحرك والراسم **متفقان على الرقم**، والرقم نفسه
**ناقص اشتقاقًا** (ثابت 3pt لا يقرأ `mathBox`).

---

## 10. خطة إصلاح (لا تُنفَّذ قبل الموافقة)

**الإصلاح الأول — الدرجة (جذري، صغير الحجم):**
1. في `_titleRow` يستبدل `Expanded(statement) + marks` بكتلة نصية واحدة:
   `RichText`/`Wrap` يحوي المنطوق والدرجة كأبناء `TextSpan` مع U+00A0 قبلها —
   أي **نفس عقد المحرك**. البديل الأخف: إبقاء الحقل لكن تحويل الدرجة إلى
   `WidgetSpan` ب`alignment: PlaceholderAlignment.baseline` **داخل** الحقل نفسه
   عبر `renderBuilder`، وترك `_marksTarget` للتحرير فقط (نقرة على الجملة).
2. حذف «+ درجة» من الورقة أو نقله إلى شريط خارج الورقة (نمط §19.15 المطبَّق
   أصلًا على أدوات السؤال).
3. إخراج أدوات النقطة من `Row` إلى طبقة علوية مطلقة (`Overlay`) حتى لا تحرّك
   الدرجة.

**الإصلاح الثاني — فراغ المعادلة (جذري):**
1. `layout_engine.dart:998` يستبدل `pxToPt(4)` بدالة مشتقة من `mathBox` وارتفاع
   السطر (المعروض في §6) — تُطبَّق قبل/بعد كل مقطع `isBlockMath`.
2. `tex_text.dart:113` يستخدم **نفس** الدالة عبر `VisualMetrics` (مصدر واحد،
   كما ينص تعليق `visual_metrics.dart:1-14`)، لا `EdgeInsets.symmetric(4)` محليًا.

**ملفات متوقعة التعديل:** `layout_engine.dart`, `visual_metrics.dart`,
`exam_preview_screen.dart` (`_titleRow`, `_marksTarget`, `_pointRow`),
`tex_text.dart`. **لا** تغيير في `question_model.dart` ولا `document_ir.dart`
ولا `layout_document.dart` ولا محرك PDF.

**اختبارات مطلوبة:**
1. `_titleRow` ← بوابة جديدة: مسافة الدرجة إلى نهاية المنطوق = فجوة NBSP
   المقيسة ±0.75pt (نفس تفاوت `preview_field_geometry_test.dart`).
2. التفاف: منطوق من سطرين ⇒ الدرجة على **السطر الثاني** (حالة اختبار صريحة).
3. `design: marks never render on the row's far edge` — يمنع الرجوع.
4. فراغ المعادلة: معادلة بكسر ارتفاعها > سطر ⇒ `gapBefore ≥ (h−lineHeight)/2`.
5. صورة مقارنة جديدة في `visual_parity_fixture_test` (سؤال بدرجة ومعادلة).

---

## 11. التأثيرات المتوقعة للإصلاح

| الميزة | التأثر |
|---|---|
| تخطيط الأسئلة والفروع والنقاط | يتغير **راتب** الدرجة فقط؛ لا ترقيم ولا نصوص |
| ترقيم الصفحات | قد يزيد ارتفاع سطر العنوان إذا التفّ المنطوق في مساحة أوسع (الأسوأ: سطر إضافي) — يُقاس بـ`test/layout/canonical/*` |
| PDF | يتغير ارتفاع المعادلة فقط عند وجود `$$…$$`؛ الإحداثيات تبقى من المحرك |
| Word/DOCX | لا مسار DOCX في هذا الإصدار |
| المحرر والـIME | `TextField` يبقى كما هو؛ الحقول لا تفقد متحكماتها (§19.9) |
| الأدلة | إعادة توليد لقطات `build/visual_parity` وتحديث القياسات |

**مخاطر:** تغيير `_titleRow` يمسّ كل سؤال/فرع/نقطة ⇒ يجب بوابات
`production_fragment_*` + `preview_field_geometry` + البوابة البصرية قبل الدمج،
ولا يُقبل الإصلاح إن نجح أحدها وفشل آخر.
