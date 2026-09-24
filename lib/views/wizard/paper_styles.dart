import 'package:flutter/material.dart';

import '../../layout/paper_metrics.dart';
import '../../models/subject_layout.dart';

/// أنماط نصوص ورقة المعاينة A4 — نفس مقاسات `ExamTextStyles` في محرك الـ PDF
/// (بالنقاط) محوّلة إلى بكسل اللوحة، وبنفس خط Noto Naskh Arabic المضمّن،
/// حتى يتطابق التفاف الأسطر وارتفاع الكتل بين الشاشة والطباعة قدر الإمكان.
abstract final class PaperStyles {
  static const String fontFamily = 'NotoNaskhArabic';

  static const Color primary = Color(0xFF1E3A8A);
  static const Color muted = Color(0xFF4B5563);
  static const Color accent = Color(0xFF2563EB);
  static const Color danger = Color(0xFFDC2626);

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

  static TextStyle hint(TextStyle base) => base.copyWith(color: Colors.grey);
}
