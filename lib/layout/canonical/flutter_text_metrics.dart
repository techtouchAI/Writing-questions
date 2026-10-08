import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter/widgets.dart'
    show PlaceholderAlignment, SizedBox, TextBaseline, TextSelection, WidgetSpan;

import '../../models/paper_font.dart';
import '../../models/paper_text_style.dart';
import '../document_direction.dart';
import 'font_metrics.dart';
import 'layout_document.dart';
import 'layout_units.dart';

/// Flutter paragraph engine adapter for P2 measurement.
///
/// `TextPainter` is intentionally confined to this adapter. It performs font
/// shaping, Unicode line breaking, paragraph bidi and line metrics. Canonical
/// justification adjusts its measured run boxes here, before primitive
/// point-space geometry escapes this class.
class FlutterTextMetrics implements FontMetricsProvider {
  const FlutterTextMetrics();

  static Future<void>? _fontRegistration;
  static bool _fontsReady = false;

  /// Register the same application font files used by PDF before TextPainter
  /// measures canonical runs. This is normally satisfied by the preview's
  /// first paint, but exports and headless tests may resolve layout directly.
  ///
  /// Once registration has actually completed, late callers receive a fresh
  /// already-completed future instead of re-awaiting the memoized one: a
  /// continuation on the memoized future is scheduled in whatever zone
  /// completed it, which strands callers awaiting from another zone. The
  /// fresh future preserves the await boundary with identical ordering.
  static Future<void> ensureFontsLoaded() => _fontsReady
      ? Future<void>.value()
      : (_fontRegistration ??= _registerFonts());

  /// Resolve source-ordered directional runs with Flutter's Unicode bidi
  /// shaping, keeping every source code unit (including neutral punctuation,
  /// whitespace, combining marks, and controls) exactly once. Export adapters
  /// may consume these directions, but must not use the result to reflow or
  /// paginate content.
  static List<({String text, DocumentDirection direction})> resolveDirectionalRuns(
    String text, {
    required DocumentDirection fallbackDirection,
  }) {
    if (text.isEmpty) return const [];
    final painter = TextPainter(
      text: TextSpan(text: text),
      textDirection: fallbackDirection == DocumentDirection.rtl
          ? ui.TextDirection.rtl
          : ui.TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout(maxWidth: double.infinity);
    try {
      final lines = painter.computeLineMetrics();
      if (lines.isEmpty) {
        return <({String text, DocumentDirection direction})>[
          (text: text, direction: fallbackDirection),
        ];
      }
      final fragments = const FlutterTextMetrics()._directionalTextFragments(
        painter,
        text,
        0,
        text.length,
        lines,
      );
      if (fragments.isEmpty) {
        return <({String text, DocumentDirection direction})>[
          (text: text, direction: fallbackDirection),
        ];
      }

      final resolved = <({String text, DocumentDirection direction})>[];
      var coveredUntil = 0;
      DocumentDirection? precedingDirection;
      void append(int start, int end, DocumentDirection direction) {
        if (end <= start) return;
        final piece = text.substring(start, end);
        if (resolved.isNotEmpty && resolved.last.direction == direction) {
          final previous = resolved.removeLast();
          resolved.add((text: '${previous.text}$piece', direction: direction));
        } else {
          resolved.add((text: piece, direction: direction));
        }
        precedingDirection = direction;
      }

      for (final fragment in fragments) {
        final start =
            fragment.startOffset.clamp(coveredUntil, text.length).toInt();
        final end = fragment.endOffset.clamp(start, text.length).toInt();
        if (start > coveredUntil) {
          append(
            coveredUntil,
            start,
            precedingDirection ?? fragment.direction,
          );
        }
        append(start, end, fragment.direction);
        if (end > coveredUntil) coveredUntil = end;
      }
      if (coveredUntil < text.length) {
        append(
          coveredUntil,
          text.length,
          precedingDirection ?? fallbackDirection,
        );
      }
      return List<({String text, DocumentDirection direction})>.unmodifiable(
        resolved,
      );
    } finally {
      painter.dispose();
    }
  }

  static Future<void> _registerFonts() async {
    for (final font in PaperFont.values) {
      final loader = FontLoader(font.family)
        ..addFont(rootBundle.load(font.regularAsset));
      if (font.hasBoldWeight && font.boldAsset != font.regularAsset) {
        loader.addFont(rootBundle.load(font.boldAsset));
      }
      try {
        await loader.load();
      } catch (_) {
        if (font == PaperFont.naskh) rethrow;
        // Optional families retain the existing Naskh fallback when an asset
        // is unavailable; the required regular family must be measurable.
      }
    }
    _fontsReady = true;
  }

  @override
  String get backendId => 'flutter-text-painter-pt-v5';

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

    // Auto-direction inline content can be an all-LTR paragraph inside an RTL
    // document (for example, an English identifier around an equation). Use
    // its strong text to resolve shaping order, while preserving the block
    // direction for start/end alignment and pagination.
    final bidiDirection = _bidiDirectionFor(spans, direction);
    return _layoutOnce(
      spans: spans,
      width: width,
      direction: direction,
      bidiDirection: bidiDirection,
      alignment: alignment,
      justify: resolveJustification && alignment == PaperAlign.justify,
    );
  }

