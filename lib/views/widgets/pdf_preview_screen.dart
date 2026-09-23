import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

/// معاينة ورقة الاختبار داخل التطبيق قبل الطباعة أو المشاركة.
///
/// تعتمد على حزمة printing لعرض صفحات الـ PDF الحقيقية كما ستُطبع،
/// مع أزرار الطباعة والمشاركة المدمجة في النظام.
class PdfPreviewScreen extends StatelessWidget {
  const PdfPreviewScreen({
    super.key,
    required this.pdfBytes,
    required this.title,
    required this.fileName,
  });

  final Uint8List pdfBytes;
  final String title;
  final String fileName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: PdfPreview(
        build: (pageFormat) async => pdfBytes,
        initialPageFormat: PdfPageFormat.a4,
        allowPrinting: true,
        allowSharing: true,
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
        pdfFileName: fileName,
        loadingWidget: const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
