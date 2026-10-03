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

/// Convenience pipeline used by Preview and PDF: ExamDocument → frozen P1 IR
/// → non-semantic layout configuration → canonical point geometry.
abstract final class CanonicalLayoutService {
  static Future<LayoutDocument> resolve({
    required ExamDocument document,
    FontMetricsProvider fontMetrics = const FlutterTextMetrics(),
    bool quranFontAvailable = true,
    List<List<String>>? questionPageAssignments,
  }) async {
    if (fontMetrics is FlutterTextMetrics) {
      await FlutterTextMetrics.ensureFontsLoaded();
    }
    final ir = DocumentIR.fromBlueprint(
      blueprint: ExamBlueprint.from(document),
      document: document,
    );
    final configuration = ExamDocumentLayoutAdapter.configurationFor(
      document,
      quranFontAvailable: quranFontAvailable,
    );
    const engine = LayoutEngine();
    var layout = engine.layout(
      document: ir,
      configuration: configuration,
      fontMetrics: fontMetrics,
      questionPageAssignments: questionPageAssignments,
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
