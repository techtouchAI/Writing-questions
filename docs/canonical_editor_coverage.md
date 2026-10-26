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

## Metadata and production evidence verified — 324fd4c

Run `40234173938`, main `121292228670`: production 8/0, focused native 17/0,
full **922/0** (103 suites), canonical 3/0, analyzer clean, actual APK built and
uploaded. Extended `40234173929` passed. Visual/C6 were still outstanding at
this checkpoint, so this is not an all-workflow completion statement.

- Question/branch printed label/marks routing, native 48dp equivalent controls,
  existing dialogs (including actual focus/field/action touch sizes), cancel,
  zero marks, undo/redo, other-question/text/range-format preservation passed.
  Point/option metadata is still missing.
- Production mixed-math 320/360 fixture passed. Actual live-plan PDF plus every
  page's phone/full-paper PNGs in three selection states are in
  `production-fragment-repro` artifact `12614122565` (11,659,580 bytes).
  Actual APK artifact `12614367237` (28,384,212 bytes). No manual image/PDF review.

### Next source-field increment — pending verification

A candidate-only 48dp access menu relocates existing empty question/branch
statement/body fields out of print flow, including entirely unprinted owners
and whitespace-only fields. It resolves persistent owner IDs against the live
model at selection and uses the original source controllers/update callbacks.
No stored model, print placeholder, or default production tool is added.
Tests cover all four source roles at 320/360, composing insertion, the transition
from no printed owner to printed text and back, and no editor/controller/focus/
IME-client replacement. Existing optional-body cases also now test composing
and no reconnection. Empty points/options/category and other parity rows remain
uncovered; production activation remains prohibited.

The production evidence fixture now additionally requires real `mathSnapshot`
metrics and successful PDF rasters for EVERY formula, verifies both inline and
block semantic nodes, and records actual maximum coordinate delta/field count.
This strengthens evidence against silent readable-text fallback; its new checks
are pending CI and do not retroactively claim a manual visual comparison.

### Option identity race reproduction — deliberately not acceptance

Audit found a concrete missing contract: option models/IR already have persistent
IDs, but candidate bindings/controllers/callbacks still use positional indices.
Deleting option 0 while option 1 is focused can synchronously sync the focused
slot to the next option; IME input arriving before the next widget build then
uses the captured old index and edits the wrong option. New 320/360 regressions
exercise that exact same-frame race for question AND branch points, require the
original option ID/controller/editor/focus/composing/IME client to survive, and
check untouched sibling data and formats plus undo/redo. The model deletion is
an external-mutation race probe, **not** proof of a native delete-button workflow.
The regression is being introduced before its source repair; a red run is not
acceptance. `b0c8b58` has passed its focused native gate and was still running the
full suite when this reproduction was added. Production remains on repaired
legacy; point/option UI parity is still incomplete.

- Race baseline `322471f`, run `40235171531`, main `121295126393`: production
  8/0, focused native **19/2**. Both widths reproduced the expected failure:
  selected option remained `SECOND` instead of `SECONDم` after the earlier
  deletion plus same-frame IME update. Full/APK correctly did not run.
- Repair now pending CI: candidate option source keys encode persistent point
  AND option IDs (transient view keys only; no stored model change). Field sync,
  lifetime pruning, current alignment/range-format targeting, and owner activation
  share that resolution. Old-layout IR options bind by model ID, not stale
  index. Candidate source callbacks resolve question/branch/point/option IDs at
  INPUT TIME, including before the next rebuild; retained controllers are not
  swapped to another option. Legacy production keeps its existing keys/surface.
  This is a race/data-identity repair, not completed point/option command parity.

### Verified persistent-source repair (`02d2c64`)

- Build run `40235447739`, main job `121295907603`: production R1/R4
  **8/0**, focused native **21/0**, full **926/0**, canonical gate **3/0**;
  analysis and **actual release APK build succeeded**. This includes the two
  same-frame option-identity regressions and strengthened real-math fixture.
- Extended run `40235447684` and the follow-on Visual job succeeded.
  C6 is still pending at this checkpoint, not counted as success.
- Production artifact `12614364524` (11,659,678 bytes), actual APK
  `12614424446` (28,384,913 bytes). Neither images nor PDFs have been manually
  reviewed/downloaded. No visual equivalence claim follows from test success.
- GitHub limits notices to ten per step: the existing production publisher
  exhausts those on R1–R7. A separate R9 notice step now exposes BOTH mixed-math
  manifests through Checks API, and requires both files after a successful full
  run. It does not replace downloadable PNG/PDF evidence or manual review.

