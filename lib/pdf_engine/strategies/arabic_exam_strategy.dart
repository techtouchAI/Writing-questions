import 'package:pdf/widgets.dart' as pw;

import '../exam_strategy.dart';

/// استراتيجية مادة اللغة العربية: RTL مع أقسام (القواعد/الأدب/الإنشاء).
class ArabicExamStrategy extends ExamStrategy {
  const ArabicExamStrategy();

  @override
  pw.TextDirection get textDirection => pw.TextDirection.rtl;

  @override
  bool get sectionsByCategory => true;

  @override
  String questionNumberLabel(int number) => 'س$number';

  @override
  String get marksUnit => 'درجة';
}