  MeasuredParagraph _layoutOnce({
    required List<MetricSpan> spans,
    required double width,
    required DocumentDirection direction,
    required DocumentDirection bidiDirection,
    required PaperAlign? alignment,
    required bool justify,
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
      textDirection: _textDirection(bidiDirection),
      // TextPainter owns wrapping and bidi boxes. Justification is applied to
      // those canonical boxes below so run positions remain renderer-neutral.
      textAlign: _textAlign(alignment),
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
      final baselineOffsets = <(int, DocumentDirection), double>{};
      double runBaselineOffset(int spanIndex, DocumentDirection runDirection) {
        final key = (spanIndex, runDirection);
        return baselineOffsets.putIfAbsent(key, () {
          final span = spans[spanIndex];
          // PDF paints every canonical run as a one-line text widget. Measure
          // that widget's natural baseline centrally, then align it to the
          // paragraph baseline. Selection-box tops vary with glyph bounds and
          // are not a stable per-run baseline (notably across Arabic words).
          return measureText(
            span.text,
            span.style.copyWith(lineHeightFactor: 1),
            runDirection,
          ).baseline;
        });
      }
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
              final runBounds = _caretBounds(
                painter,
                textRange.start,
                textRange.end,
                fallbackLeft: box.left,
                fallbackRight: box.right,
              );
              final runDirection = _documentDirection(box.direction);
              fragmentsByLine[lineIndex].add(
                MeasuredRunFragment(
                  spanIndex: range.spanIndex,
                  text: sourceText,
                  startOffset: textRange.start - range.start,
                  endOffset: textRange.end - range.start,
                  x: LayoutUnits.pxToPt(runBounds.left),
                  width: LayoutUnits.pxToPt(runBounds.right - runBounds.left),
                  direction: runDirection,
                  baselineOffset: runBaselineOffset(
                    range.spanIndex,
                    runDirection,
                  ),
                  height: LayoutUnits.pxToPt(box.bottom - box.top),
                  words: _measureWords(
                    painter,
                    plainText.substring(textRange.start, textRange.end),
                    textRange.start,
                    runBounds.left,
                    runBounds.right,
                    runDirection,
                  ),
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
              final runBounds = _caretBounds(
                painter,
                fragment.startOffset,
                fragment.endOffset,
                fallbackLeft: fragment.left,
                fallbackRight: fragment.right,
              );
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
                  x: LayoutUnits.pxToPt(runBounds.left),
                  width: LayoutUnits.pxToPt(runBounds.right - runBounds.left),
                  direction: fragment.direction,
                  baselineOffset: runBaselineOffset(
                    range.spanIndex,
                    fragment.direction,
                  ),
                  height: LayoutUnits.pxToPt(fragment.bottom - fragment.top),
                  words: _measureWords(
                    painter,
                    plainText.substring(
                      fragment.startOffset,
                      fragment.endOffset,
                    ),
                    fragment.startOffset,
                    runBounds.left,
                    runBounds.right,
                    fragment.direction,
                  ),
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
                // Placeholders are boxes, not shaped text: no measurable words.
                words: const <LayoutWord>[],
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
        final fragments = fragmentsByLine[index]
          ..sort((a, b) => a.x.compareTo(b.x));
        final opportunities =
            _breakableSpaceCount(fragments, plainText, spanRanges);
        final naturalWidth = LayoutUnits.pxToPt(metric.width);
        final eligibleForJustification = justify &&
            index < lineMetrics.length - 1 &&
            opportunities > 0;
        final extra = eligibleForJustification
            ? ((width - naturalWidth) / opportunities)
                .clamp(0.0, double.infinity)
                .toDouble()
            : 0.0;
        final isJustified = eligibleForJustification && extra > 0.01;
        final directionResolvedFragments = _resolveInlineMathDirection(
          fragments,
          plainText,
          spanRanges,
          spans,
        );
        final resolvedWidth = isJustified ? width : naturalWidth;
        final measuredFragments = isJustified
            ? _expandJustifiedFragments(
                directionResolvedFragments,
                plainText,
                spanRanges,
                bidiDirection,
                extra,
              )
            : directionResolvedFragments;
        final alignmentOffset = _alignmentOffsetPt(
          alignment: alignment,
          direction: direction,
          paragraphWidthPt: width,
          fragments: measuredFragments,
          justified: isJustified,
        );
        final positionedFragments = alignmentOffset == 0
            ? measuredFragments
            : <MeasuredRunFragment>[
                for (final fragment in measuredFragments)
                  _translateFragment(fragment, alignmentOffset),
              ];
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
            fragments: List<MeasuredRunFragment>.unmodifiable(positionedFragments),
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
    return _coalesceCurrencyRanges(
      _coalesceNonbreakingSpaceRanges(
        _coalescePeriodRanges(ranges, plainText),
        plainText,
      ),
      plainText,
    );
  }

  /// Keep generated dotted blanks as a single unbreakable visual token. ICU
  /// may report each adjacent full stop as its own word boundary; splitting
  /// them would produce a column of one-dot runs and make the placeholder
  /// wrap despite having no legal break opportunity.
  List<({int start, int end})> _coalescePeriodRanges(
    List<({int start, int end})> ranges,
    String text,
  ) {
    if (ranges.length < 2) return ranges;
    bool isPeriodRun(({int start, int end}) range) =>
        text.substring(range.start, range.end).runes.every((rune) => rune == 0x2e);

    final merged = <({int start, int end})>[];
    for (final range in ranges) {
      if (merged.isEmpty) {
        merged.add(range);
        continue;
      }
      final previous = merged.last;
      if (previous.end == range.start &&
          isPeriodRun(previous) &&
          isPeriodRun(range)) {
        merged[merged.length - 1] = (start: previous.start, end: range.end);
      } else {
        merged.add(range);
      }
    }
    return merged;
  }

  /// Keep a literal `$` glued to a following amount or identifier. ICU word
  /// segmentation isolates `$` (currency symbols join no word class per
  /// UAX #29), which would split an escaped dollar `$5` into `$` | `5`
  /// runs and break the source-offset map across the removed slash.
  /// [_wordRanges] only processes non-math spans (math and fixed-advance
  /// spans bypass it), so every `$` here is a literal dollar, and
  /// prefix-currency cohesion mirrors UAX #14 (no break between a currency
  /// prefix and its number). Strict adjacency only: `$ 5` stays split.
  List<({int start, int end})> _coalesceCurrencyRanges(
    List<({int start, int end})> ranges,
    String text,
  ) {
    if (ranges.length < 2) return ranges;
    bool startsAmount(({int start, int end}) range) {
      if (range.start >= range.end || range.start >= text.length) {
        return false;
      }
      final rune = text.codeUnitAt(range.start);
      return (rune >= 0x30 && rune <= 0x39) ||
          (rune >= 0x41 && rune <= 0x5A) ||
          (rune >= 0x61 && rune <= 0x7A) ||
          (rune >= 0x0660 && rune <= 0x0669) ||
          (rune >= 0x06F0 && rune <= 0x06F9);
    }

    final merged = <({int start, int end})>[];
    for (final range in ranges) {
      if (merged.isEmpty) {
        merged.add(range);
        continue;
      }
      final previous = merged.last;
      if (previous.end == range.start &&
          previous.end > previous.start &&
          text.codeUnitAt(previous.end - 1) == 0x24 &&
          startsAmount(range)) {
        merged[merged.length - 1] = (start: previous.start, end: range.end);
      } else {
        merged.add(range);
      }
    }
    return merged;
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

  DocumentDirection _bidiDirectionFor(
    List<MetricSpan> spans,
    DocumentDirection fallback,
  ) {
    final explicit = spans
        .map((span) => span.direction)
        .where((direction) =>
            direction == DocumentDirection.ltr ||
            direction == DocumentDirection.rtl)
        .toSet();
    if (explicit.isNotEmpty) {
      final hasAutomatic = spans.any((span) =>
          span.direction == DocumentDirection.auto ||
          span.direction == DocumentDirection.inherit);
      if (explicit.length == 1 && !hasAutomatic) return explicit.single;
      return fallback;
    }

    final sourceText = spans
        .where((span) => !span.isMath && !span.isFixedAdvance)
        .map((span) => span.text)
        .join();
    if (_containsArabic(sourceText)) return fallback;
    if (_containsStrongLtr(sourceText)) return DocumentDirection.ltr;
    return fallback;
  }

  bool _containsStrongLtr(String text) => text.runes.any((rune) =>
      (rune >= 0x0030 && rune <= 0x0039) ||
      (rune >= 0x0041 && rune <= 0x005A) ||
      (rune >= 0x0061 && rune <= 0x007A) ||
      (rune >= 0x00C0 && rune <= 0x02FF) ||
      (rune >= 0x0370 && rune <= 0x058F));

  bool _containsArabic(String text) => text.runes.any((rune) =>
      (rune >= 0x0590 && rune <= 0x05FF) ||
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

  /// Word geometry inside one measured fragment, resolved with the same
  /// [_caretBounds] machinery as the fragment box so words and their run can
  /// never disagree on positions. [fragmentText] is the fragment's exact
  /// laid-out paragraph slice and [baseOffset] its paragraph-absolute UTF-16
  /// start, so word boundaries index the string the painter shaped. Words
  /// split on ASCII whitespace — the same word notion the PDF emitter uses —
  /// and pitches close exactly: every non-last word advances to the next
  /// word's [x], and the last word ends at the fragment's trailing edge
  /// ([fragmentLeftPx]/[fragmentRightPx] selected by [direction]). Within a
  /// single-direction fragment, word edges are monotonic along the visual
  /// axis, so the absolute pitch never masks disorder. Each word also
  /// carries its own shaped text advance (the caret interval width, never
  /// reaching into the following space): the width a positioned emitter
  /// executes, so gaps stay out of advances.
  List<LayoutWord> _measureWords(
    TextPainter painter,
    String fragmentText,
    int baseOffset,
    double fragmentLeftPx,
    double fragmentRightPx,
    DocumentDirection direction,
  ) {
    final matches = canonicalWordPattern
        .allMatches(fragmentText)
        .toList(growable: false);
    if (matches.isEmpty) return const <LayoutWord>[];
    final startsPx = List<double>.filled(matches.length, 0);
    final textPx = List<double>.filled(matches.length, 0);
    for (var index = 0; index < matches.length; index++) {
      final match = matches[index];
      final bounds = _caretBounds(
        painter,
        baseOffset + match.start,
        baseOffset + match.end,
        fallbackLeft: fragmentLeftPx,
        fallbackRight: fragmentRightPx,
      );
      startsPx[index] = bounds.left;
      textPx[index] = bounds.right - bounds.left;
    }
    final trailingPx =
        direction == DocumentDirection.ltr ? fragmentRightPx : fragmentLeftPx;
    final words = <LayoutWord>[];
    for (var index = 0; index < matches.length; index++) {
      final nextPx =
          index + 1 < matches.length ? startsPx[index + 1] : trailingPx;
      words.add(LayoutWord(
        text: matches[index].group(0)!,
        x: LayoutUnits.pxToPt(startsPx[index]),
        advance: LayoutUnits.pxToPt((nextPx - startsPx[index]).abs()),
        textAdvance: LayoutUnits.pxToPt(textPx[index]),
      ));
    }
    return words;
  }

  /// Selection boxes with `BoxWidthStyle.tight` describe glyph ink and can
  /// omit side-bearing advances. Use the shaped caret interval for a run's
  /// canonical box so a painter can position the run without consuming the
  /// neighboring word-space.
  ({double left, double right}) _caretBounds(
    TextPainter painter,
    int start,
    int end, {
    required double fallbackLeft,
    required double fallbackRight,
  }) {
    if (end <= start) return (left: fallbackLeft, right: fallbackRight);
    final startCaret = painter.getOffsetForCaret(
      TextPosition(offset: start),
      ui.Rect.zero,
    );
    final endCaret = painter.getOffsetForCaret(
      TextPosition(offset: end),
      ui.Rect.zero,
    );
    final left = startCaret.dx < endCaret.dx ? startCaret.dx : endCaret.dx;
    final right = startCaret.dx > endCaret.dx ? startCaret.dx : endCaret.dx;
    final advance = right - left;
    final selectionWidth = (fallbackRight - fallbackLeft).abs();
    // Neutral punctuation and bidi-boundary carets can straddle unrelated
    // visual runs. Keep the shaped caret interval for normal side-bearing
    // differences, but fall back to this selection's own tight box when the
    // interval is implausibly wider than its glyph ink.
    final maximumPlausibleAdvance =
        selectionWidth * 2 + LayoutUnits.ptToPx(5);
    if (!advance.isFinite ||
        advance <= 0.001 ||
        (selectionWidth > 0.001 && advance > maximumPlausibleAdvance)) {
      return (left: fallbackLeft, right: fallbackRight);
    }
    return (left: left, right: right);
  }

  List<MeasuredRunFragment> _resolveInlineMathDirection(
    List<MeasuredRunFragment> fragments,
    String plainText,
    List<({int start, int end, int spanIndex})> spanRanges,
    List<MetricSpan> spans,
  ) {
    final rangesBySpan = <int, ({int start, int end, int spanIndex})>{
      for (final range in spanRanges) range.spanIndex: range,
    };
    final resolved = List<MeasuredRunFragment>.of(fragments);
    final mathLocations = resolved
        .where((fragment) => spans[fragment.spanIndex].isMath)
        .map((fragment) => (
              spanIndex: fragment.spanIndex,
              startOffset: fragment.startOffset,
              endOffset: fragment.endOffset,
            ))
        .toList(growable: false);

    int sourceStart(MeasuredRunFragment fragment) =>
        rangesBySpan[fragment.spanIndex]!.start + fragment.startOffset;
    int sourceEnd(MeasuredRunFragment fragment) =>
        rangesBySpan[fragment.spanIndex]!.start + fragment.endOffset;

    for (final location in mathLocations) {
      final mathIndex = resolved.indexWhere((fragment) =>
          fragment.spanIndex == location.spanIndex &&
          fragment.startOffset == location.startOffset &&
          fragment.endOffset == location.endOffset &&
          spans[fragment.spanIndex].isMath);
      if (mathIndex < 0) continue;
      final math = resolved[mathIndex];
      final range = rangesBySpan[math.spanIndex];
      if (range == null) continue;
      final mathStart = sourceStart(math);
      final mathEnd = sourceEnd(math);
      final previousCandidates = resolved.where((fragment) {
        final span = spans[fragment.spanIndex];
        return !span.isMath &&
            !span.isFixedAdvance &&
            sourceEnd(fragment) <= mathStart &&
            !_isOnlySpacing(fragment.text);
      }).toList()
        ..sort((a, b) => sourceEnd(a).compareTo(sourceEnd(b)));
      final nextCandidates = resolved.where((fragment) {
        final span = spans[fragment.spanIndex];
        return !span.isMath &&
            !span.isFixedAdvance &&
            sourceStart(fragment) >= mathEnd &&
            !_isOnlySpacing(fragment.text);
      }).toList()
        ..sort((a, b) => sourceStart(a).compareTo(sourceStart(b)));
      if (previousCandidates.isEmpty || nextCandidates.isEmpty) continue;

      final previous = previousCandidates.last;
      final next = nextCandidates.first;
      if (previous.direction != next.direction) continue;
      final runDirection = previous.direction;
      final beforeText = plainText.substring(sourceEnd(previous), mathStart);
      final afterText = plainText.substring(mathEnd, sourceStart(next));
      if (!_isOnlySpacing(beforeText) || !_isOnlySpacing(afterText)) continue;

      final previousSpan = spans[previous.spanIndex];
      final nextSpan = spans[next.spanIndex];
      final beforeGap = _spacingAdvance(
        beforeText,
        previousSpan.style,
        runDirection,
      );
      final afterGap = _spacingAdvance(
        afterText,
        nextSpan.style,
        runDirection,
      );
      final orderIsCorrect = runDirection == DocumentDirection.ltr
          ? previous.x + previous.width <= math.x + 0.25 &&
              math.x + math.width <= next.x + 0.25
          : previous.x >= math.x + math.width - 0.25 &&
              math.x >= next.x + next.width - 0.25;
      if (math.direction == runDirection && orderIsCorrect) continue;

      final targetMathX = runDirection == DocumentDirection.ltr
          ? previous.x + previous.width + beforeGap
          : previous.x - beforeGap - math.width;
      final targetNextX = runDirection == DocumentDirection.ltr
          ? targetMathX + math.width + afterGap
          : targetMathX - afterGap - next.width;
      final tailShift = targetNextX - next.x;
      for (var index = 0; index < resolved.length; index++) {
        final fragment = resolved[index];
        if (index == mathIndex) {
          resolved[index] = _translateFragment(
            fragment,
            targetMathX - fragment.x,
            direction: runDirection,
          );
        } else if (sourceStart(fragment) >= mathEnd) {
          resolved[index] = _translateFragment(fragment, tailShift);
        }
      }
    }
    return resolved;
  }

  bool _isOnlySpacing(String text) =>
      text.runes.every((rune) => _isJustifiableSpace(rune) || _isNonbreakingSpace(rune));

  double _spacingAdvance(
    String text,
    LayoutTextStyle style,
    DocumentDirection direction,
  ) {
    var advance = 0.0;
    for (final rune in text.runes) {
      if (_isJustifiableSpace(rune)) {
        advance += whitespaceAdvance(style, direction);
      } else if (_isNonbreakingSpace(rune)) {
        advance += whitespaceAdvance(style, direction, nonBreaking: true);
      } else {
        return 0;
      }
    }
    return advance;
  }

  List<MeasuredRunFragment> _expandJustifiedFragments(
    List<MeasuredRunFragment> fragments,
    String plainText,
    List<({int start, int end, int spanIndex})> spanRanges,
    DocumentDirection direction,
    double extraSpacePerOpportunity,
  ) {
    final rangesBySpan = <int, ({int start, int end, int spanIndex})>{
      for (final range in spanRanges) range.spanIndex: range,
    };
    var lineStart = plainText.length;
    var lineEnd = 0;
    for (final fragment in fragments) {
      final range = rangesBySpan[fragment.spanIndex];
      if (range == null) continue;
      final start = range.start + fragment.startOffset;
      final end = range.start + fragment.endOffset;
      if (end <= start) continue;
      if (start < lineStart) lineStart = start;
      if (end > lineEnd) lineEnd = end;
    }
    if (lineEnd <= lineStart) return fragments;

    final sign = direction == DocumentDirection.ltr ? 1.0 : -1.0;
    return <MeasuredRunFragment>[
      for (final fragment in fragments)
        _translateFragment(
          fragment,
          sign *
              _breakableSpaceCountBefore(
                plainText,
                lineStart,
                rangesBySpan[fragment.spanIndex] == null
                    ? lineStart
                    : rangesBySpan[fragment.spanIndex]!.start +
                        fragment.startOffset,
              ) *
              extraSpacePerOpportunity,
        ),
    ];
  }

  MeasuredRunFragment _translateFragment(
    MeasuredRunFragment fragment,
    double dx, {
    DocumentDirection? direction,
  }) =>
      MeasuredRunFragment(
        spanIndex: fragment.spanIndex,
        text: fragment.text,
        startOffset: fragment.startOffset,
        endOffset: fragment.endOffset,
        x: fragment.x + dx,
        width: fragment.width,
        direction: direction ?? fragment.direction,
        baselineOffset: fragment.baselineOffset,
        height: fragment.height,
        words: <LayoutWord>[
          for (final word in fragment.words)
            LayoutWord(
              text: word.text,
              x: word.x + dx,
              advance: word.advance,
              textAdvance: word.textAdvance,
            ),
        ],
        mathBox: fragment.mathBox,
        fixedAdvancePt: fragment.fixedAdvancePt,
      );

  int _breakableSpaceCountBefore(String text, int start, int end) {
    if (end <= start) return 0;
    var count = 0;
    for (final rune in text.substring(start, end).runes) {
      if (_isJustifiableSpace(rune)) count++;
    }
    return count;
  }

  int _breakableSpaceCount(
    Iterable<MeasuredRunFragment> fragments,
    String plainText,
    List<({int start, int end, int spanIndex})> spanRanges,
  ) {
    final rangesBySpan = <int, ({int start, int end, int spanIndex})>{
      for (final range in spanRanges) range.spanIndex: range,
    };
    var lineStart = plainText.length;
    var lineEnd = 0;
    for (final fragment in fragments) {
      final range = rangesBySpan[fragment.spanIndex];
      if (range == null) continue;
      final start = range.start + fragment.startOffset;
      final end = range.start + fragment.endOffset;
      if (end <= start) continue;
      if (start < lineStart) lineStart = start;
      if (end > lineEnd) lineEnd = end;
    }
    if (lineEnd <= lineStart) return 0;

    var count = 0;
    for (final rune in plainText.substring(lineStart, lineEnd).runes) {
      // Count opportunities from source text rather than recovered glyph
      // boxes: TextPainter may omit a zero-width box for an ordinary space.
      // Explicit nonbreaking spaces never become justification opportunities.
      if (_isJustifiableSpace(rune)) count++;
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

  TextAlign _textAlign(PaperAlign? alignment) => switch (alignment) {
      PaperAlign.center => TextAlign.center,
      PaperAlign.end => TextAlign.end,
      PaperAlign.left => TextAlign.left,
      PaperAlign.right => TextAlign.right,
      PaperAlign.justify || PaperAlign.start || null => TextAlign.start,
    };

  /// Resolve alignment from the boxes actually returned by TextPainter. Some
  /// Paragraph implementations include an alignment offset in selection boxes
  /// and others leave them line-relative; computing the target from the current
  /// visual bounds avoids either dropping or doubling that offset.
  double _alignmentOffsetPt({
    required PaperAlign? alignment,
    required DocumentDirection direction,
    required double paragraphWidthPt,
    required List<MeasuredRunFragment> fragments,
    required bool justified,
  }) {
    if (justified || fragments.isEmpty) return 0;
    var currentLeft = double.infinity;
    var currentRight = double.negativeInfinity;
    for (final fragment in fragments) {
      if (fragment.x < currentLeft) currentLeft = fragment.x;
      final fragmentRight = fragment.x + fragment.width;
      if (fragmentRight > currentRight) currentRight = fragmentRight;
    }
    final occupiedWidth = (currentRight - currentLeft)
        .clamp(0.0, double.infinity)
        .toDouble();
    final remaining =
        (paragraphWidthPt - occupiedWidth).clamp(0.0, double.infinity).toDouble();
    final alignRight = switch (alignment) {
      PaperAlign.left => false,
      PaperAlign.right => true,
      PaperAlign.center => null,
      PaperAlign.end => direction != DocumentDirection.rtl,
      PaperAlign.start || PaperAlign.justify || null =>
        direction == DocumentDirection.rtl,
    };
    final targetLeft = alignment == PaperAlign.center
        ? remaining / 2
        : alignRight == true
            ? remaining
            : 0.0;
    return targetLeft - currentLeft;
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
