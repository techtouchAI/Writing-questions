import 'package:flutter/material.dart';

import '../../layout/paper_metrics.dart';
import '../../models/exam_font.dart';
import '../../models/subject_layout.dart';

/// أنماط نصوص ورقة المعاينة A4 — نفس مقاسات `ExamTextStyles` في محرك الـ PDF
/// (بالنقاط) محوّلة إلى بكسل اللوحة، وبنفس خط Noto Naskh Arabic المضمّن،
/// حتى يتطابق التفاف الأسطر وارتفاع الكتل بين الشاشة والطباعة قدر الإمكان.
abstract final class PaperStyles {
  static const String fontFamily = ExamFont.arabicFamily;

  /// الخط القرآني لآيات القرآن (Amiri) — نفس عائلة خط الـ PDF.
  static const String quranicFamily = ExamFont.quranicFamily;

  static const Color primary = Color(0xFF1E3A8A);
  static const Color muted = Color(0xFF4B5563);
  static const Color accent = Color(0xFF2563EB);
  static const Color danger = Color(0xFFDC2626);

  /// لون الإجابات النموذجية في «نموذج الإجابة» — مطابق لـ
  /// `ExamTextStyles.successColor` في محرك الطباعة.
  static const Color answer = Color(0xFF065F46);

  static TextStyle _style(
    double points, {
    bool bold = false,
    Color color = Colors.black,
    double height = 1.45,
  }) {
    return TextStyle(
      fontFamily: fontFamily,
      fontSize: PaperMetrics.px(points),
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      color: color,
      height: height,
    );
  }

  static TextStyle get headerLine => _style(10, height: 1.6);
  static TextStyle get headerCenter => _style(10, bold: true, height: 1.6);
  static TextStyle get category => _style(12.5, bold: true, color: primary);
  static TextStyle get question => _style(11, bold: true, height: 1.7);
  static TextStyle get small => _style(9, color: muted);
  static TextStyle get note => _style(9.5, color: muted);
  static TextStyle get footer => _style(8.5, color: muted);
  static TextStyle get option => _style(10.5, height: 1.4);

  static TextStyle body(SubjectLayoutTemplate layout) =>
      _style(10.5, height: layout.lineHeightFactor);

  /// آية قرآنية قائمة بذاتها: خط قرآني وحجم أوضح وتوسيط (كما في المصحف).
  /// مقابله في الطباعة: نفس القرار داخل `PaginatedPdfExamEngine._renderText`.
  static TextStyle verse(SubjectLayoutTemplate layout) =>
      _style(12, height: layout.lineHeightFactor + 0.2)
          .copyWith(fontFamily: quranicFamily);

  /// مقطع قرآني سطري داخل نص عادي: يبقى بمقاس النص ويتغيّر خطه فقط.
  static TextStyle quranic(TextStyle base) => base.copyWith(fontFamily: quranicFamily);

  /// نص الإجابة النموذجية (فراغ/مقالي) على الورقة في وضع «نموذج الإجابة».
  static TextStyle answerBody(SubjectLayoutTemplate layout) => body(layout).copyWith(
        color: answer,
        fontWeight: FontWeight.bold,
      );

  static TextStyle hint(TextStyle base) => base.copyWith(color: Colors.grey);
}
