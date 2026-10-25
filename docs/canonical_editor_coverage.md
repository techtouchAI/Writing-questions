# الخيار أ: جدول التغطية وخطة التفعيل

حالة البداية: `d4febcc61a2f473b0eec26f84dee87eb673efa21`، فوق دمج PR #47.
لا يعني وجود معالج اختبار اكتمال نقل وظيفته إلى سطح الإنتاج. يبقى شرط التفعيل
اجتياز اختبارات السلوك والهندسة على السطح الافتراضي دون حقن الراسم.

| الوظيفة الحالية | المصدر الحالي | مقابلها في الخيار أ | الحالة قبل التنفيذ / دليل القبول |
|---|---|---|---|
| رسم الورقة والمقاطع | `_buildPage` / `_buildQuestionFragmentSlice` | `CanonicalLayoutPreviewPage` من كائن `LayoutDocument` نفسه | موجود؛ يلزم نقله إلى الإنتاج بعد بقية التغطية |
| كتابة نص السؤال/الفرع/النقطة/الخيار | `_paperField` / `_field` | متحكم المصدر نفسه في طبقة إدخال مرتبطة بالحقل القانوني | الربط موجود في `_canonicalFieldBindings`؛ يلزم إثبات IME والتركيز عند تبدل الصفحة |
| تحرير من التكملة | متحكم مشترك بين النوافذ | مصدر واحد + إحداثيات الحقل في صفحة المؤشر | اختبار قانوني موجود؛ يلزم اختبار إنتاجي مع التراجع والإعادة والتنسيق |
| الحقول الفارغة | حقول تظهر داخل التدفق عند التحديد | محرر سياقي غير مطبوع، نفس `_field` و`update*` | يحتاج نقل؛ ممنوع إسقاط الحقل أو إعطاؤه ارتفاعًا مطبوعًا |
| تنسيق نطاق نصي | `_toggleSelectionFormat` / `_applySelectionColor` | نفس النطاق والمتحكم، ورسم `LayoutRun.style` | موجود في النموذج والمحرك؛ يلزم اختبار التحديد والتنسيق من طبقة التحرير |
| نص/معادلات مختلطة | `PaperField` / `MixedContentEditor` | نفس محرر المحتوى والمصدر، عرض قانوني منفصل | يحتاج ربط وقياس معادلة منفردة ومضمنة عند الحد |
| معادلة داخل حقل | `_editEquationInField` | المعالج نفسه مع هدف الحقل المصاب هندسيًا | موجود جزئيًا؛ يلزم اختبار إنتاجي |
| معادلة حرة/قوالب التخصصات | `_openEquationEditor` و`SmartExamToolbar` | نفس staging/drop والمعالجات | لا تتغير الدلالة؛ يلزم اختبار الإدراج على صفحات مختلفة |
| تحديد سؤال/فرع/متعدد/الكل | `_tap*` / `_longPress*` / `_toggleSelectAll` | إصابة من هندسة الكتل + نفس مجموعات التحديد | موجود في المسار القانوني؛ يلزم مطابقة الفروع والمعرّفات |
| تعديل رقم السؤال/الفرع | `_editQuestionLabel` / `_editBranchLabel` | إصابة جريان label → الحوار الحالي | يحتاج نقل؛ لا نموذج بيانات جديد |
| تعديل الدرجات | `_editQuestionMarks` / `_editBranchMarks` / `_editPointMarks` | إصابة جريان marks → الحوار الحالي | يحتاج نقل، ومنها الدرجة غير الموجودة حاليًا |
| إعادة ترتيب سؤال | `LongPressDraggable<int>` و`moveQuestion` | مقابض/أهداف خارج التدفق مشتقة من الكتلة | يحتاج نقل واختبار سحب فعلي |
| نقل/تبديل الفرع | `LongPressDraggable<BranchRef>` و`moveBranch` / `swapBranchContent` | نفس المعالجات مع أهداف هندسية | يحتاج نقل مع الحفاظ على اختلاف داخل/بين السؤالين |
| إضافة/نسخ/حذف سؤال وفرع | `_buildQuestionActionsBar` و`SmartExamToolbar` | الشريط الحالي خارج الورقة، نفس اختيار الهدف | موجود؛ لا دمج لأداتي إضافة الفرع المختلفتين |
| إضافة/حذف نقطة ونوعها/خياراتها | `_addPointButton` / `_pointRow` | أوامر سياقية غير مطبوعة، نفس `PointsOwner` | يحتاج نقل دون تعطيل أنواع النقاط أو الخيارات |
| صورة/شكل/مربع نص/فاصل | شريطان مربوطان بالمعالجات نفسها | موضع إدراج واحد لكل وظيفة مثبتة الازدواج | يحتاج إزالة الإتاحة المكررة فقط، لا حذف الوظيفة |
| تحريك/تغيير حجم/تدوير/ملكية عنصر عائم | `_buildAttachment`، المسار القانوني للعناصر العائمة | معالجات الملكية نفسها مع هندسة الخطة | موجود جزئيًا؛ يلزم اختبار نقل بين الصفحات ومقاطع المالك |
| حذف/تغيير فاصل | `_buildDividerWidget` | اختيار زخرفة الفاصل + نفس المعالجات | يحتاج نقل؛ يلزم إثبات بقاء الفاصل النهائي في الخطة وPDF |
| الترويسة والتذييل | `_buildHeaderBlock` / `_editHeaderAndFooter` | نفس حوار التحرير، إصابة كتل header/footer | موجود جزئيًا؛ يلزم اختبار النقر |
| التراجع والإعادة والحفظ والتصدير | المتحكم و`_save` / `_exportPdf` | المعالجات نفسها؛ PDF يستقبل التخطيط المطابق الحالي | موجود؛ يلزم اختبار عدم تصدير خطة قديمة أثناء التحرير |
| التكبير/الملاءمة/التوسيط/القفل | `PreviewToolbar` | نفس الأوامر خارج الإدراج | موجود؛ أهداف لمس 48dp واختبار 320/360dp |
| شريط التخصصات | `_showFormulas` / زر التبديل | مغلق أولًا، التبويبات الخمسة كما هي | يحتاج تعديل واختبار أن التبديل لا يغير المستند |

