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
