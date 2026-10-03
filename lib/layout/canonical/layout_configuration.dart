import '../../models/paper_font.dart';
import '../../models/paper_settings.dart';
import '../../models/paper_text_style.dart';
import '../../models/subject_layout.dart';
import 'layout_units.dart';

/// Source-authored float geometry resolved from ExamDocument by an adapter.
/// Positions and dimensions are stored in the legacy canvas px input unit and
/// converted to pt here; measured image/font boxes never flow back into IR.
class FloatingLayoutInput {
  const FloatingLayoutInput({
    required this.id,
    required this.dxPx,
    required this.dyPx,
    required this.widthPx,
    required this.heightPx,
    required this.pageIndex,
    this.ownerQuestionId,
    this.rotationDegrees = 0,
    this.strokeWidthPt = 2,
    this.textStyle,
    this.framed = false,
    this.flowReserveHeightPx = 0,
  });

  final String id;
  final double dxPx;
  final double dyPx;
  final double widthPx;
  final double heightPx;
  final int pageIndex;
  final String? ownerQuestionId;
  final double rotationDegrees;
  final double strokeWidthPt;
  final PaperTextStyle? textStyle;
  final bool framed;

  /// Historical attachment reserve, when this source element participated in
  /// flow. It is explicit and only used for nested question attachments.
  final double flowReserveHeightPx;
}

/// Non-semantic layout context. DocumentIR is the only source of semantic
/// content; this context supplies page/style policy and source-authored float
/// geometry that P1 intentionally kept out of IR.
class DividerLayoutInput {
  const DividerLayoutInput({
    required this.sourceId,
    required this.widthFraction,
    required this.thicknessPt,
    required this.spacingBeforePt,
    required this.spacingAfterPt,
  });

  final String sourceId;
  final double widthFraction;
  final double thicknessPt;
  final double spacingBeforePt;
  final double spacingAfterPt;
}

class LayoutConfiguration {
  const LayoutConfiguration({
    this.pageSize = LayoutUnits.a4,
    this.paperSettings = const PaperSettings(),
    this.subjectLayout = SubjectLayoutTemplate.generic,
    this.lineHeightFactor = 1.45,
    this.headerStyle,
    this.questionSpacingAfterPt = const <String, double>{},
    this.floatingElements = const <String, FloatingLayoutInput>{},
    this.dividers = const <String, DividerLayoutInput>{},
    this.quranFontAvailable = true,
    this.scaleOversizedBlocks = true,
    this.headerBorder = false,
  });

  final LayoutSize pageSize;
  final PaperSettings paperSettings;
  final SubjectLayoutTemplate subjectLayout;
  final double lineHeightFactor;
  final PaperTextStyle? headerStyle;
  final Map<String, double> questionSpacingAfterPt;
  final Map<String, FloatingLayoutInput> floatingElements;
  final Map<String, DividerLayoutInput> dividers;
  final bool quranFontAvailable;
  final bool scaleOversizedBlocks;
  final bool headerBorder;

  PaperFont get defaultFont => paperSettings.defaultFont;
  double get fontScale => paperSettings.fontScale;
  double get heightScale => paperSettings.heightScale;
  double get marginPt => LayoutUnits.mmToPt(paperSettings.marginMm);
  double get contentWidthPt => pageSize.width - 2 * marginPt;
  double get contentHeightPt => pageSize.height - 2 * marginPt;

  double questionSpacing(String questionId) =>
      questionSpacingAfterPt[questionId] ?? LayoutUnits.pxToPt(10);
}