## مراحل التحقق

1. إصلاح المحرك المشترك: تغطية كامل الكتلة (بما فيها الفراغ والحشوات والفواصل)
   وإسناد المرفقات إلى مقطع المالك الصحيح. لا تعديل لمقاسات الصفحة أو الخط.
   تعاد اختبارات R2/R3/R5 واختبارات التخطيط/PDF السابقة قبل الانتقال.
2. بناء طبقة التحرير وتغطية البنود الناقصة دون تبديل السطح الافتراضي.
3. التفعيل بعد اجتياز اختبارات الوظائف؛ تحديث اختبارات السطح لتقيس الورقة
   القانونية الفعلية لا `RenderEditable` باعتباره مرجع طباعة ثانيًا. لا تخفيف
   للتوقعات الدلالية أو الهندسية، ولا استثناء لاختبارات إعادة الإنتاج.
4. تنظيم الأدوات وقياس أهداف اللمس وإنتاج الأدلة من سطح الإنتاج.
5. متابعة CI على SHA النهائي. الاختبارات الحمراء السابقة دليل فشل لا قبول.

لا تغييرات في الحقول المخزنة أو شكل المستند مطلوبة في أي مرحلة.

## نتيجة مرحلة المحرك ومهمة الأدوات المستقلة

- `c778a87` / تشغيل Build `40178123999`: التحليل بلا ملاحظات؛ 889 نجاحًا
  و6 إخفاقات معروفة غير معالجة بعد (R1/R4 وR7/R8 بعرضين). اختبارات
  R2/R3/R5، المقارنة بمرجع غير مقطّع، والأسطر النهائية عند تباعد 1.7 ناجحة.
  أصلح احتواء صندوق آخر سطر دون تحريك baseline أو تغيير الخط أو التفاف النص.
  Build APK لم ينفذ لأن بوابة الاختبارات الكاملة حمراء؛ ليس قبولًا نهائيًا.
