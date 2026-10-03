import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/widgets.dart'
    show PlaceholderAlignment, SizedBox, TextBaseline, TextSelection, WidgetSpan;

import '../../models/paper_text_style.dart';
import '../document_direction.dart';
import 'font_metrics.dart';
import 'layout_document.dart';
import 'layout_units.dart';

/// Flutter paragraph engine adapter for P2 measurement.
///
/// `TextPainter` is intentionally confined to this adapter. It performs font
/// shaping, Unicode line breaking, paragraph bidi, line metrics and justified
/// placement. Only primitive point-space measurements escape this class.
class FlutterTextMetrics implements FontMetricsProvider {
  const FlutterTextMetrics();

  @override
  String get backendId => 'flutter-text-painter-pt-v1';

  @override
  FontRunMetrics measureText(
    String text,
    LayoutTextStyle style,
    DocumentDirection direction,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: _textStyle(style)),
      textDirection: _textDirection(direction),
      textScaler: TextScaler.noScaling,
      maxLines: 1,
    )..layout(maxWidth: double.infinity);
    try {
      final lines = painter.computeLineMetrics();
      if (lines.isEmpty) {
        return const FontRunMetrics(
          advance: 0,
          ascent: 0,
          descent: 0,
          leading: 0,
          baseline: 0,
        );
      }
      final line = lines.first;
      final ascent = LayoutUnits.pxToPt(line.ascent);
      final descent = LayoutUnits.pxToPt(line.descent);
      final leading = LayoutUnits.pxToPt(line.height - line.ascent - line.descent);
      return FontRunMetrics(
        advance: LayoutUnits.pxToPt(painter.width),
        ascent: ascent,
        descent: descent,
        leading: leading,
        baseline: LayoutUnits.pxToPt(line.baseline),
      );
    } finally {
      painter.dispose();
    }
  }

  @override
  double whitespaceAdvance(
    LayoutTextStyle style,
    DocumentDirection direction, {
    bool nonBreaking = false,
  }) {
    // NBSP uses the same nominal advance as U+0020 in most fonts, but is
    // measured explicitly. Its non-breaking behavior is handled by paragraph
    // shaping rather than a whitespace regular expression.
    final sample = nonBreaking ? '\u00a0' : ' ';
    return measureText(sample, style, direction).advance;
  }

  @override
  MeasuredParagraph layoutParagraph({
    required List<MetricSpan> spans,
    required double width,
    required DocumentDirection direction,
    required PaperAlign? alignment,
    required bool resolveJustification,
  }) {
    if (width <= 0) {
      throw ArgumentError.value(width, 'width', 'Paragraph width must be positive.');
    }
    if (spans.isEmpty) {
      return MeasuredParagraph(width: width, height: 0, lines: const <MeasuredLine>[]);
    }

    final natural = _layoutOnce(
      spans: spans,
      width: width,
      direction: direction,
      alignment: alignment,
      justify: false,
    );
    final mayJustify = resolveJustification &&
        alignment == PaperAlign.justify &&
        natural.lines.length > 1 &&
        natural.lines.take(natural.lines.length - 1).any(
              (line) => line.justificationOpportunityCount > 0,
            );
    if (!mayJustify) return natural;

    return _layoutOnce(
      spans: spans,
      width: width,
      direction: direction,
      alignment: alignment,
      justify: true,
      naturalLines: natural.lines,
    );
  }

  MeasuredParagraph _layoutOnce({
    required List<MetricSpan> spans,
    required double width,
    required DocumentDirection direction,
    required PaperAlign? alignment,
    required bool justify,
    List<MeasuredLine>? naturalLines,
  }) {
    final children = <InlineSpan>[];
    final placeholderDimensions = <PlaceholderDimensions>[];
    final spanRanges = <({int start, int end, int spanIndex})>[];
    var offset = 0;

    for (var index = 0; index < spans.length; index++) {
      final span = spans[index];
      if (span.text.isEmpty && !span.isMath && !span.isFixedAdvance) continue;
      final style = _textStyle(span.style);
      final start = offset;
      if (span.isMath || span.isFixedAdvance) {
        final box = span.mathBox;
        final widthPt = span.fixedAdvancePt ??
            box?.widthPt ?? _fallbackMathWidth(span);
        final heightPt = span.isFixedAdvance
            ? 0.1
            : box?.heightPt ?? span.style.fontSizePt;
        final widthPx = LayoutUnits.ptToPx(widthPt);
        final heightPx = LayoutUnits.ptToPx(heightPt);
        final baselinePx = LayoutUnits.ptToPx(
          span.isFixedAdvance
              ? heightPt
              : box?.baselinePt ?? (box?.heightPt ?? span.style.fontSizePt),
        );
        children.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            style: style,
            child: SizedBox(width: widthPx, height: heightPx),
          ),
        );
        placeholderDimensions.add(
          PlaceholderDimensions(
            size: ui.Size(widthPx, heightPx),
            alignment: ui.PlaceholderAlignment.baseline,
            baseline: ui.TextBaseline.alphabetic,
            baselineOffset: baselinePx,
          ),
        );
        // Keep UTF-16 offsets aligned with toPlainText(includePlaceholders: true).
        offset += 1; // TextPainter's object-replacement character.
      } else {
        children.add(TextSpan(text: span.text, style: style));
        offset += span.text.length;
      }
      spanRanges.add((start: start, end: offset, spanIndex: index));
    }

    if (children.isEmpty) {
      return MeasuredParagraph(width: width, height: 0, lines: const <MeasuredLine>[]);
    }

    final painter = TextPainter(
      text: TextSpan(children: children),
      textDirection: _textDirection(direction),
      textAlign: _textAlign(alignment, justify: justify),
      textScaler: TextScaler.noScaling,
      textHeightBehavior: const TextHeightBehavior(
        applyHeightToFirstAscent: true,
        applyHeightToLastDescent: true,
      ),
    );
    painter.setPlaceholderDimensions(placeholderDimensions);
    painter.layout(maxWidth: LayoutUnits.ptToPx(width));
    final plainText = painter.text!.toPlainText(includePlaceholders: true);

    try {
      final lineMetrics = painter.computeLineMetrics();
      if (lineMetrics.isEmpty) {
        return MeasuredParagraph(width: width, height: 0, lines: const <MeasuredLine>[]);
      }

      final fragmentsByLine = List<List<MeasuredRunFragment>>.generate(
        lineMetrics.length,
        (_) => <MeasuredRunFragment>[],
      );
      for (final range in spanRanges) {
        final span = spans[range.spanIndex];
        if (range.end <= range.start) continue;
        final ranges = span.isMath || span.isFixedAdvance
            ? <({int start, int end})>[(start: range.start, end: range.end)]
            : _wordRanges(painter, range.start, range.end);
        for (final textRange in ranges) {
          if (textRange.end <= textRange.start) continue;
          if (!span.isMath && !span.isFixedAdvance) {
            final boxes = painter.getBoxesForSelection(
              TextSelection(baseOffset: textRange.start, extentOffset: textRange.end),
              boxHeightStyle: ui.BoxHeightStyle.strut,
              boxWidthStyle: ui.BoxWidthStyle.tight,
            );
            if (boxes.isEmpty) continue;
            final sourceText = _textForRange(span, range, textRange);
            final splitVisualRuns = boxes.length != 1 ||
                (boxes.single.direction == ui.TextDirection.ltr &&
                    _containsArabic(sourceText));
            if (!splitVisualRuns) {
              final box = boxes.single;
              final lineIndex = _lineForBox(box, lineMetrics);
              final metric = lineMetrics[lineIndex];
              fragmentsByLine[lineIndex].add(
                MeasuredRunFragment(
                  spanIndex: range.spanIndex,
                  text: sourceText,
                  startOffset: textRange.start - range.start,
                  endOffset: textRange.end - range.start,
                  x: LayoutUnits.pxToPt(box.left),
                  width: LayoutUnits.pxToPt(box.right - box.left),
                  direction: _documentDirection(box.direction),
                  baselineOffset: LayoutUnits.pxToPt(metric.baseline - box.top),
                  height: LayoutUnits.pxToPt(box.bottom - box.top),
                  mathBox: span.mathBox,
                ),
              );
              continue;
            }

            // A mixed selection can return several visual TextBoxes. Reusing
            // the whole selection text for each box duplicates content and
            // assigns the wrong direction to at least one copy. Recover source
            // ranges per Unicode scalar, then coalesce adjacent scalars that
            // belong to the same visual direction/run.
            for (final fragment in _directionalTextFragments(
              painter,
              plainText,
              textRange.start,
              textRange.end,
              lineMetrics,
            )) {
              final metric = lineMetrics[fragment.lineIndex];
              fragmentsByLine[fragment.lineIndex].add(
                MeasuredRunFragment(
                  spanIndex: range.spanIndex,
                  text: _textForRange(
                    span,
                    range,
                    (start: fragment.startOffset, end: fragment.endOffset),
                  ),
                  startOffset: fragment.startOffset - range.start,
                  endOffset: fragment.endOffset - range.start,
                  x: LayoutUnits.pxToPt(fragment.left),
                  width: LayoutUnits.pxToPt(fragment.right - fragment.left),
                  direction: fragment.direction,
                  baselineOffset: LayoutUnits.pxToPt(metric.baseline - fragment.top),
                  height: LayoutUnits.pxToPt(fragment.bottom - fragment.top),
                  mathBox: span.mathBox,
                ),
              );
            }
            continue;
          }

          final boxes = painter.getBoxesForSelection(
            TextSelection(baseOffset: textRange.start, extentOffset: textRange.end),
            boxHeightStyle: ui.BoxHeightStyle.strut,
            boxWidthStyle: ui.BoxWidthStyle.tight,
          );
          for (final box in boxes) {
            final lineIndex = _lineForBox(box, lineMetrics);
            final metric = lineMetrics[lineIndex];
            fragmentsByLine[lineIndex].add(
              MeasuredRunFragment(
                spanIndex: range.spanIndex,
                text: span.isMath ? span.text : '',
                startOffset: textRange.start - range.start,
                endOffset: textRange.end - range.start,
                x: LayoutUnits.pxToPt(box.left),
                width: LayoutUnits.pxToPt(box.right - box.left),
                direction: _documentDirection(box.direction),
                baselineOffset: LayoutUnits.pxToPt(
                  metric.baseline - box.top,
                ),
                height: LayoutUnits.pxToPt(box.bottom - box.top),
                mathBox: span.mathBox,
                fixedAdvancePt: span.fixedAdvancePt,
              ),
            );
          }
        }
      }

      final lines = <MeasuredLine>[];
      for (var index = 0; index < lineMetrics.length; index++) {
        final metric = lineMetrics[index];
        final naturalMetric = naturalLines != null && index < naturalLines.length
            ? naturalLines[index]
            : null;
        final fragments = fragmentsByLine[index]
          ..sort((a, b) => a.x.compareTo(b.x));
        final opportunities = _breakableSpaceCount(fragments);
        final isJustified = justify &&
            index < lineMetrics.length - 1 &&
            opportunities > 0;
        final resolvedWidth = LayoutUnits.pxToPt(metric.width);
        final naturalWidth = naturalMetric?.naturalWidth ?? resolvedWidth;
        final extra = isJustified && opportunities > 0
            ? ((resolvedWidth - naturalWidth) / opportunities)
                .clamp(0.0, double.infinity)
                .toDouble()
            : 0.0;
        lines.add(
          MeasuredLine(
            index: index,
            top: LayoutUnits.pxToPt(metric.baseline - metric.ascent),
            baseline: LayoutUnits.pxToPt(metric.baseline),
            ascent: LayoutUnits.pxToPt(metric.ascent),
            descent: LayoutUnits.pxToPt(metric.descent),
            leading: LayoutUnits.pxToPt(
              metric.height - metric.ascent - metric.descent,
            ),
            height: LayoutUnits.pxToPt(metric.height),
            naturalWidth: naturalWidth,
            resolvedWidth: resolvedWidth,
            isJustified: isJustified,
            justificationOpportunityCount: isJustified ? opportunities : 0,
            extraSpacePerOpportunity: extra,
            fragments: List<MeasuredRunFragment>.unmodifiable(fragments),
          ),
        );
      }
      final height = LayoutUnits.pxToPt(painter.height);
      return MeasuredParagraph(
        width: width,
        height: height,
        lines: List<MeasuredLine>.unmodifiable(lines),
      );
    } finally {
      painter.dispose();
    }
  }

  List<({int start, int end})> _wordRanges(TextPainter painter, int start, int end) {
    final ranges = <({int start, int end})>[];
    final plainText = painter.text!.toPlainText(includePlaceholders: true);
    var cursor = start;
    while (cursor < end) {
      final boundary = painter.getWordBoundary(TextPosition(offset: cursor));
      var rangeStart = boundary.start.clamp(start, end).toInt();
      var rangeEnd = boundary.end.clamp(start, end).toInt();
      if (rangeEnd <= cursor || rangeStart > cursor) {
        // The position is a boundary/space/object: move by one Unicode scalar
        // without splitting surrogate pairs. NBSP is not a break point.
        rangeStart = cursor;
        final first = plainText.codeUnitAt(cursor);
        rangeEnd =
            (cursor + ((first >= 0xD800 && first <= 0xDBFF) ? 2 : 1))
                .clamp(start, end)
                .toInt();
      }
      if (rangeEnd <= cursor) break;
      ranges.add((start: rangeStart, end: rangeEnd));
      cursor = rangeEnd;
    }
    return _coalesceNonbreakingSpaceRanges(ranges, plainText);
  }

  List<({int start, int end})> _coalesceNonbreakingSpaceRanges(
    List<({int start, int end})> ranges,
    String text,
  ) {
    if (ranges.length < 2) return ranges;
    final merged = <({int start, int end})>[];
    for (final range in ranges) {
      if (merged.isEmpty) {
        merged.add(range);
        continue;
      }
      final previous = merged.last;
      final gapEnd = range.start.clamp(previous.end, text.length).toInt();
      final hasJoiner = previous.end <= gapEnd &&
          text.substring(previous.end, gapEnd).runes.any(_isNonbreakingSpace);
      final touchesJoiner =
          (previous.end > previous.start &&
              _isNonbreakingSpace(text.codeUnitAt(previous.end - 1))) ||
          (range.start < text.length &&
              _isNonbreakingSpace(text.codeUnitAt(range.start)));
      if (hasJoiner || touchesJoiner) {
        merged[merged.length - 1] = (start: previous.start, end: range.end);
      } else {
        merged.add(range);
      }
    }
    return merged;
  }

  bool _isNonbreakingSpace(int codePoint) =>
      codePoint == 0x00A0 ||
      codePoint == 0x202F ||
      codePoint == 0xFEFF ||
      codePoint == 0x2060;

  bool _containsArabic(String text) => text.runes.any((rune) =>
      (rune >= 0x0600 && rune <= 0x08FF) ||
      (rune >= 0xFB50 && rune <= 0xFEFF) ||
      (rune >= 0x10E60 && rune <= 0x10E7F) ||
      (rune >= 0x1EC70 && rune <= 0x1EEFF));

  String _textForRange(
    MetricSpan span,
    ({int start, int end, int spanIndex}) spanRange,
    ({int start, int end}) range,
  ) {
    final relativeStart = range.start - spanRange.start;
    final relativeEnd = range.end - spanRange.start;
    if (relativeStart < 0 || relativeEnd > span.text.length) return span.text;
    return span.text.substring(relativeStart, relativeEnd);
  }

  List<_DirectionalTextFragment> _directionalTextFragments(
    TextPainter painter,
    String text,
    int start,
    int end,
    List<ui.LineMetrics> lineMetrics,
  ) {
    final fragments = <_DirectionalTextFragment>[];
    _DirectionalTextFragment? current;
    var offset = start;
    while (offset < end) {
      final unit = text.codeUnitAt(offset);
      final isHighSurrogate = unit >= 0xD800 && unit <= 0xDBFF;
      final hasLowSurrogate = offset + 1 < end &&
          text.codeUnitAt(offset + 1) >= 0xDC00 &&
          text.codeUnitAt(offset + 1) <= 0xDFFF;
      final nextOffset = offset + (isHighSurrogate && hasLowSurrogate ? 2 : 1);
      final boxes = painter.getBoxesForSelection(
        TextSelection(baseOffset: offset, extentOffset: nextOffset),
        boxHeightStyle: ui.BoxHeightStyle.strut,
        boxWidthStyle: ui.BoxWidthStyle.tight,
      );
      if (boxes.isEmpty) {
        // Preserve zero-width source characters with the adjacent run without
        // inventing a box or allowing a control character to become a break.
        if (current != null && current.endOffset == offset) {
          current.endOffset = nextOffset;
        }
        offset = nextOffset;
        continue;
      }

      // A single Unicode scalar cannot cross a wrapped line. Flutter may
      // return duplicate boxes for a combining sequence, so use one geometry
      // record for its source range and keep the original scalar exactly once.
      final box = boxes.first;
      final lineIndex = _lineForBox(box, lineMetrics);
      final boxDirection = _documentDirection(box.direction);
      if (current != null &&
          current.endOffset == offset &&
          current.lineIndex == lineIndex &&
          current.direction == boxDirection) {
        current
          ..endOffset = nextOffset
          ..include(box);
      } else {
        current = _DirectionalTextFragment(
          startOffset: offset,
          endOffset: nextOffset,
          lineIndex: lineIndex,
          direction: boxDirection,
          box: box,
        );
        fragments.add(current);
      }
      offset = nextOffset;
    }
    return fragments;
  }

  int _lineForBox(ui.TextBox box, List<ui.LineMetrics> lines) {
    final centerY = (box.top + box.bottom) * 0.5;
    var nearest = 0;
    var distance = double.infinity;
    for (var index = 0; index < lines.length; index++) {
      final lineCenter = lines[index].baseline - (lines[index].ascent - lines[index].descent) * 0.5;
      final candidate = (centerY - lineCenter).abs();
      if (candidate < distance) {
        nearest = index;
        distance = candidate;
      }
    }
    return nearest;
  }

  int _breakableSpaceCount(Iterable<MeasuredRunFragment> fragments) {
    var count = 0;
    for (final fragment in fragments) {
      if (fragment.fixedAdvancePt != null) continue;
      for (final rune in fragment.text.runes) {
        // Unicode White_Space characters that are explicitly nonbreaking are
        // not justification/break opportunities.
        if (_isJustifiableSpace(rune)) count++;
      }
    }
    return count;
  }

  bool _isJustifiableSpace(int rune) => switch (rune) {
        0x20 || 0x09 => true,
        0x00A0 || 0x202F || 0xFEFF => false,
        0x1680 || 0x2000 || 0x2001 || 0x2002 || 0x2003 || 0x2004 ||
        0x2005 || 0x2006 || 0x2008 || 0x2009 || 0x200A || 0x205F || 0x3000 => true,
        _ => false,
      };

  double _fallbackMathWidth(MetricSpan span) =>
      (span.text.runes.length * span.style.fontSizePt * 0.62)
          .clamp(
            span.style.fontSizePt * 0.5,
            4 * span.style.fontSizePt,
          )
          .toDouble();

  TextStyle _textStyle(LayoutTextStyle style) => TextStyle(
        fontFamily: style.font.family,
        fontSize: LayoutUnits.ptToPx(style.fontSizePt),
        fontWeight: style.bold ? FontWeight.w700 : FontWeight.w400,
        fontStyle: style.italic ? FontStyle.italic : FontStyle.normal,
        decoration: style.underline ? TextDecoration.underline : TextDecoration.none,
        color: style.colorArgb == null ? const Color(0xFF000000) : Color(style.colorArgb!),
        height: style.lineHeightFactor,
        letterSpacing: style.letterSpacingPt == null
            ? null
            : LayoutUnits.ptToPx(style.letterSpacingPt!),
      );

  ui.TextDirection _textDirection(DocumentDirection direction) =>
      direction == DocumentDirection.ltr ? ui.TextDirection.ltr : ui.TextDirection.rtl;

  DocumentDirection _documentDirection(ui.TextDirection direction) =>
      direction == ui.TextDirection.ltr ? DocumentDirection.ltr : DocumentDirection.rtl;

  TextAlign _textAlign(PaperAlign? alignment, {required bool justify}) {
    if (justify) return TextAlign.justify;
    return switch (alignment) {
      PaperAlign.center => TextAlign.center,
      PaperAlign.end => TextAlign.end,
      PaperAlign.left => TextAlign.left,
      PaperAlign.right => TextAlign.right,
      PaperAlign.justify || PaperAlign.start || null => TextAlign.start,
    };
  }
}

class _DirectionalTextFragment {
  _DirectionalTextFragment({
    required this.startOffset,
    required this.endOffset,
    required this.lineIndex,
    required this.direction,
    required ui.TextBox box,
  })  : left = box.left,
        right = box.right,
        top = box.top,
        bottom = box.bottom;

  final int startOffset;
  int endOffset;
  final int lineIndex;
  final DocumentDirection direction;
  double left;
  double right;
  double top;
  double bottom;

  void include(ui.TextBox box) {
    if (box.left < left) left = box.left;
    if (box.right > right) right = box.right;
    if (box.top < top) top = box.top;
    if (box.bottom > bottom) bottom = box.bottom;
  }
}
