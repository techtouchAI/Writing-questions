import '../../models/paper_font.dart';
import '../../models/paper_settings.dart';
import '../../models/paper_text_style.dart';
import '../../models/subject_layout.dart';
import 'visual_style.dart';

/// وصف مرجعي لدور نصّي: القيم **قبل** معاملَي الورقة العامّين ([PaperSettings.fontScale]
/// و[PaperSettings.heightScale]) وقبل أي تنسيق مخصص لعنصر.
class VisualRoleSpec {
  const VisualRoleSpec({
    required this.sizePt,
    required this.lineHeight,
    this.bold = false,
    this.font,
    this.color,
  });

  /// حجم الخط المرجعي بالنقاط.
  final double sizePt;

  /// مضاعف ارتفاع السطر المرجعي.
  final double lineHeight;

  final bool bold;

  /// خط مفروض للدور (`null` = الخط الافتراضي للورقة).
  final PaperFont? font;

  /// لون افتراضي ARGB (`null` = حبر الورقة الأسود).
  final int? color;
}

/// **عقد الطباعة الوحيد** (Typography Contract).
///
/// جدول الأحجام والارتفاعات المرجعية لكل دور، ودالة [resolve] التي تُنتج
/// [VisualTextStyle] نهائياً. القاعدة الصارمة:
///
/// 1. معامل القياس العام (`fontScale`/`heightScale`) يُطبَّق **مرة واحدة**
///    هنا على القيم المرجعية فقط — لا تضاعفه أي طبقة أعلى.
/// 2. التنسيق المخصص لعنصر (`PaperTextStyle.fontSize`/`lineHeight`) مطلق
///    ولا يتأثر بالمعامل العام (كما في المعاينة الحالية).
/// 3. لا يكتب أي راسم (Preview/PDF/DOCX) حجم خط أو تباعد أسطر بنفسه؛ يطلب
///    الدور من هنا ثم يحوّل الوحدة فقط.
abstract final class ExamTypography {
  /// لون الملاحظات (يحلّ محل الرمادي القديم المكتوب في ثلاثة أماكن).
  static const int mutedColor = 0xFF4B5563;

  /// الجدول المرجعي: نفس أرقام `ExamTextStyles.standard` و`PaperStyles`
  /// قبل توحيدهما — لم يتغيّر مقاس واحد على الشاشة.
  static const Map<VisualRole, VisualRoleSpec> reference =
      <VisualRole, VisualRoleSpec>{
    VisualRole.headerTitle: VisualRoleSpec(sizePt: 15, lineHeight: 1.6, bold: true),
    VisualRole.headerBody: VisualRoleSpec(sizePt: 10, lineHeight: 1.6),
    VisualRole.bismillah:
        VisualRoleSpec(sizePt: 17, lineHeight: 1.5, font: PaperFont.amiri),
    VisualRole.badge: VisualRoleSpec(sizePt: 9.5, lineHeight: 1.5, bold: true),
    VisualRole.category: VisualRoleSpec(sizePt: 12.5, lineHeight: 1.45, bold: true),
    VisualRole.questionTitle:
        VisualRoleSpec(sizePt: 11, lineHeight: 1.7, bold: true),
    VisualRole.questionBody: VisualRoleSpec(sizePt: 11, lineHeight: 1.7),
    VisualRole.branchTitle: VisualRoleSpec(sizePt: 10.5, lineHeight: 1.45),
    VisualRole.branchBody: VisualRoleSpec(sizePt: 10.5, lineHeight: 1.45),
    VisualRole.point: VisualRoleSpec(sizePt: 10.5, lineHeight: 1.5),
    VisualRole.option: VisualRoleSpec(sizePt: 10.5, lineHeight: 1.4),
    VisualRole.verse: VisualRoleSpec(sizePt: 12, lineHeight: 1.65),
    VisualRole.small:
        VisualRoleSpec(sizePt: 9, lineHeight: 1.45, color: mutedColor),
    VisualRole.note:
        VisualRoleSpec(sizePt: 9.5, lineHeight: 1.45, color: mutedColor),
    /// نص التذييل الصغير (`PaperStyles.footer`) — أما سطور التوقيع في
    /// التذييل فتستعمل [VisualRole.headerBody] بارتفاع 1.6 نفسهما في
    /// المعاينة وPDF وWord.
    VisualRole.footer:
        VisualRoleSpec(sizePt: 8.5, lineHeight: 1.45, color: mutedColor),
  };

  /// ارتفاع سطر دور [role] بحسب قالب المادة.
  ///
  /// النص المتن (السؤال/الفرع) يتبع `lineHeightFactor` للقالب (1.45 عام،
  /// 1.8 علمي)، والآية القائمة بذاتها تزيد عليه قليلاً، وبقية الأدوار
  /// ثابتة في الجدول. التذييل والترويسة 1.6 دائماً.
  static double referenceLineHeight(VisualRole role, SubjectLayoutTemplate layout) {
    switch (role) {
      case VisualRole.branchTitle:
      case VisualRole.branchBody:
        return layout.lineHeightFactor;
      case VisualRole.verse:
        return layout.lineHeightFactor + 0.2;
      default:
        return reference[role]!.lineHeight;
    }
  }

  /// يحلّ نمط [role] نهائياً لورقة [settings] وقالب [layout].
  ///
  /// [override] تنسيق العنصر من النموذج، والبقية استبدالات موضعية تستعملها
  /// عناصر خاصة (البسملة بخط ومدخل مستقلّين، ذيل التذييل بمضاعف 1.6...).
  static VisualTextStyle resolve(
    VisualRole role, {
    required PaperSettings settings,
    required SubjectLayoutTemplate layout,
    PaperTextStyle? override,
    PaperFont? font,
    double? sizePt,
    double? lineHeight,
    bool? bold,
    int? color,
    PaperAlign? align,
  }) {
    final spec = reference[role]!;
    // الترتيب: تنسيق العنصر ([override]) يتقدم دائماً، ثم الاستبدال الموضعي
    // الذي يمرّره الراسم (كالبسملة أو عمود الترويسة الغامق)، ثم القيمة
    // المرجعية للدور مضروبة بمعامل الورقة مرة واحدة.
    return VisualTextStyle(
      role: role,
      font: override?.font ?? font ?? spec.font ?? settings.defaultFont,
      fontSizePt:
          override?.fontSize ?? sizePt ?? spec.sizePt * settings.fontScale,
      lineHeight: override?.lineHeight ??
          lineHeight ??
          referenceLineHeight(role, layout) * settings.heightScale,
      bold: override?.bold ?? bold ?? spec.bold,
      italic: override?.italic ?? false,
      underline: override?.underline ?? false,
      color: override?.color ?? color ?? spec.color,
      align: override?.align ?? align,
    );
  }
}
