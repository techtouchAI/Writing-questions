import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/exam.dart';
import 'exam_fonts.dart';
import 'exam_strategy.dart';
import 'strategy_registry.dart';

/// محرك رسم ورقة الاختبار على «لوحة» A4 ثابتة (Canvas).
///
/// الضمانات المقصودة:
/// 1. **صفحة واحدة تماماً**: يُضاف [pw.Page] واحد فقط؛ منطقة الأسئلة داخل
///    [pw.FittedBox] بوضع [pw.BoxFit.scaleDown] فتُصغَّر الطباعة آلياً
///    بتناسق كامل حتى تتسع في المساحة المتبقية بدل أن تتجاوز الورقة.
/// 2. **مقاسات بنقاط لا بخطوط واجهة**: كل شيء محسوب من
///    [PdfPageFormat.a4] والهوامش، فلا يتغير الناتج باختلاف جهاز المستخدم.
/// 3. **لا شجرة شروط للمواد**: تُبنى قائمة الأسئلة عبر [ExamStrategy].
class PdfExamEngine {
  const PdfExamEngine();

  /// هوامش الورقة بالمليمتر (مواصفة الوحدة).
  static const double pageMarginMillimeters = 15;

  /// عرض منطقة الأسئلة داخل الهوامش (بنقطة PDF).
  static double get contentWidth => PdfPageFormat.a4.width - 2 * _margin;

  static double get _margin => pageMarginMillimeters * PdfPageFormat.mm;

