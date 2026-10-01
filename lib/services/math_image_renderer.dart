import 'dart:math' as math;
import 'dart:ui' as ui;

import '../pdf_engine/latex/latex_svg_renderer.dart';
import 'docx_document_export_service.dart' show MathRaster, MathRasterizer;

/// ترسيم صيغ LaTeX إلى صور PNG لتصدير Word.
///
/// يستخدم [LatexSvgRenderer] **نفسه** المستخدم في ملف PDF: الصيغة تُحوَّل إلى
/// مسارات متجهة ثم تُرسم على لوحة نقطية — فتظهر في Word **صورة المعادلة**
/// (رموز مرسومة) لا كودها الخام مثل `x^2` أو `\frac{a}{b}`.
///
/// - المقاسات بالنقاط (pt) هي نفسها التي يضعها محرك الـ PDF، فيتطابق حجم
///   المعادلة في الورقتين.
/// - الرسم بكثافة [density] بكسل لكل نقطة (≈430 نقطة/بوصة) لتبقى المعادلة
///   حادة عند الطباعة والتكبير.
/// - يُضاف أسفل الصورة فراغ شفاف بمقدار نزول الصيغة عن خط الأساس، لأن Word
///   يضع أسفل الصورة المضمّنة **على** خط أساس النص: بهذا تجلس المعادلة على
///   السطر تماماً بدل أن ترتفع عنه.
///
/// أي فشل (صيغة غير مدعومة أو تعذّر الرسم) يعيد `null` فيكتب المصدر نص
/// الصيغة كما هو بدل إسقاط الفقرة.
abstract final class MathImageRenderer {
  /// بكسل لكل نقطة — صور المتجهات لا تفقد الحدّة بكثافة أعلى.
  ///
  /// ‏8 بكسل/نقطة ≈ 576 نقطة/بوصة: معادلة بعرض بوصة تحمل 576 بكسلاً فتبقى
  /// حادّة عند الطباعة على طابعات الليزر (600dpi) وعند التكبير في Word.
  static const double density = 8.0;

  static Future<MathRaster?> rasterize(String latex, double fontSizePt) async {
    final rendered = LatexSvgRenderer.tryToSvg(latex, fontSize: fontSizePt);
    if (rendered == null) {
      return null;
    }
    try {
      final descent = math.max(0.0, rendered.height - rendered.baseline);
      final widthPx = math.max(1.0, rendered.width * density);
      final heightPx = math.max(1.0, (rendered.height + descent) * density);
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(
        recorder,
        ui.Rect.fromLTWH(0, 0, widthPx, heightPx),
      );
      canvas.scale(density);
      final paint = ui.Paint()
        ..color = const ui.Color(0xFF000000)
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = _strokeWidth(rendered.svg, fontSizePt)
        ..strokeCap = ui.StrokeCap.round
        ..strokeJoin = ui.StrokeJoin.round;
      for (final match in _pathDataPattern.allMatches(rendered.svg)) {
        canvas.drawPath(_parsePathData(match.group(1) ?? ''), paint);
      }
      final picture = recorder.endRecording();
      final image = await picture.toImage(widthPx.ceil(), heightPx.ceil());
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (bytes == null) {
        return null;
      }
      return MathRaster(
        pngBytes: bytes.buffer.asUint8List(),
        widthPt: rendered.width,
        heightPt: rendered.height + descent,
      );
    } catch (_) {
      return null;
    }
  }

  /// نفس الدالة بصيغة [MathRasterizer] الجاهزة للتمرير من الواجهة.
  static MathRasterizer get asRasterizer => rasterize;

  static final RegExp _pathDataPattern = RegExp(r'd="([^"]*)"');
  static final RegExp _strokeWidthPattern = RegExp(r'stroke-width="([0-9.]+)"');

  /// محلّل بيانات مسار SVG كامل: الأوامر المطلقة والنسبية
  /// (M/L/H/V/C/S/Q/T/Z) — نفس مجموعة ما يُنتجه [LatexSvgRenderer]
  /// (منحنيات Bézier للمحارف الناعمة) فيُرسم في Word كما في PDF تماماً.
  static final RegExp _tokenPattern = RegExp(
    r'[MLHVCSQTZmlhvcsqtz]|-?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?',
  );

