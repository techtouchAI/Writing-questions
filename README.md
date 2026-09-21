# تطبيق صانع ومحرر الأسئلة الاحترافي (Writing Questions)

[![Build & Release Android APK](https://github.com/techtouchAI/Writing-questions/actions/workflows/build_apk.yml/badge.svg)](https://github.com/techtouchAI/Writing-questions/actions/workflows/build_apk.yml)

تطبيق أندرويد متكامل ومبني بإطار عمل **Flutter** لتسهيل إنشاء، تنظيم، وإدارة بنوك الأسئلة، وبناء اختبارات نموذجية وتصديرها بصيغ **Word (.docx)** و **Excel (.xlsx)** بجودة عالية للطباعة والرفع على منصات التعليم الإلكتروني.

---

## 🌟 الميزات الأساسية

1. **إدارة الأسئلة الذكية:**
   - خيارات متعددة (MCQ) مع دعم إجابة واحدة أو متعددة، وتحديد الإجابة الصحيحة وشرح الحل.
   - صح وخطأ (True/False).
   - إكمال الفراغات (Fill in the blanks).
   - أسئلة مقالية وشرح مطول (Essay).
   - تحديد مستوى الصعوبة (سهل، متوسط، متقدم) والدرجة المستحقة والتصنيف (المادة، الوحدة/الفصل).

2. **منشئ الاختبارات (Exam Builder):**
   - تخصيص الترويسة الرسمية (اسم المدرسة/المؤسسة، المادة، الصف، زمن الاختبار، الدرجة الكلية، اسم المعلم، تعليمات الاختبار).
   - تحديد الأسئلة المراد إدراجها وترتيبها أو بعثرتها عشوائياً.

3. **محرك التصدير المزدوج:**
   - **تصدير إلى Word (.docx):**
     - توليد ملف OpenXML مباشر نقي متوافق 100% مع Microsoft Word و Google Docs.
     - دعم كامل لاتجاه النص العربي (RTL) وترتيب الفقرات وتنسيق الجداول.
     - خيارين للتصدير: **نسخة الطالب** (للطباعة والامتحان) أو **نموذج الإجابة للمعلم** (مع الحلول والشرح وتوزيع الدرجات).
   - **تصدير إلى Excel (.xlsx):**
     - جدول بيانات منظم بجميع التفاصيل، الترويسة، الخيارات، والإجابات النموذجية.
     - جاهز للاستيراد المباشر إلى المنصات التعليمية مثل Blackboard و Moodle و Google Forms.

4. **بناء آلي مستمر (CI/CD):**
   - سير عمل **GitHub Actions** يتحقق من جودة الكود (تحليل ثابت + اختبارات آلية) ثم يجمع حزمة `app-release.apk` تلقائياً.
   - عند رفع وسم نسخة `v*` يُرفق ملف الـ APK تلقائياً بإصدار GitHub Release.

---

## 🚀 كيفية الرفع إلى مستودع GitHub

قم بفتح الطرفية في مجلد المشروع ونفّذ الأوامر التالية:

```bash
git init
git add .
git commit -m "feat: initial release of Writing Questions Android app with Word and Excel export"
git branch -M main
git remote add origin https://github.com/techtouchAI/Writing-questions.git
git push -u origin main
```
