# تقرير الإغلاق الشامل — OPEN / candidate OFF

**حالة المراجعة الحالية: OPEN.** لا تفعيل، لا دمج PR، لا حذف فرع. هذا القسم
يحل محل أحكام الحالة القديمة أدناه؛ السجل الأقدم محفوظ للتتبع، وليس نتائج الشفرة الحالية.
الفرع: `arena/8513fa6c-writing-questions`.

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