  /// يولّد ملف PDF لورقة [exam] بصفحة A4 واحدة.
  ///
  /// [isTeacherVersion] يبدل بين ورقة الطالب ونموذج الإجابة.
  /// [strategy] يتجاوز اختيار الاستراتيجية من اسم المادة عند الحاجة.
  Future<Uint8List> generate({
    required Exam exam,
    required bool isTeacherVersion,
    ExamStrategy? strategy,
    ExamFonts? fonts,
    ExamTextStyles? styles,
  }) async {
    final loadedFonts = fonts ?? await ExamFonts.load();
    final effectiveStyles = styles ?? ExamTextStyles.standard;
    final effectiveStrategy = strategy ?? ExamStrategies.forSubject(exam.header.subject);

    final items = <IndexedQuestion>[
      for (var index = 0; index < exam.questions.length; index++)
        IndexedQuestion(number: index + 1, question: exam.questions[index]),
    ];

    final document = pw.Document(
      title: exam.name,
      author: exam.header.instructor,
      creator: 'صانع ومحرر الأسئلة',
      subject: exam.header.subject,
    );

    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(pageMarginMillimeters),
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(base: loadedFonts.regular, bold: loadedFonts.bold),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: <pw.Widget>[
              _buildHeader(exam, isTeacherVersion, effectiveStyles),
              pw.Divider(thickness: 2, color: ExamTextStyles.primaryColor),
              _buildNotes(exam, effectiveStyles),
              pw.Expanded(
                child: _buildAutoFitQuestions(
                  items,
                  effectiveStrategy,
                  effectiveStyles,
                  isTeacherVersion,
                ),
              ),
              _buildFooter(exam, effectiveStyles),
            ],
          );
        },
      ),
    );

    return document.save();
  }

  pw.Widget _buildAutoFitQuestions(
    List<IndexedQuestion> items,
    ExamStrategy strategy,
    ExamTextStyles styles,
    bool isTeacherVersion,
  ) {
    if (items.isEmpty) {
      return pw.Center(
        child: pw.Text('لا توجد أسئلة في هذا الاختبار.', style: styles.note),
      );
    }

    // اللبنة الأساسية لضمان صفحة واحدة: عرض ثابت ثم تصغير تلقائي
    // بتناسق كامل عند تجاوز المحتوى المساحة المتبقية.
    return pw.Directionality(
      textDirection: strategy.textDirection,
      child: pw.FittedBox(
        fit: pw.BoxFit.scaleDown,
        alignment: pw.AlignmentDirectional.topStart,
        child: pw.SizedBox(
          width: contentWidth,
          child: strategy.buildQuestionsList(
            items,
            styles: styles,
            isTeacherVersion: isTeacherVersion,
          ),
        ),
      ),
    );
  }

  pw.Widget _buildHeader(Exam exam, bool isTeacherVersion, ExamTextStyles styles) {
    final header = exam.header;
    final totalMarks = exam.totalMarks;

    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: ExamTextStyles.primaryColor, width: 1.2),
      ),
      padding: const pw.EdgeInsets.all(6),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisSize: pw.MainAxisSize.min,
              children: <pw.Widget>[
                pw.Text(
                  header.institutionName,
                  maxLines: 2,
                  style: styles.headerBody.copyWith(fontWeight: pw.FontWeight.bold),
                ),
                if (header.directorate.isNotEmpty)
                  pw.Text('المديرية: ${header.directorate}', style: styles.small),
                pw.Text('المادة: ${header.subject}', style: styles.headerBody),
                pw.Text('الصف: ${header.gradeStage}', style: styles.headerBody),
                if (header.section.isNotEmpty)
                  pw.Text('الشعبة: ${header.section}', style: styles.headerBody),
                if (header.instructor.isNotEmpty)
                  pw.Text('المعلم: ${header.instructor}', style: styles.small),
              ],
            ),
          ),
          pw.SizedBox(width: 6),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              mainAxisSize: pw.MainAxisSize.min,
              children: <pw.Widget>[
                pw.Text(
                  header.title,
                  textAlign: pw.TextAlign.center,
                  maxLines: 2,
                  style: styles.headerTitle,
                ),
                if (header.examType.isNotEmpty)
                  pw.Text(header.examType, textAlign: pw.TextAlign.center, style: styles.badge),
                if (isTeacherVersion)
                  pw.Text(
                    'نموذج الإجابة وتوزيع الدرجات للمعلم — العام الدراسي: ${header.academicYear}',
                    textAlign: pw.TextAlign.center,
                    maxLines: 2,
                    style: styles.badge.copyWith(color: ExamTextStyles.dangerColor),
                  )
                else
                  pw.Text(
                    'العام الدراسي: ${header.academicYear}',
                    textAlign: pw.TextAlign.center,
                    style: styles.badge.copyWith(color: ExamTextStyles.mutedColor),
                  ),
                if (header.examDate != null)
                  pw.Text(
                    'التاريخ: ${_formatDate(header.examDate!)}',
                    textAlign: pw.TextAlign.center,
                    style: styles.small,
                  ),
              ],
            ),
          ),
          pw.SizedBox(width: 6),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisSize: pw.MainAxisSize.min,
              children: <pw.Widget>[
                pw.Text('الزمن: ${header.computedDuration}', style: styles.headerBody),
                pw.Text(
                  'الدرجة الكلية: ${_formatMarks(totalMarks)} درجة',
                  style: styles.headerBody.copyWith(fontWeight: pw.FontWeight.bold),
                ),
                if (!isTeacherVersion)
                  pw.Text(
                    'اسم الطالب: ..............................',
                    maxLines: 1,
                    style: styles.small,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildNotes(Exam exam, ExamTextStyles styles) {
    final instructions = exam.header.generalInstructions.trim();

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      mainAxisSize: pw.MainAxisSize.min,
      children: <pw.Widget>[
        pw.SizedBox(height: 5),
        pw.Text(
          'عدد الأسئلة: ${exam.questions.length} سؤال  |  '
          'الدرجة الكلية: ${_formatMarks(exam.totalMarks)} درجة',
          textAlign: pw.TextAlign.center,
          style: styles.small,
        ),
        if (instructions.isNotEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 2),
            child: pw.Text(
              'تعليمات الاختبار: $instructions',
              textAlign: pw.TextAlign.center,
              maxLines: 2,
              style: styles.note,
            ),
          ),
        pw.SizedBox(height: 4),
      ],
    );
  }

  pw.Widget _buildFooter(Exam exam, ExamTextStyles styles) {
    final instructor = exam.header.instructor.trim();

    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: <pw.Widget>[
        if (instructor.isNotEmpty) pw.Text('المعلم: $instructor', style: styles.footer),
        pw.Text('صفحة 1 من 1', style: styles.footer),
        pw.Text(exam.header.institutionName, style: styles.footer, maxLines: 1),
      ],
    );
  }

  static String _formatMarks(double marks) {
    return marks == marks.truncateToDouble()
        ? marks.toInt().toString()
        : marks.toString();
  }

  static String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}/$month/$day';
  }
}
