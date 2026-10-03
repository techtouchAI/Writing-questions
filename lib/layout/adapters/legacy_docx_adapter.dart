import '../../models/exam_document.dart';
import '../../models/floating_element.dart';
import '../blueprint/exam_blueprint.dart';
import '../document_ir.dart';
import 'legacy_blueprint_projection.dart';

/// Temporary bridge from canonical DocumentIR into the current DOCX builder's
/// string-shaped ExamBlueprint contract. It preserves the IR block order and
/// turns typed inline nodes into legacy projections only at the boundary.
abstract final class LegacyDocxAdapter {
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
