import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/label_alphabet.dart';
import '../models/main_question.dart';
import '../models/question_branch.dart';
import '../models/question_type.dart';

/// سؤال رئيسي مع رقمه المتسلسل داخل ورقة الامتحان (س1، س2... أو Q1...).
class IndexedQuestion {
  const IndexedQuestion({required this.number, required this.question});

  final int number;
  final MainQuestion question;
}

/// مجموعة أسئلة متتالية تشترك في نفس القسم (القواعد/الأدب/...).
class QuestionGroup {
  const QuestionGroup({required this.category, required this.items});

  /// قسم المجموعة؛ [null] يعني أسئلة بدون عنوان قسم.
  final String? category;
  final List<IndexedQuestion> items;
}

/// يجمع الأسئلة المتتالية حسب قسمها **مع الحفاظ الكامل على ترتيب المعلم**
/// (تجميع منطاق لا يُعيد ترتيب أي سؤال).
List<QuestionGroup> groupQuestionsByCategory(List<IndexedQuestion> items) {
  if (items.isEmpty) {
    return const <QuestionGroup>[];
  }

  final groups = <QuestionGroup>[];
  var openCategory = _normalizedCategory(items.first.question);
  var openStart = 0;

  for (var index = 1; index < items.length; index++) {
    final category = _normalizedCategory(items[index].question);
    if (category != openCategory) {
      groups.add(
        QuestionGroup(category: openCategory, items: items.sublist(openStart, index)),
      );
      openCategory = category;
      openStart = index;
    }
  }
  groups.add(
    QuestionGroup(category: openCategory, items: items.sublist(openStart)),
  );
  return groups;
}

String? _normalizedCategory(MainQuestion question) {
  final category = question.category.trim();
  return category.isEmpty ? null : category;
}

/// مقاسات الخطوط والمسافات الموحدة لورقة الامتحان.
///
/// القيم بنقاط A4 ثابتة؛ لا تعتمد على جهاز المستخدم النهائي إطلاقاً.
class ExamTextStyles {
  const ExamTextStyles({
    required this.headerTitle,
    required this.headerBody,
    required this.badge,
    required this.category,
    required this.question,
    required this.option,
    required this.body,
    required this.small,
    required this.note,
    required this.footer,
  });

  final pw.TextStyle headerTitle;
  final pw.TextStyle headerBody;
  final pw.TextStyle badge;
  final pw.TextStyle category;
  final pw.TextStyle question;
  final pw.TextStyle option;
  final pw.TextStyle body;
  final pw.TextStyle small;
  final pw.TextStyle note;
  final pw.TextStyle footer;

  static const PdfColor primaryColor = PdfColor.fromInt(0xFF1E3A8A);
  static const PdfColor successColor = PdfColor.fromInt(0xFF065F46);
  static const PdfColor dangerColor = PdfColor.fromInt(0xFFDC2626);
  static const PdfColor mutedColor = PdfColor.fromInt(0xFF4B5563);

  static final ExamTextStyles standard = ExamTextStyles(
    headerTitle: _textStyle(
      fontSize: 15,
      bold: true,
      color: primaryColor,
      lineSpacing: 1.5,
    ),
    headerBody: _textStyle(fontSize: 10, lineSpacing: 1.5),
    badge: _textStyle(fontSize: 9.5, bold: true, lineSpacing: 1.5),
    category: _textStyle(
      fontSize: 12.5,
      bold: true,
      color: primaryColor,
      lineSpacing: 1.5,
    ),
    question: _textStyle(fontSize: 11, bold: true, lineSpacing: 2),
    option: _textStyle(fontSize: 10.5, lineSpacing: 1.4),
    body: _textStyle(fontSize: 10.5, lineSpacing: 1.5),
    small: _textStyle(fontSize: 9, color: mutedColor, lineSpacing: 1.4),
    note: _textStyle(fontSize: 9.5, color: mutedColor, lineSpacing: 1.5),
    footer: _textStyle(fontSize: 8.5, color: mutedColor),
  );

  /// بناء أسلوب نص في وقت التشغيل.
  ///
  /// يمرّ عبر دالة بدل const مباشرة لأن مكتبة pdf 3.11.x لا تحتمل
  /// التقييم الثابت لـ TextStyle داخل const contexts.
  static pw.TextStyle _textStyle({
    required double fontSize,
    bool bold = false,
    PdfColor? color,
    double? lineSpacing,
  }) {
    return pw.TextStyle(
      fontSize: fontSize,
      fontWeight: bold ? pw.FontWeight.bold : null,
      color: color,
      lineSpacing: lineSpacing,
    );
  }
}