### Native point/option commands — implementation awaiting CI

Candidate-only external 48dp controls now route to existing point kind/label/
marks/delete and option add/label/delete handlers, using persistent IDs and
fresh owner/index lookup. Printed point/option metadata opens the same dialogs.
The empty-source menu exposes existing blank point text and blank MCQ options;
no empty source, button, or editor is inserted into printed flow. Kind changes
preserve existing options; changing away from MCQ while an option is active
switches the editor to that point's text. Deleting an active source explicitly
closes its editor, retaining the selected question/branch owner.

New 320/360 tests exercise real menus/dialogs for question AND branch points:
all four kinds, option-ID retention, native/printed metadata, blank option to
text, UI option deletion with sibling preservation and undo/redo, option add,
UI point deletion and exact-model undo, existing add-point action, empty point
access, multiline source and undo-to-empty/redo with the same native editor,
focus and IME-client count, and other-owner/range-format preservation.
**Not yet compiled/tested; not acceptance.** Active-option kind-switch focus,
category clearing, reorder drag, math/formatting command parity, every remaining
control's touch target, and stale completed-asset/layout pairing remain open.
Production candidate flag remains OFF; no activation, merge, or branch removal.


### Point command first run and focus-switch repair (pending verification)

- `02d2c64` finished ALL workflows successfully: Build `40235447739`,
  including Visual `121297507891` and C6 `121298187920`, plus Extended
  `40235447684`. Release attachment skipped because this is not a tag/release;
  the actual APK build and artifact succeeded. No manual visual review.
- `4d79d57`, Build `40236825017`, main `121300068869`: production **8/0**,
  native **21/2**; both new command tests fail opening an empty option (the
  expected source field is absent). Full suite and APK correctly did not run.
  Analysis has one `curly_braces_in_flow_control_structures` info; Extended
  `40236825028` succeeded. This is NOT point-command acceptance.
- Candidate native field focus callbacks now reject a retired field whose key
  differs from the explicitly selected active source. Popup focus restoration
  must not overwrite a newly selected source before its widget mounts; legacy
  activation is unchanged. The original missing-field assertion is retained
  and now reports mounted field keys if it fails again. The analyzer info is
  corrected with braces. This repair awaits CI, not a claim of a green result.


### Point commands accepted by tests; analyzer still blocks APK (`a02d717`)

Build `40343329932`, main `121643562734`: production **8/0**, native **23/0**,
full **928/0**, canonical gate **3/0**. The source-switch guard repairs both
missing-option regressions without closing the old editor in the test. The
new native add/delete/undo/redo/empty point/option workflows pass at both widths
for question and branch owners. This is scoped integration evidence, not full
parity or activation. One multiline empty-option-menu `if` still violates the
brace lint (the prior correction addressed the adjacent point-text `if`).
Analysis failed and APK did NOT build on this SHA; this is not acceptance.

The separate manifest publisher worked: R9 at BOTH widths reports 5 pages,
question pages 0/1/2, branch pages 2/3/4, 8 math runs / 4 unique rasters with
`mathSnapshot` metrics, 20 measured source fields, and **0.0px maximum selection
geometry delta**, tolerance 1e-6px, PDF using the observed production live plan.
Manual visual review remains false.

### Point continuation/geometry evidence increment — pending verification

The remaining multiline brace lint is fixed. New 320/360 tests require each
question/branch POINT TEXT and MCQ OPTION itself to span multiple pages, cover
every non-whitespace source offset exactly once, keep line/glyph metric boxes
inside the shared plan's body bounds, and leave the following question clear of
the final branch. They hit the original AND every continuation (the ending run
on the final fragment), compose text into the same model field from EACH,
and undo to the exact original document including other owners/options/formats.
The native editor/controller/focus/IME connection must survive every fragment
and edit/undo. No activation or assertion weakening is involved.

All candidate printed-hit helpers now compare the actual transformed paper
rectangle before/after activation within 1e-6px (floating-point matrix roundoff
only), as well as identical unchanged-data layout. Opening native command
menus/dialogs must keep all planned printed line coordinates unchanged.
The command test additionally switches the ACTIVE OPTION away from/back to MCQ,
requiring focused point-text fallback and exact retained option models.

