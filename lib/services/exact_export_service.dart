import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../layout/paper_metrics.dart';
import 'export_file_service.dart';
import 'page_snapshot_service.dart';

/// التصدير الدقيق (Exact): الصفحة تُصدَّر **صورة الصفحة النهائية** كما
/// رسمها Flutter في المعاينة، فلا يبقى في المسار أي محرك تخطيط ثانٍ يعيد
/// حساب المواضع أو المقاسات.
///
/// - PDF: كل صفحة صورة A4 كاملة (300dpi افتراضاً) — مطابقة للمعاينة بالبناء.
/// - Word: كل صفحة صورة بحجم A4 بالضبط داخل مستند بلا هوامش — مطابقة أيضاً،
///   لكنه **غير قابل للتحرير** (هذا مقصود ومعلن: للمعادلات القابلة للتحرير
///   يوجد مسار `DOCX Editable` في [DocxDocumentExportService]).
abstract final class ExactExportService {
  /// دقة اللقط الافتراضية للتصدير الدقيق.
  static const double defaultDpi = PageSnapshotService.defaultDpi;

  /// يبني PDF بحيث تكون كل صفحة صورة الصفحة الملتقطة نفسها.
  ///
  /// يفشل برسالة واضحة إذا كانت القائمة فارغة (لا تُنشأ ورقة بلا صفحات).
  static Future<Uint8List> buildPdfFromSnapshots(
    List<PageSnapshot> snapshots,
  ) async {
    if (snapshots.isEmpty) {
      throw StateError('التصدير الدقيق يحتاج صفحة واحدة على الأقل.');
    }
    final document = pw.Document(
      title: 'ورقة الامتحان (مطابقة للمعاينة)',
      creator: 'Writing Questions',
      producer: 'Writing Questions',
    );
    for (final snapshot in snapshots) {
      final image = pw.MemoryImage(snapshot.pngBytes);
      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.zero,
          build: (context) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Image(image, fit: pw.BoxFit.fill),
          ),
        ),
      );
    }
    return document.save();
  }

  /// يكتب الورقة الدقيقة PDF على القرص ويعيد الملف.
  static Future<File> exportPdfFile({
    required List<PageSnapshot> snapshots,
    required String baseName,
    Directory? outputDirectory,
  }) async {
    final bytes = await buildPdfFromSnapshots(snapshots);
    return ExportFileService.writeExportFile(
      baseName: baseName,
      extension: 'pdf',
      bytes: bytes,
      destination: outputDirectory,
    );
  }

  /// يبني ملف Word تكون كل صفحة فيه صورة صفحة A4 كاملة.
  ///
  /// مستند Word هنا **غير قابل للتحرير** نصياً: هو صورة الورقة النهائية —
  /// الاسم في الواجهة يعلن ذلك صراحةً بوسم «مطابق للمعاينة».
  static Uint8List buildDocxFromSnapshots(List<PageSnapshot> snapshots) {
    if (snapshots.isEmpty) {
      throw StateError('التصدير الدقيق يحتاج صفحة واحدة على الأقل.');
    }
    final archive = Archive();
    final media = StringBuffer();
    final relationships = StringBuffer();
    final body = StringBuffer();
    final imageTags = <String>[];

    for (var index = 0; index < snapshots.length; index++) {
      final relationId = 'rIdPage${index + 1}';
      final fileName = 'page${index + 1}.png';
      media.write(
        '<Override PartName="/word/media/$fileName" '
        'ContentType="image/png"/>',
      );
      relationships.write(
        '<Relationship Id="$relationId" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" '
        'Target="media/$fileName"/>',
      );
      imageTags.add(
        '<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="1" w:lineRule="exact"/>'
        '<w:jc w:val="center"/></w:pPr><w:r>${_pageDrawing(index + 1, relationId)}</w:r></w:p>',
      );
      final bytes = snapshots[index].pngBytes;
      archive.addFile(ArchiveFile('word/media/$fileName', bytes.length, bytes));
    }

    _addText(
      archive,
      '[Content_Types].xml',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Default Extension="png" ContentType="image/png"/>'
      '<Override PartName="/word/document.xml" '
      'ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
      '$media'
      '</Types>',
    );
    _addText(
      archive,
      '_rels/.rels',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
      'Target="word/document.xml"/></Relationships>',
    );
    _addText(
      archive,
      'word/_rels/document.xml.rels',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '$relationships</Relationships>',
    );
    _addText(
      archive,
      'word/document.xml',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
      'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
      'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
      'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">'
      '<w:body>'
      '${imageTags.join()}'
      '<w:sectPr>'
      '<w:pgSz w:w="${_pageWidthTwips}" w:h="${_pageHeightTwips}"/>'
      '<w:pgMar w:top="0" w:right="0" w:bottom="0" w:left="0" '
      'w:header="0" w:footer="0" w:gutter="0"/>'
      '<w:bidi/>'
      '</w:sectPr>'
      '</w:body></w:document>',
    );
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  /// يكتب ملف Word الدقيق على القرص ويعيد الملف.
  static Future<File> exportDocxFile({
    required List<PageSnapshot> snapshots,
    required String baseName,
    Directory? outputDirectory,
  }) async {
    final bytes = buildDocxFromSnapshots(snapshots);
    return ExportFileService.writeExportFile(
      baseName: baseName,
      extension: 'docx',
      bytes: bytes,
      destination: outputDirectory,
    );
  }

  // ------------------------------ أدوات داخلية ------------------------------

  /// عرض/ارتفاع A4 بالتويب (210×297 مم).
  static final int _pageWidthTwips = (210 / 25.4 * 1440).round();
  static final int _pageHeightTwips = (297 / 25.4 * 1440).round();

  /// صورة الصفحة بحجم الورقة كاملة بوحدة EMU (1/914400 بوصة).
  static String _pageDrawing(int id, String relationId) {
    final widthEmu = (210 / 25.4 * 914400).round();
    final heightEmu = (297 / 25.4 * 914400).round();
    return '<w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0">'
        '<wp:extent cx="$widthEmu" cy="$heightEmu"/>'
        '<wp:docPr id="$id" name="Page $id"/>'
        '<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<pic:pic><pic:nvPicPr><pic:cNvPr id="$id" name="Page $id"/><pic:cNvPicPr/></pic:nvPicPr>'
        '<pic:blipFill><a:blip r:embed="$relationId"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
        '<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="$widthEmu" cy="$heightEmu"/></a:xfrm>'
        '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>'
        '</pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing>';
  }

  static void _addText(Archive archive, String path, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }
}