- أُنجزت مهمة الأدوات المستقلة قبل تفعيل الورق الجديد، وهي لا تبدّل مسار
  الرسم. الأوامر المكررة حُذفت من الشريط الأساسي فقط؛ تبويب وسائط يبقى
  موضع الإدراج الوحيد. الصورة تعيد استعمال `_pickImageToSelection` نفسه
  بما فيه الإلغاء والخطأ؛ الأشكال الستة تعيد استعمال `_addShapeToSelection`؛
  مربع النص والفاصل يستعملان المعالجين نفسيهما بلا تعديل هدفهما.
- لم تُدمج «إضافة فرع» و«فرع جديد»: الأولى تستهدف سؤال أدوات السؤال،
  والثانية تبقي حل الهدف السابق `_addBranchToSelected`.
- اختبارات الأوامر القديمة أصبحت تفتح التخصصات وتختار الوسائط عبر نقرات
  حقيقية، ثم تتحقق من النموذج/التراجع/الإلغاء/الخطأ كما كانت؛ لا استدعاء
  مباشر للمعالجات. فحص اللمس يشمل كل استجابات الشريط الأساسي وكل أوامر
  التبويبات الخمسة بعرضي 320 و360، لا الأزرار الثمانية الأصلية فقط.
- هذا لا يثبت بعد أهداف لمس أدوات الورقة القديمة/مقابض العناصر: تبقى ضمن
  نقل طبقة التحرير. لا تفعيل للسطح القانوني الإنتاجي قبل اكتمال بقية الجدول.

### أساس طبقة التحرير (غير مفعّل)

`canonical_editing_layer.dart` ينقل مستطيل الحقل من الخطة عبر التحويل الفعلي
لصفحة الرسم إلى إحداثيات منفذ العرض، ويضع المحرر بحجم لمس أصلي خارج شجرة
طباعة الصفحة. لا يعيد قياس النص ولا يكتب ارتفاعًا في الخطة. تبديل مرساة
التكملة يغيّر الموضع لا موضع الودجت في الشجرة؛ اختبار المكوّن يفحص بقاء
`EditableTextState` والتركيز ونطاق IME composing مع التمرير والتكبير.
هذا أساس هندسي فقط؛ **لم يُربط بعد بمحرر السؤال/الفروع في الإنتاج**، ولا
يحقق وحده شروط نقل الحقول الفارغة والأرقام والدرجات والسحب وبقية الجدول.

### قيود الوصول إلى الأدلة

الصور وPDF تُرفع كـ artifact إنتاجي `production-fragment-repro` حتى عند فشل
الاختبارات. تعذّر تحميلها من رابط التنزيل الموقّع في بيئة الوكيل. جُرّبت
قناة نقل عبر annotations، لكن GitHub أعاد 4096 محرفًا فقط من كل رسالة؛
لم يكتمل التحقق من SHA256 للأرشيف ولم تُستخرج منه أي صورة. أُزيلت قناة
النقل غير الصالحة بدل إبقاء نصوص Base64 مقطوعة في سجلات CI. تبقى قياسات
JSON ومقتطفات السجلات مقروءة، وهذا **لا يعادل مراجعة بصرية** للصور/PDF.

### إصلاحا الإنتاج أولًا — قيد التحقق

بعد قياس 420615e: أدوات المتن الفارغ وإضافة النقطة تنقل من التدفق المطبوع
إلى `_buildQuestionActionsBar` ذي الارتفاع الثابت 52px والأزرار 48px.
محرر المتن السياقي يعيد استخدام `_field`/`PaperField` ومتحكم المصدر ومعالج
`updateQuestionBody`/`updateBranchBody`؛ إضافة النقطة تبقى `addPoint(PointsOwner)`.
اختبارات جديدة 320/360 تفحص الهدف، التحرير الفارغ/غير الفارغ، بقاء المحرر
والتركيز وIME، وإضافة نقطة فرع مع undo/redo. حالة هذه الاختبارات **غير محققة
بعد** حتى صدور CI. هذا إصلاح للمسار الإنتاجي القديم وليس تفعيل الخيار أ،
ولا يغيّر حالة الصفوف الأخرى في جدول التكافؤ.