This fixture generates clearly labelled **opt-in candidate** R10 PNGs for every
page at phone/paper resolution before selection and with the option editor
active, plus PDF using the displayed restored-model layout and manifests.
These are separate from default-production mixed-math R9 evidence. The workflow
publishes/requires both widths of each after a successful unfiltered full run.
New assertions and evidence generation are NOT compiled/tested yet. Neither
candidate PNGs nor PDFs have been manually reviewed; production remains legacy.


`a02d717` follow-on Visual `121646916853` and C6 `121648615396` subsequently
finished successfully; Extended `40343329986` also succeeded. Overall Build
remains FAILED due to the analyzer lint, and APK remained skipped. C6's
non-gating historical geometry report still lists 95 tight-centre violations
for its legacy comparison artifacts; a green diagnostic job is not proof of
zero PDF/preview discrepancies and does not replace manual R9/R10 review.


### R10 boundary diagnosis — shared run-box style mismatch (repair pending CI)

`dc9ba67`, Build `40345220783`, main `121650227093`: production **8/0**,
native **23/2**; the two new continuation cases stop BEFORE input at a boundary
run box bottom **801.1151728723931pt**, body bottom **799.3700787401575pt**.
The planned line itself fits. Analysis is clean, but full suite/APK did not run;
Extended `40345220369` succeeded, downstream Visual/C6 correctly skipped.

Tracing the box to both painters distinguishes metadata from actual ink:
`FlutterTextMetrics._layoutOnce` takes fragment HEIGHT from the styled paragraph
selection box but measures its BASELINE OFFSET with `lineHeightFactor: 1`.
The actual preview painter measures the same styled run with the document's
line-height factor and independently aligns its baseline; PDF also aligns from
its own embedded-font baseline. Thus the hit/selection box is displaced downward
relative to what is painted. This failure is NOT yet proof of cropped pixels.

The fix uses the SAME resolved style for the run baseline and its styled box;
no pagination/line baseline/wrapping/font/page/clip changes, no larger tolerance,
and no source/model fields. Metrics backend version increments to invalidate
cached box metadata. A focused independent TextPainter regression checks both
baseline and box height at factors 1/1.2/1.45/1.7, and joins the native-first gate.
The R10 body-bound/coverage/hit/edit assertions remain unchanged. This is a
pending shared-metrics repair, not acceptance or a visual equivalence claim.


### Font frames versus painted ink — R10 measurement correction

`4b9d144`, Build `40346352752`, main `121654187481`: production **8/0**,
native **33/3**; Extended `40346352543` succeeded. Full/APK did not run.
The independent metric case shows why a font frame is not an ink measurement:
at height 1, the adapter's STRUT selection height is **13.999998pt**, while
Flutter's TIGHT font selection bounds are **23.841999pt**. The styled baseline
fix clears the former bottom overrun but a boundary frame begins at
**42.219685pt** versus body top **42.519685pt**. Neither observation alone
proves clipped painted pixels. Analysis also flags the test's missing const.

The metric regression now compares the SAME `BoxHeightStyle.strut` as the
adapter (and fixes the const lint), retaining the actual styled-baseline check.
R10 retains exact planned line containment, source-offset coverage, unchanged
paper geometry, per-fragment input and native-state invariants. Instead of
calling a strut rectangle “ink”, every near-edge source run is rasterized using
exactly the preview painter's font, style, baseline, scale and page pixel phase.
Its raw RGBA bytes with versus without the UNCHANGED shared body clip must be
**identical, zero differing bytes**. Only scratch image allocation is padded;
no production clip, font, geometry tolerance, or pagination is changed. This
is a stronger direct painted-pixel visibility check, not allowance for overflow.
All results still await CI; do not infer actual glyph clipping or acceptance
from the earlier incorrectly interpreted frame measurements.

### Point/option integration checkpoint `97c7569` — verified main gate

Build `40347503909`, main `121658253342`: production **8/0**, native **36/0**
(4 suites including focused font metrics), full **931/0**, canonical **3/0**,
clean analysis and **actual release APK build succeeded**. Extended
`40347504021` succeeded. Visual/C6 are still pending at this checkpoint.

R10 manifests for BOTH widths confirm **20 real pages**, point text pages
0–2 / branch-point text 9–11, question option pages 2–9 / branch option 11–19.
Each printable source offset appears once; every source fragment edits its
original model and undo restores the entire document and range formats.
Actual boundary run raster bytes are identical with/without the unchanged body
clip. Actual page activation delta is **0.0px** (tolerance 1e-6px). The following
question shares page 19 without planned-line overlap. PDF uses the displayed
live restored-model plan; manual visual review remains false.

