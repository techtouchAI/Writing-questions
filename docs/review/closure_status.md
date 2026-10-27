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
