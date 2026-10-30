# تقرير الإغلاق الشامل — OPEN / candidate OFF

**حالة المراجعة الحالية: OPEN.** لا تفعيل، لا دمج PR، لا حذف فرع. هذا القسم
يحل محل أحكام الحالة القديمة أدناه؛ السجل الأقدم محفوظ للتتبع، وليس نتائج الشفرة الحالية.
الفرع: `arena/8513fa6c-writing-questions`.


## متابعة6b72453 — أصل الفشل معروف؛ التعديل التالي ينتظر البوابات

**هذا القسم يتقدم على السجل التاريخي أدناه. OPEN / candidate OFF؛ لا دمج ولا حذف.**
اعتمد المستخدم صراحةً **inline بعد المنطوق حسب اتجاه السطر**، لا حافة الورقة؛
الدرجة وحدة غير قابلة للتجزئة وتبقى مع آخر كلمة عند الالتفاف. تخطي السؤال القديم
لم يعد الحالة الحالية. قاعدة NBSP موجودة أصلًا في `_titleBlock` المشترك؛ لا ندّعي
أن قرار المستخدم أو إضافة اختبار يصلح صف `_titleRow` القديم ذي Expanded تلقائيًا.
يبقى اختلاف ذلك الصف الإنتاجي مانعًا، إلى أن تثبت طبقة Option A كاملة قبل التفعيل.

### قياس6b نفسه، لا642 ولاcf

