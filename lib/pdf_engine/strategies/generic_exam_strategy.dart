import 'package:pdf/widgets.dart' as pw;

import '../exam_strategy.dart';

/// الاستراتيجية الافتراضية لبقية المواد: RTL، وتظهر عناوين الأقسام إن وُجدت.
class GenericExamStrategy extends ExamStrategy {
  const GenericExamStrategy();

  @override
  pw.TextDirection get textDirection => pw.TextDirection.rtl;

  @override
  bool get sectionsByCategory => true;

  @override
  String questionNumberLabel(int number) => 'س$number';

  @override
  String get marksUnit => 'درجة';
}
