import '../../models/exam_document.dart';
import '../../services/math_snapshot_renderer.dart';
import '../blueprint/exam_blueprint.dart';
import '../document_ir.dart';
import 'exam_document_layout_adapter.dart';
import 'flutter_text_metrics.dart';
import 'font_metrics.dart';
import 'layout_document.dart';
import 'layout_engine.dart';
import 'layout_math_metrics_resolver.dart';
import 'layout_units.dart';

/// Convenience pipeline used by Preview and PDF: ExamDocument → frozen P1 IR
/// → non-semantic layout configuration → canonical point geometry.
abstract final class CanonicalLayoutService {
  static Future<LayoutDocument> resolve({
    required ExamDocument document,
    DocumentIR? sourceIr,
    LayoutSize? pageSize,
    FontMetricsProvider fontMetrics = const FlutterTextMetrics(),
    bool quranFontAvailable = true,
    List<List<String>>? questionPageAssignments,
  }) async {
    if (fontMetrics is FlutterTextMetrics) {
      await FlutterTextMetrics.ensureFontsLoaded();
    }
    final ir = sourceIr ??
        DocumentIR.fromBlueprint(
          blueprint: ExamBlueprint.from(document),
          document: document,
        );
    final configuration = ExamDocumentLayoutAdapter.configurationFor(
      document,
      pageSize: pageSize,
      quranFontAvailable: quranFontAvailable,
    );
    const engine = LayoutEngine();
    // الممرّ الأول **قياس**: تقسيم صفحاته يُهمَل إن جاءت مقاييس المعادلات
    // بعدها، فلا تُسلَّم إليه خطة قد لا تتسع بقياسات أصغر. الخطة المُسلَّمة
    // تُطبَّق مرة واحدة على التخطيط النهائي الذي يُعاد للمستهلك.
    var layout = engine.layout(
      document: ir,
      configuration: configuration,
      fontMetrics: fontMetrics,
      questionPageAssignments:
          MathSnapshotRenderer.isAvailable ? null : questionPageAssignments,
    );
    if (!MathSnapshotRenderer.isAvailable) return layout;

    final math = await LayoutMathMetricsResolver.resolve(layout);
    if (math.isEmpty) return layout;
    layout = engine.layout(
      document: ir,
      configuration: configuration,
      fontMetrics: fontMetrics,
      mathMetrics: math,
      questionPageAssignments: questionPageAssignments,
    );
    return layout;
  }
}
