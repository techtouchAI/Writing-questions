import '../../models/exam_document.dart';
import '../../models/floating_element.dart';
import '../../models/paper_divider.dart';
import 'layout_configuration.dart';
import 'layout_units.dart';

/// Resolves source-authored ExamDocument layout inputs into canonical policy.
/// It does not create or mutate DocumentIR and does not add geometry to semantic
/// models. IDs are used to join source floats/dividers with their IR references.
abstract final class ExamDocumentLayoutAdapter {
  static LayoutConfiguration configurationFor(
    ExamDocument document, {
    LayoutSize? pageSize,
    bool quranFontAvailable = true,
  }) {
    final floating = <String, FloatingLayoutInput>{};
    final dividers = <String, DividerLayoutInput>{};
    final spacing = <String, double>{};

    void addFloating(
      FloatingElement element, {
      String? ownerQuestionId,
      bool participatesInFlow = false,
    }) {
      var reserve = 0.0;
      if (participatesInFlow) {
        reserve = (element.dy + element.height).clamp(0.0, double.infinity).toDouble();
      }
      floating.putIfAbsent(
        element.id,
        () => FloatingLayoutInput(
          id: element.id,
          dxPx: element.dx,
          dyPx: element.dy,
          widthPx: element.width,
          heightPx: element.height,
          pageIndex: element.pageIndex,
          ownerQuestionId: ownerQuestionId ?? element.ownerQuestionId,
          rotationDegrees: element.rotationDegrees,
          strokeWidthPt: element.strokeWidth,
          textStyle: element.textStyle,
          framed: element.framed,
          flowReserveHeightPx: reserve,
        ),
      );
    }

    void addDivider(String sourceId, PaperDivider divider) {
      dividers[sourceId] = DividerLayoutInput(
        sourceId: sourceId,
        widthFraction: divider.widthFraction,
        thicknessPt: divider.thickness,
        spacingBeforePt: divider.spacingBefore,
        spacingAfterPt: divider.spacingAfter,
      );
    }

    for (final element in document.floatingElements) {
      addFloating(element);
    }
    for (final question in document.questions) {
      spacing[question.id] = LayoutUnits.pxToPt(question.spacingAfter);
      for (final element in question.attachments) {
        addFloating(
          element,
          ownerQuestionId: question.id,
          participatesInFlow: true,
        );
      }
      final questionDivider = question.dividerAfter;
      if (questionDivider != null) {
        addDivider('question:${question.id}', questionDivider);
      }
      for (final branch in question.branches) {
        for (final element in branch.attachments) {
          addFloating(
            element,
            ownerQuestionId: question.id,
            participatesInFlow: true,
          );
        }
        final branchDivider = branch.dividerAfter;
        if (branchDivider != null) {
          addDivider('branch:${branch.id}', branchDivider);
        }
      }
    }

    return LayoutConfiguration(
      pageSize: pageSize ?? LayoutUnits.a4,
      paperSettings: document.settings,
      subjectLayout: document.layout,
      lineHeightFactor: document.layout.lineHeightFactor,
      headerStyle: document.header.style,
      questionSpacingAfterPt: Map<String, double>.unmodifiable(spacing),
      floatingElements: Map<String, FloatingLayoutInput>.unmodifiable(floating),
      dividers: Map<String, DividerLayoutInput>.unmodifiable(dividers),
      quranFontAvailable: quranFontAvailable,
      headerBorder: document.settings.headerBorder,
    );
  }
}
