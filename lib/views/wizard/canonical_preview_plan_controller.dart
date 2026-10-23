import 'dart:async';

import 'package:flutter/scheduler.dart';

import '../../layout/canonical/canonical_layout_service.dart';
import '../../layout/canonical/canonical_page_plan.dart';
import '../../layout/canonical/layout_document.dart';
import '../../layout/document_ir.dart';
import '../../models/exam_document.dart';
import '../../services/export_file_service.dart';

/// مُحوِّل مستند ↔ خطة صفحات: نداء واحد، ومهل قصيرة للكتابة المتصلة.
typedef CanonicalPlanResolver = Future<LayoutDocument> Function({
  required ExamDocument document,
  required DocumentIR sourceIr,
});

/// يحسم **خطة الصفحات الوحيدة** التي ترسمها كل الأسطح.
///
/// المسؤولية الوحيدة: أن يبقى `_plan` مطابقاً للمستند الحالي، وألّا يُعرض
/// أبداً تخطيط يخصّ نسخة قديمة. لا يقيس نصاً ولا يقسّم صفحات؛ كل ذلك في
/// `LayoutEngine`، وهذا الكائن يخزّن النتيجة ويبلّغ الواجهة.
///
/// حالتان صريحتان:
///   * [plan] != null  ⇒ ارسم صفحاتها (و[matches] تقول هل تخصّ المستند الحالي
///                       أم أنها نسخة اللحظة السابقة أثناء حسم التعديل الجديد).
///   * [plan] == null  ⇒ أول حسم أو فشل: حالة تخطيط/فشل صريحة، ولا تُخترع
///                       هندسة من ارتفاع ودجات.
///
/// لماذا تُعرض الخطة السابقة أثناء الحسم؟ لأن إسقاط الشجرة إلى دوّارة تحميل
/// عند كل حرف يُفقد التركيز وجهاز الإدخال (IME) أثناء الكتابة. الخطة السابقة
/// تبقى **معلنة كغير مطابقة** ([matches] = false)، فلا تُستخدم في التصدير ولا
/// في حساب أي هندسة نهائية.
///
/// لماذا لا `ChangeNotifier` للمتحكم؟ لأن سطح المعاينة يرسم أصلاً على إشعار
/// `ExamWizardController`؛ إشعار إضافي هنا كان سيضاعف إعادة البناء بلا داعٍ.
class CanonicalPreviewPlanController {
  CanonicalPreviewPlanController({CanonicalPlanResolver? resolver})
      : _resolver = resolver;

  final CanonicalPlanResolver? _resolver;

  /// مهلة الخطة السابقة للارتفاع 70ms: يحسب الاختبار والحسم في كل تعديل
  /// حرف، فيتجنّب هذا العرض المتكرر بلا داعٍ. قرار التقسيم نفسه لا يُخفَّف.
  static const Duration debounce = Duration(milliseconds: 70);

  CanonicalPagePlan? _plan;
  ExamDocument? _pendingDocument;
  ExamDocument? _failedDocument;
  Timer? _timer;
  int _revision = 0;
  bool _disposed = false;

  /// الخطوة القادمة لإعادة البناء في الواجهة: تُطلب من المتحكم المستضيف.
  VoidCallback? onChanged;

  CanonicalPagePlan? get plan => _plan;
  ExamDocument? get failedFor => _failedDocument;
  bool get isPlanning => _plan == null && _failedDocument == null;

  /// هل الخطة الحالية تخصّ [document] و[sourceIr] بالذات؟
  bool matches(ExamDocument document, DocumentIR sourceIr) {
    final plan = _plan;
    if (plan == null) return false;
    return identical(plan.layout.source, sourceIr) &&
        identical(_planDocument, document);
  }

  ExamDocument? _planDocument;

  /// يطلب خطة للمستند الحالي (إن لم توجد خطة مطابقة ورخيصة). لا يعيد البناء
  /// إن لم يكن ثمة شيء ليعرضه.
  void request(ExamDocument document, DocumentIR sourceIr) {
    if (_disposed) return;
    if (matches(document, sourceIr)) return;
    if (identical(_pendingDocument, document)) return;
    if (identical(_failedDocument, document)) return;
    _pendingDocument = document;
    _timer?.cancel();
    final revision = ++_revision;
    _notify();
    _timer = Timer(debounce, () async {
      if (_disposed || revision != _revision) return;
      try {
        final resolver = _resolver;
        final layout = resolver == null
            ? await CanonicalLayoutService.resolve(
                document: document,
                sourceIr: sourceIr,
              )
            : await resolver(document: document, sourceIr: sourceIr);
        // حسم أقدم اكتمل بعد حسم أحدث: يُهمَل بالكامل، ولا يُستبدل به ما
        // تُعرَض صفحاتُه الآن. الفحص قبل النداء لا يكفي لأن النداء غير متزامن
        // (اختبار «stale layout completion» يقيس هذا بالضبط).
        if (_disposed || revision != _revision) return;
        if (!identical(layout.source, sourceIr)) {
          throw StateError(
            'التخطيط القانوني لا يخصّ المصدر الدلالي الحالي (نسخة قديمة).',
          );
        }
        _plan = CanonicalPagePlan.fromLayout(layout);
        _planDocument = document;
        _pendingDocument = null;
        _failedDocument = null;
        _notify();
      } catch (error, stackTrace) {
        ExportFileService.logError(
          'Canonical page plan failed',
          error,
          stackTrace,
        );
        if (_disposed || revision != _revision) return;
        _plan = null;
        _planDocument = null;
        _pendingDocument = null;
        _failedDocument = document;
        _notify();
      }
    });
  }

  /// إعادة محاولة الحسم بعد فشل (زر «إعادة المحاولة»).
  void retry(ExamDocument document, DocumentIR sourceIr) {
    if (identical(_failedDocument, document)) {
      _failedDocument = null;
    }
    request(document, sourceIr);
  }

  /// يُستدعى من `build` أيضاً؛ فالتنبيه يُؤجَّل إلى نهاية الإطار كي لا يُبنى
  /// `setState` داخل بناء الشجرة.
  void _notify() {
    if (_disposed) return;
    final callback = onChanged;
    if (callback == null) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_disposed) return;
      callback();
    });
    // `addPostFrameCallback` وحده لا يطلب إطاراً: بلا هذا السطر يبقى التنبيه
    // معلّقاً إن لم يكن ثمة سبب آخر لإعادة البناء (مثلاً بعد حسم الخطة في
    // اختبار لا يحفّز أي حركة).
    SchedulerBinding.instance.scheduleFrame();
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    onChanged = null;
  }
}
