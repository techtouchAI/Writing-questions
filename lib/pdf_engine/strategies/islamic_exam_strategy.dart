import 'package:pdf/widgets.dart' as pw;

import '../exam_strategy.dart';

/// استراتيجية التربية الإسلامية: RTL مع أقسام رسمية (التلاوة/الحفظ/...).
class IslamicExamStrategy extends ExamStrategy {
  const IslamicExamStrategy();

  @override
  pw.TextDirection get textDirection => pw.TextDirection.rtl;

  @override
  bool get sectionsByCategory => true;

  @override
  String questionNumberLabel(int number) => 'س$number';

  @override
  String get marksUnit => 'درجة';
}
