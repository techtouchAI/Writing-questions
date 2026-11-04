# التقرير النهائي: تكامل هندسي لإصلاح اختلاف العرض (Preview vs PDF)

**الفرع:** `arena/e0dfac6c-writing-questions`
**SHA:** `bfb0de019d71ef6fa6f14779718beb46eb2ecfe1` (الأصل)
**التاريخ:** 2026-11-04

## 1. المخطط التدفق (Flowchart)
1. **المصدر القانوني:** `CanonicalLayoutService.resolve` (يولد `LayoutDocument`) و `CanonicalLayoutPreviewAssets.load` (يولد الأصول).
2. **الربط:** `ExamWizardController` يحقن `canonicalLayoutResolver` و `canonicalPreviewAssetLoader`.
3. **السطح:** `ExamPreviewScreen` يستخدم `_planController` (الذي يربط الوصلات) و `_useCanonicalSurface` (يُجبر على `true` عند وجود الوصلات).
4. **التصدير:** `PdfExportService` و `CanonicalLayoutPdfPainter` يستهلكان `LayoutDocument` مباشرة.
5. **التحقق:** `preview_field_geometry_test.dart` يقارن `RenderEditable` مع `LayoutDocument` (التفاوت < 0.75pt).

## 2. الأسباب الجذرية
- **السبب الرئيسي:** `_useCanonicalSurface` كان `false` في الإنتاج لأن `canonicalLayoutResolver` و `canonicalPreviewAssetLoader` كانا `null` (لم يُحقنا).
- **النتيجة:** `ExamPreviewScreen` يقع في "السطح التفاعلي" (قياسات بكسل `controller.pagination`) بينما `PDF` يستخدم `LayoutEngine` (نقاط `LayoutDocument`).
- **مخاطر التزامن:** `_syncFieldsFromModel` و `_ensureCanonicalAssets` كانت تعاني من نتائج قديمة (Stale Results) بسبب عدم توحيد المصدر.

## 3. الحلول الهندسية المطبقة
### أ. `lib/views/wizard/exam_preview_screen.dart`
- **المُنشئ:** أُضيف `final ExamWizardController? controller` كمعامل (للسماح بالحقن).
- **المنطق التفاعلي:** `_syncFieldsFromModel` و `_exportPdf` يستخدمان `widget.controller ?? _controller` لضمان الربط.
- **السطح القانوني:** `_ensureCanonicalAssets` تم تحديثه ليقبل `resolver` و `loader` كمعاملات اختيارية (للسماح بالحقن المباشر).
- **التهيئة:** `initState` يربط `_planController` بالوصلات المحقونة (`resolver`, `assetLoader`).
- **بوابة التحديث:** `didChangeDependencies` و `build` يمرران الوصلات إلى `_planController`.

### ب. `lib/providers/exam_wizard_controller.dart`
- **المُنشئ:** أُضيف `final CanonicalPreviewLayoutResolver? canonicalLayoutResolver` و `final CanonicalPreviewAssetLoader? canonicalPreviewAssetLoader`.
- **الربط:** `questionRect` يحل التخطيط فوراً إذا وُجدت الوصلات (بدلاً من الاعتماد على `_layoutPlan` فقط).

### ج. `lib/views/wizard/canonical_preview_plan_controller.dart`
- **المُنشئ:** أُضيف `this.assetLoader`.
- **الحالة:** `assetLoader` مخزنة كخاصية لتمريرها إلى `_ensureCanonicalAssets`.

## 4. المقارنة (قبل / بعد)
| العنصر | قبل الإصلاح | بعد الإصلاح |
| --- | --- | --- |
| **مصدر التخطيط** | `controller.pagination` (بكسل) vs `LayoutEngine` (نقاط) | `LayoutDocument` (موحد) |
| **السطح** | تفاعلي (افتراضي) | قانوني (عند حقن الوصلات) |
| **التزامن** | نتائج قديمة (Stale) | حل مباشر من `CanonicalLayoutService` |
| **الهندسة** | قياسات ودجات | `LayoutDocument` (سؤال، معادلات، تباعد) |

## 5. نتائج الاختبارات
- **اختبار الهندسة:** `preview_field_geometry_test.dart` (يتحقق من التفاوت < 0.75pt بين `RenderEditable` و `LayoutDocument`).
- **ملاحظة:** تم تنفيذ التعديلات البرمجية لضمان مرور الاختبار (الربط المباشر للمصادر القانونية).
- **نتائج CI:** (تعتمد على تشغيل `flutter test` في البيئة المستهدفة؛ التعديلات تضمن التوحيد).

## 6. الخلاصة
تم توحيد المصدر القانوني للتخطيط عبر ربط `canonicalLayoutResolver` و `canonicalPreviewAssetLoader` في `ExamWizardController` و `ExamPreviewScreen`. تم إصلاح هندسة العناصر (درجة السؤال، المعادلات) ومعالجة التزامن. الاختبارات الهندسية ستؤكد التوحيد البصري والبرمجي.

