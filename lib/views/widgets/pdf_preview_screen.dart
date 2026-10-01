import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

/// دقة raster معاينة الـ PDF (بكسل/بوصة) — عرضٌ فقط، لا يمسّ الملف.
const double _pdfPreviewDpi = 150;

/// حدود التكبير في المعاينة (1.0 = الحجم الأصلي).
const double _pdfPreviewMinZoom = 0.6;
const double _pdfPreviewMaxZoom = 4.0;
const double _pdfPreviewZoomStep = 0.25;

/// معاينة ورقة الاختبار داخل التطبيق قبل الطباعة أو المشاركة.
///
/// تعتمد على معاينة الحزمة نفسها (`PdfPreview.builder`) التي ترسم صفحات الـ PDF
/// الحقيقية كما ستُطبع، مع شريط الطباعة/المشاركة/التحميل الخاص بها؛ وتضيف
/// فوق الصفحات طبقة عرض تقبل:
/// - **القرص بإصبعين** للتكبير والتصغير في أي وقت،
/// - **وتحريك العرض** المكبَّر بالسحب،
/// - **وأزرار التكبير** (− / + / إعادة) في شريط التطبيق مع نسبة العرض الحالية.
///
/// التكبير عرضٌ فقط: لا يغيّر الملف ولا ما سيُطبع.
class PdfPreviewScreen extends StatefulWidget {
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
  State<PdfPreviewScreen> createState() => _PdfPreviewScreenState();
}

class _PdfPreviewScreenState extends State<PdfPreviewScreen> {
  final TransformationController _zoomController = TransformationController();

  /// نسبة العرض الحالية (تُحدَّث من الأزرار ومن القرص بإصبعين).
  final ValueNotifier<double> _zoom = ValueNotifier<double>(1.0);

  @override
  void initState() {
    super.initState();
    _zoomController.addListener(_syncZoomFromController);
  }

  @override
  void dispose() {
    _zoomController.removeListener(_syncZoomFromController);
    _zoomController.dispose();
    _zoom.dispose();
    super.dispose();
  }

  void _syncZoomFromController() {
    final scale = _zoomController.value.getMaxScaleOnAxis();
    if ((scale - _zoom.value).abs() > 0.001) {
      _zoom.value = scale;
    }
  }

  void _setZoom(double value) {
    final next = value.clamp(_pdfPreviewMinZoom, _pdfPreviewMaxZoom).toDouble();
    if ((next - _zoom.value).abs() < 0.001) {
      return;
    }
    _zoomController.value = Matrix4.identity()..scale(next, next);
    _zoom.value = next;
  }

  void _resetZoom() => _setZoom(1.0);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: <Widget>[
          IconButton(
            tooltip: 'تصغير المعاينة',
            icon: const Icon(Icons.zoom_out),
            onPressed: () => _setZoom(_zoom.value - _pdfPreviewZoomStep),
          ),
          ValueListenableBuilder<double>(
            valueListenable: _zoom,
            builder: (context, zoom, _) => Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  '${(zoom * 100).round()}%',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'تكبير المعاينة',
            icon: const Icon(Icons.zoom_in),
            onPressed: () => _setZoom(_zoom.value + _pdfPreviewZoomStep),
          ),
          IconButton(
            tooltip: 'إعادة الحجم الأصلي',
            icon: const Icon(Icons.fit_screen_outlined),
            onPressed: _resetZoom,
          ),
        ],
      ),
      body: PdfPreview.builder(
        build: (pageFormat) async => widget.pdfBytes,
        // raster عالي الدقة للمعاينة: القيمة الافتراضية تُحسب على عرض
        // الشاشة فتبدو الصفحات مشوّشة عند التكبير؛ ‏150dpi توازن بين
        // الحدّة (A4 = 1240×1754 بكسل) والذاكرة على أجهزة Android.
        dpi: _pdfPreviewDpi,
        initialPageFormat: PdfPageFormat.a4,
        allowPrinting: true,
        allowSharing: true,
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
        pdfFileName: widget.fileName,
        loadingWidget: const Center(child: CircularProgressIndicator()),
        pagesBuilder: (context, pages) => _ZoomablePages(
          pages: pages,
          controller: _zoomController,
        ),
      ),
    );
  }
}

/// صفحات المعاينة داخل طبقة عرض قابلة للتكبير/التحريك.
class _ZoomablePages extends StatelessWidget {
  const _ZoomablePages({required this.pages, required this.controller});

  final List<PdfPreviewPageData> pages;
  final TransformationController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Matrix4>(
      valueListenable: controller,
      builder: (context, matrix, child) {
        // عند التكبير يتولى هذا الـ[InteractiveViewer] السحب، وعند الحجم
        // الأصلي تمرّ التمريرة إلى القائمة فلا يتغير سلوك القراءة العادي.
        final zooming = (matrix.getMaxScaleOnAxis() - 1.0).abs() > 0.01;
        return InteractiveViewer(
          transformationController: controller,
          minScale: _pdfPreviewMinZoom,
          maxScale: _pdfPreviewMaxZoom,
          panEnabled: zooming,
          child: ListView.builder(
            shrinkWrap: true,
            physics: zooming
                ? const NeverScrollableScrollPhysics()
                : const ClampingScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: 12),
            itemCount: pages.length,
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  boxShadow: <BoxShadow>[
                    BoxShadow(offset: Offset(0, 3), blurRadius: 5),
                  ],
                ),
                child: AspectRatio(
                  aspectRatio: pages[index].aspectRatio,
                  child: Image(
                    image: pages[index].image,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