Reviewable PNG/PDF artifact `12662827368` (32,655,826 bytes) includes R9 default
production mixed math AND clearly separate R10 opt-in candidate evidence.
Actual APK artifact `12662233586` (28,385,653 bytes). Logs/artifact downloads
remain inaccessible in the agent environment, so none were manually reviewed.

| Current parity area | Implemented counterpart | Verified scope / still open |
|---|---|---|
| Question/branch source, empty fields, continuations, IME | Existing source controllers in anchored native editor | Integration verified at both widths; category clear/reopen still open |
| Point/option add/delete/kinds/labels/marks/undo/redo | Existing handlers + external 48dp native commands and empty-source menu | Question AND branch owners verified; active-option kind switch retains all option data |
| Long point/option source, every continuation, native lifetime | Actual shared-plan hits + the SAME model/controller/editor | 20-page cases verified, all characters covered, model/format round-trip exact |
| Selection/command opening and page-edge visibility | Fixed canonical paper + external chrome | 0px activation shift and byte-exact painted boundary visibility verified |
| Actual ink separation from the following question | Planned non-overlap plus actual glyph bounds | Additional raster-ink gap assertion below awaits CI |
| Reorder drag, math/range-format command parity, remaining touch targets | Existing handlers remain available; counterpart coverage incomplete | NOT accepted; production activation prohibited |
| Completed asset/layout pairing, stale export transitions | Current async canonical preview pipeline | Still needs deterministic delayed-asset coverage and repair if exposed |
| Default-production preview/PDF evidence | R9 live-plan PNG/PDF with real inline/block math | Automated geometry/snapshots verified, manual visual comparison NOT performed |

The next test-only increment additionally scans actual alpha pixels of the
final branch and next-question runs, requiring non-overlapping raster ink (not
only line rectangles), and records the measured pixel gap. Scratch RGBA copies
retain compact byte storage; no production code/geometry/clip change. This new
assertion is pending CI. The candidate remains OFF; no merge or branch removal.

### Follow-on setup stall — no false all-CI acceptance

At 2026-10-26 15:53 UTC, `97c7569` Visual job `121665272351` remains in
“Install rendering tools” since 15:28:30 (over 24 minutes); comparison has not
started. Main/APK and Extended successes remain valid, but overall/Visual/C6
success is NOT claimed. A fresh download attempt of artifact `12662827368`
also failed with EOF at its signed Azure URL; no images/PDF were extracted.

The Visual install step now adopts the existing C6 bounded-network approach:
150s apt update, 600s installation, 20s network idle timeouts/retries, 16m step
budget. All THREE existing required packages remain required; timeout/failure
is an actual failure, with phase/status and the failing log tail exposed through
Checks annotations. No visual fixture, comparison, RMSE threshold, or test gate
is removed/relaxed. The new push supersedes this unbounded setup stall, not a
failed comparison or test. Final-SHA follow-on jobs still must actually finish.
The ink-gap test/doc checkpoint landed in `e5f9189`; the bounded setup is in the
following commit after a local patch-script syntax error was corrected.

### Final-run scheduling note

`78af1eb` Build `40353886832` was cancelled before any job/check ran while the
two close pushes competed with the still-running `97c7569` workflow and pending
`e5f9189` Build. It is NOT a test/build result. Local workflow YAML and setup
Bash parsing succeed. `gh run rerun` gave a generic “workflow may be broken”
message, but the direct rerun API reports **403 Resource not accessible by
integration**; no rerun/cancel API retry is attempted. A documentation-only push
now requests a fresh normal run with the SAME source/tests/bounded tool setup.
Final acceptance still requires this latest SHA's actual jobs and APK, not a
cancelled run or the earlier main-gate success.

## Acceptance closure after `2ed3ec9`: actual evidence retrieval

The artifact redirect was reproduced: the authenticated GitHub API succeeds,
then the signed Azure blob download returns EOF in this sandbox. This is not
an APK/test failure or an invalid GitHub credential. A new opt-in
`[review-evidence]` CI job transports allowlisted ORIGINAL fixture PNG/PDF/JSON
bytes through GitHub's blob API. Blobs are unattached: no commit, tree, ref,
branch, release or tracked binary is created. Job-scoped contents:write is only
for that API; no new repository branch or publication destination is used.
Checks notices contain small references/checksums, not truncated Base64 data.
The reader verifies run/SHA provenance, byte length, SHA-256 AND Git blob SHA-1
before writing any review file. Missing/truncated data is an error, not review.
This diagnostic transport does not change app code, clipping, tolerances,
fonts, rendering or test gates. R1/R4/native/full/analyze/actual APK still run.
Visual review remains pending until original files are retrieved and opened.
Remaining drag/math/format/async/touch parity remains unaccepted; flag stays OFF.