/// استراتيجية بناء قائمة الأسئلة داخل ورقة الـ PDF.
///
/// كل مادة لها استراتيجيتها (نقاط/أقسام/اتجاه) بدل شجرة if-else في المحرك؛
/// البنية المشتركة (خيارات، صح/خطأ، فروع...) مطبقة مرة واحدة هنا.
abstract class ExamStrategy {
  const ExamStrategy();

  /// اتجاه رسم كتلة الأسئلة.
  pw.TextDirection get textDirection;

  /// هل تظهر عناوين أقسام (القواعد/الأدب/...) قبل كل مجموعة أسئلة؟
  bool get sectionsByCategory;

  /// بادئة ترقيم الأسئلة داخل النص.
  String questionNumberLabel(int number);

  /// وحدة الدرجة لعرض "[2 درجة]" أو "[2 marks]".
  String get marksUnit;

  /// بناء القائمة كاملة من الأسئلة المرقّمة [items].
  ///
  /// ترتيب [items] هو ترتيب المعلم اليدوي 100% (بدون أي خلط آلي).
  pw.Widget buildQuestionsList(
    List<IndexedQuestion> items, {
    required ExamTextStyles styles,
    required bool isTeacherVersion,
  }) {
    final groups = sectionsByCategory
        ? groupQuestionsByCategory(items)
        : <QuestionGroup>[QuestionGroup(category: null, items: items)];

    final children = <pw.Widget>[];
    for (var index = 0; index < groups.length; index++) {
      if (index > 0) {
        children.add(pw.SizedBox(height: 8));
      }
      children.addAll(_buildGroup(groups[index], styles, isTeacherVersion));
    }

    return pw.Directionality(
      textDirection: textDirection,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisSize: pw.MainAxisSize.min,
        children: children,
      ),
    );
  }

  List<pw.Widget> _buildGroup(
    QuestionGroup group,
    ExamTextStyles styles,
    bool isTeacherVersion,
  ) {
    final children = <pw.Widget>[];
    final category = group.category;
    if (category != null) {
      children.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 4),
          child: pw.Text(category, style: styles.category),
        ),
      );
    }

    for (var index = 0; index < group.items.length; index++) {
      if (index > 0) {
        children.add(pw.SizedBox(height: 5));
      }
      children.add(_buildQuestion(group.items[index], styles, isTeacherVersion));
    }
    return children;
  }

  pw.Widget _buildQuestion(
    IndexedQuestion item,
    ExamTextStyles styles,
    bool isTeacherVersion,
  ) {
    final question = item.question;
    // الدرجة المعروضة = مجموع درجات الفروع آلياً (roll-up).
    final children = <pw.Widget>[
      pw.Text(
        '${questionNumberLabel(item.number)}: ${question.title} '
        '[${_formatMarks(question.marks)} $marksUnit]',
        style: styles.question,
      ),
    ];

    final branches = question.branches
        .where((branch) => branch.text.trim().isNotEmpty)
        .toList(growable: false);
    if (branches.isNotEmpty) {
      children.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 2),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              for (var index = 0; index < branches.length; index++)
                pw.Text(
                  // التسمية ديناميكية من الفهرس دائماً (أ، ب، ج...) —
                  // لا تسمية مخزنة تُحدث فجوات عند حذف فرع وسط القائمة.
                  _branchLabel(index, branches[index]),
                  style: styles.body,
                ),
            ],
          ),
        ),
      );
    }

    children.add(
      pw.Padding(
        padding: const pw.EdgeInsetsDirectional.only(start: 14, top: 2),
        child: _buildTypeBody(question, styles, isTeacherVersion),
      ),
    );

    if (isTeacherVersion && question.explanation.trim().isNotEmpty) {
      children.add(
        pw.Padding(
          padding: const pw.EdgeInsetsDirectional.only(start: 14, top: 2),
          child: pw.Text(
            'سبب الإجابة / الملاحظات: ${question.explanation}',
            style: styles.small.copyWith(color: ExamTextStyles.primaryColor),
          ),
        ),
      );
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisSize: pw.MainAxisSize.min,
      children: children,
    );
  }

  /// تسمية الفرع تُولَّد **من فهرسه فقط** (أ، ب، ج...) دون قراءة أي حقل
  /// تسمية مخزن؛ درجة الفرع تُلحق بالتسمية نفسها.
  String _branchLabel(int index, QuestionBranch branch) {
    final label = LabelAlphabet.at(index);
    final marksSuffix =
        branch.marks > 0 ? ' [${_formatMarks(branch.marks)} $marksUnit]' : '';
    return '$label) ${branch.text}$marksSuffix';
  }

  pw.Widget _buildTypeBody(
    MainQuestion question,
    ExamTextStyles styles,
    bool isTeacherVersion,
  ) {
    switch (question.type) {
      case QuestionType.multipleChoice:
        return _buildOptions(question, styles, isTeacherVersion);
      case QuestionType.trueFalse:
        return _buildTrueFalse(question, styles, isTeacherVersion);
      case QuestionType.fillInTheBlank:
        return _buildFillInTheBlank(question, styles, isTeacherVersion);
      case QuestionType.essay:
        return _buildEssay(question, styles, isTeacherVersion);
    }
  }

  pw.Widget _buildOptions(
    MainQuestion question,
    ExamTextStyles styles,
    bool isTeacherVersion,
  ) {
    final options = question.options
        .where((option) => option.text.trim().isNotEmpty)
        .toList(growable: false);

    return pw.Wrap(
      spacing: 14,
      runSpacing: 2,
      children: [
        for (var index = 0; index < options.length; index++)
          pw.Text(
            '( ${LabelAlphabet.at(index)} )  ${options[index].text}'
            '${isTeacherVersion && options[index].isCorrect ? ' •' : ''}',
            style: isTeacherVersion && options[index].isCorrect
                ? styles.option.copyWith(
                    color: ExamTextStyles.successColor,
                    fontWeight: pw.FontWeight.bold,
                  )
                : styles.option,
          ),
      ],
    );
  }

  pw.Widget _buildTrueFalse(
    MainQuestion question,
    ExamTextStyles styles,
    bool isTeacherVersion,
  ) {
    if (!isTeacherVersion) {
      return pw.Text('الإجابة: (     ) صح      (     ) خطأ', style: styles.body);
    }

    final correctAnswers = question.options
        .where((option) => option.isCorrect && option.text.trim().isNotEmpty)
        .map((option) => option.text.trim())
        .toList(growable: false);
    return pw.Text(
      'الإجابة الصحيحة: ${correctAnswers.isEmpty ? 'غير محدد' : correctAnswers.join('، ')} •',
      style: styles.body.copyWith(
        color: ExamTextStyles.successColor,
        fontWeight: pw.FontWeight.bold,
      ),
    );
  }

  pw.Widget _buildFillInTheBlank(
    MainQuestion question,
    ExamTextStyles styles,
    bool isTeacherVersion,
  ) {
    if (!isTeacherVersion) {
      return pw.Text(
        'الإجابة: ....................................................................................',
        style: styles.body,
      );
    }

    final modelAnswer = question.modelAnswer.trim();
    return pw.Text(
      'الإجابة النموذجية: ${modelAnswer.isEmpty ? 'غير محدد' : modelAnswer} •',
      style: styles.body.copyWith(
        color: ExamTextStyles.successColor,
        fontWeight: pw.FontWeight.bold,
      ),
    );
  }

  pw.Widget _buildEssay(
    MainQuestion question,
    ExamTextStyles styles,
    bool isTeacherVersion,
  ) {
    if (isTeacherVersion) {
      final modelAnswer = question.modelAnswer.trim();
      return pw.Text(
        'الإجابة النموذجية وعناصر التقييم: ${modelAnswer.isEmpty ? 'غير محدد' : modelAnswer} •',
        style: styles.body.copyWith(
          color: ExamTextStyles.successColor,
          fontWeight: pw.FontWeight.bold,
        ),
      );
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisSize: pw.MainAxisSize.min,
      children: List<pw.Widget>.generate(
        4,
        (index) => pw.Text(
          '................................................................................................',
          style: styles.small.copyWith(color: ExamTextStyles.mutedColor),
        ),
      ),
    );
  }

  static String _formatMarks(double marks) {
    return marks == marks.truncateToDouble()
        ? marks.toInt().toString()
        : marks.toString();
  }
}