## بوابة إصلاح الإنتاج: 80fbd9c — تحققت

- التشغيل `40230479989`: R1/R4 أولًا **8 نجاحات/0 إخفاق** (5 حالات فعلية
  مع أحداث تحميل/تهيئة المجموعة)، ثم **904/0** في البوابة الكاملة، و3/0 في
  البوابة القانونية. التحليل نجح، و**Build release APK وUpload APK نجحا
  فعلًا**؛ ليس مجرد إرفاق إصدار متخطّى.
- Visual وC6 ناجحان، وExtended `40230479922` ناجح. مصدر APK
  `writing-questions-release-apk`، artifact `12613156304`.
- R4 الطويل: 71 سطرًا/1775px في المصدر والخطة؛ مصدر السؤال كله
  1846.066665px في الجانبين. النقر الفعلي على آخر محرف والتحرير نجح؛ الفرع
  ينتهي في الصفحة 1 (ترقيم داخلي)، والسؤال التالي في الصفحة 2.
- فحص عرض الحقل صار يقيس عمود الحبر الفعلي لا مساحة مؤشر TextField،
  وصناديق الأسطر تستثني **مسافة اختيار طرفية غير مرسومة فقط**. عدد الأسطر
  ونص كل سطر وحجم الخط والسماحيات السابقة لم تُخفّف. قيد عرض الحبر يساوي
  عرض المصدر بـ1e-6px، ومؤشر 2px باقٍ.
- مرفق الإنتاج `12613345760` يتضمن PNG/PDF للحالات. لم تُجر مراجعة بصرية
  يدوية؛ وجود المرفق ونجاح CI ليسا ادعاء مراجعة.

## الدمج المرشّح التالي — لا تفعيل إنتاجي

`enableSeparateEditorCandidate` لا يعمل إلا مع حقن **كلتا** وصلتي السطح
القانوني؛ افتراضي الإنتاج لا يزال السطح القديم الذي اجتاز الإصلاح أعلاه.
يربط المرشّح `CanonicalEditingLayer` بحقل `PaperField` مرئي واحد في جذر
المنفذ خارج صفحات الطباعة. مرساته `LayoutLine.rect` من الخطة، وتحويله من
RenderBox الفعلي بعد layout، وبقاء الحقل تحت والد واحد عند تبدل المقطع.
المصدر `_field` والمعالجات الموجودة دون نسخ نص. أنماطه الافتراضية من
صاحب الحقل والعقد، وليست نمط كلمة محددة يُعمّم خطأ على بقية النص.

اختبارات المرشّح 320/360 (قيد التحقق): نقر النص المطبوع الحقيقي لكل مقطع
سؤال وفرع طويل، هوية المحرر/المتحكم والتركيز، IME، undo/redo، وعدم وجود
PaperField تحت شجرة الورقة، وبقاء كائن الخطة نفسه عند التحديد. أضيف ضابط
مستقل لاحتياطي المؤشر يقارن TextField عاديًا وآخر بعرض حبر مصحح وبنفس الخط
والعرض ومؤشر مرئي؛ حالة السطر المنكسر مشتقة بقياس الخط لا رقم عرض تخميني.

**ما يزال ناقصًا قبل التفعيل:** الحقول التي لا تملك جريانًا مطبوعًا، الأرقام
والدرجات والنقاط/خياراتها، مقابض/أهداف السحب، التغطية الكاملة للنص/المعادلات
والأوامر والحفظ، وتدقيق لمس جميع أدوات الورق. المرشّح ليس برهان تكافؤ هذه
الوظائف؛ لا يتغير حكم صفوفها إلى «مغطاة» لمجرد وجوده.

### Candidate follow-up — pending CI (production still off)

- `7ed5e38`: R1/R4 8/0, full 911/2 (both candidate fragment hit helpers),
  canonical 3/0, analyzer clean; Extended diagnostics passed. APK did not build.
- Diagnosed the test-coordinate mismatch: `WidgetTester.getRect` combines a
  transformed top-left with the **unscaled local size**. Actual paper is zoomed.
  Pointer targets now use `RenderBox.getTransformTo(null)` over the complete
  local bounds, matching the actual print transform. No layout tolerance or
  print geometry was changed to make a test pass.