## Original-byte review checkpoint — a82ccc8 (not visual acceptance)

The original Azure redirect still fails in the review sandbox. The same-run
Git-blob route worked: 50 original files were downloaded and checked against
run `40378917968`, source `a82ccc809800f3ab5e91b21483467f7f4bad4c10`, byte
length, SHA-256, and Git blob SHA-1. However, GitHub capped the job's annotations
at **50 of 52 references**. The missing files were `r9-360-same-live-plan.pdf`
and `r9-360-question-selected-page-4-paper.png`. This is **partial retrieval**,
not successful complete transport. The repair packs two references per notice
(maximum 40 notices for 80 files), enumerates required companion files from the
manifests, and verifies an inventory count plus inventory checksum before
retrieval can emit a complete-success marker. Four offline regressions exercise
packing, complete retrieval, truncated annotations, and corrupt original bytes.
No application code, print geometry, clips, fonts, or tolerances changed here.

### Actual visual examination performed

Original PNGs were opened alongside **the corresponding original PDF pages**
rasterized with MuPDF at 96 dpi. This is agent examination of visible content,
not a human/device sign-off and not a deduction from green CI.

| Evidence actually opened | Visible result | Acceptance |
| --- | --- | --- |
| R9 production, 320, all five paper pages against corresponding PDF pages | Inline/display math are black Ahem-like blocks, not readable equations. Header typography/placement differs. Continuation boundaries show partial glyph rows; preview's final branch tail does not visibly contain all of PDF's B109 ending. Text/line placement differs. | **Fail / investigate**; neither visual match nor math readability proved |
| R9 production, 320, page 3 before/question-selected/branch-selected and page 5 before/branch-selected | Selection decorations appear without an obvious reflow in the opened pairs; existing boundary/tail defects remain. | Selection observation only, **not** print acceptance |
| R10 native candidate, 320 **and** 360, page 20 paper against corresponding PDF page 20; same paper before/option-selected | Last option text remains visible above NEXT without overlap; selection decoration does not visibly move printed text in these pairs. | Narrow visual check passed for **this page only**, not complete candidate acceptance |
| R10 native candidate, 320 and 360, selected phone screenshots | Native editor is visible, but labels/icons appear as test-font boxes. | Cannot use these images to sign off tool readability/touch or all functions |
| R9 production, 360, complete PDF comparison | PDF reference was truncated by GitHub. | **Not reviewed** until complete republish/retrieval |

Review files reside outside Git at `/home/user/review-a82ccc8/`; derived
same-page views are under `comparison/`. Original run:
https://github.com/techtouchAI/Writing-questions/actions/runs/40378917968

The font hypothesis has a concrete test-environment lead:
`test/views/widgets/math_snapshot_host_test.dart` explicitly documents Ahem
instead of KaTeX, while R9 only registers application paper fonts through
`FlutterTextMetrics.ensureFontsLoaded`. This is not yet proof that loading the
package's production fonts resolves layout differences. First reproduce with
the **unchanged production font assets** registered in the evidence harness;
then trace any remaining plan/source/paint mismatch. Do not replace fonts,
enlarge clips, change tolerances, or call the existing block images math parity.

All Actions for a82 completed: R1/R4 8/0; native 36/0; full 931/0; canonical
3/0; analyzer clean; **actual release APK built**; Visual and C6 succeeded;
Extended `40378917818` succeeded. C6 still reports 95 historical non-gating
violations. These automated successes do **not** override the visible failure.

### Acceptance still open (no production activation)

| Required remaining behavior | Current proof status |
| --- | --- |
| Actual question and branch drag, resulting model/order/coordinates/PDF | **Unproved** on the candidate; legacy handlers are not equivalent proof |
| Readable inline/display math, mixed RTL/English, colors/all formats vs PDF | **Failed/incomplete visual evidence**, expanded matrix pending |
| Async image/math/layout completion and export/save races | Root candidates identified; draft real-work regressions not yet compiled/run, no repair claimed |
| ALL editing tools, touch targets, and empty fields at 320/360 | Existing targeted cases do not establish an exhaustive audit; missing rows remain missing |
| Candidate activation / merge | **Prohibited**; stays off, no PR merged, no branches deleted |
