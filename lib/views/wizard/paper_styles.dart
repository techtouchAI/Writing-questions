import 'package:flutter/material.dart';

import '../../layout/paper_metrics.dart';
import '../../layout/visual/visual_flutter_style.dart';
import '../../layout/visual/visual_style.dart';
import '../../layout/visual/visual_typography.dart';
import '../../models/exam_font.dart';
import '../../models/paper_font.dart';
import '../../models/paper_settings.dart';
import '../../models/paper_text_style.dart';
import '../../models/subject_layout.dart';

/// أنماط نصوص لوحة المعاينة A4 — **مُلحِق عرض** لعقد الطباعة الوحيد
/// [ExamTypography]، لا جدول أرقام مستقل.
///
/// كانت هذه الطبقة تحمل جدول أحجام موازياً لجدول محرك الـ PDF (`ExamTextStyles`)
/// فتنحرف المقاسات بين الشاشة والملف عند أي تعديل. الآن كل نمط هنا يُبنى من
/// دور في العقد ([VisualRole])، وقيمته النهائية تُحسب في
/// [ExamTypography.resolve] مرة واحدة ثم تُترجم إلى بكسل اللوحة — فما تراه
/// الشاشة هو نفسه ما يحسبه PDF وWord بالضبط.
///
/// [resolve]/[scale] تحافظان على التوقيع القديم (ولوحة الورقة وقوالب المواد
/// تُمرَّر إليهما كما كانت)، لكن القرار صار من العقد.
abstract final class PaperStyles {
  static const String fontFamily = ExamFont.arabicFamily;

  /// الخط القرآني لآيات القرآن (Amiri) — نفس عائلة خط الـ PDF.
  static const String quranicFamily = ExamFont.quranicFamily;

  /// لون حبر الورقة لكل ما يُطبع (إطارات، فواصل، حدود): أسود دائماً.
  static const Color ink = Colors.black;

  /// لون أدوات التحرير على الشاشة فقط (تحديد/إبراز) — لا يُطبع أبداً.
  static const Color primary = Color(0xFF1E3A8A);
  static const Color muted = Color(0xFF4B5563);
  static const Color accent = Color(0xFF2563EB);
  static const Color danger = Color(0xFFDC2626);

  /// إعدادات محايدة (معاملا قياس = 1.0) لبناء القيم المرجعية غير المقاسة.
  static const PaperSettings _referenceSettings = PaperSettings();

  /// نمط دور [role] المرجعي (بلا قياس عام) للقالب [layout].
  ///
  /// يُستعمل لبناء الأنماط المعروضة مباشرة (`PaperStyles.question`...)
  /// ولقراءة القيمة المرجعية في [resolve]/[scale].
  static PaperRoleTextStyle role(
    VisualRole role, {
    SubjectLayoutTemplate layout = SubjectLayoutTemplate.generic,
    double? sizePt,
    double? lineHeight,
    bool? bold,
    PaperFont? font,
    int? color,
  }) {
    return PaperRoleTextStyle(
      role,
      ExamTypography.resolve(
        role,
        settings: _referenceSettings,
        layout: layout,
        sizePt: sizePt,
        lineHeight: lineHeight,
        bold: bold,
        font: font,
        color: color,
      ),
    );
  }

  // ----------------------------- أدوار العقد -----------------------------

  static PaperRoleTextStyle get headerLine => role(VisualRole.headerBody);

  /// سطر منتصف الترويسة (اسم الامتحان): حجم نص الترويسة نفسه، غامقاً —
  /// وهو قرار `PdfPaperBuilder.header` (‏`styles.headerBody` + غامق) وملف
  /// Word (‏`w:b` على سطر الوسط) نفسه.
  static PaperRoleTextStyle get headerCenter =>
      role(VisualRole.headerBody, bold: true);

  /// البسملة: أكبر من نص الترويسة (الخط الخطّي يُفرض عبر العقد).
  static PaperRoleTextStyle get bismillah => role(VisualRole.bismillah);

  static PaperRoleTextStyle get category => role(VisualRole.category);

  static PaperRoleTextStyle get question => role(VisualRole.questionTitle);

  static PaperRoleTextStyle get prompt => role(VisualRole.questionBody);

  static PaperRoleTextStyle get small => role(VisualRole.small);

  static PaperRoleTextStyle get note => role(VisualRole.note);

  static PaperRoleTextStyle get footer => role(VisualRole.footer);

  static PaperRoleTextStyle get option => role(VisualRole.option);

  static PaperRoleTextStyle get item => role(VisualRole.point);

  /// نمط متن الفرع/النقاط بحسب قالب المادة (ارتفاع السطر من القالب).
  static PaperRoleTextStyle body(SubjectLayoutTemplate layout) =>
      role(VisualRole.branchBody, layout: layout);

