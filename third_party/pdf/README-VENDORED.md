# نسخة معدّلة محلياً من حزمة `pdf` 3.11.3

هذه الحزمة **ليست** من تأليفنا. المصدر: [DavBfr/dart_pdf](https://github.com/DavBfr/dart_pdf)
عند الوسم `pdf-3.11.3` (الالتزام `219de6f`)، الرخصة Apache-2.0 (انظر `LICENSE`).

## لماذا نُسخت؟

لأن الإصدار 3.11.3 (وكل الإصدارات حتى اليوم في `master`) تحوي خللاً يجعل
مسافات الكلمات العربية تتآكل في مخرجات PDF من اليمين إلى اليسار:

* `_Line.realign()` في `lib/src/widgets/text.dart` تعكس موضع كل كلمة بعرض
  **الحبر** (`span.width` = `metrics.width`) بينما المؤشر المنطقي في
  `RichTextContext.layout` يتقدّم بعرض **التقدّم** (`metrics.advanceWidth`).
* الفرق بين الاثنين هو الفراغات الجانبية للمحارف (lsb/rsb)، ولذلك تظهر
  «تدور الأرض» كأنها «تدورالأرض» (الفجوة تنقص من 2.431 نقطة إلى 1.298 نقطة
  عند حجم خط 11 نقطة).

## ما التعديل بالضبط؟

تعديل واحد في ملف واحد: `lib/src/widgets/text.dart`

* إضافة `double get advanceWidth;` إلى الصنف المجرّد `_Span`، وتنفيذها في
  `_Word` (بـ `metrics.advanceWidth`) و`_WidgetSpan` (بعرض العنصر المضمّن).
* استخدام `advanceWidth` بدل `width` في انعكاس RTL داخل `_Line.realign()`
  وفي فرع `TextAlign.justify` (نفس الخلل في التوزيع).

لا تغيير في أي واجهة عامة، ولا في الخط، ولا في المقاسات، ولا في الالتفاف،
ولا في المسار LTR (المعدّل فرع RTL فقط).

## كيف نتحقق أن التعديل لم يُفقد؟

* `test/pdf_engine/pdf_content_probe.dart` + `arabic_word_spacing_test.dart` +
  `pdf_exam_engine_arabic_test.dart` تقيس ملف PDF الناتج وتفشل إن عاد الخلل.
* `dart run tool/verify_vendored_pdf_patch.dart` فحص سريع لوجود التعديل
  (يفشل بوضوح إن استُبدلت الحزمة بنسخة أصلية).

## كيف نُحدّث الحزمة لاحقاً؟

1. استنسخ المستودع الأصلي واخرج على الوسم الجديد:
   `git clone https://github.com/DavBfr/dart_pdf`
2. انسخ `pdf/lib` و`pdf/pubspec.yaml` و`pdf/LICENSE` و`pdf/CHANGELOG.md` إلى هنا.
3. طبّق التعديل: `dart run tool/apply_pdf_rtl_word_spacing_patch.dart third_party/pdf`
   (سيفشل بوضوح إن لم تعد المواضع تنطبق، أو يخبرك أن التعديل مطبّق مسبقاً).
4. شغّل `flutter test` للتأكد من نجاح اختبارات المسافات العربية.

> إن أُصلح الخلل في المستودع الأصلي، فاحذف هذه النسخة وأزل
> `dependency_overrides` من `pubspec.yaml` وارفع رقم الحزمة (الأفضل).
