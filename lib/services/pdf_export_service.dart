import 'dart:io';
import 'dart:typed_data';

import '../models/exam_document.dart';
import '../pdf_engine/pdf_engine.dart';
import 'export_file_service.dart';
import 'page_frame_store.dart';

/// توليد وحفظ ومشاركة ورقة الاختبار بصيغة PDF.
///
/// تعتمد بالكامل على وحدة [PaginatedPdfExamEngine]؛ لا تنسيق حيّ هنا إطلاقاً —
/// الناتج لوحة A4 ثابتة لا تتغير بين الأجهزة أو إصدارات الأوفيس.
abstract final class PdfExportService {
  /// يحسب توزيع الأسئلة نفسه الذي سيستخدمه محرك PDF عند غياب قياسات المعاينة.
  /// يمكن تمريره إلى Word لتتوافق فواصل الصفحات والعناصر الحرة مع PDF.
  static Future<List<List<String>>> resolvePageAssignments({
    required ExamDocument document,
  }) {
    return PaginatedPdfExamEngine().resolveQuestionPages(document: document);
  }

  /// يبني بايتات PDF متعدد الصفحات لورقة الأسئلة [document].
  ///
  /// [pageAssignments] هو توزيع الأسئلة على الصفحات كما حُسب على لوحة
  /// المعاينة، فيُطبع الملف بنفس التقسيم المعروض تماماً. وصورة الإطار
  /// (إن اختارها المدرس) تُقرأ من مسارها هنا وتُسلَّم للمحرك.
  static Future<Uint8List> buildDocumentPdfBytes({
    required ExamDocument document,
    List<List<String>>? pageAssignments,
  }) async {
    final frameImage = document.settings.pageBorder
        ? await PageFrameStore.read(document.settings.frameImagePath)
        : null;
    return PaginatedPdfExamEngine().generate(
      document: document,
      pageAssignments: pageAssignments,
      frameImage: frameImage,
    );
  }

  /// يكتب ورقة [document] كملف PDF على القرص ويعيد الملف.
  static Future<File> exportDocumentToPdf({
    required ExamDocument document,
    List<List<String>>? pageAssignments,
    String? fileName,
    Directory? outputDirectory,
  }) async {
    final bytes = await buildDocumentPdfBytes(
      document: document,
      pageAssignments: pageAssignments,
    );
    return ExportFileService.writeExportFile(
      baseName: fileName ?? '${document.name}_ورقة_الامتحان',
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