- Optional question/branch bodies now have an opt-in native editor fallback
  anchored to their real owner/title block, or the shared plan's unplanned-owner
  page/body origin when nothing is printed. Existing body command/controllers/
  model callbacks are retained. Empty placeholders remain outside print flow.
  Typing/clearing bodies and retaining focus/controller/state at 320/360 are
  covered by new **unverified** integration tests, not yet claimed as passing.
- Native/contextual fields can request a 48dp minimum interactive height;
  printed legacy fields keep the zero default. This is not a print-height fix.
- CI now runs production R1/R4, then the native candidate/caret regressions,
  then the full suite/analyzer/APK. Candidate failures must not trigger costly
  downstream visual jobs or be hidden by full-suite output truncation.
- All previous missing-parity rows remain missing until individually proved;
  this does **not** approve or enable the candidate in production.

- `703909d` targeted results: production 8/0; native candidate 7/4 (load/setup
  included), so full tests and APK correctly did not run. Extended passed.
  Actual-transform hits reached pages 0/1, but short question continuation on
  page 2 remained occluded by the old editor anchor. Placement now docks to
  the opposite viewport edge only when the actual prior anchor is offscreen;
  the same native child/focus/composing/IME connection is retained. Component
  regression measures the offscreen anchor and visible continuation region.
  Empty-body test selectors corrected to the real `/title/statement` IDs.
  These follow-up fixes are pending CI, not yet acceptance evidence.

- `cdddb7a`: R1/R4 8/0; native gate 13/2. Empty body and placement/IME
  component cases passed at both widths; multi-page question traversal passed,
  but the final branch continuation still failed reachability. Full/APK did not
  run. At document end both `ensureVisible` alignments clamp to the same maximum
  offset. The integration helper now also performs bounded real edge drags in
  both directions (without closing/recreating the editor), and reports actual
  transformed page/pane bounds if no printed hit can be reached. Still pending.

## Candidate core verified — cdf1b73 (still not production activation)

Build run `40233457138`, main job `121289923152`, passed production R1/R4,
then the focused native gate, full required tests, analyzer, actual release APK
build and upload. Visual/C6 were not yet complete when this entry was written;
Extended run `40233457180` passed. Binary evidence remains not manually reviewed.

Integration-tested at 320/360: real printed-pointer editing across every fragment
of genuinely multi-page question AND branch bodies; one native editor/controller/
focus and no new IME client across fragments; composing insertion survives
reflow; undo/redo; optional question/branch bodies accessed outside print, typed,
cleared, and re-anchored without replacing the input; no printed geometry/data
change from selection. These do not prove empty statements/entirely unprinted
owners, math/commands/formatting, drag, points/options, or every touch target.

Next candidate-only increment (pending CI): printed question/branch label/marks
hits route to the existing `_edit*Label`/`_edit*Marks` dialogs, resolving owner IDs
against the current model. Equivalent native 48dp commands remain available
outside the paper even when a zero mark has no printed run. Tests exercise actual
printed hits, native command/field/dialog touch sizes, save/cancel, zero marks,
undo/redo, unchanged other question/text and stored range formatting. Point and
option metadata, empty statements, and the other missing rows remain uncovered.

### Production mixed-math evidence fixture — pending validation

`production_mixed_math_evidence_test.dart` uses the DEFAULT production screen
with the same `MathSnapshotHost` installed by `main.dart` (no resolver or asset
injection). A test-only controller subclass observes `applyLayoutPlan`, so its
PDF receives the **actual live plan object**, not a recomputed lookalike. At
320/360 both question and branch bodies must independently span pages and
contain inline/display math. The fixture writes phone PNGs and full-paper PNGs
for every page before selection, after question selection, and after branch-only
selection, plus the same-live-plan PDF and JSON manifest into the existing
`production-fragment-repro` artifact directory. Selection compares all native
source field rectangles in page coordinates to 1e-6px (IEEE roundoff only),
while asserting identical document and plan objects. These files are not yet
verified/generated and are not a manual visual review or an editing-parity claim.
