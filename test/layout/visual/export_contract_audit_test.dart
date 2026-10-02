// حارس عقد التصدير: لا خاصية «تعمل في المعاينة وحدها».
//
// الاختبار يقرأ [ExportContractAudit] (تصنيف كل إعداد ومساره ودليله) ويفشل
// إذا ظهر بند لا يصل إلا إلى المعاينة، أو بند بلا دليل، أو بند تجاوز الأسطح
// التي كُتبت بلا إعلان قيد. القيود الجزئية (إن وُجدت) تُعدّ صراحةً ولا تُخفى.
import 'package:flutter_test/flutter_test.dart';

import 'package:writing_questions_app/layout/visual/export_contract_audit.dart';

void main() {
  test('لا توجد خاصية تعمل في المعاينة وحدها', () {
    expect(
      ExportContractAudit.previewOnly,
      isEmpty,
      reason: 'كل إعداد في النموذج يجب أن يصل إلى PDF وWord أيضاً '
          '(أو يُعلَن قيده صراحةً بدل ادّعاء التغطية).',
    );
  });

  test('كل بند موسوم بدليل ودور/دالة في الشيفرة', () {
    for (final entry in ExportContractAudit.entries) {
      expect(entry.property.trim(), isNotEmpty);
      expect(entry.effect.trim(), isNotEmpty);
      expect(
        entry.evidence.trim(),
        isNotEmpty,
        reason: 'البند «${entry.property}» بلا دليل — التصنيف بلا دليل تخمين.',
      );
      expect(
        entry.surfaces,
        isNotEmpty,
        reason: 'البند «${entry.property}» لا يصل إلى أي سطح إخراج.',
      );
    }
  });

  test('البنود الجزئية معلنة صراحةً ولا تتنكّر كتغطية كاملة', () {
    // القيد الوحيد المعروف والمقصود: محاذاة خيار داخل صف الخيارات في Word
    // القابل للتحرير (الصف فقرة واحدة). لا يُدَّعى أنه يصل إلى Word.
    for (final entry in ExportContractAudit.partial) {
      expect(
        entry.surfaces.contains(ExportSurface.docxEditable),
        isFalse,
        reason: 'البند «${entry.property}» جزئي فيجب ألا يدّعي تغطية Word.',
      );
      expect(entry.reachesPreview, isTrue,
          reason: 'البند الجزئي يجب أن يبقى ظاهراً في المعاينة كمرجع.');
    }
    for (final entry in ExportContractAudit.entries) {
      if (entry.surfaces.contains(ExportSurface.docxEditable) &&
          entry.surfaces.length == ExportSurface.values.length) {
        expect(entry.isPartial, isFalse);
      }
    }
  });

  test('التصدير الدقيق يغطي كل بند لأنه صورة الصفحة النهائية', () {
    for (final entry in ExportContractAudit.entries) {
      expect(
        entry.surfaces.contains(ExportSurface.exact),
        isTrue,
        reason: 'البند «${entry.property}» يجب أن يكون مشمولاً في Exact '
            '(الصورة تحمل كل ما في الصفحة)، أو يُعلَن قيده صراحةً.',
      );
    }
  });
}
