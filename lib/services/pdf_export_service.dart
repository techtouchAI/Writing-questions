import 'dart:io';
import 'dart:typed_data';

import '../models/exam.dart';
import '../models/exam_document.dart';
import '../pdf_engine/pdf_engine.dart';
import 'export_file_service.dart';

/// توليد وحفظ ومشاركة ورقة الاختبار بصيغة PDF.
///
/// تعتمد بالكامل على وحدة [PdfExamEngine]؛ لا تنسيق حيّ هنا إطلاقاً —
/// الناتج لوحة A4 ثابتة لا تتغير بين الأجهزة أو إصدارات الأوفيس.
abstract final class PdfExportService {
  /// يبني بايتات ملف PDF لورقة [exam] بصفحة واحدة.
  static Future<Uint8List> buildExamPdfBytes({
    required Exam exam,
    required bool isTeacherVersion,
  }) {
    return const PdfExamEngine().generate(
      exam: exam,
      isTeacherVersion: isTeacherVersion,
    );
  }

  /// يبني بايتات PDF متعدد الصفحات للنموذج الوزاري [document].
  ///
  /// [pageAssignments] هو توزيع الأسئلة على الصفحات كما حُسب على لوحة
  /// المعاينة، فيُطبع الملف بنفس التقسيم المعروض تماماً.
  static Future<Uint8List> buildDocumentPdfBytes({
    required ExamDocument document,
    bool isTeacherVersion = false,
    List<List<String>>? pageAssignments,
  }) {
    return PaginatedPdfExamEngine().generate(
      document: document,
      isTeacherVersion: isTeacherVersion,
      pageAssignments: pageAssignments,
    );
  }

  /// يكتب ورقة [document] كملف PDF على القرص ويعيد الملف.
  static Future<File> exportDocumentToPdf({
    required ExamDocument document,
    bool isTeacherVersion = false,
    List<List<String>>? pageAssignments,
    String? fileName,
    Directory? outputDirectory,
  }) async {
    final bytes = await buildDocumentPdfBytes(
      document: document,
      isTeacherVersion: isTeacherVersion,
      pageAssignments: pageAssignments,
    );
    final suffix = isTeacherVersion ? 'نموذج_الإجابة' : 'ورقة_الامتحان';
    return ExportFileService.writeExportFile(
      baseName: fileName ?? '${document.name}_$suffix',
      extension: 'pdf',
      bytes: bytes,
      destination: outputDirectory,
    );
  }

  /// يكتب ملف PDF على القرص ويعيد مساره.
  static Future<File> exportExamToPdf({
    required Exam exam,
    required bool isTeacherVersion,
    String? fileName,
    Directory? outputDirectory,
  }) async {
    final bytes = await buildExamPdfBytes(
      exam: exam,
      isTeacherVersion: isTeacherVersion,
    );
    final suffix = isTeacherVersion ? 'نموذج_الإجابة' : 'ورقة_الامتحان';
    return ExportFileService.writeExportFile(
      baseName: fileName ?? '${exam.name}_$suffix',
      extension: 'pdf',
      bytes: bytes,
      destination: outputDirectory,
    );
  }

  static Future<void> sharePdfFile(File file, {String? subject}) {
    return ExportFileService.shareExportFile(
      file,
      mimeType: 'application/pdf',
      subject: subject ?? 'ورقة اختبار بصيغة PDF',
    );
  }
}
