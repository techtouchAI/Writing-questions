import '../../services/math_snapshot_renderer.dart';
import 'layout_document.dart';

/// Resolves optional math placeholder geometry through the application's shared
/// math snapshot host. The returned map is point-only and keyed by stable
/// DocumentIR node paths; snapshots are released before this method returns.
abstract final class LayoutMathMetricsResolver {
  static Future<Map<String, LayoutMathBox>> resolve(LayoutDocument measured) async {
    final mathRuns = <String, LayoutRun>{};
    for (final line in measured.allLines) {
      for (final run in line.runs) {
        if (!run.isMath || run.text.trim().isEmpty) continue;
        mathRuns.putIfAbsent(run.semanticNodeId, () => run);
      }
    }
    if (mathRuns.isEmpty || !MathSnapshotRenderer.isAvailable) {
      return const <String, LayoutMathBox>{};
    }

    final snapshots = <String, Future<MathSnapshot?>>{};
    for (final run in mathRuns.values) {
      final key = '${run.text}\u0000${run.style.fontSizePt.toStringAsFixed(3)}';
      snapshots.putIfAbsent(
        key,
        () => MathSnapshotRenderer.render(
          run.text,
          fontSizePt: run.style.fontSizePt,
        ),
      );
    }
    final resolved = <String, MathSnapshot?>{};
    for (final entry in snapshots.entries) {
      try {
        resolved[entry.key] = await entry.value;
      } catch (_) {
        resolved[entry.key] = null;
      }
    }

    final boxes = <String, LayoutMathBox>{};
    for (final entry in mathRuns.entries) {
      final run = entry.value;
      final key = '${run.text}\u0000${run.style.fontSizePt.toStringAsFixed(3)}';
      final snapshot = resolved[key];
      if (snapshot == null) continue;
      boxes[entry.key] = LayoutMathBox(
        widthPt: snapshot.widthPt,
        heightPt: snapshot.heightPt,
        baselinePt: snapshot.baselinePt,
        source: 'mathSnapshot',
      );
    }
    for (final snapshot in resolved.values) {
      snapshot?.dispose();
    }
    return Map<String, LayoutMathBox>.unmodifiable(boxes);
  }
}
