import 'package:pdf/widgets.dart' as pw;

import '../exam_strategy.dart';

/// استراتيجية مادة اللغة الإنجليزية: قائمة مسطّحة باتجاه LTR.
class EnglishExamStrategy extends ExamStrategy {
  const EnglishExamStrategy();

  @override
  pw.TextDirection get textDirection => pw.TextDirection.ltr;

  @override
  bool get sectionsByCategory => false;

  @override
  String questionNumberLabel(int number) => 'Q$number';

  @override
  String get marksUnit => 'marks';
}