- [Main41103676578](https://github.com/techtouchAI/Writing-questions/actions/runs/41103676578)
  انتهى FAILURE فقط في Android320/360: `Actual PDF share control not available`.
  build/Visual/C6/transports SUCCESS؛ release attachment SKIPPED. نجاح C6 job التشخيصي
  ليس قبولًا للـRMSE أو كل finding.
- [Extended41103676730](https://github.com/techtouchAI/Writing-questions/actions/runs/41103676730)
  SUCCESS. السجلات الكاملة المتحققة: production8، native249، full1068، canonical3،
  صفر error/skip في هذه الأوامر؛ الأعداد تشمل setup/loading كما في السجل الأصلي.
  الحالات غير المخفية:5/195/867/2. analyzer: No issues found؛ actual APK بُني.
  ملفات `*-before.log` اختبارات baseline سالبة محفوظة، لا نتائج إصلاح جديدة.
- APK الفعلي30,600,573byte، SHA256
  `6bfdd30f31e91d5d2d3f19b9456e05942b7ad20688e2738bf4ab567e19c2d37e`؛
  طابق audit وruntime **للـ320 والـ360** مع SHA/run نفسيهما.
- جُلبت51 أصلًا كاملة لكل عرض،11سجلًا،14Visual،80إنتاج من6b عبر القارئ الصارم؛
  لا dedup ولا تعطيل تحقق SHA/عدد/هوية. أصول الفشل محفوظة لا تستبدل بأصول تاريخية.
  provenance والمصادر في `/home/user/final-followup/6b-*` خارج Git.
- عبر InputConnection الفعلي وصل BODY كاملًا8360codepoint وIMETAIL؛ حفظ المحتوى
  مع IME مفتوح ثم عرض PDF الحقيقي. لا يُحوّل هذا إلى نجاح fullsave/reopen/PDF:
  المشاركة والفحص بعد إعادة التشغيل لم يُنجزا. صور09/11 وnative XML توثق المرحلة.

### التعديل الحالي وماذا لا يغير

`PdfPreviewScreen`: أيقونتا الحزمة printing5.13.4 الأصليتان بلا اسم في native
accessibility، رغم وجودهما مرئيًا. نستعمل **نفس PdfPrintAction/PdfShareAction**
والـbuild callback وbytes/filename وشروط قدرة المنصة، مع semanticLabel وTooltip
وأهداف48dp. تُعطّل الإضافتان المجهولتان الافتراضيتان فقط، لا وظيفة الطباعة/المشاركة.
لا نقر إحداثيات بديل، ولا تغيير fonts/PDF engine/pagination/clip/هوامش/ارتفاع صفحة.

أُضيف انحدار320/360 يستدعي أفعال الحزمة الحقيقية حتى method channel، يتحقق من
الأسماء والتباعد/containment و48dp ونقر الزوايا والـPDF bytes/filename/bounds،
وثلاثة أزرار zoom والقدرات غير المتاحة. ليس دليل Android أو raster parity.
اختبار marks لم يُحذف أو تُرخَ سماحيته؛ صار يشترط **آخر source fragment** والسطر
الأخير، لا أي label/word، مع العربية/English ومختلط/قصير/طويل/سطر جديد.
اختبارا PDF/marks ضمن native-first ثم full، لا استثناء ولا bypass.

امتد actual IME إلى3ترتيبات Arabic/English/digits داخل **حقل الاسم نفسه وحقل
المنطوق نفسه**، مع مقارنة حرفية بعد كل جزء، ونطاق events وXML كامل لكل ترتيب
داخل runtime.json؛ ثم يعود المصدر النهائي نفسه قبل clipboard والحفظ والتصدير.
لم يُضف hook أو تغيير بيانات إلى APK الإنتاج. Python المحلي15Android و16transport
نجح؛ Flutter/analyze/APK/Android/Visual/C6/Extended للتعديل الحالي **لم تعمل بعد**.

### C6 والقيود الباقية

أُعيد تدقيق الأصول6b نفسها: الصفوف التاريخية الثلاثة حاضرة؛ outlines مطابقة،
أخطاء أصل glyph القصوى0.000015021/0.000028571/0.000025979pt، وفحوص سلبية5 ناجحة
على الأصول نفسها. ليس ادعاء التقاط glyph IDs من Flutter أو تطابق raster عام.
RMSE العام، كل tool×content×boundary×history×PDF، جميع مقابض48dp الفعلية،
الوسائط/التزامن الكامل، export أثناء التحرير وبعد إغلاق IME، وfull native reopen
كلها لم تُغلق بهذه التغييرات. لا يغني نجاح العربية/الاسم عن long options/continuations.
يلزم كل البوابات وفحص الأصول على SHA نهائي واحد؛ نجاحات6b ليست نتائج التعديل التالي.

---

## الدورة الحالية بعد6732191 — تنفيذ وتحقق جاريان، OPEN

### حماية البداية

حُفظت الشجرة المستعادة في نسخة خارج Git، وقورنت كل blobs مع origin6732191:
صفر اختلاف وصفر ملف زائد. حُوذي HEAD على الفرع نفسه بلا تغيير للمحتوى أو
force-push. أُعيد جلب125 أصلًا متحققًا: 11سجلًا،80إنتاج،7Visual،27Android.
هذه baseline فقط؛ لا تُنقل نتائجها إلى تعديلات لاحقة. لا تفعيل ولا دمج ولا حذف.

### موضع الدرجة: لم يصل اعتماد

عُرض اقتراح Inline غير قابل للتجزئة مع أثره؛ تخطي سؤال الاختيار أو تكرار الطلب
ليس موافقة. لم يُختر مرجع legacy/PDF تلقائيًا، ويستمر العمل الآخر دون تغيير
موضع الدرجات افتراضًا. ما زال القرار مطلوبًا قبل توحيد ذلك التصميم.

### Android: تركيب نص عبر لوحة حقيقية منفصلة

أُضيف fixture APK مستقل يستخدم InputMethodService وInputConnection الفعليين.
تُضغط أزراره عبر الواجهة: setComposingText،commitText،finishComposingText،
العربية المشكّلة، الإنجليزية، الأرقام، clipboard، multiline، و320تكرارًا ينتهي
بـIMETAIL. لا adb text في هذه الحالات، ولا بث لإدخال النص أو seed للنموذج.
APK الإنتاج لا يحتوي لوحة الاختبار أو hook. يبقى smoke ASCII السابق اختبارًا
منفصلًا، لا دليل تركيب. matrix320/360dp على Android35 يستخدم APK الإنتاج نفسه.

المسار يطلب تطابق الاسم والمنطوق والجسم حرفيًا، تنقلًا وحفظًا والكيبورد مفتوح،
PDF فعليًا متعدد الصفحات من مسار المشاركة، ثم restart وفتح الحقول الثلاثة
وفحص كامل قيمها، لا مجرد ظهور اسم في المكتبة. تحفظ الأحداث وXML وPNG
وdumpsys وPDF وهاش APK. ست مجموعات نشر تغطي حتى60مرجعًا؛ لا تغيير لحدود
القارئ أو فحوص النقص والتلف وSHA. نشر11سجلًا محفوظ.

**3987e69 لم ينجح في قبول IME.** في Main41087652854 بُنيت لوحة الاختبار،
لكن كلا العرضين رفض `ime enable`: Android قال إن معرف اللوحة غير معروف في سجله،
بعد انتهاء التثبيت مباشرة. logcat الأصلي يحفظ الرفض. أُضيف انتظار محدود
لسجل `ime list -a -s` الفعلي قبل طلب التفعيل، لا إعادة محاولة لفشل تركيب
أو تجاوز له. كما تحفظ أحدث أحداث/صورة/XML حتى إذا فشل المسار مبكرًا.
يلزم نجاح إعادة التشغيل الجديدة؛ لم يُحتسب هذا التشخيص إصلاحًا مثبتًا بعد.
رفض القارئ الصارم جلب حزمة من job فاشل رغم أن خطوات نشره نجحت. لم يُخفف
القارئ: فُصل نقل أدلة Android في job مستقل دائم بعد القبول الفاشل أو الناجح،
كما في نقل الإنتاج، كي تبقى أصول الفشل قابلة للجلب ولا تتحول إلى نجاح قبول.
اختبارات Python المحلية10 (6بروتوكول+4smoke) لا تعادل تشغيل Android.
حتى نجاح fixture لا يثبت Gboard prediction/swipe/handwriting أو كل السباقات؛
completeAcceptance يبقى false ولا ادعاء تجربة جهاز مادي.

### السحب القانوني: تنفيذ جديد ينتظر Flutter

أُضيفت CanonicalReorderPanel إلى **المرشح المحقون فقط**: مقابض48×48dp بمسار
hit-test opaque، أهداف56dp، وتمرير أثناء السحب، كلها خارج هندسة الطباعة.
بيانات السحب IDs ثابتة؛ تُحل الفهارس من النموذج الحالي عند الإفلات، مع رفض
القفل أو المصدر المحذوف. نفس moveQuestion/moveBranch/swapBranchContent:
نقل داخل السؤال، وتبديل المحتوى والدرجة بين سؤالين، دون تغيير الدلالة.

اختبارات الإنتاج الستة الأصلية محفوظة دون تعديل. أُضيفت6حالات corner-drag
320/360 مع النموذج وترتيب/نص/إحداثيات PDF وundo/redo وصور قبل/بعد، و4حالات
تزامن/حذف/قفل/وصول لآخر عنصر. **لم تُنفذ Flutter لهذه الإضافة بعد**.
حزمة19أصلًا مستقلة تمنع زيادة حزمة الإنتاج80 أو تجاوز سقف التعليقات.
لا يُعمم هذا على كل مقابض الإنتاج؛ المرشح OFF حتى اكتمال بقية التغطية.

### C6: فحص مستقل لكل واحد من الصفوف التاريخية الثلاثة

شُغّل التدقيق الجديد فعليًا على أصول6732191 المتحققة. فُتحت PNG الأصلية،
وتصيير صفحة PDF الفعلية، والقصاصات الست لكل ظهور من الكلمتين. النتيجة:

| الظهور | glyphs فعلية / aliases إضافية | أكبر خطأ أصل glyph بالـpt |
|---|---:|---:|
| الكوثر في الجسم |12 /5|0.000015021|
| أعطيناك في الجسم |13 /6|0.000028571|
| الكوثر في النقطة |12 /5|0.000025979|

الأغلفة الفعلية في خط PDF المضمن تطابق تسلسل HarfBuzz المستقل للخط Amiri
الأصلي، وGPOS من الخطة إلى الطلاء ضمن1e-4pt (دقة serialization/float، كما في
اختبارات PDF الأصلية). GID=-1 يمثل Unicode alias لنفس CID، لا glyph مرسومة
أخرى. تُسجل aliases ولا تُحذف حروف مرسومة؛ الثلاثة مطلوبة بعدّ صريح وربط هاش.
نافذة الحبر المتماثلة أظهرت صفر فرق أفقي لهذه العينات؛ **قد يدخلها حبر القوس
المجاور، وليست قناع glyph معزولًا**. بصريًا الكلمات وعلاماتها ومواضعها مقابلة،
مع بقاء اختلافات تغطية الحبر بين المصيرين. لذلك إشارات tight-centre القديمة
12.79/14.18/12.21pt مصنفة لهذه الأصول كحدود استخراج لا تمثل انتقال الحبر
بذلك المقدار، وليست عيب موضع مثبتًا. لا تعميم بأن كل فرق AA غير مؤثر.

اختبارات سلبية5 على الأصول نفسها ترفض: إزاحة glyph0.25pt رغم إعادة ربط الهاش،
خطًا مخالفًا، مسح حبر PNG، وفقد ظهور. أُضيف التدقيق و7ملفات دليل إلى CI دون
تعديل عتبة C6/RMSE أو السماحيات أو الاستثناءات. **فرق RMSE العام لم يُغلق**،
ويلزم تكرار الفحص وفتح الأصول على SHA النهائي؛ المرجع المستقل ليس التقاطًا
لـglyph IDs من Flutter. لا يُعد هذا التدقيق وحده قبولًا بصريًا شاملًا.

### فشل ddad9e4 وتشخيصه — لا قبول

Main41090615592 توقف عند compile: Flutter3.22.3 لا يمرر معامل
hitTestBehavior من LongPressDraggable إلى Draggable. وظهر info لغياب أقواس
حلقة اختبار. نُقلت السجلات الثلاثة المتاحة مع manifest صريح بالأوامر غير
المنفذة؛ لم يُبن APK ولم تعمل Android/Visual، وفشل نقلا الصور لأن الاختبار لم
يُنتجها. Extended41090615734 فشل كذلك؛ لا تُحسب أي بوابة منها نجاحًا.
الإصلاح يستعمل Listener opaque داخل child48dp (متوافق مع Flutter المثبت)،
بدل معامل غير مدعوم؛ يبقى اختبار السحب من الزاوية شرطًا للسلوك الفعلي.
أُضيف انتظار جاهزية صفحات المرشح، كي لا تُلتقط دوارة تحميل بدل الورقة.
أُصلح info دون تخطيه. يلزم تشغيل كل البوابات على SHA الإصلاح.

### فشل aad16f4 وتشخيصه — لا تجاوز لشرط الاحتواء

Main41091087766: R1/R4 نجح8/0 والتحليل نظيف. حالات التزامن والحذف والتمرير
حتى آخر عنصر والقفل نجحت فعليًا. الحالات الست للسحب المتكامل توقفت عند فحص
الاحتواء: استُخدم Rect.contains(bottomRight)، وهو يرفض النقطة على الحد الأيمن
رياضيًا رغم أن المستطيل ملاصق للحافة ومحتوى بالكامل. صُحح الفحص إلى مقارنة
الحواف الأربع مع حواف الشاشة، **بصفر سماحية**؛ شروط48dp وعدم التداخل كما هي.
ليس تصغيرًا للمقابض أو إخراجًا لها من الجرد. بقيت PNG/PDF/history لتلك الست
غير منفذة؛ لم يُبن APK، فتخطى Android/Visual ولا نجاح لهما على هذا SHA.
فشل نقل المرشح لنقص أصوله، ونجح نقل الإنتاج الأصلي والسجلات كاملة.

أثناء مراجعة Flutter3.22.3 المثبت اتضح أن onDragUpdate/onDragEnd لا يُستدعيان
بعد إعادة تدوير source row في القائمة. أُضيف Listener إلى اللوحة الأم لتتبع
المؤشر وإيقاف timer عند up/cancel حتى بعد خروج المصدر من cache. اختبار جديد
يسحب حتى يختفي المصدر فعليًا، يعيد المؤشر للوسط ثم يلغي خارج اللوحة، ويتحقق
من توقف التمرير وبقاء المستند؛ لا يُكتفى بمستطيل أو callback. ينتظر CI التالي.

### 642453a: سحب مثبت، Android لم يصل بعد إلى التركيب

Main41092463296:8production،249native،1068full،3canonical، بلا فشل/تخطي؛
تحليل نظيف، APK فعلي30,600,571bytes وتدقيقه ناجح. هاش APK:
`209194da74a3a7db9ed24142f736fbaf4d12dadbdf9fc4586ae64171f47ae22b`.
Extended41092463173 ناجح. نُقلت11سجلًا و19أصلًا للمرشح بتحقق كامل.
حالات السحب الست نجحت بالفعل:48×48dp، بفواصل8dp، داخل حدود الشاشة بصفر
سماحية، وسحب من الزاوية خارج حبر الأيقونة، مع ترتيب ونص وإحداثيات PDF
والتراجع/الإعادة. نجحت أيضًا5حالات التزامن والحذف والقفل والتمرير وإلغاء
السحب بعد إعادة تدوير المصدر. لا يُنقل هذا إلى مقابض الإنتاج القديمة.

فُتحت صور المرشح الاثنتا عشرة قبل/بعد لكل الحالات والعرضين، وصُيّرت وفُتحت
كل ملفات PDF الستة. الترتيب والدرجات وتوزيع الرأس تقابلت في هذه المستندات
القصيرة دون فقد أو تداخل مرئي؛ ليست مراجعة split/long/media الشاملة. **UI الافتراضي في widget test هو Ahem، وتظهر تسمياته مربعات**؛
الورقة نفسها تستخدم أصول الخطوط الإنتاجية المحملة فعلًا. ليست تلك الصور
قبولًا بصريًا لتسميات UI على Android. لا استبدال خط التطبيق لإخفاء ذلك.

Android320/360 فشل عند البحث عن IME clear. نجح التثبيت والتسجيل والتحديد،
وفُتحت لقطة Android360 الأصلية: اللوحة موجودة كاملة والـNext فوقها، لكن XML
يحوي نافذة التطبيق وحدها. ذلك قصور `uiautomator dump` (active-window root)،
لا فقد زر فعلي. لم يُنفذ تركيب حتى ذلك الموضع، ولم يُحسب PASS. نُقلت أصول
الفشل بنجاح من job النقل المستقل دون تخفيف القارئ. الإصلاح الجاري يضيف APK
رصد مستقلًا ثالثًا، read-only UiAutomation.getWindows مع العلم اللازم، كي
تُقرأ نافذة IME الفعلية. لا يُستهدف process الإنتاج أو اللوحة بالـinstrumentation
لئلا تعاد تشغيلهما أثناء التركيب. الأزرار ما زالت تُضغط عبر UI، لا text API.
تُحفظ نافذة Android الكاملة الأخيرة وهاش APK الرصد؛ لا تُقبل نتيجة بلا roots.
نجاح هذا الإصلاح ينتظر تنفيذ Android الجديد. بقية شروط الإغلاق لم تكتمل.

### مراجعة642 التكميلية — أصول طويلة فعلية، لا قبول SHA أحدث

نُقلت حزمة الإنتاج80 كاملة وVisual14 كاملة بالقارئ الصارم. هاشا الجردين:
`17b3b3c33f1c86b163269b99a33883baf947a49b93bef0af18bd3c29f977051a`
و`06d40a5129afde961d511f4595f1fc7239bd069ebfd06531a7d0f76f0c2422df`.
الأصول محفوظة خارجGit في `/home/user/closure-audit/642-production` و`642-visual`؛
كل `retrieval-provenance.json` يربط المصدر بـMain41092463296 و642453a.

فُتحت فعليًا R9 page2 (الفهرس0) قبل التحديد وبعد تحديد السؤال وبعد تحديد
الفرع: paper وphone عند320 و360، مع صفحةPDF2 للمستند نفسه. فُتحت أيضًا
paper0 و4 وPDF0 و4 عند320؛ B109 كامل ظاهر في الذيل بلا قص/تداخل مرئي.
المعادلتان السطرية والمنفردة موجودتان في الصفحة المشتركة. مواضع النص واللف
ثابتة في الصور المفتوحة قبل/بعد؛ حدود التحديد UI وليست حبرPDF. هذا ليس
فحصًا لكل صفحة أو أدوات/وسائط/تنسيق، ولا إثبات48dp للمقابض المطبوعة الصغيرة.

فُتحت R10 page19 الأخيرة عند العرضين، قبل/بعد تحديد الخيار، مع صفحتيPDF
المقابلتين: آخر option124 ظاهر، والسؤالNEXT بعده بفجوة مرئية، بلا تداخل.
تصيير PDF للمراجعة بمقياس96dpi مشتق من الأصل؛ ليس أصلًا جديدًا فيmanifest.
تظل تسميات UI في widget screenshots مربعاتAhem كما سبق، وليست قبولAndroid.

فُتحت صفحتاVisual وPDF المقابلتان وجميع قصاصات الكلمات القرآنية الست الأصلية.
أُعيد التدقيق المستقل على أصول642 فعلًا: الثلاثة بنفس تسلسل الأغلفة والخط
المضمن، أكبر أخطاء الأصل0.000015021/0.000028571/0.000025979pt؛ خمسة اختبارات
الضبط السلبية ناجحة بعد ضبطC6_ARTIFACTS إلى المجلد المتحقق. هاشPDF:
`df43f2dda9338c580deac6a4d26b5ba8443e0460264895b60739403faca89447`.
الفروق المرئية في كثافة الحبر باقية؛ لا تغيير RMSE أو إغلاق الفرق العام بهذا
التدقيق المحدود. لا تُنقل هذه المراجعة إلىcf278d4 أو أيSHA لاحق تلقائيًا.

### cf278d4: مراقب Android يعمل، فشل جديد مشخص في لوحة الاختبار

[Main41095731607](https://github.com/techtouchAI/Writing-questions/actions/runs/41095731607)
**FAILURE** بسبب Android320/360 فقط؛ بقية jobs وتدقيقC6 والنقل ناجحة، release
متخطّى (ليس بناءAPK). [Extended41095731608](https://github.com/techtouchAI/Writing-questions/actions/runs/41095731608)
ناجح. سجلات أوامر CI المتحققة11 تحفظ8production/249native/1068full/3canonical،
صفر فشل/تخطي في تلك المجموعات، analyze نظيف. APK30,600,573bytes، تدقيقELF
والخط الفعلي ناجح، SHA256:
`cf7156065167461d27327000160707b788259f93c9ec7f25bf2dfea630fd53b3`.
نُقلت أيضًا19candidate و80production و39Android أصلًا **لكل عرض** بتحقق كامل.
أخطاءGitHub502 عطلت بعض محاولات الجلب؛ أعيدت المحاولة حتى نجاح الجرد والهاش،
دون تعديل القارئ أو عدّ المحاولات الناقصة نجاحًا.

بُني APK الرصد وثُبّت وعمل على المحاكي فعلًا؛ لم يعد زرIMEclear مفقودًا من
الرصد. تطابقت قيمة الاسم المختلط المشكّل والـcopy/paste والمنطوق حرفيًا؛
Save فوق لوحة المفاتيح الفعلية. حُفظت53عمليةInputConnection مقبولة في كل
عرض، كلّها تستهدف حزمة التطبيق. تتضمن تركيب العربية والإنجليزية والأرقام
وmultiline. لا يكفي هذا لقبول المسار كله: فشل فحصBODY8360codepoints.

قورنت الأصول الكاملة: XML والحقل وtrace متفقون على33codepoints فقط، أي
multiline32 ثم newline واحد. **لا توجد أي عمليةlong أصلًا**، لا رفض أو قص
لـ8360حرفًا من المحرر. فُتحت لقطتا الفشل320/360 ولقطتا الاسم والمنطوق320.
السطر الأخير من fixtureIME مرسوم تحت أزرار التنقل النظامية؛ زر إخفاء اللوحة
ظاهر فوقIME long. بعد اللمسة اختفت اللوحة ولم ينفذlistener. لا يُنسب هذا
إلى فقد نص في نموذج التطبيق ولا يُحسب إدخالlong ناجحًا.

الإصلاح الجديد يعالج layout لوحة الاختبار نفسها: bottom inset من
WindowInsets.navigationBars الفعلي مع wrap-content، لتبقى صفوف48dp كاملة فوق
التنقل، دون إزاحة إحداثيات اللمس أو تعطيل أزرار النظام. يشترط المشغّل بعد كل
لمسة أحداثInputConnection جديدة مقبولة تنتهي بعملية الزر نفسه، ويتحقق من
تركيبlong أيضًا. لا retry لمسة فاشلة ولاadb text. نجاح ذلك على Android
**ما زال مطلوبًا**؛ ليس نجاح53عملية دليلًا على إصلاح السطر الأخير الجديد.

أُصلح كذلك اختيارOverride الأخير فيwm size بدلPhysical الأول، ولمس الجزء
المرئي فعليًا من حقل طويل داخل ancestor scroll viewport مع إثبات focus أصلي،
ورفض نتيجةobserver ذاتcode فاشل حتى إن حملتXML. أخطاء التطابق الطويل تحفظ
الهاش والطول وأول اختلاف في annotation قصير، بينما تبقى الأصول كاملة فيXML
والـtrace. محليًا14اختبارAndroid/بروتوكول و16اختبارنقل ناجحة؛ syntax/compile
وdiff نظيفة. لاJava/Flutter/Android محلي، فيلزم تشغيل كل ذلك فيCI الجديد.
فشل جلبVisual الخاص بـcf بالقارئ الصارم رغم اخضرار job النقل: أعادChecks
28مرجعًا (14مكررة حرفيًا)، والجرد المعلن14. لم تُحذف التكرارات لتمريره، ولم
تُعد أصول642 بديلًا عنه. أُضيف تشخيصduplicate inventory صريح واختبار رفض
نسختين كاملتين؛ العدد والـhash/الهوية وبقية الشروط كما هي. يبقى نقلVisual
لهذاSHA غير مقبول، ويلزم جرد جديد صحيح علىSHA النهائي.
الحفظ وإعادة الفتح الكاملان والتصدير بعدBODY **لم يصلا بعد إلى التنفيذ**.
حالة الإغلاق تبقىOPEN/candidateOFF، وكامل48dp/الأدوات/الفروق/قرارالدرجة باقية.

### بوابات3987e69 — لا تغطي الشفرة الجديدة غير المشغلة

Main41087652854:8production/234native/1053full/3canonical؛ تحليل نظيف،
بناء APK وتدقيقه الفعلي ناجحان. نُقلت11سجلًا بتدقيق كامل. APK30,596,907bytes،
SHA256`73b14ede7cadab166275e8e8ae8702ce6cf3f3f81a571f211599f7328a9a2ddb`.
Extended41087652735 وVisual ناجحان؛ Android فشل كما سبق، وC6 ناجح (تشخيص غير ملزم). هذه ليست بوابات نهائية لإضافة السحب والتدقيق اللاحقة.
تبقى كامل48dp، كامل مصفوفة الأدوات/الحدود، الفروق البصرية، قرار الدرجات،
والقبول على SHA واحد شروطًا غير مستوفاة. الحالة OPEN، candidate OFF.

## دورة الاستئناف بعد29fbb92 — OPEN، لا نقل لقبول SHA أقدم

ثُبِّتت البداية الفعلية لا المفترضة: HEAD المستعاد كان `eab6c5a` مع رقعة
تراكمية؛ قورنت كل الملفات/الـblobs مع `4b1f458efd36453a66114c512ce5ff3043962129`:
**صفر اختلاف وصفر ملف زائد**. حُفظت نسخة خارج Git، ثم جُلب الفرع نفسه.
كان origin قد تقدّم إلى `29fbb9270fe8737a35eb292aa1a8332631222304`؛ احتُفظ بجميع
التزاماته الأحدث، وحُوذي HEAD والفهرس والشجرة معها دون تبديل فرع أو force-push.
لا تفعيل مرشح، لا دمج، لا حذف. السجل أدناه قبل هذا القسم تاريخي.

### نتائج29fbb92 المثبتة — خط أساس هذه الدورة فقط

[Main40738891473](https://github.com/techtouchAI/Writing-questions/actions/runs/40738891473)
و[Extended40738891446](https://github.com/techtouchAI/Writing-questions/actions/runs/40738891446)
SUCCESS. قرئت تعليقات build الأصلية: production8، native234، full1053، canonical3؛
صفر فشل/تخطي في هذه المجموعات؛ APK30,596,906bytes، auditPassed=true،
SHA256 `e4f1d9a0949d9ac0906c88338c9dc83a03918dd459edfefb156d54ee31e0e792`.
**Android job SKIPPED لهذا SHA؛ لا يجوز نقل نجاح محاكي050ea إليه.**

نُقلت80 أصلًا إنتاجيًا و7 أصول Visual مع hash/هوية التشغيل والجرد الكامل.
فُتح native drag320 branch-between وPDF لنفس المستند؛ اتجاه الرأس المختلط
متوافق في هذه العينة، والدرجة **ما زالت edge مقابل inline**. كذلك فُتحت صفحة1
من Visual PNG وPDF الحاليين: المعادلات والترويسة موجودتان؛ ليست مراجعة لكل
الصفحات أو إثبات تكافؤ pixel. لا نُسب إصلاحات الالتزامات المسترجعة إلى إصلاح النقل أدناه.

C6 الهندسي الحالي **0 violations**، 77line/684visible word/36independent spacer/
2861char/7math/1math-only/0skipped. أُعيد التنفيذ محليًا على نفس الأصول في
`enforce` مع source binding: PASS؛48اختبارًا بما فيها الأصول الحقيقية PASS/0SKIP.
هذا ليس إغلاقًا لكل C6: التشخيص التاريخي tight-box ما زال يحفظ3صفوف WORD-POSITION
(أَعْطَيْنَاكَ، الْكَوْثَرَ مرتين)، والتقرير يسمي السبب extraction؛ لا نعتبره
إعفاءً عامًا أو نَسقطه. RMSE الحاليp1≈0.05297 وp2=0.062327 أمام0.02 الأصلي؛
لا تغيير للحد أو قبول تلقائي للفرق باعتباره AA. الفحص البصري/التشخيص المتبقي
وكل عيب native/PDF يظل مانع إغلاق، رغم صفر مخالفات **عقد الهندسة** الحالي.
جرد83 baseline و70 وسيطًا الفرديان مرتبطان أدناه ومحفوظان دون حذف صفوف.

### عيب مثبت جديد وإصلاحه المحدود

جلب11 سجلًا/مرافقًا من29fbb92 فشل صراحة بـ
`Incomplete evidence inventory: annotation truncation`، رغم اخضرار transport job.
السبب: validation profile صار6سجلات+manifest+APK audit+3negative controls=11،
بينما workflow ينشر group0 فقط (10مراجع). التعديل يضيف خطوة group1 مستقلة؛
حد5notices/step وحد40/job وبقية فحوص الهوية/الأعداد/الهاشات لم تتغير.
اختبار انحدار يقرأ **مجموعات workflow الفعلية**، ينشر ثم يجلب الجرد11 كاملًا
مع mock API ويفحص كل بايت؛ فشل قبل الإصلاح بنفس رفض reader، وبعده13/13 PASS.
لا تخفيف للاختبار القديم، ولا اعتبار الجرد الناقص نجاحًا. لم تُعدَّل هندسة
الورقة أو الخطوط أو PDF أو الترقيم أو أدوات الإنتاج في هذا الإصلاح.

### المرجع المطلوب وموانع الإغلاق

- **موضع الدرجة:** توثيق§5 لا يحسم edge/inline؛§7 يقترح عدم التجزئة لكنه ليس
  اختيارًا نهائيًا لموضع العمود. طُلب توضيح ولم يصل اختيار صريح؛ إعادة وصف
  المهمة ليست موافقة على أحد الخيارين. لا تغيير اعتباطي ولا تفعيل للمرشح.
- **أهداف48dp:** جرد mounted primitives فيediting-manifest يظل تشخيصًا فقط؛
  effectiveTargetVerified=false. لا يُستنتج من48px محلية أو منR8 قبول المقابض
  المطبوعة المصغرة أو عدم التداخل. كامل الحالات/الامتدادات/platform handles غير مثبت.
- **الأدوات:** كل صف في[الجرد](closure_editing_inventory.md) يحدد اختبارًا وحدوده؛
  لا ادعاء لكل command→history→same-document PDF عند كل boundary/width/media.
- **Android:** لا Flutter/Dart/Java/adb/emulator/KVM محليًا. المسار المناسب المتاح
  هو CI emulator Android35 x86_64. التشغيل التالي يطلبه صراحة؛ smoke لا يثبت
  Arabic/English composing region أو جميع multiline/option/save/export scenarios.

**أي تعديل في هذه الدورة يبطل نتائج29fbb92 كقبول نهائي.** يلزم تشغيل جديد
يتضمن `[closure-audit] [review-evidence] [android-runtime]`، وجلب11سجلًا كاملًا،
APK مدققًا، Visual/C6/Extended وAndroid على SHA نفسه، ثم فحص الأدلة فعليًا.
القسم الحالي لا يدّعي هذه النتائج قبل وقوعها. التقرير النهائي التنفيذي المرافق
يضيف receipt SHA/run/الهاشات من ذلك التشغيل دون تغيير الشفرة المختبرة أو اختلاق قبول.


## تحديث التنفيذ بعد تحقق050ea — ما زال OPEN

آخر SHA مكتمل: `050ea339399c7415b6f19ab67d185fe8ac973822`،
[Main40730800447](https://github.com/techtouchAI/Writing-questions/actions/runs/40730800447)
و[Extended40730800463](https://github.com/techtouchAI/Writing-questions/actions/runs/40730800463)
كلاهما SUCCESS. قرئت السجلات الكاملة: production8، native227، full1046، canonical3؛
صفر فشل/تخطي، analyzer بلا ملاحظات، APK فعلي30,596,308bytes، audit ABI/font/exports ناجح.
SHA256 للـAPK: `bb10b11c26a6e9a509c60282918e3077cf46be46389753a29f2c0d3db14725af`.
Android15/API35/x86_64 emulator ثبّت **نفس** APK، ونجحت7 فحوص smoke؛
ليست قبول IME شاملًا ولا جهازًا فعليًا. صور03/04/06 فُتحت بالفعل: زر التالي
في03 مخفي خلف لوحة المفاتيح رغم وجود عقدته، ويظهر في04 بعد الإخفاء.

قراءة C6 الفعلية لذلك SHA: **70 WOULD FAIL**، لا parity رغم job الأخضر.
التجربة المضبوطة على **نفس** PNG/PDF/positions ذي الهاشات المحفوظة أثبتت3 عيوب
تشخيص: ملكية محرف عند بداية كلمة مشتركة مع نهاية علامة أضيق؛ إسناد جزيرة نصية
واحدة فقط لسطر تتخلله صور معادلات؛ وطلب حبر لـNBSP بدل قياس تقدمها.
الإصلاح الجديد لا يغيّر أي حد قبول قديم: يفحص684 كلمة مرئية +36مسافة
(=720فاصلًا أصليًا)، ويُسنِد2861محرفًا بدل2820، ويقيس7معادلات/1سطر معادلة/0تخطي.
المسافات36/36 مثبتة من origins PDF المستقلة، أكبر فرق0.0000305176pt،
أمام حد جديد صارم0.001pt لتسلسل PDF العددي؛ غياب الجار/origin يفشل كغير متحقق،
وتقليص/زيادة المسافة0.25pt يفشل. ملكية جزيرة السطر لا تضم الأعمدة المستقلة
ولا تسقط glyph إضافيًا؛ أقصى baseline لكل جزء يظل خاضعًا لحد1pt الأصلي.

[السجل الفردي لكل مخالفة من السبعين](c6_050_individual_review.json) يحتفظ بالنص
الأصلي وتصنيف العيب/الدليل/اختبار الارتداد/هوية السطر، ومراحل التشخيص والهاشات.
النتيجة المحلية0 مخالفة مع48اختبار Python PASS/0SKIP، بينها الاختبارات السلبية
الثلاثة على الأصول الفعلية؛ كل الاختبارات القديمة محفوظة. **ليست نتيجة CI لشفرة جديدة بعد.**

أضيف إلى شاشتي header/question هامش IME خارج SafeArea لشريط التنقل فقط،
دون تغيير هندسة الورق أو النموذج.4 اختبارات320/360dp تفحص الموضع الكامل فوق
الكيبورد، hit-test، الإظهار/الإخفاء المتكرر، واستدعاء التالي وهو مفتوح.
CI يعيد الشاشتين الأصليتين مؤقتًا ليثبت الفشل الهندسي القديم ثم يستعيد الشفرة.
فحص Android الجديد يرفض bounds الأصلية `[30,1385][870,1510]` أمام keyboardTop852px؛
وجود العقدة وحده لم يعد ينجح. تشغيل Flutter/Android بعد هذا الإصلاح **مطلوب**.

**كل تغييرات هذا التحديث تبطل اعتبار050ea قبولًا نهائيًا للشفرة التالية.**
بوابات SHA الجديد وفتح PNG/PDF بعده لازمة. تظل موانع marks edge/inline غير المحسومة،
كامل48dp لكل مقبض، ومصفوفة الأدوات/IME غير المثبتة كما هي؛ لا تفعيل/دمج/حذف.
السكربت الخارجي الأول للمسافات استُبعد بسبب خلط فهارس صفحات0/1؛ الأرقام المذكورة
هنا من قراءة الصفحات المصححة ومقارنة البوابة على الأصول المربوطة، لا من الناتج المستبعد.

## الهوية وخط الأساس المعاد التحقق منه

قبل التعديل: HEAD وorigin كلاهما `4b1f458efd36453a66114c512ce5ff3043962129`؛
الشجرة نظيفة بعد مطابقة كل blob مع الملفات الفعلية، بما فيها الملفات غير المتتبعة.
النسخة المستعادة كانت تعرض HEAD قديمًا مع الرقعة التراكمية نفسها؛ أثبتت المطابقة
صفر اختلاف/صفر ملف زائد قبل محاذاة الفهرس، دون تغيير محتوى الملفات.

- [Main40600056283](https://github.com/techtouchAI/Writing-questions/actions/runs/40600056283): SUCCESS، **خط أساس فقط**.
- [Extended40600056273](https://github.com/techtouchAI/Writing-questions/actions/runs/40600056273): SUCCESS، خط أساس فقط.
- production8، native219، full1038، canonical3؛ صفر فشل/تخطي في هذه المجموعات؛ analyzer نظيف.
- APK فعلي30,596,046 bytes؛ SHA256 `1d4be96652fe4bc1fc1bd3204d93a79213ea4eb14ad8129e05a585b7af1102b9`.
  ABI/ELF/exports/font audit ناجح؛ `deviceLaunchVerified=false`، وليس تجربة تشغيل.
- أُعيد نقل logs/production/visual عبر القناة الصارمة وفحص SHA/عدد الملفات/هوية التشغيل.
  نُسخ المراجعة الخارجية في `/home/user/closure-audit/baseline-*`؛ ليست ملفات Git.

**أي تغيير أدناه يبطل نقل قبول4b1f إلى الشفرة الجديدة.** لا توجد هنا نتيجة
نهائية للشيفرة الجديدة قبل اكتمال تشغيل SHA الجديد وفحص مرفقاته فعليًا.

## الأسباب والتغييرات المحدودة

| الحالة | السبب المثبت من المصدر / الإجراء | حالة الإثبات |
|---|---|---|
| اتجاه الرأس المختلط | `HeaderLineBlock.direction` يصل للمحرك القانوني، لكن `PaperHeaderView` أسقطه وورّث `TexText` اتجاه أعمدة الواجهة RTL. مرّر اتجاه الفقرة الدلالي صراحة، مع إبقاء ترتيب الأعمدة الفعلي والقيم والنموذج كما هي. | أضيف انحداران English/Arabic داخل واجهة RTL، بمقارنة مواضع كل محرف بمرجع TextPainter مستقل. تنفيذ Flutter/الفحص البصري بعد التغيير مطلوب. |
| قياس C6 ليس من المعاينة المعروضة | الاختبار التشخيصي أعاد `CanonicalLayoutService.resolve` خارج MathSnapshotHost؛ الخدمة ترجع تخطيطًا أوليًا عند غياب المضيف، بينما المعاينة تعيد التخطيط بمقاييس المعادلات. لذا لا يصح افتراض أنه نفس LayoutDocument. | نُقل التسجيل إلى التركيبة التي تملك **نفس الكائن** المستخدم لـPNG/PDF. حُفظ الاختبار المستقل كتشخيص `reconstructed_positions.json`، دون حذف اختبار سلبي/تغيير حد. ربط هاشات الملفات والحماية من مصدر معاد بناؤه/ملف متغير أضيفا؛ إعادة التقرير مطلوبة. |
| الدرجة عند الحافة مقابل inline | `_titleRow` يجعل النص Expanded ثم الدرجة، ويستهلك مقبض السحب عرضًا مطبوعًا؛ `_titleBlock` القانوني inline. اختلاف فعلي مؤكد بفتح الأصلين. | **غير مُصلح.** الوثيقة §5 لا تحدد قاعدة طباعية نهائية، و§7 يقترح inline غير قابل للكسر. لا أختار native أوPDF كمرجع تلقائي ولا أغيّر القاعدة دون حسم المتطلب. |
| حبر معاملات المعادلة | في أصل Visual page1، علامتا + في المعادلة الزرقاء منخفضتا التباين جدًا في PNG مقارنة بـPDF؛ المصدر `x^2+2x+1=0`. فُتح الأصلان ثم تكبير غير مغير للمحتوى. | **تشخيص وإصلاح مصدر بانتظار CI.** الصورة الأصلية منPDF تحتفظ بالحبر؛ native يحتفظ0.47 مقابل10.32 و0.89 مقابل10.51 pixel-equivalent. المحرك المثبت يحذر من dropout في high عند تصغير<0.5 ويوصي medium/mipmap. غُيّر ترشيح صور المعادلات فقط، دون الخط/الحجم/الموضع؛ أضيف actual-glyph ink-conservation regression وBEFORE/AFTER بنفس الاختبار. |

مرجع اتجاه الفقرة: العقد المعلن `DocumentBlock.direction` و`InlineNode.direction`،
وقيم HeaderLineBlock التي ينشئها المصنع، لا تفضيل بصري لأحد الراسمين.
المرشح لا يزال OFF؛ لا تغيير لترقيم/هندسة الورق/المقاطع/حجم الخط/حدود القص.

## جميع مخالفات C6 في خط الأساس

83 finding =82 block+1 float. العدد مطابق حرفيًا للتقرير:
BASELINE2، BRACKET-COUNT2، LINE-EXTRA6، LINE-MISSING1، LINE-SHIFT6،
MATH-IMAGE4، WORD-CONTENT12، WORD-MISSING50.
النتيجة **WOULD FAIL** رغم نجاح job؛ ليست parity.

الملف الآلي [c6_baseline_inventory.json](c6_baseline_inventory.json) يحتفظ بكل
سطر، رقم الصفحة، source، نتيجة الفحص، تفسير ما يلزم إثباته، رقم chunk/السطر
وSHA256، ونصوص التعليقات الأصلية. أُعيد وصل chunks بترتيب الإرسال قبل تحليل الصفوف،
لأن Checks API يعكس الترتيب، والناشر يقطع أحيانًا وسط الكلمة. لا دمج للمخالفات المتكررة ولا إسقاط لها.
**12 عيبًا تشخيصيًا مؤكدًا و71 غير حاسمة**: C6-011 يطلب سطرPDF نصيًا
لكسر مرسوم صورةً موجودة في الأصلين؛ أُصلح المسار ليتحقق من الصورة وموضعها/حجمها
أفقيًا وعموديًا مع اختبارات حذف/إزاحة/ارتفاع/صورة في سطر آخر ورفض fallback صامت.
11صفًا من WORD-MISSING هي NBSP: القارئ يسقط whitespace ثم المقارن يطلب لها glyph،
وهو خلل عقد قياس مؤكد؛ **لم يُستثنَ أي منها**. التقدم/المسافة الفعلية يحتاجان
قياسًا مستقلاً قبل إصلاح التشخيص أو إعفاء الطباعة. إصلاح مصدر القياس لا ينفي
أي عيب مطبوع آخر؛ لكل صف تفسيره وأدلته فيJSON. لا توجد فروق مقصودة مقبولة بلا متطلب،
ولا إعفاء extraction/whitespace تلقائي. التصنيف النهائي يتطلب مقابلة التقرير
الجديد بالأصول قبل/بعد لكل صف. جميعها تبقى مانعًا للإغلاق حتى الحسم.

| ID | Check / page / source | النتيجة والتصنيف | الدليل الحرفي |
|---|---|---|---|
| C6-001 | BASELINE / 1 / block | WOULD FAIL — غير حاسمة | baseline moved 6.75pt: ')درجة\xa0٥(\xa0.المعادلةحل-١' |
| C6-002 | BASELINE / 1 / block | WOULD FAIL — غير حاسمة | baseline moved 3.84pt: '.ثم،وأنأنلاحظ' |
| C6-003 | BRACKET-COUNT / 1 / block | WOULD FAIL — غير حاسمة | preview ')(' vs pdf '' |
| C6-004 | BRACKET-COUNT / 1 / block | WOULD FAIL — غير حاسمة | preview ')(' vs pdf '' |
| C6-005 | LINE-EXTRA / 1 / block | WOULD FAIL — غير حاسمة | PDF line with no Preview line at baseline 712.98: ')ةجرد١٥(.' |
| C6-006 | LINE-EXTRA / 1 / block | WOULD FAIL — غير حاسمة | PDF line with no Preview line at baseline 712.98: '/يناثلالاؤسلا' |
| C6-007 | LINE-EXTRA / 1 / block | WOULD FAIL — غير حاسمة | PDF line with no Preview line at baseline 740.82: 'نأو' |
| C6-008 | LINE-EXTRA / 1 / block | WOULD FAIL — غير حاسمة | PDF line with no Preview line at baseline 740.82: 'نأظحال' |
| C6-009 | LINE-EXTRA / 1 / block | WOULD FAIL — غير حاسمة | PDF line with no Preview line at baseline 767.32: ')ةجرد٥(.' |
| C6-010 | LINE-EXTRA / 1 / block | WOULD FAIL — غير حاسمة | PDF line with no Preview line at baseline 767.32: '-١' |
| C6-011 | LINE-MISSING / 1 / float | WOULD FAIL — عيب تشخيصي مؤكد | no PDF line within 14.0pt of baseline 633.89 with overlapping x: '' |
| C6-012 | LINE-SHIFT / 1 / block | WOULD FAIL — غير حاسمة | line edges moved left d=57.56pt right d=147.32pt |
| C6-013 | LINE-SHIFT / 1 / block | WOULD FAIL — غير حاسمة | line edges moved left d=25.71pt right d=143.39pt |
| C6-014 | LINE-SHIFT / 1 / block | WOULD FAIL — غير حاسمة | line edges moved left d=78.61pt right d=53.23pt |
| C6-015 | LINE-SHIFT / 1 / block | WOULD FAIL — غير حاسمة | line centre moved 58.84pt |
| C6-016 | LINE-SHIFT / 1 / block | WOULD FAIL — غير حاسمة | line centre moved 44.88pt |
| C6-017 | LINE-SHIFT / 1 / block | WOULD FAIL — غير حاسمة | line centre moved 12.69pt |
| C6-018 | MATH-IMAGE / 1 / block | WOULD FAIL — غير حاسمة | maths text '\\begin{matrix} 1 & 2' left d=22.80pt |
| C6-019 | MATH-IMAGE / 1 / block | WOULD FAIL — غير حاسمة | maths text 'x^2+2x+1=0' left d=11.96pt |
| C6-020 | MATH-IMAGE / 1 / block | WOULD FAIL — غير حاسمة | maths image 'x^2 - 4 = 0' left d=0.67pt width d=4.61pt |
| C6-021 | MATH-IMAGE / 1 / block | WOULD FAIL — غير حاسمة | maths image '\\sqrt{x^2}=\|x\|' left d=2.91pt width d=2.90pt |
| C6-022 | WORD-CONTENT / 1 / block | WOULD FAIL — غير حاسمة | box 'قيمة' holds 'أجو' (100% different) cause=letters-absent-from-extract |
| C6-023 | WORD-CONTENT / 2 / block | WOULD FAIL — غير حاسمة | box '٤' holds '' (100% different) cause=letters-absent-from-extract |
| C6-024 | WORD-CONTENT / 2 / block | WOULD FAIL — غير حاسمة | box '٢' holds '' (100% different) cause=letters-absent-from-extract |
| C6-025 | WORD-CONTENT / 2 / block | WOULD FAIL — غير حاسمة | box '٢' holds '' (100% different) cause=letters-absent-from-extract |
| C6-026 | WORD-CONTENT / 2 / block | WOULD FAIL — غير حاسمة | box '٢' holds '' (100% different) cause=letters-absent-from-extract |
| C6-027 | WORD-CONTENT / 2 / block | WOULD FAIL — غير حاسمة | box '٤' holds '' (100% different) cause=letters-absent-from-extract |
| C6-028 | WORD-CONTENT / 2 / block | WOULD FAIL — غير حاسمة | box '٢' holds '' (100% different) cause=letters-absent-from-extract |
| C6-029 | WORD-CONTENT / 1 / block | WOULD FAIL — غير حاسمة | box '١٠' holds '٠' (50% different) cause=letters-absent-from-extract |
| C6-030 | WORD-CONTENT / 1 / block | WOULD FAIL — غير حاسمة | box 'هو' holds 'ه' (50% different) cause=letters-absent-from-extract |
| C6-031 | WORD-CONTENT / 1 / block | WOULD FAIL — غير حاسمة | box 'المعادلة' holds 'اةفلمي' (50% different) cause=letters-absent-from-extract |
| C6-032 | WORD-CONTENT / 1 / block | WOULD FAIL — غير حاسمة | box 'في' holds 'دقي' (50% different) cause=letters-absent-from-extract |
| C6-033 | WORD-CONTENT / 1 / block | WOULD FAIL — غير حاسمة | box 'حل' holds 'ح' (50% different) cause=letters-absent-from-extract |
| C6-034 | WORD-MISSING / 1 / block | WOULD FAIL — غير حاسمة | no glyphs inside ':' at x=402.14..405.15 (deleted, moved away or reordered) cause=unresolved |
| C6-035 | WORD-MISSING / 1 / block | WOULD FAIL — غير حاسمة | no glyphs inside '﴿' at x=453.05..460.55 (deleted, moved away or reordered) cause=unresolved |
| C6-036 | WORD-MISSING / 1 / block | WOULD FAIL — عيب تشخيصي مؤكد | no glyphs inside '\xa0' at x=447.41..449.73 (deleted, moved away or reordered) cause=unresolved |
| C6-037 | WORD-MISSING / 1 / block | WOULD FAIL — غير حاسمة | no glyphs inside '(' at x=454.45..458.08 (deleted, moved away or reordered) cause=unresolved |
| C6-038 | WORD-MISSING / 1 / block | WOULD FAIL — عيب تشخيصي مؤكد | no glyphs inside '\xa0' at x=459.18..461.50 (deleted, moved away or reordered) cause=unresolved |
| C6-039 | WORD-MISSING / 1 / block | WOULD FAIL — عيب تشخيصي مؤكد | no glyphs inside '\xa0' at x=469.85..472.17 (deleted, moved away or reordered) cause=unresolved |
| C6-040 | WORD-MISSING / 1 / block | WOULD FAIL — غير حاسمة | no glyphs inside ')' at x=227.36..230.78 (deleted, moved away or reordered) cause=unresolved |
| C6-041 | WORD-MISSING / 1 / block | WOULD FAIL — غير حاسمة | no glyphs inside 'درجة' at x=230.78..252.68 (deleted, moved away or reordered) cause=letters-absent-from-extract |
| C6-042 | WORD-MISSING / 1 / block | WOULD FAIL — عيب تشخيصي مؤكد | no glyphs inside '\xa0' at x=252.68..255.31 (deleted, moved away or reordered) cause=unresolved |
| C6-043 | WORD-MISSING / 1 / block | WOULD FAIL — غير حاسمة | no glyphs inside '١٥' at x=255.31..263.31 (deleted, moved away or reordered) cause=letters-absent-from-extract |
| C6-044 | WORD-MISSING / 1 / block | WOULD FAIL — غير حاسمة | no glyphs inside '(' at x=263.31..266.72 (deleted, moved away or reordered) cause=unresolved |
| C6-045 | WORD-MISSING / 1 / block | WOULD FAIL — عيب تشخيصي مؤكد | no glyphs inside '\xa0' at x=266.72..269.36 (deleted, moved away or reordered) cause=unresolved |
| C6-046 | WORD-MISSING / 1 / block | WOULD FAIL — غير حاسمة | no glyphs inside '.' at x=269.36..272.97 (deleted, moved away or reordered) cause=unresolved |
| C6-047 | WORD-MISSING / 1 / block | WOULD FAIL — غير حاسمة | no glyphs inside 'أوجد' at x=415.09..436.50 (deleted, moved away or reordered) cause=letters-absent-from-extract |
| C6-048 | WORD-MISSING / 1 / block | WOULD FAIL — غير حاسمة | no glyphs inside '/' at x=480.50..483.88 (deleted, moved away or reordered) cause=unresolved |
| C6-049 | WORD-MISSING / 1 / block | WOULD FAIL — غير حاسمة | no glyphs inside 'الثاني' at x=483.88..510.17 (deleted, moved away or reordered) cause=letters-absent-from-extract |
| C6-050 | WORD-MISSING / 1 / block | WOULD FAIL — غير حاسمة | no glyphs inside 'السؤال' at x=512.81..549.01 (deleted, moved away or reordered) cause=letters-absent-from-extract |
| C6-051 | WORD-MISSING / 1 / block | WOULD FAIL — غير حاسمة | no glyphs inside '.' at x=337.22..340.13 (deleted, moved away or reordered) cause=unresolved |
| C6-052 | WORD-MISSING / 1 / block | WOULD FAIL — غير حاسمة | no glyphs inside 'وأن' at x=448.55..464.04 (deleted, moved away or reordered) cause=letters-absent-from-extract |
| C6-053 | WORD-MISSING / 1 / block | WOULD FAIL — غير حاسمة | no glyphs inside 'أن' at x=513.31..523.38 (deleted, moved away or reordered) cause=letters-absent-from-extract |
| C6-054 | WORD-MISSING / 1 / block | WOULD FAIL — غير حاسمة | no glyphs inside 'لاحظ' at x=526.02..549.01 (deleted, moved away or reordered) cause=letters-absent-from-extract |
| C6-055 | WORD-MISSING / 1 / block | WOULD FAIL — غير حاسمة | no glyphs inside ')' at x=365.30..369.16 (deleted, moved away or reordered) cause=unresolved |
| C6-056 | WORD-MISSING / 1 / block | WOULD FAIL — غير حاسمة | no glyphs inside 'درجة' at x=369.16..388.71 (deleted, moved away or reordered) cause=letters-absent-from-extract |
| C6-057 | WORD-MISSING / 1 / block | WOULD FAIL — عيب تشخيصي مؤكد | no glyphs inside '\xa0' at x=388.71..391.23 (deleted, moved away or reordered) cause=unresolved |
| C6-058 | WORD-MISSING / 1 / block | WOULD FAIL — غير حاسمة | no glyphs inside '٥' at x=391.23..395.78 (deleted, moved away or reordered) cause=letters-absent-from-extract |
| C6-059 | WORD-MISSING / 1 / block | WOULD FAIL — غير حاسمة | no glyphs inside '(' at x=395.78..399.64 (deleted, moved away or reordered) cause=unresolved |
| C6-060 | WORD-MISSING / 1 / block | WOULD FAIL — عيب تشخيصي مؤكد | no glyphs inside '\xa0' at x=399.64..402.16 (deleted, moved away or reordered) cause=unresolved |
| C6-061 | WORD-MISSING / 1 / block | WOULD FAIL — غير حاسمة | no glyphs inside '.' at x=402.16..404.94 (deleted, moved away or reordered) cause=unresolved |
| C6-062 | WORD-MISSING / 1 / block | WOULD FAIL — غير حاسمة | no glyphs inside '-' at x=543.31..546.21 (deleted, moved away or reordered) cause=unresolved |
| C6-063 | WORD-MISSING / 1 / block | WOULD FAIL — غير حاسمة | no glyphs inside '١' at x=546.21..549.01 (deleted, moved away or reordered) cause=letters-absent-from-extract |
| C6-064 | WORD-MISSING / 2 / block | WOULD FAIL — عيب تشخيصي مؤكد | no glyphs inside '\xa0' at x=68.10..70.53 (deleted, moved away or reordered) cause=unresolved |
| C6-065 | WORD-MISSING / 2 / block | WOULD FAIL — عيب تشخيصي مؤكد | no glyphs inside '\xa0' at x=85.65..88.08 (deleted, moved away or reordered) cause=unresolved |
| C6-066 | WORD-MISSING / 2 / block | WOULD FAIL — غير حاسمة | no glyphs inside '.' at x=179.03..181.98 (deleted, moved away or reordered) cause=unresolved |
| C6-067 | WORD-MISSING / 2 / block | WOULD FAIL — غير حاسمة | no glyphs inside '(' at x=371.23..375.63 (deleted, moved away or reordered) cause=unresolved |
| C6-068 | WORD-MISSING / 2 / block | WOULD FAIL — عيب تشخيصي مؤكد | no glyphs inside '\xa0' at x=375.63..378.06 (deleted, moved away or reordered) cause=unresolved |
| C6-069 | WORD-MISSING / 2 / block | WOULD FAIL — غير حاسمة | no glyphs inside '٢' at x=502.30..507.01 (deleted, moved away or reordered) cause=letters-absent-from-extract |
| C6-070 | WORD-MISSING / 2 / block | WOULD FAIL — غير حاسمة | no glyphs inside '(' at x=508.26..511.89 (deleted, moved away or reordered) cause=unresolved |
| C6-071 | WORD-MISSING / 2 / block | WOULD FAIL — غير حاسمة | no glyphs inside '٤' at x=354.59..359.95 (deleted, moved away or reordered) cause=letters-absent-from-extract |
| C6-072 | WORD-MISSING / 2 / block | WOULD FAIL — غير حاسمة | no glyphs inside '5' at x=366.78..372.92 (deleted, moved away or reordered) cause=letters-absent-from-extract |
| C6-073 | WORD-MISSING / 2 / block | WOULD FAIL — غير حاسمة | no glyphs inside '٢' at x=502.30..507.01 (deleted, moved away or reordered) cause=letters-absent-from-extract |
| C6-074 | WORD-MISSING / 2 / block | WOULD FAIL — غير حاسمة | no glyphs inside '(' at x=508.26..511.89 (deleted, moved away or reordered) cause=unresolved |
| C6-075 | WORD-MISSING / 2 / block | WOULD FAIL — عيب تشخيصي مؤكد | no glyphs inside '\xa0' at x=351.90..354.33 (deleted, moved away or reordered) cause=unresolved |
| C6-076 | WORD-MISSING / 2 / block | WOULD FAIL — غير حاسمة | no glyphs inside '(' at x=359.69..364.09 (deleted, moved away or reordered) cause=unresolved |
| C6-077 | WORD-MISSING / 2 / block | WOULD FAIL — غير حاسمة | no glyphs inside '6' at x=366.52..372.66 (deleted, moved away or reordered) cause=letters-absent-from-extract |
| C6-078 | WORD-MISSING / 2 / block | WOULD FAIL — غير حاسمة | no glyphs inside '٢' at x=502.30..507.01 (deleted, moved away or reordered) cause=letters-absent-from-extract |
| C6-079 | WORD-MISSING / 2 / block | WOULD FAIL — غير حاسمة | no glyphs inside '(' at x=508.26..511.89 (deleted, moved away or reordered) cause=unresolved |
| C6-080 | WORD-MISSING / 2 / block | WOULD FAIL — غير حاسمة | no glyphs inside '(' at x=367.87..372.26 (deleted, moved away or reordered) cause=unresolved |
| C6-081 | WORD-MISSING / 2 / block | WOULD FAIL — غير حاسمة | no glyphs inside '7' at x=374.69..380.84 (deleted, moved away or reordered) cause=letters-absent-from-extract |
| C6-082 | WORD-MISSING / 2 / block | WOULD FAIL — غير حاسمة | no glyphs inside '٢' at x=502.30..507.01 (deleted, moved away or reordered) cause=letters-absent-from-extract |
| C6-083 | WORD-MISSING / 2 / block | WOULD FAIL — غير حاسمة | no glyphs inside '(' at x=508.26..511.89 (deleted, moved away or reordered) cause=unresolved |

## مصفوفة التحرير والأهداف

المخرجات الفعلية الوسيطة93ed86e (ليست SHA نهائيًا):6/6 سحبات ناجحة؛ لكل إطار
96 primitive مبنيًا،52 صندوقًا داخل viewport بالكامل،34 صندوقًا دون48dp.
مقبضا السؤال7.20×7.20dp عند320 و7.62×7.62عند360؛ مقابض الفروع6.40 و6.77dp.
هذه قياسات screen-dp مرتبطة بـPNG فيediting-manifest، وليست إثبات hit ownership.
تثبت ضرورة معالجة المقابض المطبوعة؛ لا يجوز تعميم R8 على هذه الأهداف الصغيرة.
فُتح drag320 branch-between PNG/PDF بعد الإصلاح: ترتيب الرأس/colon صار متوافقًا
في العينة، لكن الدرجة ما زالت edge مقابل inline. الأصلان/السجلات من93ed نُقلت
بهوية/هاش. لا تنقل هذه الملاحظة إلى SHA نهائي غير مفحوص.

المرجع المتراكم [closure_editing_inventory.md](closure_editing_inventory.md)
و[canonical_editor_coverage.md](../canonical_editor_coverage.md)؛ أُضيفت الحالة
الحالية إلى كليهما بدل إنشاء نتيجة مستقلة. وجود command ليس تنفيذًا أو قبولًا.

- baseline يثبت6 سحبات فعلية مع model/history/live-PDF عند320/360، وسباقي
  export-version وasset-completion. لا يعمم ذلك على كل الأدوات/المقاطع الطويلة.
- جميع42 أوامر التخصصات لها قياسات R8 محدودة؛ لا يثبت ذلك كل إدراج/تعديل/حذف/
  undo/redo/export لكل نوع ومقطع وحدّ صفحة. القائمة الحالية توضح الفجوات.
- أضيف جرد لكل primitive تفاعلي **مبني في إطارات** حالات السحب الست، قبل/بعد،
  داخل editing-manifest مع screenshot وrect محوّل إلى dp ووجوده في viewport
  وعينة hit-path. تُحفظ أنواع الحقول/السحب/Ink/Gesture دون استنتاج من عينات.
- هذا **ليس** برهان48×48 فعالًا: `effectiveTargetVerified=false` لكل صف؛
  الحوارات/صفحات التكملة/مقابض المنصة وتداخل مالكي الإيماءات غير مكتملة.
  حد الـ48/عدم التداخل/الاحتواء وإمكانية الوصول لجميع الحالات مانع إغلاق،
  ولا يُستبدل بصندوق رسم أو padding محلي قبل التكبير.

## Android / IME

البيئة المحلية لا تحتوي Flutter/Dart/Java/adb/emulator أو/dev/kvm.
أضيف مسار CI مع KVM وAndroid35 x86_64/Pixel2، يعيد تثبيت **APK هذا التشغيل**،
ويحفظ model/OS/ABI/keyboard/APKhash وPNG/XML/dumpsys/logcat لكل خطوة.
تجربته محدودة صراحة: launch، حقل اسم، ASCII+numbers عبر adb، ظهور الكيبورد،
إخفاؤه، انتقال، autosave، force-stop/reopen. **PENDING** قبل تنفيذه.

حتى نجاحه لا يثبت تركيب Arabic/English الفعلي؛ adb injection ليس IME composition.
الخيارات الطويلة/تعدد الأسطر/التركيز/insets/الحفظ المرئي والتنقل والتصدير مع
الكيبورد، والجهاز الحقيقي مقابل المحاكي، تبقى متطلبات غير مثبتة.
`runtime.json.completeAcceptance=false` دائمًا؛ لا عرض نجاح smoke كإغلاق IME.

## الأصول المفتوحة والهاشات قبل التغيير

فُتحت من التنزيل الطازج: Visual preview1 وPDFpage1، وdrag320 branch-between
PNG/PDF، لا مجرد أسماء الملفات. PDF رُندِر بـPyMuPDF محليًا؛ PNG الأصل لم يتغير.

| الأصل | SHA256 |
|---|---|
| Visual vector.pdf | `09a75d3e96925267923ea637ae5e6eca888b42baa71522ba4127750b61ab3b57` |
| Visual preview_page_1.png | `4119c5e5f8dc6192dc44802fe891d1fc3fe07af06d5c261898c83a567cad39cf` |
| drag320 branch-between PDF | `4b7b2e51817f80b19fed0f352e254db692a9cdf476efa309beaaf4f03abe6c50` |
| drag320 branch-between PNG | `633ee921431a1a74bc93e1e9f19c312f326dd7802852202ccf1e213db7de3d01` |

تشغيل f52da5d Main40727445468 توقف في BEFORE، وليس دليل نجاح أو فشل الإصلاح:
فشل English بالاتجاه المتوقع، وفشل Arabic لأن مرجع TextPainter استعمل minWidth0
بدل عرض العمود المفروض على RenderParagraph (انحراف محاذاة85.98px). صُحح قيد
المرجع إلى العرض الفعلي نفسه، مع الإبقاء على المقارنة1e-6؛ كذلك يقرأ حارس BEFORE
رسالة framework من print events بدل رسالة error العامة. APK/Visual لم يُنفذا.
أصل log نُقل بهوية/هاش ضمن f52-logs، ولا إخفاء للفشل أو احتسابه PASS.

تشغيل93ed86e Main40728303766: BEFORE أثبت عيب اتجاه English وحبر + الأصلي؛
Native226passed/1failed، وانحدارا اتجاه الرأس نجحا. تحسين medium وحده أعاد
8.83556 من10.32202 pixel-equivalent لأول+، لكنه **فشل** نفس حد1pixel (فرق1.48647).
لم يُرفع الحد أو يُحذف الاختبار؛ full/APK/Visual/Android لم تُنفذ بعد الفشل.
التعديل التالي يختبر backing شفافًا بقوة2 وحدود مصدر أصلية لحماية mipmaps
عند حواف صورة73px ذات أحجام فردية. هذه **فرضية إصلاح قيد الاختبار**، لا نجاح
معلن: بايتات الأصل/PDF ومقاس المحتوى ووجهته تبقى كما هي؛ لا تكبير خط أو حبر مصطنع.

42ade1e: Native gate اجتاز بعد حماية mipmap؛ math regression الأصلي بنفس حد1pixel
بقي كما هو، وfull قيد التنفيذ وقت إعداد التعديل التالي. النتيجة ليست قبولًا نهائيًا؛
التغيير التالي يقوّي C6 typed math ويستلزم إعادة دورة SHA واحدة كاملة.

AFTER النهائي غير متوفر قبل اكتمال تشغيل SHA الجديد. لا وصف لفرقٍ بأنه مُصلح قبل فتح أصليه.
تبقى إعادة فحص equations/OPTEND/B109/كل الصفحات/RTL والمقاطع الطويلة واجبة.

## بوابات الشفرة الجديدة / موانع CLOSED

قبل CI: Python inventory5/5، transport11/11، APK-audit7/7؛ geometry34/34
و3 real-artifact tests لم تُنفذ محليًا لغياب المدخلات الجديدة (ليست PASS).
لا Flutter محلي؛ tests/analyze/actualAPK/Visual/C6/Extended الجديدة **PENDING**.
يُتبع تشغيل GitHub الجديد حتى نتيجته؛ لا تُنقل نتائج baseline إلى SHA جديد.

1. حسم قاعدة الدرجة، ثم إصلاح اختلاف السطحين والانحدار وفتح before/after.
2. إعادة C6 من نفس plan وقراءة كل finding؛ حل/تصنيف كل مخالفة بدليل.
3. حبر المعادلات والمقارنة البصرية الشاملة وعدم تكرار/فقدان المقاطع.
4. كل tool/content/boundary/history/media/race/export sequences؛ لا يكفي الوجود.
5. كل handle فعلي320/360، effective48×48، overlap/viewport/accessibility.
6. مصفوفة Android/IME الفعلية، لا مجرد بناء أو smoke أو إدخال adb.
7. دورة البوابات الكاملة وAPK/ABI/font على SHA نهائي واحد؛ أي تعديل يعيد المطلوب.

**الحكم الحالي OPEN** لهذه الشروط المحددة، لا CLOSED ولا parity ولا تفعيل مرشح.

---
## سجل تاريخي محفوظ — ليس حالة القبول الحالية

# متابعة الإغلاق — OPEN / candidate OFF

لا تفعيل ولا دمج PR ولا حذف فرع. هذا سجل مرحلي، **ليس قبولًا نهائيًا**.
الفرع الثابت: `arena/8513fa6c-writing-questions`.

## هوية الأدلة المرصودة (لا تُنقل إلى التعديلات التالية)

SHA: `fbb9b8e1c16ebd46344d60d48b6e4dedc02d2145`.
- [Main 40582445191](https://github.com/techtouchAI/Writing-questions/actions/runs/40582445191): **FAILURE**.
- [Extended 40582445200](https://github.com/techtouchAI/Writing-questions/actions/runs/40582445200): **SUCCESS**.
- production-first: 8 passed / 0 failed؛ native-first: 70 / 0؛ full: **951 / 3**، 0 skipped، 106 suites؛ canonical gate: 3 / 0.
- analyzer: **No issues found**. APK: **لم يُنفّذ**؛ manifest يصرّح `flutter-build.log` ضمن `notProduced`، وليس نجاحًا.
- Visual وC6 ونقل الأصول/السجلات: SUCCESS، لا تعوّض فشل المجموعة أو غياب APK.

نُقلت السجلات الكاملة لأوامر Flutter الخمسة المنفّذة مع SHA-256؛ ليست أرشيف setup/job الكامل. قناة git-blob تعمل؛ مشكلة 403 التاريخية ليست عائقًا حاليًا.

## التشخيص والتغيير

| العيب | السبب / التغيير | ما ثبت وما لم يثبت |
|---|---|---|
| OPTEND | التوقع القديم كان يفحص الصفحة الأولى فقط. الخيار الطويل فعليًا يمتد لصفحتين؛ التوقع المصحح يفحص جميع الصفحات ويقارن الموضع وحفظ الأسطر بمرجع غير مقسّم. لا إخفاء محتوى أو تعديل ارتفاع الورق. | ملف fbb الأصلي: OPTEND صفر في صفحة0، واحد في صفحة1؛ أُعيد رندره. لا تُنقل نتيجته إلى SHA لاحق. |
| الترويسة العربية | الخط Amiri الأصلي يحتاج GSUB/GPOS؛ أشكال presentation-form لا تكفي. أضيف جسر HarfBuzz native وsubset للـGIDs الأصلية، مع هندسة الخطة المشتركة كما هي. | fbb: تسلسلات outlines الأربعة تطابق مرجع HB مستقل 4/4. فُتح PNG المعاينة وPDF المعاد رندره فعليًا؛ لم يعد اختلاف التشكيل السابق ظاهرًا في هذه العينة. هذا ليس إثباتًا لكل BiDi/التشكيل/الأجهزة. |
| فشل Quran/P0 في fbb | قارئ القياس كان يسقط TJ اللاحقة بعد Ts، والتصحيح العددي المنفرد في آخر الكلمة؛ وكان يعامل وجهة ToUnicode الفارغة المصرّح بها كـCID غير معروف. | اختبارات المصدر الأصلية وتسامحاتها باقية. أضيفت raw-PDF regressions لكل TJ والتصحيح المنفرد وفصل الكلمات وCID المفقود الحقيقي (ما زال U+FFFD). التنفيذ بعد التعديل **PENDING**. |
| دلالة نص المجموعات المركبة | استخراج MuPDF من fbb أظهر control characters مكان مكونات glyph ذات الوجهة الفارغة، رغم صحة الرسم. ليست مشكلة قارئ الاختبار وحده. | أضيف ActualText المنطقي القياسي حول كلمات OpenType، واختبار PDF حقيقي يحفظ المصدر/التقدم/.notdef، وبوابة مستقلة للمصدر وcontrol artifacts. تجربة تعديل تشخيصية منفصلة نجحت، **ليست دليل PDF صادر عن التطبيق بعد الإصلاح**. ترتيب النسخ RTL في MuPDF غير مثبت؛ لا ادعاء بحله. |
| تصدير أثناء التغيير | حارس الخطة عند بدء التصدير لا يكفي بعد await للخطوط/الصور/حفظ المكتبة. | أضيف تحقق snapshot بعد إنشاء PDF وبعد حفظ المكتبة، مع اختبار UI بتأخير اكتمال PDF حقيقي ثم تغيير النسخة. **PENDING**. |
| أصول قديمة متأخرة | الحارس الموجود يرفض loader قديمًا بحسب layout identity؛ يحتاج تنفيذًا. | أضيفت صورتان فعليتان red/green وتكميل متحكَّم به؛ فحص pixels الحالية وPDF أثناء بقاء القديم pending. **PENDING**؛ ليست تجربة image-picker منصة. |
| السحب والتاريخ | استدعاء move/swap لا يثبت فعلًا gesture/drop/export. | أضيفت 6 حالات ضغط مطوّل وسحب حقيقي عند320/360، ترتيب السؤال/الفرع/تبديل بين سؤالين، model كامل وundo/redo وPDF من الخطة الحية وإحداثياته و18 صورة/ملفًا. **PENDING**؛ لا قبول قبل تشغيلها وفتح الأصول. |

تم تقليم vendor بإزالة أمثلة/tests/generators غير المستخدمة فقط؛ 369 ملف مكتبة `.h/.hh/.cc` أصلية مع COPYING. بناء Linux بعد الاستعادة/التقليم نجح في31.47s. لا ادعاء بأن ذلك يثبت CMake/Android APK.

## مراجعة الأصول الفعلية على fbb فقط

الأصول خارج Git في `/home/user/closure-audit/fbb-{production,visual,logs}`، لكل مجموعة `retrieval-provenance.json` يربط run وSHA وhash. المشتقات منفصلة؛ لا تُستبدل الأصول.

- فُتح `fbb-visual-page-0.png` من PDF الأصلي و`fbb-visual/preview_page_1.png`: الترويسة والعربية والرياضيات inline/display ظاهرة؛ لا قبول شامل بالبكسل.
- فُتح `fbb-r9-320-page-4.png`: B109 والسطر النهائي كاملان دون قص ظاهر في العينة.
- عرض360 وبقية seams/selection والـPDF الجديد بعد ActualText والسحب لا تزال تحتاج مراجعة أصلية، لا استنتاجًا من مساواة hashes وحدها.
- `diagnostic-actualtext.pdf` **تجربة معدَّلة خارج التطبيق**، ليست AFTER ولا دليل قبول.

SHA-256 لأصول fbb المرصودة:

| الأصل | SHA-256 |
|---|---|
| Visual vector.pdf | `22334bcc3f1df8cce4ae77578ff9aa683760e2549da10031f155cf2afddee562` |
| Visual preview_page_1.png | `3aa58a80a196f248449a7848ff96abccea654f2c40a248010d93142a14b3695a` |
| Arabic outline JSON | `5893400649d45d86b410e3452b9154ee4f8e3570f0b61213a770b8bd55ee40ab` |
| OPTEND long.pdf | `05b83dab85bc0f64fe4aa71f612d2acaae02320f0c645b69124800fba252ceaf` |
| r9-320 live-plan.pdf | `3b44462e7a29a3bb25a2171ef10f204431e471fedac1c6c79320687771bf632e` |

## بوابات النسخة التالية / الموانع

بعد أي تعديل يلزم targeted ثم full، analyzer بلا infos، **APK منفّذ ناجح**، Visual/C6/Extended، ونقل/فتح الأصول على **SHA واحد**. النتائج أعلاه ليست هذه البوابات.

المحلي: Python audit12 PASS، transport9 PASS بما فيه companion completeness؛ YAML وdiff-check PASS. لا Flutter/Dart محليًا؛ اختبارات Dart الجديدة لم تُنفَّذ عند كتابة هذا السجل.

تبقى مصفوفة `closure_editing_inventory.md` المرجع للفجوات: IME كامل/المنصة/كل الحوارات والوسائط/كل عمليات التنسيق/كل الحدود/تكافؤ المرشح.42 invocation أو8 قياسات ليست إثباتًا وظيفيًا كاملًا. إذا بقي فشل/اختلاف مرئي/غياب APK أو تغطية أساسية فالحالة **OPEN** دون تفعيل.


## متابعة تشغيل513938a (لا يُنقل إلى الإصلاح التالي)

SHA `513938a93714d527bd85bcd519d33ed5d8f6061d`:
[Main40585963097](https://github.com/techtouchAI/Writing-questions/actions/runs/40585963097)
FAILURE، [Extended40585962900](https://github.com/techtouchAI/Writing-questions/actions/runs/40585962900) SUCCESS.
production-first8/0؛ native-first116/2؛ analyzer نظيف؛ full/APK/Visual/C6 لم تُنفّذ.

كل اختبارات GPOS/ActualText/Quran/P0 الأصلية وسباقي export/image نجحت؛ سحب
الفروع4 حالات نجح، وسحب السؤال عند320/360 فشل بـRangeError بعد العمليات.
السجل الكامل native SHA-256:
`bce7d01e598e5e4ca51d3713966ff0dfb7fc5f418baab250e384d54877a93244`.

المصدر يكشف أن DragTarget.builder يُعاد بناؤه مستقلًا بعد drop/leave ويستعمل
BranchRef مفهرسًا ملتقطًا قبل تبديل السؤال؛ فالسؤال الجديد في الفهرس0 يحمل
فرعًا واحدًا بينما المرجع القديم يطلب الفرع1. الإصلاح التالي يحسم المعرف
الثابت للفرع داخل builder وكل event بدل هذا المرجع الملتقط؛ يغيّر الحارس
والقراءة فقط، لا التخطيط أو التسامح. أُضيف حفظ FlutterErrorDetails وتوقعات
بعد drop/undo/redo دون إسكات الأخطاء. **نتيجة الإصلاح PENDING**.


## متابعة8bfcc66 وإصلاح BiDi اللاحق

SHA `8bfcc665a87be0d1fe4977b6beec0b01e0267130`،
[Main40586966297](https://github.com/techtouchAI/Writing-questions/actions/runs/40586966297):
job122480895940 **SUCCESS**؛ native118/0، full979/0 (0 skipped،111 suites)،
analyzer نظيف؛ **APK بُني فعليًا31.3MB**، assembleRelease412.1s، وartifact رُفع.
ليس تشغيلًا على جهاز Android. [Extended40586966135](https://github.com/techtouchAI/Writing-questions/actions/runs/40586966135) SUCCESS.
Visual/C6 لم ينتهيا عند كتابة هذه الإضافة؛ لا تُنقل هذه النتائج للتعديل التالي.
سجل البناء الكامل متحقق SHA-256:
`c09a540b61b05aa71df5bd2d9f091091ee7aced97b51d4b1ee96c64ac7645fa1`.

نجاح اختبارات السحب لا يكفي: فُتحت PNG وPDF الأصلية لسحب الفرع من513؛
الترتيب والدرجات صحيحان، لكن عنوان English المختلط كشف **تداخلًا مرئيًا**.
في PDF الأصلي، كلمتا «مختلط» و«نص» تبدأان عند142.196 و144.625pt،
ومجالهما يتداخل مع «(5 marks)». لم يُخفَ هذا العيب خلف نتائج السحب الخضراء.

تتبُّع السبب: `_measureWords` يستعمل carets عند حد BiDi من المقطع التالي،
وبمرجع سقوط يشمل المقطع كله بدل الكلمة. أُعد إصلاح في القياس المشترك:
مرجع selection خاص بكل كلمة، وحسم upstream/downstream بحسب صندوق المصدر
الأصلي. لا إزاحة PDF تعويضية ولا تغيير خط/حجم/clip/صفحة. أضيف توقع مستقل
منTextPainter عند1e-6، وتوقعات عدم تداخل للكلمات العربية/الدرجات في PDF
السحب نفسه. **التنفيذ بعد هذا الإصلاح PENDING**.

أضيفت أيضًا25 حالة pointer/model الحالية عند defaults1600/320/360 مع إبقاء
النسخة المكتبية، وبقاء أي width صريح في اختبار بعينه كما هو. لا تُعد حوارات
المعادلات التي تُلغى إدراجًا/undo/export ناجحًا. لقطات السحب الجديدة3x قابلة
للقراءة، وlocale العربية كالبرنامج؛ لم يُغيَّر DPI/قياس المستند.

أضيف تدقيق APK بعد نجاح البناء: كلABI لـFlutter يقابله libwriting_harfbuzz،
ELF class/machine صحيح، أربع دوال C ABI عامة معرّفة فيdynsym، وAmiri المضمَّن
مطابق بايتًا للمصدر، مع hash للـAPK والمكتبات.6 اختبارات validator محلية PASS
وفحص ELF المكتبةLinux الفعلية PASS؛ **APK الحقيقي بهذا التدقيق PENDING**.


اكتمل8bf Main40586966297 **SUCCESS** بما فيه Visual/C6 ونقل الأصول؛ لا إلغاء
لهذا التشغيل. Visual الأصلي بعد ActualText: PDF SHA-256
`0d0b948d679ce75b00b44ee5f885126be8b9d1721ce5e0512768424b387a72dc`،
audit JSON `d720b450ea764fcccba74d65143bd2052c4d826b1fa26318993b380f88ddb83d`.
هذه نتيجة قبل إصلاح العنوان الإنجليزي/قياس BiDi وتوسيع viewport cases وتدقيق
APK الجديد، وليست بوابات SHA التالي. **OPEN** رغم هذه الدورة الخضراء.

أُعيد جلب Visual80 الأصلي للمقارنة التاريخية: PDF
`950bb1c45be06c343a10043e31f150032f4b4ca1b960bf3404dba6117c5bc2ea`،
وفُتح raster صفحة0؛ اختلاف الترويسة BEFORE ظاهر. PNG المعاينة80/fbb/8bf
نفسها بايتًا `3aa58a80a196f248449a7848ff96abccea654f2c40a248010d93142a14b3695a`،
فلا يُفسَّر فرق PDF باختلاف إعدادات عينة المعاينة.

## متابعة5eb88fd: فشل narrow audit وتشخيصه، لا قبول نهائي

SHA `5eb88fdcc99c9bb63efaf5dcd407ee2ee68251ae`؛
[Main40590392389](https://github.com/techtouchAI/Writing-questions/actions/runs/40590392389)
FAILURE؛ [Extended40590392484](https://github.com/techtouchAI/Writing-questions/actions/runs/40590392484)
SUCCESS. production8/0، native185/12/0 في18suite، analyzer نظيف17.3s.
full/APK/Visual/C6 **SKIPPED وليس نجاحًا**. نُقلت4سجلات و80أصلًا كاملة وتحقق SHA-256.
السجل native: `cfae66157efe52cfc1aa5d6f8364840d666a28fd47163440b91ee4b0ef53e8fd`.

الأخطاء12 هي6حالات بكل عرض320/360:
- أربع حالات بحثت عن أوامر lazy ListView قبل بنائها. `ensureVisible` لا يبني child غير موجود؛ يلزم تمرير قائمة التبويب الحقيقية أولًا. أضيف helper للتنقّل/التمرير/النقر الفعلي، لا استدعاء callbacks ولا حذف توقعات النموذج/الحوار.
- حوار الإعدادات: Dropdown numerals وquestion label تجاوزا العرض بـ106px عند320. التعديل يقيّد العرض المتاح ويتيح item height طبيعيًا مع زر48dp، دون تصغير خط/حذف محتوى/إخفاء overflow. يُطبّق على font dropdown أيضًا.
- مقبض تغيير الحجم: يتنافس PanRecognizer مع تمرير الصفحة، فيفوز التمرير عند الزوم الصغير. إضافة إلى ذلك delta المحلي للورقة لا يجوز قسمته على zoom ثانيةً. التعديل يستخدم pointer screen-space مباشرًا مع EagerRecognizer مثل سحب جسم العنصر، يحتفظ بحالة المؤشر عبر إعادة البناء، ويبقي tap/cancel والتدوير والتحرير والحذف. أُبقيت توقعات النمو الأصلية وأضيفت هندسة `36/zoom` و`24/zoom` (1e-4 للتجميع العددي فقط). تنفيذ التعديلات الجديدة **PENDING**.

اجتازت5eb اختبارات حدود الكلمات المختلطة الستة في PDF واختبار TextPainter المستقل.
فُتح بالفعل PDF بعد السحب وصورة PNG الأصلية3× عند320:
- PDF `drag-320-branch-between-after.pdf`: `885399667b385a644c06dbdd06e9bb58d771d06467952e40d7b684c22c7f6adc`.
- PNG `drag-320-branch-between-after.png`: `633ee921431a1a74bc93e1e9f19c312f326dd7802852202ccf1e213db7de3d01`.
**تداخل كلمتي العربية مع الدرجة في PDF لم يعد ظاهرًا في هذه العينة**.
لكن الفتح أثبت اختلافًا آخر فعليًا: native legacy يضع الدرجة على الحافة اليمنى، وPDF يضعها inline بعد المنطوق؛ native يحمل مقابض السحب داخل مساحة النص أيضًا. هذا ليس تكافؤًا كاملًا ولا تعالجه نتيجة عدم التداخل.
المصدر legacy `_titleRow` (handle + Expanded statement + marks) لا يطابق تركيب عنوان الخطة المشتركة. لا masking في PDF ولا تفعيل المرشح لإخفاء هذا العيب؛ يلزم إكمال طبقة Option A المنفصلة وإثبات أدواتها على نفس الوثيقة قبل القبول. Chrome في widget-test يستخدم fallback/Ahem في بعض أزراره؛ PNG ليست دليل تشغيل Android.
الحالة **OPEN / candidate OFF**، ولا نتائج SHA قديم تُنقل إلى التعديلات التالية.

## متابعة0fa4e41: بقي overflow محرر البنى الرياضية، لا تجاوز للاختبارات

SHA `0fa4e413ec05fe041448697b66103eebce717528`؛
[Main40591884959](https://github.com/techtouchAI/Writing-questions/actions/runs/40591884959)
FAILURE: production8/0؛ native195/2/0، analyzer نظيف؛ full/APK/Visual/C6 لم تُنفّذ.
السجل الكامل المتحقق: `98e576c866534c8b6248d17466124625dd7e02ad38123b17d238680b68f11a5e`.
الإعدادات، تغيير الحجم مع توقعات delta المطلقة، والوصول إلى قوائم الأوامر الكسولة نجحت في هذا التشغيل، وليست إثباتًا لنسخة تالية.
الحالتان المتبقيتان هما عرض جميع قوالب الرياضيات/الكيمياء/الفيزياء عند320/360؛ بعد إصلاح التنقّل ظهرت البنى المركّبة الجذر/الدليل التي عرضها الطبيعي أكبر من قيود Wrap. أمثلة السجل: Rows في`visual_equation_editor.dart`1155/1198، تجاوز5.8/34/57px عند320.

التعديل التالي يعطي **منطقة البناء داخل الحوار** تمريرًا أفقيًا مع scrollbar ظاهر؛ البنى تحتفظ بعرضها الطبيعي ولا تصغير خط أو تغيير MathStyle/serializer/هندسة الورقة/PDF. يبقى clip الافتراضي للـviewport؛ المكونات خارج النافذة قابلة للوصول بالتمرير، وحشوة داخلية تحفظ مقابض الحذف الموجودة. أضيفت4حالات narrow inline/display: سحب فعلي للـviewport، تحرير الذيل، undo/redo للنص، وحفظ المقطع كاملًا بنفس delimiters. بقيت5حالات المحرر الأصلية، وأضيف الملف كاملًا إلى native-first. لكل قالب فحص exception مستقل لتحديد السبب دون تراكم أخطاء مخفية. **التنفيذ التالي PENDING**؛ لا تفعيل أو قبول تكافؤ.

## متابعةb79519f: native209/0، full1035/1؛ سبب كامل محفوظ

SHA `b79519f1d52d5b763022f9d6ed33e5502eb1554f`؛
[Main40593147542](https://github.com/techtouchAI/Writing-questions/actions/runs/40593147542):
production8/0؛ native209/0/0 في19suite؛ full1035/1/0 في111suite؛ canonical3/0، analyzer نظيف. APK لم يُنفّذ لأن full فشل.
[Extended40593147442](https://github.com/techtouchAI/Writing-questions/actions/runs/40593147442) SUCCESS.
السجل الكامل full: `b5d1de51b1086657aa4f2c455e8a6e78171abe0d1dc3ae37b8559ea5f973f0c2`؛ native: `8ffbcb751c30418acc4cb7f571a976c38f38084fe3ad131284789e8238e3ebb7`.

أول سبب فعلي للفشل الوحيد ليس StateError اللاحق: Scenario4/5/11 في`compound_equation_pipeline_test.dart` نقر حقل`x+1` عندx807.4 خارج الحوار ذي الحد الأيمن760، فأغلق modal barrier المحرر. بعد ذلك لم يوجد زر الحذف. بعد إتاحة تمرير المعادلة أفقيًا يجب أولًا إظهار الحقل المطلوب، كما يفعل المستخدم. أضيف `ensureVisible + real tap` للحقلين الأوسطين فقط، مع إبقاء المصدر الأصلي وتوقعات التركيز/الحذف/undo/redo/المقطع النهائي كاملة. أصبحت تحذيرات hit-test قاتلة في هذا الملف بدل السماح بإغلاقات صامتة. أضيف الملف كاملًا إلى native-first. الاختبارات4 الجديدة للتمرير/تحرير الذيل/التاريخ/inline/display وجميع75pointer cases نجحت فيb795، لا تُنقل نتيجتها إلى SHA التالي؛ التشغيل التالي PENDING.

## متابعة07cd63f: full أخضر وAPK مبني، لكن package audit فشل ولم يُخفَ

SHA `07cd63f0b42eb17dcd360abbd818b52359e26855`؛
[Main40595329771](https://github.com/techtouchAI/Writing-questions/actions/runs/40595329771) FAILURE؛
[Extended40595329723](https://github.com/techtouchAI/Writing-questions/actions/runs/40595329723) SUCCESS.
production8/0؛ native219/0/0 في20suite؛ full1038/0/0 في111suite؛ canonical3/0؛ analyzer نظيف؛ Visual/C6/transports SUCCESS.
**APK مبني فعليًا31.3MB في221.8s**، لكن خطوة`Verify packaged OpenType runtime and pinned face for every APK ABI` فشلت. لا يُعَد نجاح البناء قبولًا للتغليف.
سجل البناء المتحقق `090e7f1a8929bd5e602d1cbaadb7429b4e23688b8325cc6c4c8382138724fe9e`؛ full`ee641e7e60dba2873419b2ab7c245db3529fdf632a97d1ac09df1ffef7262abb`.

أرشيف job الكامل ورابط job الفردي يعيدان EOF من signed hosts، بينما7سجلات أوامر أصلية نُقلت بنجاح. لا يحتوي تقرير الفشل سوى exit1، و`apk-native.json` لم يكن يُكتب عند exception. لا نغيّر ABI filters أو نحذف شرطًا تخمينًا. أضيف حفظ JSON للفشل مع السبب الفعلي/hash الـAPK و`auditPassed:false` وإعادة رمي الاستثناء، وإشعار error؛ اختبار CLI جديد يثبت بقاء exit غير صفري وعدم قبول APK تالف. فحص ZIP/ABI/ELF/الصادرات/الخط الأصلي **لم يتغير أو يُضعّف**. الغاية من التشغيل التالي إتاحة التشخيص الفعلي ثم إصلاح السبب؛ جميع بوابات SHA التالي لازمة، والحالةOPEN.

## تشخيص1917adc الفعلي وإصلاح اختيار ABIs في CMake

SHA `1917adc2a1d74c10ce70b726f6b19c557c61bdf9`؛
[Main40597643558](https://github.com/techtouchAI/Writing-questions/actions/runs/40597643558) رفض التدقيق مجددًا، معproduction8/0 وnative219/0 وfull1038/0 وanalyzer نظيف وبناءAPK منفّذ.
نُقل `apk-native.json` الأصلي وتحقق hash`4d283d33781f5a153a31c219e3e44c1354485a6f9397f323289f76aadd096eb0`.
السبب الحرفي: `Flutter={'arm64-v8a', 'armeabi-v7a', 'x86_64'}, shaper={'x86_64', 'arm64-v8a', 'armeabi-v7a', 'x86'}`.
APK المرفوض hash`6b3ddabe54a74d27ca55a13da4bb51487090cfb0e731fad480d1555d8cfb4aa8`.

CMake بنى x86 افتراضيًا رغم عدم وجود Flutter engine له في release؛ ABI أصلي بلا engine قد يجعل APK يبدو قابلًا للتثبيت على جهاز غير مدعوم. قورن اختيار Flutter3.24.5 الأصلي في`packages/flutter_tools/gradle/src/main/groovy/flutter.groovy` (`getTargetPlatforms`/`PLATFORM_ARCH_MAP`). التعديل يجعل **قائمة بناء CMake** تتبع `-Ptarget-platform` نفسها وافتراض Flutter الثلاثي، دون تغيير فلاتر تغليف APK أو split-per-ABI أو تخفيف التدقيق. يبقى x86 قابلًا للبناء عند طلب`android-x86` صراحةً للـdebug/emulator. يرفض target مجهول بدل fallback صامت. أضيف regression صريح يبقي رفض native-only x86 إلى اختبارات ZIP الموجودة؛ المحلي7APK+12PDF+9transport PASS. يلزم الآن بناء حقيقي وتدقيق كل ELF على SHA الجديد؛ لا تُنقل نتائج191 إليه.
