import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/layout/canonical/layout_units.dart';
import 'package:writing_questions_app/layout/paper_metrics.dart';

void main() {
  test('source typography and canonical geometry use one physical unit ratio', () {
    for (final points in [1.0, 10.5, 14.0, 72.0, 841.8897637795277]) {
      expect(PaperMetrics.px(points), LayoutUnits.ptToPx(points));
      expect(PaperMetrics.pt(LayoutUnits.ptToPx(points)), closeTo(points, 1e-12));
    }
    expect(PaperMetrics.px(10.5), 14);
  });
}