  /// آية قرآنية قائمة بذاتها: خط قرآني وحجم أوضح وتوسيط (كما في المصحف).
  static PaperRoleTextStyle verse(SubjectLayoutTemplate layout) =>
      role(VisualRole.verse, layout: layout);

  /// مقطع قرآني سطري داخل نص عادي: يبقى بمقاس النص ويتغيّر خطه فقط.
  static TextStyle quranic(TextStyle base) =>
      base.copyWith(fontFamily: quranicFamily);

  static TextStyle hint(TextStyle base) => base.copyWith(color: Colors.grey);

  // ----------------------------- القياس والتنسيق -----------------------------

  /// يطبّق تنسيق عنصر [override] فوق النمط الأساسي [base].
  ///
  /// [defaultFont] خط الورقة الافتراضي من إعداداتها. القيم الفارغة في
  /// [override] ترث من الأساس.
  ///
  /// [fontScale]/[heightScale] معاملا القياس العامّان من إعدادات الورقة:
  /// يُطبَّقان **مرة واحدة** على القيم المرجعية فقط، ويبقى التنسيق المخصص
  /// لعنصر بعينه (حجم/تباعد مطلق) متقدماً عليهما — وهو قرار العقد نفسه
  /// ([ExamTypography.resolve]).
  static TextStyle resolve(
    TextStyle base,
    PaperTextStyle? override, {
    PaperFont defaultFont = PaperFont.naskh,
    double fontScale = 1.0,
    double heightScale = 1.0,
  }) {
    // نمط من العقد: تُشتق القيم النهائية من دوره مباشرة.
    if (base is PaperRoleTextStyle) {
      final s = base.reference;
      // أثاث الصفحة معفي من القياس العام كما في العقد نفسه
      // ([ExamTypography.isPageChrome])؛ التنسيق المخصص يتقدم دائماً.
      final effectiveFontScale =
          ExamTypography.isPageChrome(s.role) ? 1.0 : fontScale;
      final effectiveHeightScale =
          ExamTypography.isPageChrome(s.role) ? 1.0 : heightScale;
      return VisualFlutterStyle.from(
        s.copyWith(
          font: override?.font ?? defaultFont,
          fontSizePt: override?.fontSize ?? s.fontSizePt * effectiveFontScale,
          lineHeight:
              override?.lineHeight ?? s.lineHeight * effectiveHeightScale,
          bold: override?.bold ?? s.bold,
          italic: override?.italic ?? s.italic,
          underline: override?.underline ?? s.underline,
          color: () => override?.color ?? s.color,
          align: () => override?.align,
        ),
      );
    }
    // نمط خارج العقد (نص تحريري عابر): يُقاس كما كان، مع الحفاظ على الدلالة.
    return base.copyWith(
      fontFamily: (override?.font ?? defaultFont).family,
      fontSize: override?.fontSize != null
          ? PaperMetrics.px(override!.fontSize!)
          : (base.fontSize ?? 14) * fontScale,
      fontWeight: (override?.bold ?? base.fontWeight == FontWeight.bold)
          ? FontWeight.bold
          : FontWeight.normal,
      fontStyle:
          (override?.italic ?? false) ? FontStyle.italic : FontStyle.normal,
      decoration: (override?.underline ?? false)
          ? TextDecoration.underline
          : TextDecoration.none,
      height: override?.lineHeight ?? (base.height ?? 1.45) * heightScale,
      color: override?.color != null ? Color(override!.color!) : base.color,
    );
  }

  /// يقيس نمطاً من العقد بمعاملَي الورقة العامّين (بلا تنسيق عنصر).
  ///
  /// يُستخدم للأنماط التي تُعرض كما هي بلا [resolve] (الخيارات، النقاط،
  /// الملاحظات...) حتى تكبر الورقة كلها وتصغر معاً من مكان واحد.
  static TextStyle scale(
    TextStyle base, {
    double fontScale = 1.0,
    double heightScale = 1.0,
  }) {
    if (fontScale == 1.0 && heightScale == 1.0) {
      return base;
    }
    if (base is PaperRoleTextStyle) {
      final s = base.reference;
      final effectiveFontScale =
          ExamTypography.isPageChrome(s.role) ? 1.0 : fontScale;
      final effectiveHeightScale =
          ExamTypography.isPageChrome(s.role) ? 1.0 : heightScale;
      return VisualFlutterStyle.from(
        s.copyWith(
          fontSizePt: s.fontSizePt * effectiveFontScale,
          lineHeight: s.lineHeight * effectiveHeightScale,
        ),
      );
    }
    return base.copyWith(
      fontSize: (base.fontSize ?? 14) * fontScale,
      height: (base.height ?? 1.45) * heightScale,
    );
  }

  /// يحوّل محاذاة الورقة إلى محاذاة Flutter (null = الافتراضي الممرّر).
  static TextAlign toTextAlign(
    PaperAlign? align, [
    TextAlign fallback = TextAlign.start,
  ]) =>
      VisualFlutterStyle.toTextAlign(align, fallback);
}