  /// يحوّل بيانات مسار SVG إلى [ui.Path].
  static ui.Path _parsePathData(String data) {
    final tokens = _tokenPattern
        .allMatches(data)
        .map((match) => match.group(0) ?? '')
        .toList(growable: false);
    final path = ui.Path();
    var index = 0;
    var command = 'M';
    var x = 0.0;
    var y = 0.0;
    var startX = 0.0;
    var startY = 0.0;
    var lastControlX = 0.0;
    var lastControlY = 0.0;

    bool isCommand(String token) => RegExp(r'[A-Za-z]').hasMatch(token);
    double nextNumber() {
      final value = double.parse(tokens[index]);
      index++;
      return value;
    }

    while (index < tokens.length) {
      if (isCommand(tokens[index])) {
        command = tokens[index];
        index++;
      }
      switch (command) {
        case 'M':
        case 'm':
          x = nextNumber() + (command == 'm' ? x : 0);
          y = nextNumber() + (command == 'm' ? y : 0);
          path.moveTo(x, y);
          startX = x;
          startY = y;
          command = command == 'm' ? 'l' : 'L';
        case 'L':
        case 'l':
          x = nextNumber() + (command == 'l' ? x : 0);
          y = nextNumber() + (command == 'l' ? y : 0);
          path.lineTo(x, y);
        case 'H':
        case 'h':
          x = nextNumber() + (command == 'h' ? x : 0);
          path.lineTo(x, y);
        case 'V':
        case 'v':
          y = nextNumber() + (command == 'v' ? y : 0);
          path.lineTo(x, y);
        case 'C':
        case 'c':
          final c1x = nextNumber() + (command == 'c' ? x : 0);
          final c1y = nextNumber() + (command == 'c' ? y : 0);
          final c2x = nextNumber() + (command == 'c' ? x : 0);
          final c2y = nextNumber() + (command == 'c' ? y : 0);
          x = nextNumber() + (command == 'c' ? x : 0);
          y = nextNumber() + (command == 'c' ? y : 0);
          path.cubicTo(c1x, c1y, c2x, c2y, x, y);
          lastControlX = c2x;
          lastControlY = c2y;
        case 'S':
        case 's':
          final c1x = 2 * x - lastControlX;
          final c1y = 2 * y - lastControlY;
          final c2x = nextNumber() + (command == 's' ? x : 0);
          final c2y = nextNumber() + (command == 's' ? y : 0);
          x = nextNumber() + (command == 's' ? x : 0);
          y = nextNumber() + (command == 's' ? y : 0);
          path.cubicTo(c1x, c1y, c2x, c2y, x, y);
          lastControlX = c2x;
          lastControlY = c2y;
        case 'Q':
        case 'q':
          final cx = nextNumber() + (command == 'q' ? x : 0);
          final cy = nextNumber() + (command == 'q' ? y : 0);
          x = nextNumber() + (command == 'q' ? x : 0);
          y = nextNumber() + (command == 'q' ? y : 0);
          path.quadraticBezierTo(cx, cy, x, y);
          lastControlX = cx;
          lastControlY = cy;
        case 'T':
        case 't':
          final cx = 2 * x - lastControlX;
          final cy = 2 * y - lastControlY;
          x = nextNumber() + (command == 't' ? x : 0);
          y = nextNumber() + (command == 't' ? y : 0);
          path.quadraticBezierTo(cx, cy, x, y);
          lastControlX = cx;
          lastControlY = cy;
        case 'Z':
        case 'z':
          path.close();
          x = startX;
          y = startY;
        default:
          // أمر غير معروف: تُتخطّى أرقامه بأمان بدل كسر الرسم كله.
          while (index < tokens.length && !isCommand(tokens[index])) {
            index++;
          }
      }
    }
    return path;
  }

  /// عرض الخط من وسم `<g>` نفسه؛ وإن غاب يُحسب كما يحسبه المرسّم.
  static double _strokeWidth(String svg, double fontSizePt) {
    final match = _strokeWidthPattern.firstMatch(svg);
    final parsed = match == null ? null : double.tryParse(match.group(1) ?? '');
    if (parsed != null && parsed > 0) {
      return parsed;
    }
    return math.max(0.5, fontSizePt * 0.07);
  }

  /// يحوّل بيانات مسار SVG (M/L مطلقة أو نسبية، وZ) إلى [ui.Path].
  static ui.Path _parsePathData(String data) {
    final path = ui.Path();
    final tokens = _tokenPattern
        .allMatches(data)
        .map((match) => match.group(0) ?? '')
        .toList(growable: false);
    var index = 0;
    var command = 'M';
    var currentX = 0.0;
    var currentY = 0.0;
    while (index < tokens.length) {
      final token = tokens[index];
      if (token.length == 1 && 'MLZmlz'.contains(token)) {
        if (token == 'Z' || token == 'z') {
          path.close();
        } else {
          command = token;
        }
        index += 1;
        continue;
      }
      if (index + 1 >= tokens.length) {
        break;
      }
      final isRelative = command == 'm' || command == 'l';
      final x = double.parse(tokens[index]) + (isRelative ? currentX : 0.0);
      final y = double.parse(tokens[index + 1]) + (isRelative ? currentY : 0.0);
      if (command == 'M' || command == 'm') {
        path.moveTo(x, y);
        // النقاط التالية بلا حرف أمر تُقرأ خطوطاً (قواعد SVG).
        command = isRelative ? 'l' : 'L';
      } else {
        path.lineTo(x, y);
      }
      currentX = x;
      currentY = y;
      index += 2;
    }
    return path;
  }
}
