import 'dart:io';
import 'dart:typed_data';

import '../layout/canonical/layout_document.dart';
import '../models/exam_document.dart';
import '../pdf_engine/pdf_engine.dart';
import 'export_file_service.dart';
import 'page_frame_store.dart';

/// توليد وحفظ ومشاركة ورقة الاختبار بصيغة PDF.
///
/// تعتمد بالكامل على وحدة [PaginatedPdfExamEngine]؛ لا تنسيق حيّ هنا إطلاقاً —
/// الناتج لوحة A4 ثابتة لا تتغير بين الأجهزة أو إصدارات الأوفيس.
abstract final class PdfExportService {
  /// يحسم التخطيط نفسه الذي سيستخدمه محرك PDF، ويمكن تمريره إليه مباشرة.
  static Future<LayoutDocument> resolveLayoutDocument({
    required ExamDocument document,
  }) {
    return PaginatedPdfExamEngine().resolveLayoutDocument(document: document);
  }

  /// إسقاط P1-compatible لتوزيع الأسئلة؛ DOCX لا يستقبل إحداثيات التخطيط.
  static Future<List<List<String>>> resolvePageAssignments({
    required ExamDocument document,
  }) {
    return PaginatedPdfExamEngine().resolveQuestionPages(document: document);
  }

  /// يبني بايتات PDF متعدد الصفحات لورقة الأسئلة [document].
  ///
  /// [layoutDocument] هو التخطيط المحسوم في مسار المعاينة؛ يضمن أن يرسم PDF
  /// الإحداثيات وتقسيم الصفحات نفسيهما. عند غيابه يحسب المحرك التخطيط
  /// بالـ pipeline المشترك. أما [pageAssignments] فحقل توافق قديم لا يعيد
  /// تدفق المحتوى داخل PDF. وصورة الإطار تُقرأ هنا وتُسلَّم للمحرك.
  static Future<Uint8List> buildDocumentPdfBytes({
    required ExamDocument document,
    List<List<String>>? pageAssignments,
    LayoutDocument? layoutDocument,
  }) async {
    final frameImage = document.settings.pageBorder
        ? await PageFrameStore.read(document.settings.frameImagePath)
        : null;
    return PaginatedPdfExamEngine().generate(
      document: document,
      pageAssignments: pageAssignments,
      layoutDocument: layoutDocument,
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
