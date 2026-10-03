import '../../models/exam_document.dart';
import '../../models/floating_element.dart';
import '../blueprint/exam_blueprint.dart';
import '../document_ir.dart';
import 'legacy_blueprint_projection.dart';

/// Temporary bridge from canonical DocumentIR into the current PDF builder's
/// string-shaped ExamBlueprint contract. The adapter only projects nodes; it
/// does not recalculate labels, marks, visibility, rich-content boundaries, or
/// ordering.
abstract final class LegacyPdfAdapter {
  static ExamBlueprint adapt({
    required DocumentIR documentIr,
    required ExamDocument sourceDocument,
  }) =>
      LegacyBlueprintProjection.build(documentIr, sourceDocument);

  static FloatingElement adaptFloatingElement({
    required DocumentIR documentIr,
    required FloatingElement sourceElement,
  }) =>
      LegacyBlueprintProjection.adaptFloatingElement(
        documentIr,
        sourceElement,
      );
}
