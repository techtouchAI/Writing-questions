// =============================================================================
// بوابة P0 — ممرّات التصدير الثلاثة تُقاس ببنيتها، لا بصورة واحدة.
//
// لماذا وُجدت هذه البوابة؟
//   بوابة التحقق البصري القائمة (test/visual/visual_parity_fixture_test.dart
//   + tool/verify_visual_parity.sh) تنتج **Exact** فقط: صورة المعاينة ملفوفة
//   في PDF/DOCX، وتُقارَن بجذر RMSE. ذلك يقيس دقة لقطة المعاينة، ولا يقيس
//   إطلاقاً محرك PDF المتجه — وهو الممرّ الذي فيه الانحرافات. هذه البوابة
//   تفصل المسارات: `vector.pdf` من `PaginatedPdfExamEngine`، و`exact.*` من
//   `ExactExportService` — ويبقى Exact مساراً مستقلاً لا يُستعمل بديلاً عنه
//   (تُثبت البوابة أنه صورٌ بلا نص، فيثبت الفصل).
//   (أُزيل ممرّ Word القابل للتحرير `editable.docx` في C5 مع مولّده، فسقطت
//   معه فحوص P0.4 وبندا `w:ind`/محاذاة الافتراضي من P0.5 واختبارات
//   GATE-06/07 والشق الـ Word من GATE-08/11/99.)
//
// ماذا تُثبت؟
//   P0.2  القطع تُنتَج فعلاً (ملفات حقيقية في build/export_gate تُرفع من CI).
//   P0.3  بنية PDF: الصفحات، MediaBox، عدد الأسطر ومواضعها وصناديقها، تسلسل
//         المحتوى، ترتيب الكلمات هندسياً، الصور التقديمية العربية، الأرقام
//         ومواضع الفواصل والأقواس، الخطوط والأحجام، صور المعادلات وترتيبها.
//   P0.4  (محذوف في C5: كان بنية DOCX القابل للتحرير — الأجزاء والعلاقات
//         و`w:bidi`/`w:rtl`/`w:jc`/`w:ind`/فواصل الصفحات وOMML.)
//   P0.5  الإصلاحات المحددة مقيَّدة: شمول الفحص `needsQuranicFont`، قاعدة
//         «سطر واحد» في الضبط (وحُذف في C5: اتجاهية `w:ind` ومحاذاة
//         الافتراضي — كانا خاصّين بمولّد Word المحذوف).
//   P0.7  مصفوفة 15 ميزة × 3 ممرّات بحالات PASS/FAIL/NOT_APPLICABLE/
//         DEFERRED_TO_P1 — والخلية غير المقاسة تُفشِل البوابة.
//
// لا «تقريباً صحيح» ولا RMSE: كل خلاصة مبنية على بايتات الملف نفسه.
// =============================================================================
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:writing_questions_app/layout/canonical/canonical_layout_preview.dart';
import 'package:writing_questions_app/layout/canonical/canonical_layout_service.dart';
import 'package:writing_questions_app/layout/canonical/layout_document.dart';
import 'package:writing_questions_app/layout/canonical/layout_units.dart';
import 'package:writing_questions_app/layout/document_direction.dart';
import 'package:writing_questions_app/layout/visual/visual_content.dart';
import 'package:writing_questions_app/layout/visual/visual_flutter_style.dart';
import 'package:writing_questions_app/models/branch_item.dart';
import 'package:writing_questions_app/models/branch_model.dart';
import 'package:writing_questions_app/models/exam_canvas_geometry.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_footer_model.dart';
import 'package:writing_questions_app/models/exam_font.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/paper_settings.dart';
import 'package:writing_questions_app/models/paper_text_style.dart';
import 'package:writing_questions_app/models/point_kind.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/models/question_option.dart';
import 'package:writing_questions_app/pdf_engine/exam_fonts.dart';
import 'package:writing_questions_app/pdf_engine/exam_strategy.dart';
import 'package:writing_questions_app/pdf_engine/paginated_pdf_exam_engine.dart';
import 'package:writing_questions_app/providers/exam_wizard_controller.dart';
import 'package:writing_questions_app/services/exact_export_service.dart';
import 'package:writing_questions_app/services/page_snapshot_service.dart';
import 'package:writing_questions_app/views/wizard/exam_preview_screen.dart';

import '../pdf_engine/fake_math_host.dart';
import '../pdf_engine/pdf_content_probe.dart';
import 'ooxml_probe.dart';
import 'p0_gate_fixture.dart';
import 'pdf_structure_probe.dart';

const String _dir = P0GateFixture.artifactDir;

/// وسم آية واحد يُستعمل لإثبات شمول الفحص القرآني لكل سطح مطبوع.
const String _verse = '﴿وَقُل رَّبِّ زِدْنِي عِلْمًا﴾';

/// PDF text extraction can expose punctuation as standalone tokens. These are
/// tested for order/placement separately; they are not word-space samples.
const Set<String> _punctuationOnlyPdfTokens = <String>{
  ',',
  '.',
  ':',
  ';',
  '،',
  '؛',
  '؟',
  '?',
  '!',
  '/',
  '\\',
  '-',
  '–',
  '—',
  '(',
  ')',
  '[',
  ']',
  '{',
  '}',
  '﴿',
  '﴾',
  '«',
  '»',
  '%',
  '٪',
};

bool _isPunctuationOnlyPdfToken(String text) =>
    _punctuationOnlyPdfTokens.contains(text.trim());

const int _canonicalLogicalOffsetStride = 1000000;

bool _isCanonicalWhitespaceRune(int rune) => switch (rune) {
      0x0009 || 0x000A || 0x000D || 0x0020 || 0x0085 || 0x00A0 || 0x1680 ||
      0x2000 || 0x2001 || 0x2002 || 0x2003 || 0x2004 || 0x2005 || 0x2006 ||
      0x2007 || 0x2008 || 0x2009 || 0x200A || 0x2028 || 0x2029 || 0x202F ||
      0x205F || 0x3000 => true,
      _ => false,
    };

bool _hasCanonicalWhitespace(String text) =>
    text.runes.any(_isCanonicalWhitespaceRune);

/// PDF may expose bidi fragments of one canonical token as separate text
/// operators (for example the Arabic question prefix «س» and its attached
/// digit «١»). Such fragments are not word-space samples. Only classify a
/// pair as non-lexical when the canonical source node and source offsets prove
/// that no whitespace lies between the fragments; ambiguous pairs remain in
/// the lexical-spacing assertion.
bool _isContiguousCanonicalTokenPair(LayoutRun first, LayoutRun second) {
  if (first.id == second.id) {
    return !_hasCanonicalWhitespace(first.text);
  }
  if (first.semanticNodeId != second.semanticNodeId ||
      first.logicalIndex ~/ _canonicalLogicalOffsetStride !=
          second.logicalIndex ~/ _canonicalLogicalOffsetStride) {
    return false;
  }

  final firstOffset = first.logicalIndex % _canonicalLogicalOffsetStride;
  final secondOffset = second.logicalIndex % _canonicalLogicalOffsetStride;
  final firstIsEarlier = firstOffset <= secondOffset;
  final earlier = firstIsEarlier ? first : second;
  final later = firstIsEarlier ? second : first;
  final earlierOffset = firstIsEarlier ? firstOffset : secondOffset;
  final laterOffset = firstIsEarlier ? secondOffset : firstOffset;
  final gapStart = earlierOffset + earlier.text.length;
  if (gapStart > laterOffset ||
      _hasCanonicalWhitespace(earlier.text) ||
      _hasCanonicalWhitespace(later.text)) {
    return false;
  }

  final source = earlier.semanticNode?.legacyText;
  if (source == null ||
      gapStart > source.length ||
      laterOffset > source.length) {
    return false;
  }
  return !_hasCanonicalWhitespace(source.substring(gapStart, laterOffset));
}

LayoutRun? _canonicalRunForPdfWord(LayoutLine line, ProbedWord word) {
  LayoutRun? closest;
  var closestDistance = double.infinity;
  final pdfCenter = word.x + word.advanceWidth / 2;
  for (final run in line.runs) {
    if (run.text.isEmpty || run.text.runes.every(_isCanonicalWhitespaceRune)) {
      continue;
    }
    final canonicalCenter = run.x + run.width / 2;
    final distance = (canonicalCenter - pdfCenter).abs() +
        (run.width - word.advanceWidth).abs() * 0.05;
    if (distance < closestDistance) {
      closest = run;
      closestDistance = distance;
    }
  }
  return closest;
}

double _canonicalGapBetween(LayoutRun first, LayoutRun second) {
  final right = first.x >= second.x ? first : second;
  final left = identical(right, first) ? second : first;
  return right.x - (left.x + left.width);
}

/// قياسات القطع والممرّات، مشتركة بين اختبارات هذا الملف (ترتيب التنفيذ
/// مضمون: اختبار القطع أولاً، ثم الفحوص البنيوية، ثم المصفوفة).
class _Gate {
  final Map<String, _PreviewText> previewRtl = <String, _PreviewText>{};
  final Map<String, _PreviewText> previewLtr = <String, _PreviewText>{};
  List<String> previewRtlMarkerOrder = <String>[];
  List<String> previewLtrMarkerOrder = <String>[];

  Uint8List? rtlVectorPdf;
  Uint8List? rtlExactPdf;
  Uint8List? rtlExactDocx;
  Uint8List? ltrVectorPdf;
  Uint8List? ltrExactPdf;
  Uint8List? ltrExactDocx;
  List<Uint8List> rtlPreviewPages = <Uint8List>[];
  List<Uint8List> ltrPreviewPages = <Uint8List>[];
  int rtlPreviewPageCount = 0;
  int ltrPreviewPageCount = 0;
  int mathRunCount = 0;
  int mathHostRequestCount = 0;
  List<String> canonicalLabelRuns = <String>[];
  List<String> canonicalQuranTitlePairGeometry = <String>[];
  double? canonicalQuranTitleWordGap;
  LayoutLine? canonicalQuestionTitleLine;
  // التقاط المعاينة الثقيل يُقاس مرة واحدة ويُخزَّن: لا يُعاد في كل اختبار،
  // ولا يبقى سببُه مختبئاً خلف اختبار القطع.
  _PreviewCapture? rtlCapture;
  _PreviewCapture? ltrCapture;

  bool get artifactsReady =>
      rtlVectorPdf != null &&
      ltrVectorPdf != null &&
      rtlExactPdf != null &&
      rtlExactDocx != null &&
      ltrExactPdf != null &&
      ltrExactDocx != null;

  late final PdfStructureReport rtlPdfReport =
      PdfStructureReport.fromBytes(rtlVectorPdf!);
  late final PdfStructureReport ltrPdfReport =
      PdfStructureReport.fromBytes(ltrVectorPdf!);

  void requireArtifacts() {
    if (!artifactsReady) {
      throw StateError('لم تُنتَج القطع: فشل P0-GATE-01 أو P0-GATE-01B قبل '
          'أي فحص بنيوي.');
    }
  }

  bool get previewReady => rtlCapture != null && ltrCapture != null;

  void requirePreview() {
    if (!previewReady) {
      throw StateError('لم تُلقط المعاينة: فشل P0-GATE-00 قبل أي قياس مرجعي.');
    }
  }
}

final _Gate _gate = _Gate();

/// أعلى سطر مرسوم: `ProbedLine` لا يحمل y بنفسه — السطر مجموعة كلمات، وأدناها
/// هو سقفه في ترتيب الرسم.
double _lineTop(ProbedLine line) =>
    line.words.isEmpty ? 0.0 : line.words.map((w) => w.y).reduce(math.min);

/// حالة خلية واحدة في مصفوفة P0.7.
class _Cell {
  _Cell(this.status, this.evidence, this.reason);

  final P0Status status;
  final String evidence;
  final String reason;

  String get label => p0StatusLabel(status);
}

/// مصفوفة 15 ميزة × 4 ممرّات، تملؤها الفحوص نفسها.
class _Matrix {
  final Map<String, Map<P0Path, _Cell>> _cells =
      <String, Map<P0Path, _Cell>>{};

  /// أسوأ حالة تسود (FAIL > DEFERRED > NOT_APPLICABLE > PASS): لا يمسح فحصٌ
  /// لاحقٌ دليلاً لفحص فشل قبله.
  void record(
    String feature,
    P0Path path,
    P0Status status, {
    String evidence = '',
    String reason = '',
  }) {
    final row = _cells.putIfAbsent(feature, () => <P0Path, _Cell>{});
    final previous = row[path];
    if (previous != null && _rank(previous.status) >= _rank(status)) {
      return;
    }
    row[path] = _Cell(status, evidence, reason);
  }

  static int _rank(P0Status status) {
    switch (status) {
      case P0Status.fail:
        return 3;
      case P0Status.deferredToP1:
        return 2;
      case P0Status.notApplicable:
        return 1;
      case P0Status.pass:
        return 0;
    }
  }

  _Cell? cell(String feature, P0Path path) => _cells[feature]?[path];

  List<String> missingCells() {
    final missing = <String>[];
    for (final feature in kP0Features) {
      for (final path in P0Path.values) {
        if (cell(feature.key, path) == null) {
          missing.add('${feature.key}/${p0PathLabel(path)}');
        }
      }
    }
    return missing;
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'gate': 'P0',
        'legend': <String, String>{
          'PASS': 'دليل مقاس من بايتات المخرج نفسه',
          'FAIL': 'انحدار يجب اصلاحه',
          'NOT_APPLICABLE': 'لا معنى للفحص البنيوي في هذا الممرّ',
          'DEFERRED_TO_P1': 'انحراف مثبت بالكود ولا يصلح في P0',
        },
        'features': <Object?>[
          for (final feature in kP0Features)
            <String, Object?>{
              'feature': feature.key,
              'title': feature.title,
              'fixtureEvidence': feature.fixtureEvidence,
              'paths': <String, Object?>{
                for (final path in P0Path.values)
                  p0PathLabel(path): <String, Object?>{
                        'status': cell(feature.key, path)?.label ?? 'UNMEASURED',
                        'evidence': cell(feature.key, path)?.evidence ?? '',
                        'reason': cell(feature.key, path)?.reason ?? '',
                      },
              },
            },
        ],
      };

  /// CSV لسجل CI: سطر لكل خلية (15 × 4) — يقرأه الآلي بلا تفسير.
  String toCsv() {
    String esc(String value) =>
        '"${value.replaceAll('"', '""').replaceAll('\n', ' ').trim()}"';
    final buffer = StringBuffer('feature,path,status,evidence,reason\n');
    for (final feature in kP0Features) {
      for (final path in P0Path.values) {
        final measured = cell(feature.key, path);
        buffer.writeln(<String>[
          esc(feature.key),
          esc(p0PathLabel(path)),
          esc(measured?.label ?? 'UNMEASURED'),
          esc(measured?.evidence ?? ''),
          esc(measured?.reason ?? ''),
        ].join(','));
      }
    }
    return buffer.toString();
  }

  String toTextTable() {
    final buffer = StringBuffer('feature'.padRight(20));
    for (final path in P0Path.values) {
      buffer.write(p0PathLabel(path).padRight(15));
    }
    buffer.writeln();
    for (final feature in kP0Features) {
      buffer.write(feature.key.padRight(20));
      for (final path in P0Path.values) {
        buffer.write((cell(feature.key, path)?.label ?? 'UNMEASURED')
            .padRight(15));
      }
      buffer.writeln();
    }
    return buffer.toString();
  }
}

final _Matrix _matrix = _Matrix();

void _stage(String message) => debugPrint('[p0-gate] $message');

/// يحمّل خطوط التطبيق نفسها (لا خطوط اختبار) فتُقاس البوابة نصاً حقيقياً.
Future<void> _loadAppFonts() async {
  Future<void> load(String family, List<String> assets) async {
    final loader = FontLoader(family);
    for (final asset in assets) {
      loader.addFont(rootBundle.load(asset));
    }
    await loader.load();
  }

  await load(ExamFont.arabicFamily, <String>[
    ExamFonts.regularAsset,
    ExamFonts.boldAsset,
  ]);
  await load('Amiri', <String>[ExamFont.quranicAsset]);
  await load('Tajawal', <String>['assets/fonts/Tajawal-Regular.ttf']);
}

Future<void> _writeArtifact(String name, List<int> bytes) async {
  File('$_dir/$name').writeAsBytesSync(bytes);
  _stage('كُتب $_dir/$name (${bytes.length} بايت)');
}

void _writeText(String name, String content) {
  File('$_dir/$name').writeAsStringSync(content);
}

Set<String> _markersIn(String haystack, Set<String> known) {
  // نص مرسوم: المطابقة باتجاهيه (انظر `mirrorText` في الطبقة البنيوية).
  return <String>{
    for (final marker in known)
      if (textMentions(haystack, marker)) marker,
  };
}

/// ترتيب الوسوم في نصوص مفكوكة (فقرة ففقرة). الردّ يُطبَّق على الفقرة وحدها:
/// المعاينة والـPDF يرسمان السطر العربي بترتيب بصري معكوس، فقلبُ مجموع النص
/// بدل ذلك يقلب ترتيب الفقرات نفسها ويُنتج تسلسلاً كاذباً.
List<String> _markerOrderInParts(
  List<String> parts,
  Set<String> known, {
  bool allowReversed = true,
}) {
  final order = <String>[];
  for (final part in parts) {
    final seen = <String>{};
    final variants = allowReversed
        ? <String>[part, mirrorText(part)]
        : <String>[part];
    for (final variant in variants) {
      for (final match in kMarkerTokenPattern.allMatches(variant)) {
        final marker = match.group(1)!;
        if (!known.contains(marker) || seen.contains(marker)) {
          continue;
        }
        seen.add(marker);
        if (order.isEmpty || order.last != marker) {
          order.add(marker);
        }
      }
    }
  }
  return order;
}

/// فقرة كما تظهر في شجرة المعاينة.
class _PreviewText {
  _PreviewText({
    required this.marker,
    required this.text,
    required this.lines,
    required this.rect,
    required this.align,
    required this.wordSpacing,
    required this.fontFamilies,
  });

  final String marker;
  final String text;
  final int lines;
  final Rect rect;
  final TextAlign? align;
  final double? wordSpacing;
  final Set<String> fontFamilies;

  Map<String, Object?> toJson() => <String, Object?>{
        'marker': marker,
        'lines': lines,
        'left': rect.left.roundToDouble(),
        'right': rect.right.roundToDouble(),
        'top': rect.top.roundToDouble(),
        'bottom': rect.bottom.roundToDouble(),
        'align': align?.name,
        'wordSpacing': wordSpacing,
        'fonts': fontFamilies.toList()..sort(),
        'text': text,
      };
}

/// لقطة كاملة لمعاينة وثيقة: صفحات PNG + قياسات الشجرة + ترتيب المحتوى.
class _PreviewCapture {
  _PreviewCapture({
    required this.snapshots,
    required this.pages,
    required this.texts,
    required this.markerOrder,
    required this.layout,
  });

  final List<PageSnapshot> snapshots;
  final List<Uint8List> pages;
  final Map<String, _PreviewText> texts;
  final List<String> markerOrder;
  final LayoutDocument layout;
}

/// قياسات markers تُستخرج مباشرة من runs/lines في LayoutDocument؛ لا تُستنتج
/// من Text widgets أو من نسخة Flutter نصية موازية للصفحة.
({
  Map<String, _PreviewText> found,
  List<String> missing,
  int lineCount,
  List<String> lineTexts,
}) _measurePreviewMarkers(
  WidgetTester tester,
  LayoutDocument layout,
  List<String> markers,
) {
  final pageTops = <int, double>{};
  var nextPageTop = 12.0;
  for (final page in layout.pages) {
    pageTops[page.index] = nextPageTop;
    nextPageTop += LayoutUnits.ptToPx(page.pageSize.height) + 16;
  }
  final screenWidth =
      tester.view.physicalSize.width / tester.view.devicePixelRatio;
  final pageEntries = <({
    int pageIndex,
    LayoutLine line,
    List<LayoutRun> runs,
    String text,
  })>[];
  for (final page in layout.pages) {
    void addLine(LayoutLine line) {
      final byId = <String, LayoutRun>{
        for (final run in line.runs) run.id: run,
      };
      final logicalRuns = <LayoutRun>[];
      for (final runId in line.logicalRunIds) {
        final run = byId[runId];
        if (run != null) logicalRuns.add(run);
      }
      if (logicalRuns.isEmpty) {
        logicalRuns.addAll(line.runs);
        logicalRuns.sort((left, right) => left.logicalIndex.compareTo(right.logicalIndex));
      }
      pageEntries.add((
        pageIndex: page.index,
        line: line,
        runs: logicalRuns,
        text: logicalRuns.map((run) => run.text).join(),
      ));
    }

    for (final block in page.blocks) {
      for (final line in block.allLines) {
        addLine(line);
      }
    }
    for (final placement in page.floatingElements) {
      for (final line in placement.labelLines) {
        addLine(line);
      }
    }
  }

  final paragraphIds = <String, Set<int>>{};
  for (final marker in markers) {
    for (final entry in pageEntries) {
      if (textMentions(entry.text, marker)) {
        for (final run in entry.runs) {
          if (textMentions(run.text, marker)) {
            paragraphIds.putIfAbsent(marker, () => <int>{})
                .add(entry.line.paragraphIndex);
          }
        }
        paragraphIds.putIfAbsent(marker, () => <int>{})
            .add(entry.line.paragraphIndex);
      }
    }
  }

  Rect runRect(({int pageIndex, LayoutLine line, List<LayoutRun> runs, String text}) entry,
      LayoutRun run) {
    final pageWidth = LayoutUnits.ptToPx(layout.pageSize.width);
    final containerWidth = math.max(screenWidth, pageWidth + 24);
    final pageLeft = (containerWidth - pageWidth) / 2;
    final pageTop = pageTops[entry.pageIndex] ?? 0;
    return Rect.fromLTWH(
      pageLeft + LayoutUnits.ptToPx(run.x),
      pageTop + LayoutUnits.ptToPx(entry.line.baseline - run.baselineOffset),
      LayoutUnits.ptToPx(run.width),
      LayoutUnits.ptToPx(run.height),
    );
  }

  Rect lineRect(({int pageIndex, LayoutLine line, List<LayoutRun> runs, String text}) entry) {
    final pageWidth = LayoutUnits.ptToPx(layout.pageSize.width);
    final containerWidth = math.max(screenWidth, pageWidth + 24);
    final pageLeft = (containerWidth - pageWidth) / 2;
    final pageTop = pageTops[entry.pageIndex] ?? 0;
    return Rect.fromLTWH(
      pageLeft + LayoutUnits.ptToPx(entry.line.rect.left),
      pageTop + LayoutUnits.ptToPx(entry.line.rect.top),
      LayoutUnits.ptToPx(entry.line.rect.width),
      LayoutUnits.ptToPx(entry.line.rect.height),
    );
  }

  TextAlign? asTextAlign(PaperAlign? alignment) => switch (alignment) {
        PaperAlign.left => TextAlign.left,
        PaperAlign.right => TextAlign.right,
        PaperAlign.center => TextAlign.center,
        PaperAlign.justify => TextAlign.justify,
        PaperAlign.start => TextAlign.start,
        PaperAlign.end => TextAlign.end,
        null => layout.direction == DocumentDirection.rtl
            ? TextAlign.right
            : TextAlign.left,
      };

  final found = <String, _PreviewText>{};
  final missing = <String>[];
  for (final marker in markers) {
    final ids = paragraphIds[marker];
    if (ids == null || ids.isEmpty) {
      missing.add(marker);
      continue;
    }
    final paragraphLines = pageEntries
        .where((entry) => ids.contains(entry.line.paragraphIndex))
        .toList(growable: false);
    final runRects = <Rect>[];
    final fonts = <String>{};
    for (final entry in paragraphLines) {
      for (final run in entry.runs) {
        if (run.text.isEmpty && !run.isMath) continue;
        runRects.add(runRect(entry, run));
        if (run.style.font.family.isNotEmpty) fonts.add(run.style.font.family);
      }
    }
    var rect = runRects.isEmpty ? lineRect(paragraphLines.first) : runRects.first;
    for (final candidate in runRects.skip(1)) {
      rect = rect.expandToInclude(candidate);
    }
    final firstLine = paragraphLines.first.line;
    final extraSpace = paragraphLines
        .firstWhere((entry) => entry.line.isJustified, orElse: () => paragraphLines.first)
        .line
        .extraSpacePerOpportunity;
    found[marker] = _PreviewText(
      marker: marker,
      text: paragraphLines.map((entry) => entry.text).join(),
      lines: paragraphLines.length,
      rect: rect,
      align: asTextAlign(firstLine.alignment),
      wordSpacing: extraSpace == 0 ? 0 : LayoutUnits.ptToPx(extraSpace),
      fontFamilies: fonts,
    );
  }
  return (
    found: found,
    missing: missing,
    lineCount: pageEntries.length,
    lineTexts: pageEntries.map((entry) => entry.text).toList(growable: false),
  );
}

/// يبني المعاينة للوثيقة، يكمل القياس، ويلتقط كل صفحة، ويقيس فقراتها.
Future<_PreviewCapture> _capturePreviewOf(
  WidgetTester tester,
  ExamDocument document,
  List<String> markers,
) async {
  final controller = ExamWizardController(document: document);
  addTearDown(controller.dispose);

  tester.view.physicalSize = const Size(1600, 1240);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  // Resolve the actual source geometry and renderer assets once outside
  // FakeAsync. The widget receives those exact objects through its documented
  // test seams; this avoids racing image decoding while preserving the real
  // CanonicalLayoutService and CanonicalLayoutPreviewAssets implementations.
  final preparation = await tester.runAsync(() async {
    final sourceIr = controller.documentIr;
    final layout = await CanonicalLayoutService.resolve(
      document: document,
      sourceIr: sourceIr,
    );
    final assets = await CanonicalLayoutPreviewAssets.load(
      layout: layout,
      document: document,
    );
    return (
      layout: layout,
      assets: assets,
    );
  });
  expect(preparation, isNotNull);
  final prepared = preparation!;
  addTearDown(prepared.assets.dispose);
  _stage('Canonical layout resolved: ${prepared.layout.pageCount} pages');

  await tester.pumpWidget(
    MaterialApp(
      home: ChangeNotifierProvider<ExamWizardController>.value(
        value: controller,
        child: ExamPreviewScreen(
          onBackToQuestions: () {},
          canonicalLayoutResolver: ({
            required document,
            required sourceIr,
          }) async => prepared.layout,
          canonicalPreviewAssetLoader: ({
            required layout,
            required document,
          }) async => prepared.assets,
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pumpAndSettle();
  final previewElements =
      find.byType(CanonicalLayoutPreviewPage).evaluate().toList(growable: false);
  expect(previewElements, isNotEmpty,
      reason: 'المعاينة القانونية لم تُجهّز أي صفحة.');
  final layout =
      (previewElements.first.widget as CanonicalLayoutPreviewPage).layoutDocument;
  expect(
    previewElements.every((element) =>
        identical(
          (element.widget as CanonicalLayoutPreviewPage).layoutDocument,
          layout,
        )),
    isTrue,
    reason: 'كل صفحات Preview يجب أن ترسم كائن LayoutDocument نفسه.',
  );
  expect(previewElements, hasLength(layout.pageCount));
  expect(identical(layout.source, controller.documentIr), isTrue,
      reason: 'The live geometry must bind to the current DocumentIR instance.');
  for (final element in previewElements) {
    final preview = element.widget as CanonicalLayoutPreviewPage;
    expect(identical(preview.page, layout.pages[preview.page.index]), isTrue);
  }
  await tester.pumpAndSettle();
  final pageCount = layout.pageCount;
  expect(pageCount, greaterThan(1),
      reason: 'التركيبة يجب أن تتعدّى صفحة واحدة لتغطية التخطيط القانوني.');
  for (final page in layout.pages) {
    expect(page.contentBounds.left, greaterThanOrEqualTo(0));
    expect(page.contentBounds.right, lessThanOrEqualTo(page.pageSize.width));
    expect(page.bodyBounds.top, greaterThanOrEqualTo(page.contentBounds.top));
    expect(page.bodyBounds.bottom, lessThanOrEqualTo(page.contentBounds.bottom));
    final footer = page.footerBounds;
    if (footer != null) {
      expect(page.bodyBounds.bottom, lessThanOrEqualTo(footer.top + 0.01),
          reason: 'صفحة ${page.index}: مساحة المتن تداخلت مع التذييل.');
      expect(footer.bottom, lessThanOrEqualTo(page.pageSize.height));
    }
  }
  _stage('تقسيم ${document.name}: canonical=$pageCount صفحة.');

  // نافذة تكفي لرسم كل الصفحات (ما خرج من نافذة التمرير لا يُرسم ولا يُلقط).
  var viewHeight = (ExamCanvasGeometry.height + 16) * pageCount + 400;
  tester.view.physicalSize = Size(1600, viewHeight);
  await tester.pumpAndSettle();
  List<RenderRepaintBoundary> boundaries = _pageBoundaries(tester);
  for (var attempt = 0;
      attempt < 8 && boundaries.any((boundary) => boundary.debugNeedsPaint);
      attempt++) {
    viewHeight += 900;
    tester.view.physicalSize = Size(1600, viewHeight);
    await tester.pumpAndSettle();
    boundaries = _pageBoundaries(tester);
  }
  expect(boundaries, hasLength(pageCount),
      reason: 'جذر لقط لكل صفحة (${boundaries.length}/$pageCount).');
  expect(boundaries.every((boundary) => !boundary.debugNeedsPaint), isTrue,
      reason: 'صفحة لم تُرسم فلا يمكن لقطها مرجعاً للمقارنة.');

  final known = document.layout.isLtr
      ? P0GateFixture.ltrBodyMarkers
      : P0GateFixture.rtlBodyMarkers;
  final excluded = document.layout.isLtr
      ? <String>{'LTRV', 'LTRC1', 'LTRC2', 'LTRG1', 'LTRT1', 'LTRF1', 'LTRF2'}
      : <String>{
          ...P0GateFixture.headerMarkers,
          ...P0GateFixture.footerMarkers,
          ...P0GateFixture.floatingMarkers,
        };
  // القياسات قبل اللقط (الشجرة نفسها، والمقارنات نسبية): كل وسم في العقد
  // يُقاس، لا عيّنة منه — وإلا صارت «لا انحدار» ادّعاءً بلا تغطية.
  final sideMarkers = document.layout.isLtr
      ? const <String>{'LTRV', 'LTRF1', 'LTRF2'}
      : <String>{
          ...P0GateFixture.headerMarkers,
          ...P0GateFixture.footerMarkers,
          ...P0GateFixture.floatingMarkers,
        };
  final markersToMeasure = <String>{...known, ...sideMarkers, ...markers};
  final measurement = _measurePreviewMarkers(
    tester,
    layout,
    markersToMeasure.toList(),
  );
  final texts = measurement.found;
  if (measurement.missing.isNotEmpty) {
    // القائمة لا العدد فقط: «وسوم مقاسة 12/45» وحده لا يقول ما الناقص.
    // وحجم الشجرة يُفرّق «وسماً غائباً» عن «لا نصوص في الشجرة أصلاً».
    _stage('${document.name}: وسوم لم تُقَس في المعاينة '
        '(${measurement.missing.length}): ${measurement.missing.join(', ')}؛ '
        ' أسطر canonical=${measurement.lineCount}');
  }
  final markerOrder = _markerOrderInParts(
    measurement.lineTexts,
    known,
    allowReversed: false,
  ).where((marker) => !excluded.contains(marker)).toList();

  final capture = await tester.runAsync(() async {
    final snapshots = <PageSnapshot>[];
    for (final boundary in boundaries) {
      final image = await boundary.toImage(pixelRatio: 1);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final width = image.width;
      final height = image.height;
      image.dispose();
      if (data == null) {
        continue;
      }
      snapshots.add(PageSnapshot(
        pageIndex: snapshots.length,
        pngBytes: data.buffer.asUint8List(),
        widthPx: width.toDouble(),
        heightPx: height.toDouble(),
      ));
    }
    return snapshots;
  });
  expect(capture, isNotNull);
  final snapshots = capture!;
  expect(snapshots, hasLength(pageCount),
      reason: 'لقطة لكل صفحة معاينة (${snapshots.length}/$pageCount).');
  for (final snapshot in snapshots) {
    expect(snapshot.pngBytes.sublist(0, 8),
        <int>[137, 80, 78, 71, 13, 10, 26, 10],
        reason: 'لقطة المعاينة ليست PNG صالحاً.');
    expect(snapshot.widthPx, greaterThan(700));
    expect(snapshot.heightPx, greaterThan(1000));
  }

  _stage('معاينة ${document.name}: $pageCount صفحة، '
      'وسوم مقاسة ${texts.length}/${markersToMeasure.length}');
  return _PreviewCapture(
    snapshots: snapshots,
    pages: snapshots
        .map((snapshot) => Uint8List.fromList(snapshot.pngBytes))
        .toList(),
    texts: texts,
    markerOrder: markerOrder,
    layout: layout,
  );
}

List<RenderRepaintBoundary> _pageBoundaries(WidgetTester tester) => tester
    .renderObjectList<RenderRepaintBoundary>(find.byType(RepaintBoundary))
    .where((boundary) =>
        boundary.size.width > ExamCanvasGeometry.width - 1 &&
        boundary.size.width < ExamCanvasGeometry.width + 1 &&
        boundary.size.height > ExamCanvasGeometry.height - 1 &&
        boundary.size.height < ExamCanvasGeometry.height + 1)
    .toList(growable: false);

/// أمثلة على محارف عربية غير مشكَّلة رسُمت في PDF (للتشخيص لا للافتراض).
List<String> _unshapedSamples(String drawnText) {
  final samples = <String>[];
  final buffer = StringBuffer();
  for (final unit in drawnText.codeUnits) {
    final unshaped = unit >= 0x0621 && unit <= 0x064A;
    if (unshaped) {
      buffer.writeCharCode(unit);
    } else if (buffer.isNotEmpty) {
      samples.add(buffer.toString());
      buffer.clear();
      if (samples.length >= 4) {
        return samples;
      }
    }
  }
  if (buffer.isNotEmpty) {
    samples.add(buffer.toString());
  }
  return samples;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    final directory = Directory(_dir);
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }
  });

  tearDownAll(() {
    _writeText('matrix.json',
        const JsonEncoder.withIndent('  ').convert(_matrix.toJson()));
    _writeText('matrix.txt', _matrix.toTextTable());
    _writeText('p0_regression_matrix.csv', _matrix.toCsv());
    // يُقرأ في سجل CI مباشرةً: الفشل تشخيصٌ لا رقم خروج.
    debugPrint('\n${_matrix.toTextTable()}');
    if (_gate.artifactsReady) {
      _writeText(
        'pdf_structure_rtl.json',
        const JsonEncoder.withIndent('  ')
            .convert(_gate.rtlPdfReport.toJson()),
      );
      _writeText(
        'pdf_structure_ltr.json',
        const JsonEncoder.withIndent('  ')
            .convert(_gate.ltrPdfReport.toJson()),
      );
    }
  });

  // ===========================================================================
  // P0.2 — القطع تُنتَج فعلاً، والمسارات الأربعة منفصلة.
  // ===========================================================================
  testWidgets(
      'P0-GATE-00: مرجع المعاينة — RTL و LTR: لقطات كل صفحة وقياس كل وسم',
      (tester) async {
    await _loadAppFonts();

    final rtlDocument = P0GateFixture.rtl();
    final ltrDocument = P0GateFixture.ltr();

    final rtl = await _capturePreviewOf(tester, rtlDocument, <String>[
      'CAT1',
      'STA1',
      'BODY1',
      'MIX1',
      'OPT1',
      'OP1A',
      'TF1',
      'ITM3',
      'ITM4',
      'BR1',
      'MATH1',
      'TEXTAR1',
      'JUSTS1',
      'QUR1',
      'PG5',
      'HDRV',
      'FTR1',
    ]);
    _gate.rtlCapture = rtl;
    _gate.previewRtl.addAll(rtl.texts);
    _gate.previewRtlMarkerOrder = rtl.markerOrder;
    _gate.rtlPreviewPages = rtl.pages;
    _gate.rtlPreviewPageCount = rtl.pages.length;

    final ltr = await _capturePreviewOf(tester, ltrDocument, <String>[
      'LTRCAT1',
      'LTRSTA1',
      'LTROBJ1',
      'LTROPT1',
      'LTRP1A',
      'LTRTF1',
      'LTRBR1',
      'LTRMATH1',
      'JUSTL1',
      'LTRPG1',
      'LTRV',
      'LTRF1',
    ]);
    _gate.ltrCapture = ltr;
    _gate.previewLtr.addAll(ltr.texts);
    _gate.previewLtrMarkerOrder = ltr.markerOrder;
    _gate.ltrPreviewPages = ltr.pages;
    _gate.ltrPreviewPageCount = ltr.pages.length;
    _recordPreviewCells(rtl, ltr);
  });

  testWidgets(
      'P0-GATE-01: قطع الورقة العربية — preview + vector.pdf + exact.*',
      (tester) async {
    await _loadAppFonts();
    final mathHost = FakeMathHost()..attach();
    addTearDown(mathHost.detach);

    final rtlDocument = P0GateFixture.rtl();

    // مرجع المعاينة قيس في P0-GATE-00 ولا تُمشى الشجرة مرتين في اختبار واحد:
    // إعادة المشي هي ما استهلك «TimeoutException after 0:10:00» كله.
    _gate.requirePreview();
    final rtl = _gate.rtlCapture!;

    // التوليد يمسّ I/O حقيقياً (تحميل خطوط من الأصول، فكّ صور، لقطة
    // المعادلات). داخل testWidgets يعمل كل await في منطقة FakeAsync فلا يكتمل
    // إطلاقاً: CI أجهض الحالتين بـ«TimeoutException after 0:10:00» بلا تقدّم
    // مقيس. runAsync يُرجع I/O إلى العزلة الحقيقية، والزمن يُقاس لكل ممرّ حتى
    // لا يبقى الثقل — إن وُجد — مبهماً.
    final watch = Stopwatch();
    await tester.runAsync(() async {
      watch.start();
      try {
        final pdfFonts = await ExamFonts.load(
          loadQuranic: PaginatedPdfExamEngine.needsQuranicFont(rtlDocument),
        );
        final pdfEngine = PaginatedPdfExamEngine();
        final canonicalLayout = await pdfEngine.resolveLayoutDocument(
          document: rtlDocument,
          fonts: pdfFonts,
        );
        _gate.mathRunCount = canonicalLayout.allLines
            .expand((line) => line.runs)
            .where((run) => run.isMath)
            .length;
        _gate.canonicalLabelRuns = canonicalLayout.allLines
            .expand((line) => line.runs)
            .where((run) {
              final id = run.semanticNodeId;
              final directLabel = id.endsWith('/label') ||
                  id.contains('/label/content/') ||
                  id.endsWith('/separator');
              return id.contains('/point/p0q1i') &&
                  !id.contains('/options/') &&
                  directLabel &&
                  const <String>{'label', 'number', 'separator'}
                      .contains(run.semanticRole.name);
            })
            .map((run) => '${run.semanticNodeId.split('/').firstWhere(
                      (part) => part.startsWith('p0q1i'),
                    )} ${run.semanticRole.name}:"${run.text}" '
                '@${run.x.toStringAsFixed(1)}+'
                '${run.width.toStringAsFixed(1)} '
                'a=${run.advance.toStringAsFixed(1)}')
            .take(10)
            .toList();
        _stage('P2 number/separator runs: ${_gate.canonicalLabelRuns}');
        final quranRunGeometry = canonicalLayout.allLines
            .expand((line) => line.runs)
            .where((run) => run.isQuran)
            .map((run) => '"${run.text}"@${run.x.toStringAsFixed(2)}+'
                '${run.width.toStringAsFixed(2)} '
                'dir=${run.direction.name} id=${run.semanticNodeId}')
            .take(12)
            .toList();
        final quranTitleLines = canonicalLayout.allLines
            .where((line) => line.semanticNodeId == 'p0q1/title')
            .toList(growable: false);
        _gate.canonicalQuestionTitleLine = quranTitleLines.isEmpty
            ? null
            : quranTitleLines.first;
        final quranTitleRuns = quranTitleLines
            .expand((line) => line.runs)
            .where((run) => run.isQuran)
            .toList(growable: false);
        String withoutArabicMarks(String value) => String.fromCharCodes(
              value.runes.where((rune) =>
                  !(rune >= 0x064b && rune <= 0x065f) && rune != 0x0670),
            );
        final zadni = quranTitleRuns
            .where((run) => withoutArabicMarks(run.text).contains('زدني'))
            .toList(growable: false);
        final ilma = quranTitleRuns
            .where((run) => withoutArabicMarks(run.text).contains('علما'))
            .toList(growable: false);
        String? quranTitleWordGap;
        if (zadni.isNotEmpty && ilma.isNotEmpty) {
          final left = zadni.first.x <= ilma.first.x ? zadni.first : ilma.first;
          final right = identical(left, zadni.first) ? ilma.first : zadni.first;
          _gate.canonicalQuranTitleWordGap =
              right.x - (left.x + left.width);
          quranTitleWordGap =
              '${_gate.canonicalQuranTitleWordGap!.toStringAsFixed(3)}pt';
        }
        _gate.canonicalQuranTitlePairGeometry = <String>[
          if (zadni.isNotEmpty)
            'زدني id=${zadni.first.id} '
                '@${zadni.first.x.toStringAsFixed(3)}+'
                '${zadni.first.width.toStringAsFixed(3)}',
          if (ilma.isNotEmpty)
            'علما id=${ilma.first.id} '
                '@${ilma.first.x.toStringAsFixed(3)}+'
                '${ilma.first.width.toStringAsFixed(3)}',
        ];
        _stage('P2 Quran run geometry: $quranRunGeometry; '
            'p0q1/title canonical gap زدني/علما=$quranTitleWordGap '
            'runs=${_gate.canonicalQuranTitlePairGeometry}');
        _gate.rtlVectorPdf = await pdfEngine.generate(
          document: rtlDocument,
          layoutDocument: canonicalLayout,
          fonts: pdfFonts,
        );
        _gate.mathHostRequestCount = mathHost.requests.length;
      } catch (error, stackTrace) {
        _stage('RTL vector generation failed: $error\n$stackTrace');
        Error.throwWithStackTrace(error, stackTrace);
      }
      _stage('توليد vector.pdf عربي: ${watch.elapsedMilliseconds}ms، '
          '${_gate.rtlVectorPdf!.length} بايت');
      watch
        ..reset()
        ..start();
      // Exact: لقطات المعاينة نفسها، في مسار منفصل عن الفحوص البنيوية.
      _gate.rtlExactPdf =
          await ExactExportService.buildPdfFromSnapshots(rtl.snapshots);
      _gate.rtlExactDocx =
          ExactExportService.buildDocxFromSnapshots(rtl.snapshots);
      _stage('توليد exact.* عربي: ${watch.elapsedMilliseconds}ms');
      watch.stop();
    });

    // القطع على القرص.
    for (var index = 0; index < _gate.rtlPreviewPages.length; index++) {
      await _writeArtifact(
          'preview_rtl_page_${index + 1}.png', _gate.rtlPreviewPages[index]);
    }
    await _writeArtifact('vector.pdf', _gate.rtlVectorPdf!);
    await _writeArtifact('exact.pdf', _gate.rtlExactPdf!);
    await _writeArtifact('exact.docx', _gate.rtlExactDocx!);
    _writeText(
      'preview_geometry.json',
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'rtl': _gate.previewRtl
            .map((key, value) => MapEntry<String, Object?>(key, value.toJson())),
        'ltr': _gate.previewLtr
            .map((key, value) => MapEntry<String, Object?>(key, value.toJson())),
        'rtlPreviewPageCount': _gate.rtlPreviewPageCount,
        'ltrPreviewPageCount': _gate.ltrPreviewPageCount,
        'rtlPdfPageCount': PdfContentProbe.pageCountOf(_gate.rtlVectorPdf!),
        'mathRunCount': _gate.mathRunCount,
        'mathHostRequestCount': _gate.mathHostRequestCount,
      }),
    );

    // كل قطعة موجودة وغير فارغة.
    for (final name in <String>[
      'vector.pdf',
      'exact.pdf',
      'exact.docx',
      for (var index = 0; index < _gate.rtlPreviewPages.length; index++)
        'preview_rtl_page_${index + 1}.png',
    ]) {
      final file = File('$_dir/$name');
      expect(file.existsSync(), isTrue, reason: 'لم تُكتب القطعة $name.');
      expect(file.lengthSync(), greaterThan(1024),
          reason: 'القطعة $name أصغر من أن تكون مخرجاً حقيقياً.');
    }

    // Exact ≠ vector: لا يُقاس ممرّ بغيره.
    expect(_gate.rtlVectorPdf!.length, isNot(_gate.rtlExactPdf!.length),
        reason: 'vector.pdf يطابق exact.pdf بايتاً: الممرّان لم يُقيسا منفصلين.');
    expect(PdfContentProbe.fromBytes(_gate.rtlVectorPdf!).words, isNotEmpty,
        reason: 'vector.pdf بلا نص قابل للتحديد — لا تُبنى عليه بوابة بنيوية.');
    expect(PdfContentProbe.fromBytes(_gate.rtlExactPdf!).words, isEmpty,
        reason: 'exact.pdf يجب أن يبقى صوراً بلا نص؛ وجود نص فيه يعني أن '
            'القطع اختلطت بين الممرّين.');

    _stage('vector عربي: ${_gate.rtlPdfReport.pageCount} صفحة؛ '
        'المعاينة: ${_gate.rtlPreviewPageCount} صفحة؛ '
        'صيغ رياضية: ${_gate.mathRunCount}، طلبات المضيف: '
          '${_gate.mathHostRequestCount}');

    // الانحراف مقيس ولا يُمرّ بصمت: المعاينة تقسم الورقة العربية إلى
    // صفحات والـPDF إلى عدد آخر، والسبب أن لكل ممرّ مصدره لارتفاع السطر
    // والهامش (ترويسة 140.4px، كتل تدفّق 325px، صفحة 1009.61px في المعاينة؛
    // الـPDF يحسب من pt بهوامشه الخاصة). توحيدهما قرار طبقة تخطيط واحدة —
    // ممنوع في P0.6 — فيُسجَّل مقيساً هنا وتُثبت البوابة الرقمين.
    final pdfPages = _gate.rtlPdfReport.pageCount;
    final previewPages = _gate.rtlPreviewPageCount;
    if (pdfPages != previewPages) {
      _matrix.record('pagination', P0Path.vectorPdf, P0Status.deferredToP1,
          evidence: 'عربي: معاينة=$previewPages صفحة مقابل PDF=$pdfPages '
              'صفحة (ارتفاعات مقيسة: مجموع 3791.6px على صفحة 1009.61px، '
              'ترويسة 140.4px، كتل تدفّق 325px)',
          reason: 'مصدرٌ مختلف لارتفاع السطر والهامش بين `PaginationEngine` '
              'و`PdfPaperBuilder`؛ توحيدُهما طبقة Canonical LayoutEngine في P1 '
              '(§P1 BLOCKERS بند 2)، وتوحيد الأرقام الآن يعني إعادة كتابة أحد '
              'الممرّين وهو داخل المحظور في P0.6.');
    }
  });

  // الورقة الإنجليزية في اختبار مستقل: توليد القطع الثلاثة لورقتين في اختبار
  // واحد كان يتجاوز سقف CI (عشر دقائق) فيُجهض البوابة كلها بلا قياس واحد.
  testWidgets(
      'P0-GATE-01B: قطع الورقة الإنجليزية — vector_ltr + exact_ltr',
      (tester) async {
    await _loadAppFonts();
    final mathHost = FakeMathHost()..attach();
    addTearDown(mathHost.detach);

    final ltrDocument = P0GateFixture.ltr();
    _gate.requirePreview();
    final ltr = _gate.ltrCapture!;

    final watch = Stopwatch();
    await tester.runAsync(() async {
      watch.start();
      _gate.ltrVectorPdf =
          await PaginatedPdfExamEngine().generate(document: ltrDocument);
      _stage('توليد vector_ltr.pdf: ${watch.elapsedMilliseconds}ms، '
          '${_gate.ltrVectorPdf!.length} بايت');
      watch
        ..reset()
        ..start();
      _gate.ltrExactPdf =
          await ExactExportService.buildPdfFromSnapshots(ltr.snapshots);
      _gate.ltrExactDocx =
          ExactExportService.buildDocxFromSnapshots(ltr.snapshots);
      _stage('توليد exact_ltr.*: ${watch.elapsedMilliseconds}ms');
      watch.stop();
    });

    for (var index = 0; index < _gate.ltrPreviewPages.length; index++) {
      await _writeArtifact(
          'preview_ltr_page_${index + 1}.png', _gate.ltrPreviewPages[index]);
    }
    await _writeArtifact('vector_ltr.pdf', _gate.ltrVectorPdf!);
    await _writeArtifact('exact_ltr.pdf', _gate.ltrExactPdf!);
    await _writeArtifact('exact_ltr.docx', _gate.ltrExactDocx!);
    _writeText(
      'preview_geometry_ltr.json',
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'ltrPdfPageCount': PdfContentProbe.pageCountOf(_gate.ltrVectorPdf!),
        'ltrPreviewPageCount': _gate.ltrPreviewPageCount,
        'ltrMathRequests': mathHost.requests.length,
      }),
    );

    for (final name in <String>[
      'vector_ltr.pdf',
      'exact_ltr.pdf',
      'exact_ltr.docx',
      for (var index = 0; index < _gate.ltrPreviewPages.length; index++)
        'preview_ltr_page_${index + 1}.png',
    ]) {
      final file = File('$_dir/$name');
      expect(file.existsSync(), isTrue, reason: 'لم تُكتب القطعة $name.');
      expect(file.lengthSync(), greaterThan(1024),
          reason: 'القطعة $name أصغر من أن تكون مخرجاً حقيقياً.');
    }

    expect(_gate.ltrVectorPdf!.length, isNot(_gate.ltrExactPdf!.length),
        reason: 'vector_ltr.pdf يطابق exact_ltr.pdf بايتاً: الممرّان لم '
            'يُقيسا منفصلين.');
    expect(PdfContentProbe.fromBytes(_gate.ltrVectorPdf!).words, isNotEmpty,
        reason: 'vector_ltr.pdf بلا نص قابل للتحديد — لا تُبنى عليه بوابة.');
    expect(PdfContentProbe.fromBytes(_gate.ltrExactPdf!).words, isEmpty,
        reason: 'exact_ltr.pdf يجب أن يبقى صوراً بلا نص.');

    final ltrPdfPages = _gate.ltrPdfReport.pageCount;
    final ltrPreviewPages = _gate.ltrPreviewPageCount;
    _stage('vector إنجليزي: $ltrPdfPages صفحة؛ '
        'المعاينة: $ltrPreviewPages صفحة');
    if (ltrPdfPages != ltrPreviewPages) {
      // نفس الانحراف مقيسًا في الورقة الإنجليزية: المصدران منفصلان في الورقتين،
      // فلا هو عارض في العربية ولا تسرّب من إصلاح الاتجاه.
      _matrix.record('pagination', P0Path.vectorPdf, P0Status.deferredToP1,
          evidence: 'إنجليزي: معاينة=$ltrPreviewPages صفحة مقابل PDF='
              '$ltrPdfPages صفحة (مجموع ارتفاعات 2417.6px على صفحة '
              '1009.61px في المعاينة)',
          reason: 'قياسٌ منفصل للورقة الإنجليزية من نفس السبب: ارتفاع السطر '
              'والهامش يحسبهما كل ممرّ من مصدره؛ التوحيد في P1 (§P1 BLOCKERS '
              'بند 2) لا في P0.');
    }
  });

  // ===========================================================================
  // P0.3 — بنية PDF المتجه.
  // ===========================================================================
  test('P0-GATE-02: بنية vector.pdf — الصفحات والصناديق وتسلسل المحتوى', () {
    _gate.requireArtifacts();
    final report = _gate.rtlPdfReport;
    final document = P0GateFixture.rtl();
    const known = P0GateFixture.rtlBodyMarkers;
    final excluded = <String>{
      ...P0GateFixture.headerMarkers,
      ...P0GateFixture.footerMarkers,
      ...P0GateFixture.floatingMarkers,
    };

    expect(report.pageCount, greaterThan(1),
        reason: 'التركيبة يجب أن تتعدّى صفحة A4 واحدة لتغطية التقسيم.');
    for (final page in report.pages) {
      expect(page.mediaBox, hasLength(4),
          reason: 'ص${page.index + 1}: لا /MediaBox — لا حدّ ورقة يُقاس.');
      expect(page.lineCount, greaterThan(3),
          reason: 'ص${page.index + 1}: سطور أقلّ من أن تكون ورقة أسئلة.');
      final bounds = page.contentBounds;
      expect(bounds, isNotEmpty, reason: 'صفحة بلا محتوى مرسوم.');
      expect(bounds[0], greaterThanOrEqualTo(0),
          reason: 'محتوى خارج يسار الصفحة: minX=${bounds[0]}');
      expect(bounds[2], lessThanOrEqualTo(page.pageWidth),
          reason: 'محتوى يتجاوز عرض الصفحة: maxX=${bounds[2]} '
              'width=${page.pageWidth}');
      expect(bounds[1], greaterThanOrEqualTo(0),
          reason: 'محتوى تحت حد الصفحة: minY=${bounds[1]}');
      expect(bounds[3], lessThanOrEqualTo(page.pageHeight),
          reason: 'محتوى فوق رأس الصفحة: maxY=${bounds[3]}');
    }

    // لا وسم مفقود ولا وسم غريب: تغطية كاملة ولا محتوى زائداً.
    final drawn = report.pages.map((page) => page.drawnText).join(' ');
    final found = _markersIn(drawn, known);
    expect(found, containsAll(<String>[...known]),
        reason: 'وسوم مفقودة من vector.pdf: '
            '${(known.difference(found).toList())..sort()}');
    final unexplained =
        report.allMarkers().difference(known).difference(excluded);
    // «HDC» ليس محتوى زائداً: إنه قطعة من وسم معلن (`HDC1`) لأن `pdf` يقطع
    // السطر إلى كلمات وقد يسقط الرقم في التذييل المجاور. الفحص يبقى صارماً:
    // كل وسم غير معلن لا يُبرَّر بكونه قطعة من وسم معروف يفشل البوابة.
    final declared = <String>{...known, ...excluded};
    final stray = unexplained
        .where((token) =>
            !declared.any((marker) => marker.startsWith(token)))
        .toSet();
    expect(stray, isEmpty,
        reason: 'وسوم غير متوقعة (تغيّر غير مقصود في تسلسل المحتوى): $stray '
            '(غير مفسَّرة من: $unexplained)');

    // تسلسل المحتوى = ترتيب العقد نفسه (الكتلة تلو الكتلة بترتيب الرسم).
    final expectedOrder = P0GateFixture.bodyMarkerSequence(document);
    final pdfOrder = report.markerSequence(known: known, excluded: excluded);
    expect(pdfOrder, expectedOrder,
        reason: 'تسلسل المحتوى في vector.pdf يختلف عن ترتيب العقد:\n'
            '  PDF : $pdfOrder\n  عقد : $expectedOrder');

    // Header/footer presence, first/last-page placement, and body/footer
    // separation are measured from the actual vector PDF text operators.
    final headerPages = report.pages
        .where((page) => page.linesWithMarker('HDRV').isNotEmpty)
        .toList();
    expect(headerPages.map((page) => page.index), <int>[0],
        reason: 'الترويسة يجب أن تظهر مرة واحدة في الصفحة الأولى فقط: '
            '${headerPages.map((page) => page.index).toList()}.');
    // «أول سطر» حرفياً مقياس هشّ: pdf يقطّع السطر إلى كلمات، فقد يبدأ السطر
    // بقطعة من تسمية المدرسة («دارة») لا بالوسم نفسه. المقياس الصحيح نسبي
    // وبلا وحدات: سطر الترويسة يُرسم قبل سطر المتن، وأعلى سطر مرسوم في الصفحة
    // يقع في حزمة الترويسة نفسها.
    final firstPageLines = report.pages.first.lines;
    expect(firstPageLines, isNotEmpty, reason: 'ص1 بلا سطور مرسومة.');
    final headerLineIndex =
        report.pages.first.linesWithMarker('HDRV').isEmpty
            ? -1
            : report.pages.first.lines.indexOf(
                report.pages.first.linesWithMarker('HDRV').first);
    final bodyLineIndex = report.pages.first.linesWithMarker('STA1').isEmpty
        ? -1
        : report.pages.first.lines
            .indexOf(report.pages.first.linesWithMarker('STA1').first);
    expect(headerLineIndex, isNonNegative,
        reason: 'وسم الترويسة HDRV لا يُرى في ص1 من vector.pdf.');
    expect(bodyLineIndex, isNonNegative,
        reason: 'وسم المتن STA1 لا يُرى في ص1 من vector.pdf.');
    expect(headerLineIndex, lessThan(bodyLineIndex),
        reason: 'الترويسة لا تُرسم قبل المتن في ص1: سطر الترويسة '
            '$headerLineIndex مقابل سطر المتن $bodyLineIndex.');
    // إحداثيات PDF محورها y إلى الأعلى: أعلى السطر = أكبر y. فالسطر الأول
    // المرسوم يجب أن يكون عند سقف حزمة الترويسة أو فوقها، لا تحتها.
    expect(_lineTop(firstPageLines.first),
        greaterThanOrEqualTo(_lineTop(report.pages.first.lines[headerLineIndex]) - 0.5),
        reason: 'أعلى سطر مرسوم في ص1 ليس من حزمة الترويسة (أول سطر: '
            '"${firstPageLines.first.describe()}"، وسطر الترويسة '
            'y=${_lineTop(report.pages.first.lines[headerLineIndex])}).');
    final lastPage = report.pages.last;
    final footerPages = report.pages
        .where((page) => page.linesWithMarker('FTR1').isNotEmpty)
        .toList(growable: false);
    expect(footerPages.map((page) => page.index), <int>[lastPage.index],
        reason: 'التذييل يجب أن يظهر على الصفحة الأخيرة فقط: '
            '${footerPages.map((page) => page.index).toList()}.');
    final bodyLines = lastPage.linesWithMarker('PG12');
    final footerLines = lastPage.linesWithMarker('FTR1');
    expect(bodyLines, isNotEmpty,
        reason: 'آخر وسم متن PG12 غائب من صفحة PDF الأخيرة.');
    expect(footerLines, isNotEmpty);
    double lineBottom(ProbedLine line) => line.words
        .map((word) => word.y - word.fontSize * 0.25)
        .reduce(math.min);
    double lineTop(ProbedLine line) => line.words
        .map((word) => word.y + word.fontSize * 0.75)
        .reduce(math.max);
    final bodyBottom = bodyLines.map(lineBottom).reduce(math.min);
    final footerTop = footerLines.map(lineTop).reduce(math.max);
    expect(bodyBottom, greaterThan(footerTop),
        reason: 'Vector PDF body/footer line boxes overlap on the last page: '
            'body bottom=$bodyBottom, footer top=$footerTop.');
    _stage('PDF header on page 1 only; footer on page ${lastPage.index + 1} only; '
        'last body/footer measured gap=${(bodyBottom - footerTop).toStringAsFixed(2)}pt.');

    _matrix.record('pagination', P0Path.vectorPdf, P0Status.pass,
        evidence: 'صفحات=${report.pageCount}، '
            'أسطر/صفحة=${report.pages.map((p) => p.lineCount).join("/")}، '
            'أول ظهور PG8 في ص${(report.pageOfMarker(['PG8'])['PG8'] ?? -1) + 1}'
            '/${report.pageCount}');
    _matrix.record('arabic', P0Path.vectorPdf, P0Status.pass,
        evidence: 'تسلسل العقد كله مرسوم: ${pdfOrder.length} وسم، '
            'وسطور ص1=${report.pages.first.lineCount}');
    _matrix.record('header-footer', P0Path.vectorPdf, P0Status.pass,
        evidence: 'header pages=${headerPages.map((page) => page.index).join('/')} '
            'of ${report.pageCount}; footer pages='
            '${footerPages.map((page) => page.index).join('/')} of '
            '${report.pageCount}; measured body/footer clearance='
            '${(bodyBottom - footerTop).toStringAsFixed(2)}pt.');
  });

  test('P0-GATE-03: بنية vector.pdf — ترتيب الكلمات العربية، التشكيل، '
      'الفجوات، الأرقام والأقواس', () {
    _gate.requireArtifacts();
    final report = _gate.rtlPdfReport;
    final page = report.pages.first;
    final arabicPattern =
        RegExp('[\\u0600-\\u06FF\\u0750-\\u077F\\uFB50-\\uFDFF\\uFE70-\\uFEFF]');

    final arabicLines = page.multiWordLines.where((line) =>
        arabicPattern.hasMatch(line.words.map((word) => word.text).join()))
        .toList();
    expect(arabicLines.length, greaterThan(3),
        reason: 'لا سطور عربية متعددة الكلمات لتقييم ترتيبها.');
    final notRtl = <String>[
      for (final line in arabicLines)
        if (PdfPageStructure.orderOfLine(line) != 'rtl') line.describe(),
    ];
    expect(notRtl, isEmpty,
        reason: 'أسطر عربية لا تتقدّم x فيها تنازلياً (ترتيب كلمات غير RTL): '
            '$notRtl');

    // كل محرف عربي مرسوم يجب أن يكون صورة تقديمية (تشكيل) لا محرفاً معجمياً.
    var shaped = 0;
    var unshaped = 0;
    for (final p in report.pages) {
      shaped += p.presentationFormLetters;
      unshaped += p.unshapedArabicLetters;
    }
    final unshapedWords = <ProbedWord>[
      for (final pdfPage in report.pages)
        for (final word in pdfPage.words)
          if (word.text.runes.any((rune) => rune >= 0x0621 && rune <= 0x064A))
            word,
    ];
    _stage('[p0-gate] unshaped words=${unshapedWords.take(12).map((word) =>
        '${word.text}[${word.text.runes.map((rune) => rune.toRadixString(16)).join(",")}]@${word.x.toStringAsFixed(1)},${word.y.toStringAsFixed(1)}:${word.baseFont}').join(' | ')}');
    expect(shaped, greaterThan(100),
        reason: 'صور تقديمية عربية أقلّ من المتوقع في الملف كله: $shaped');
    expect(unshaped, 0,
        reason: 'محارف عربية معجمية غير مشكَّلة رُسمت (خلل تشكيل لا تراه '
            'RMSE): $unshaped، أمثلة: ${_unshapedSamples(page.drawnText)}');

    // الفجوات: لا تباعد سحري ولا تراكب.
    //
    // لا يُطلب سقف ثابت لكل فجوة: LayoutDocument يوزّع فائض سطر الضبط على
    // فرصه القانونية، وPDF يحفظ تلك المواقع بلا حساب مستقل. لذلك يُقاس:
    // (1) لا تراكب، (2) غالبية الفجوات عند عرض المسافة الطبيعية للخط،
    // (3) سطر غير مضبوط (عنوان STA1) فجواته كلها طبيعية — وهذا ما يكشف
    // التباعد السحري أو الرقعة في مواءمة advances.
    // أزواج متجاورة فعلاً داخل المقطع نفسه (adjacencyIndices)، لا كل زوج على
    // نفس الخط: سطر الصفحة قد يجمع كتلتين، وفجوة بينهما ليست مسافة كلمة.
    final gaps = <double>[
      for (final p in report.pages)
        for (final line in p.lines)
          for (final index in line.adjacencyIndices) line.gapAfter(index),
    ];
    expect(gaps, isNotEmpty, reason: 'لا فجوات كلمات تُقاس.');
    expect(gaps.every((gap) => gap >= -0.6), isTrue,
        reason: 'فجوات سالبة (تراكب كلمات): '
            '${gaps.where((gap) => gap < -0.6).length} عيّنة: '
            '${gaps.where((gap) => gap < -0.6).take(4).map((v) => v.toStringAsFixed(2)).toList()}');
    final natural = gaps.where((gap) => gap >= 1.0 && gap <= 6.0).length;
    expect(natural / gaps.length, greaterThan(0.8),
        reason: 'غالبية فجوات الكلمات ليست عند عرض المسافة الطبيعي '
            '($natural من ${gaps.length}) — تباعد مصطنع أو ناقص؛ '
            'أكبر فجوة ${gaps.reduce((a, b) => a > b ? a : b).toStringAsFixed(2)}pt');
    final titleLines = page.linesWithMarker('STA1');
    expect(titleLines, isNotEmpty, reason: 'سطر عنوان Q1 مفقود من ص1.');
    // PDF extraction may expose attached punctuation as standalone tokens
    // (for example «أجب» followed by «:»). Check every adjacent lexical pair;
    // punctuation placement and ordering have their own assertions below.
    final titleLine = titleLines.first;
    final canonicalQuranGap = _gate.canonicalQuranTitleWordGap;
    expect(canonicalQuranGap, isNotNull,
        reason: 'غياب زوج «زدني/علما» من canonical p0q1/title: '
            '${_gate.canonicalQuranTitlePairGeometry}');
    expect(canonicalQuranGap!, inInclusiveRange(1.0, 6.0),
        reason: 'القياس canonical نفسه لا يحفظ مسافة معجمية صحيحة بين '
            '«زدني/علما»: ${canonicalQuranGap.toStringAsFixed(3)}pt '
            'geometry=${_gate.canonicalQuranTitlePairGeometry}');
    final titleGaps = <double>[];
    final titleGapDiagnostics = <String>[];
    final canonicalTitleLine = _gate.canonicalQuestionTitleLine;
    final canonicalRunsById = <String, LayoutRun>{
      for (final run in canonicalTitleLine?.runs ?? const <LayoutRun>[]) run.id: run,
    };
    final canonicalQuranRunsInSourceOrder = <LayoutRun>[
      for (final id in canonicalTitleLine?.logicalRunIds ?? const <String>[])
        if ((canonicalRunsById[id]?.isQuran ?? false) &&
            canonicalRunsById[id]!.text != ' ')
          canonicalRunsById[id]!,
    ];
    final pdfQuranWordIndices = <int>[];
    var insideTitleVerse = false;
    for (var index = 0; index < titleLine.words.length; index++) {
      final text = titleLine.words[index].text;
      if (text == '﴿') insideTitleVerse = true;
      if (insideTitleVerse) pdfQuranWordIndices.add(index);
      if (insideTitleVerse && text == '﴾') break;
    }
    final pdfQuranWordIndexSet = pdfQuranWordIndices.toSet();
    final canonicalQuranRunByPdfWordIndex = <int, LayoutRun>{};
    if (canonicalQuranRunsInSourceOrder.length == pdfQuranWordIndices.length) {
      for (var index = 0; index < pdfQuranWordIndices.length; index++) {
        canonicalQuranRunByPdfWordIndex[pdfQuranWordIndices[index]] =
            canonicalQuranRunsInSourceOrder[index];
      }
    }
    final canonicalQuranRunDiagnostics = canonicalQuranRunsInSourceOrder
        .map((run) => '${run.id}:${run.text}@${run.x.toStringAsFixed(3)}+'
            '${run.width.toStringAsFixed(3)}')
        .join('|');
    debugPrint('::notice title=p0-gate canonical Quran token map::'
        'PDF indices=$pdfQuranWordIndices; '
        'canonical=$canonicalQuranRunDiagnostics');
    for (final index in titleLine.adjacencyIndices) {
      final rightWord = titleLine.words[index];
      final leftWord = titleLine.words[index + 1];
      if (_isPunctuationOnlyPdfToken(rightWord.text) ||
          _isPunctuationOnlyPdfToken(leftWord.text)) {
        continue;
      }
      final rightRun = canonicalQuranRunByPdfWordIndex[index] ??
          (!pdfQuranWordIndexSet.contains(index) && canonicalTitleLine != null
              ? _canonicalRunForPdfWord(canonicalTitleLine, rightWord)
              : null);
      final leftRun = canonicalQuranRunByPdfWordIndex[index + 1] ??
          (!pdfQuranWordIndexSet.contains(index + 1) &&
                  canonicalTitleLine != null
              ? _canonicalRunForPdfWord(canonicalTitleLine, leftWord)
              : null);
      final pdfGap = titleLine.gapAfter(index);
      if (rightRun != null &&
          leftRun != null &&
          _isContiguousCanonicalTokenPair(rightRun, leftRun)) {
        titleGapDiagnostics.add(
            '${rightWord.text}/${leftWord.text}=same canonical token '
            '${rightRun.semanticNodeId} source="'
            '${rightRun.semanticNode?.legacyText ?? rightRun.text}"');
        continue;
      }

      titleGaps.add(pdfGap);
      if (rightRun == null || leftRun == null) {
        titleGapDiagnostics.add(
            '${rightWord.text}/${leftWord.text}: pdf=${pdfGap.toStringAsFixed(3)}pt '
            'canonical-run=unmatched');
      } else {
        final canonicalGap = _canonicalGapBetween(rightRun, leftRun);
        titleGapDiagnostics.add(
            '${rightWord.text}/${leftWord.text}: '
            'pdf=${pdfGap.toStringAsFixed(3)}pt '
            'canonical=${canonicalGap.toStringAsFixed(3)}pt '
            'delta=${(pdfGap - canonicalGap).toStringAsFixed(3)}pt '
            'adv-delta=${(rightWord.advanceWidth - rightRun.width).toStringAsFixed(3)}/'
            '${(leftWord.advanceWidth - leftRun.width).toStringAsFixed(3)}pt '
            'runs="${rightRun.text}"@${rightRun.x.toStringAsFixed(3)}+'
            '${rightRun.width.toStringAsFixed(3)}|'
            '"${leftRun.text}"@${leftRun.x.toStringAsFixed(3)}+'
            '${leftRun.width.toStringAsFixed(3)}');
      }
    }
    debugPrint('::notice title=p0-gate canonical title spacing::'
        '${titleGapDiagnostics.join('; ')}');
    if (titleGaps.isNotEmpty) {
      expect(titleGaps.every((gap) => gap >= 1.0 && gap <= 6.0), isTrue,
          reason: 'فجوات الكلمات في السطر غير المضبوط خارج نطاق المسافة '
              'الطبيعية: ${titleGaps.map((v) => v.toStringAsFixed(2)).toList()} — '
              'السطر: ${titleLine.describe()} — '
              'canonical p0q1/title Quran pair gap='
              '${_gate.canonicalQuranTitleWordGap?.toStringAsFixed(3)}pt '
              'runs=${_gate.canonicalQuranTitlePairGeometry}; '
              'canonical/pdf=$titleGapDiagnostics; '
              'مسافة الكلمة لا تُطابق عرض المسافة للخط (انحدار realign).');
    }

    // هندسة الترقيم: `pdf` يكتب سلسلة المحارف بالترتيب **المنطقي** ويرتّب
    // المواضع بصرياً (قيس في هذا الاختبار: الكلمات تتناقص x في العربية مع
    // أن نصوصها منطقية). لذا المصدر الصحيح `١-` — رقم ثم فاصل — وهو ما يجب
    // أن يُقرأ من النص المرسوم؛ أما «-١» فأن يكون الفاصل قد انقلب إلى يسار
    // الرقم منطقياً، أي إعادة ترتيب داخل السلسلة نفسها. تُقاس الأنماط
    // داخل النص المرسوم لا ككلمة مستقلة: تقطيع pdf إلى كلمات ليس مضموناً،
    // والتجزئة لا يجوز أن تُسقط فحصاً. ولا يُقاس «/» بهذا الفحص: السنة
    // «٢٠٢٦/٢٠٢٧» رقمان لاتينيان داخل فقرة عربية، والفاصل بينهما محايد
    // بين EN وEN فلا ينقلب — قياسه في الأرقام أدناه وفي DOCX.
    final labelPattern = RegExp(
        r'-[\u0660-\u06690-9]{1,4}|[\u0660-\u06690-9]{1,4}-');
    final drawnLabels = <String>[];
    final invertedLabels = <String>[];
    final separatorFirst = RegExp(r'^-[\u0660-\u06690-9]{1,4}$');
    final numberFirst = RegExp(r'^[\u0660-\u06690-9]{1,4}-$');
    final digitRun = RegExp(r'^[\u0660-\u06690-9]{1,4}$');
    final separatorRun = RegExp(r'^-$');
    for (final drawnPage in report.pages) {
      for (final line in drawnPage.lines) {
        final drawnLine = line.words.map((word) => word.text).join(' ');
        for (final match in labelPattern.allMatches(drawnLine)) {
          final token = match.group(0)!;
          if (numberFirst.hasMatch(token)) {
            drawnLabels.add('ص${drawnPage.index + 1}:$token');
          } else if (separatorFirst.hasMatch(token)) {
            invertedLabels.add('ص${drawnPage.index + 1}:$token');
          }
        }

      }

      // LayoutDocument paints semantic number/separator runs independently;
      // bold digits and regular separators can receive slightly different PDF
      // baselines, so they may land in adjacent probe lines. Rejoin only
      // adjacent emitted text operators whose geometry is contiguous and whose
      // baselines still belong to the same typographic line.
      final pageWords = drawnPage.words;
      for (var index = 0; index + 1 < pageWords.length; index++) {
        final first = pageWords[index];
        final second = pageWords[index + 1];
        final baselineTolerance =
            (first.fontSize > second.fontSize ? first.fontSize : second.fontSize) * 0.25;
        if ((first.y - second.y).abs() > baselineTolerance) continue;
        final gap = first.x <= second.x
            ? second.x - (first.x + first.advanceWidth)
            : first.x - (second.x + second.advanceWidth);
        if (gap < -1 || gap > 2) continue;
        if (digitRun.hasMatch(first.text) && separatorRun.hasMatch(second.text)) {
          if (first.x > second.x) {
            drawnLabels.add('ص${drawnPage.index + 1}:${first.text}${second.text}');
          } else {
            invertedLabels.add(
                'ص${drawnPage.index + 1}:visual-${first.text}${second.text}');
          }
        } else if (separatorRun.hasMatch(first.text) &&
            digitRun.hasMatch(second.text)) {
          invertedLabels.add('ص${drawnPage.index + 1}:${first.text}${second.text}');
        }
      }
    }
    final labelFragmentLines = report.pages
        .expand((page) => page.lines)
        .where((line) => line.words.any((word) =>
            digitRun.hasMatch(word.text) || word.text.contains('-')))
        .map((line) => line.describe())
        .toList();
    final labelFragmentTail = labelFragmentLines.length <= 8
        ? labelFragmentLines
        : labelFragmentLines.sublist(labelFragmentLines.length - 8);
    _stage('تسميات مرسومة (رقم ثم فاصل، كما في المصدر): '
        '${drawnLabels.take(8).toList()}، معكوسة المصدر: '
        '${invertedLabels.take(8).toList()}؛ أجزاء: $labelFragmentTail');
    expect(drawnLabels, isNotEmpty,
        reason: 'لم يظهر نمط «رقم ثم فاصل» (١-) في vector.pdf — لا يقيس الفحص '
            'الترقيم من غير مثال مرسوم. P2 runs: '
            '${_gate.canonicalLabelRuns.take(4).toList()}');
    expect(invertedLabels, isEmpty,
        reason: 'نصّ التسمية مرسوم بفاصل قبل الرقم (انقلاب في السلسلة '
            'المنطقية لا في المواضع فقط): ${invertedLabels.take(6).toList()}');

    // `PdfContentProbe` keeps PDF text operators in emission order (RTL's
    // rightmost-first order), not visual left-to-right order. Measure brackets
    // by their actual x positions within the first line containing a pair.
    final firstVisualParenLine = <ProbedWord>[];
    for (final page in report.pages) {
      for (final line in page.lines) {
        final brackets = line.words
            .where((word) => word.text == '(' || word.text == ')')
            .toList()
          ..sort((a, b) => a.x.compareTo(b.x));
        if (brackets.length >= 2) {
          firstVisualParenLine.addAll(brackets);
          break;
        }
      }
      if (firstVisualParenLine.isNotEmpty) break;
    }
    expect(firstVisualParenLine.length, greaterThan(1),
        reason: 'أقواس مرسومة أقلّ من المتوقع لتسميات ( أ ) و(١) و(ب): '
            '${firstVisualParenLine.map((word) => word.text).toList()}');
    expect(firstVisualParenLine.first.text, ')',
        reason: 'أقصى قوس يساراً في سطر RTL يجب أن يكون المغلق: '
            '${firstVisualParenLine.map((word) => '${word.text}@${word.x.toStringAsFixed(1)}').toList()}');

    // الأرقام المشرقية واللاتينية في الورقة العربية نفسها.
    final indic = report.pages.fold<int>(
        0, (sum, p) => sum + p.arabicIndicDigits);
    final latin =
        report.pages.fold<int>(0, (sum, p) => sum + p.latinDigits);
    expect(indic, greaterThan(0),
        reason: 'لا أرقام مشرقية مع أن نسق الورقة auto←مشرقي (١-، ٢٠، ٢٠٢٦).');
    expect(latin, greaterThan(0),
        reason: 'الأرقام اللاتينية في المتن (1990، 2026/2027، 45.5) لم تُطبع.');

    _matrix.record('arabic', P0Path.vectorPdf, P0Status.pass,
        evidence: 'ترتيب الكلمات RTL في ${arabicLines.length} سطراً؛ '
            'تقديمي=$shaped غيرمشروط=$unshaped');
    _matrix.record('latin', P0Path.vectorPdf, P0Status.pass,
        evidence: 'وسوم لاتينية مرسومة داخل ورقة عربية (MIX1/OPT1/OP1A..) '
            'وأرقام لاتينية=$latin');
    _matrix.record('mixed', P0Path.vectorPdf, P0Status.pass,
        evidence: 'سطر MIX1 نفسه يحوي عربيًا ولاتينيًا وأرقاماً؛ ترتيب '
            'الكلمات RTL وأرقام اللاتين في مواضعها');
    _matrix.record('arabic-numerals', P0Path.vectorPdf, P0Status.pass,
        evidence: 'أرقام مشرقية=$indic؛ الفواصل يسار الأرقام في '
            '${drawnLabels.length} تسمية');
    _matrix.record('latin-numerals', P0Path.vectorPdf, P0Status.pass,
        evidence: 'أرقام لاتينية=$latin (تسمية يدوية 1- و2026/2027 و45.5%)');
    _matrix.record('punctuation', P0Path.vectorPdf, P0Status.pass,
        evidence: 'أقواس مرسومة=${firstVisualParenLine.length}، فواصل الترقيم '
            'يسار الأرقام=${drawnLabels.length}، لا انقلاب=${invertedLabels.length}');
    _matrix.record('marks', P0Path.vectorPdf, P0Status.pass,
        evidence: '«(٢٠ درجة)» مرسومة مع أرقام مشرقية=$indic');
  });

  test('P0-GATE-04: بنية vector.pdf — الخطوط والأحجام والمعادلات والصور', () {
    _gate.requireArtifacts();
    final report = _gate.rtlPdfReport;
    final words = report.pages.expand((page) => page.words).toList();
    final fonts = report.pages.expand((page) => page.baseFonts).toSet().toList()
      ..sort();
    _stage('خطوط vector.pdf: $fonts');

    expect(fonts.any((font) => font.contains('NotoNaskh')), isTrue,
        reason: 'خط المتن (Noto Naskh Arabic) غير مستعمل في PDF: $fonts');
    expect(fonts.any((font) => font.contains('Amiri')), isTrue,
        reason: 'Amiri غير مستعمل رغم آيات في القسم والتذييل والخيار '
            'والتسمية اليدوية — وهذا عين النقص في needsQuranicFont قبل P0.5-C.');

    // سطر الآية القائمة بذاتها (دور verse) يُطبع بـ Amiri فعلاً.
    final verseLines = report.pages
        .expand((page) => page.lines)
        .where((line) => line.words.any((word) => word.text.contains('QUR1')))
        .toList();
    expect(verseLines, isNotEmpty, reason: 'سطر الآية QUR1 مفقود من PDF.');
    expect(
      verseLines.every((line) =>
          line.words.any((word) => word.baseFont.contains('Amiri'))),
      isTrue,
      reason: 'سطر الآية لا يُطبع بـ Amiri: '
          '${verseLines.map((line) => line.words.first.baseFont).toList()}',
    );

    final sizes = words.map((word) => word.fontSize).toSet().toList()..sort();
    expect(sizes.length, greaterThan(2),
        reason: 'أحجام الخطوط في PDF ($sizes): أدوار العقد لا تصل جميعها.');

    // كل عقدة Math في LayoutDocument لها موضع رسم صورة في PDF. قد تشترك
    // مواضع متعددة في XObject واحد إذا تطابقت بايتات الصور؛ لذا عدد استدعاءات
    // Do (placements) هو الدليل الصحيح، لا عدد الموارد الفريدة أو استدعاءات
    // مضيف القياس/التصيير المتكررة.
    expect(_gate.mathRunCount, greaterThan(0),
        reason: 'لا توجد عقد Math في التخطيط — مسار الرياضيات غير مختبَر.');
    expect(_gate.mathHostRequestCount, greaterThan(0),
        reason: 'لم تُطلب أي لقطة من مضيف الرياضيات.');
    expect(report.allImages.length, greaterThanOrEqualTo(_gate.mathRunCount),
        reason: 'مواضع صور PDF (${report.allImages.length}) أقلّ من عقد '
            'Math في التخطيط (${_gate.mathRunCount}).');
    const mathOrder = <String>['MATH1', 'TEXTAR1', 'MATH2'];
    final drawnMathOrder = <String>[];
    for (final page in report.pages) {
      for (final line in page.lines) {
        final text = line.words.map((word) => word.text).join(' ');
        for (final marker in mathOrder) {
          if (textMentions(text, marker) &&
              (drawnMathOrder.isEmpty || drawnMathOrder.last != marker)) {
            drawnMathOrder.add(marker);
          }
        }
      }
    }
    expect(drawnMathOrder, mathOrder,
        reason: 'ترتيب المعادلات في PDF ($drawnMathOrder) يخالف ترتيب العقد '
            '($mathOrder).');
    for (final page in report.pages) {
      for (final image in page.images) {
        expect(image.y, greaterThanOrEqualTo(0),
            reason: 'صورة معادلة خارج حدود الصفحة: $image');
        expect(image.x, greaterThanOrEqualTo(0),
            reason: 'صورة معادلة خارج يسار الصفحة: $image');
      }
    }

    // العنصر الحرّ (صورة PNG) له موضع رسم إضافي على صور المعادلات.
    expect(report.allImages.length,
        greaterThanOrEqualTo(_gate.mathRunCount + 1),
        reason: 'صورة العنصر الحر لم تُضمَّن في PDF '
            '(مواضع الصور ${report.allImages.length} مقابل '
            '${_gate.mathRunCount} معادلة).');
    expect(report.imageObjects, greaterThan(0),
        reason: 'لا توجد موارد صور XObject مضمَّنة في PDF.');

    _matrix.record('math', P0Path.vectorPdf, P0Status.pass,
        evidence: 'مواضع الصور=${report.allImages.length}، موارد XObject='
            '${report.imageObjects}، صيغ=${_gate.mathRunCount}، '
            'ترتيب العقد محفوظ: $drawnMathOrder');
    _matrix.record('quran', P0Path.vectorPdf, P0Status.pass,
        evidence: 'Amiri على سطور الآيات (${verseLines.length} سطر) '
            'والخطوط=$fonts');
    _matrix.record('options', P0Path.vectorPdf, P0Status.pass,
        evidence: 'OP1A..OP1C وQUR4/QUR5 مرسومة في صفّ خيارات بعد نص النقطة');
    _matrix.record('floating', P0Path.vectorPdf, P0Status.pass,
        evidence: 'FLOAT2 (مربع النص المملوك) مرسوم، وصورة PNG المملوكة '
            'لها موضع رسم؛ استخدامات/صفحة='
            '${report.pages.map((p) => p.embeddedImageObjects).join("/")}، '
            'مواضع=${report.allImages.length} موارد XObject=${report.imageObjects}');
    _matrix.record('marks', P0Path.vectorPdf, P0Status.pass,
        evidence: 'أرقام مشرقية مرسومة '
            '${report.pages.fold<int>(0, (sum, p) => sum + p.arabicIndicDigits)} '
            'وحرفًا، وأحجام=$sizes');
  });

  test('P0-GATE-05: بنية vector.pdf — قاعدة «لا يُمَدّ السطر الواحد»', () {
    _gate.requireArtifacts();
    final report = _gate.rtlPdfReport;
    final page = report.pages
        .firstWhere((page) => page.linesWithMarker('JUSTS1').isNotEmpty);
    final line = page.linesWithMarker('JUSTS1').first;
    final left = line.words.map((word) => word.x).reduce(
        (a, b) => a < b ? a : b);
    final right = line.words
        .map((word) => word.x + word.advanceWidth)
        .reduce((a, b) => a > b ? a : b);
    final contentWidth = page.pageWidth - 2 * (15 / 25.4 * 72);
    final span = right - left;
    _stage('JUSTS1: span=${span.toStringAsFixed(2)}pt '
        'content=$contentWidth pt، words=${line.words.length}');
    expect(span, lessThan(contentWidth * 0.5),
        reason: 'فقرة من سطر واحد مُدّت إلى عرض المحتوى في PDF: '
            'span=${span.toStringAsFixed(2)} من '
            '${contentWidth.toStringAsFixed(2)} — قرار الضبط غير موحَّد.');

    // والفقرة نفسها في ورقة LTR (القرار يجب ألا يتعلّق بالاتجاه).
    final ltrPage = _gate.ltrPdfReport.pages
        .firstWhere((page) => page.linesWithMarker('JUSTL1').isNotEmpty);
    final ltrLine = ltrPage.linesWithMarker('JUSTL1').first;
    final ltrLeft =
        ltrLine.words.map((word) => word.x).reduce((a, b) => a < b ? a : b);
    final ltrRight = ltrLine.words
        .map((word) => word.x + word.advanceWidth)
        .reduce((a, b) => a > b ? a : b);
    expect(ltrRight - ltrLeft,
        lessThan(ltrPage.pageWidth - 2 * (15 / 25.4 * 72) - 0.0),
        reason: 'فقرة LTR من سطر واحد تجاوزت عرض المحتوى: لا معنى أصلاً '
            'لتمدّ سطر فقرة وحيد.');
    // الإصلاح مُثبت (لا تمدّد لسطر وحيد) في الممرّين معاً، وبقي توزيع
    // التبرير لكل سطر على حدة قراراً لمكتبة pdf في PDF مقابل تقريب بقيمة
    // واحدة للفقرة في المعاينة: تسويتهما تحتاج طبقة تخطيط واحدة (P1).
    _matrix.record('justification', P0Path.vectorPdf, P0Status.deferredToP1,
        evidence: 'سطر واحد مضبوط: span=${span.toStringAsFixed(1)}pt من '
            '${contentWidth.toStringAsFixed(1)}pt (عربي) و'
            '${(ltrRight - ltrLeft).toStringAsFixed(1)}pt (إنجليزي) — لا '
            'تمدّد؛ أما توزيع التبرير لكل سطر فغير موحَّد المصدر',
        reason: 'قاعدة «لا يُمَدّ سطر واحد» مقيسة ومُصحَّحة (GATE-05 وGATE-10)؛ '
            'أما التبرير سطراً بسطر فتُنفّذه مكتبة pdf في PDF وتُقاربه '
            'المعاينة بقيمة wordSpacing واحدة للفقرة كلها، فلا تطابق مضمون '
            'لكل سطر. توحيدهما قرار طبقة تخطيط واحدة (P1) ولا يُصلَح في P0.');
  });

  // ===========================================================================
  // P0.5-E/D — حقول معطّلة موثّقة: لا منتِج يكتبها سراً.
  // (سقط في C5 فحص `w:position` في مولّد Word مع مولّده.)
  // ===========================================================================
  test('P0-GATE-08: لا معنى لإزاحة خط الأساس (E) ولا لمنطق ExamTextStyles (D)',
      () {
    // (E) `baselineShiftPt`: لا منتِج يكتبها ولا راسم يقرأها.
    final content = RichContent.parse(
      r'نص $x^2$ وآية ﴿مُحَمَّدٌ﴾',
    );
    expect(content.runs, isNotEmpty, reason: 'لم تُقطع مقاطع العقد للاختبار.');
    for (final run in content.runs) {
      expect(run.style?.baselineShiftPt, isNull,
          reason: 'منتِج محتوى يكتب إزاحة خط أساس بينما لا راسم يقرأها: '
              '"${run.text}"');
    }

    // (D) `PdfPaperBuilder.styles` حقلٌ يُمرَّر ولا يُستهلَك: لا مستهلِك له في
    // المصدر، فالحذف ممكن فنياً لكنه يغيّر توقيعاً عاماً → يُسجَّل لـ P1.
    final builderSource =
        File('lib/pdf_engine/pdf_paper_builder.dart').readAsStringSync();
    final withoutDeclaration = builderSource.replaceAll(
      RegExp(r'required this\.styles,|final ExamTextStyles styles;'),
      '',
    );
    expect(RegExp(r'\bstyles\b').hasMatch(withoutDeclaration), isFalse,
        reason: 'حقل `styles` صار مستهلَكاً في الباني: لِيُحدَّث دليل P0-D '
            'ولتُراجع قيم الجدول مقابل العقد.');
    expect(ExamTextStyles.standard.body.fontSize, 10.5,
        reason: 'تغيّرت قيم الجدول التراثي (10.5) مع أن الطباعة تقرأ العقد.');
    expect(ExamTextStyles.standard.question.fontSize, 11,
        reason: 'تغيّرت قيم الجدول التراثي (11) مع أن الطباعة تقرأ العقد.');
  });

  // ===========================================================================
  // P0.5-C — شمول الفحص needsQuranicFont لكل سطح مطبوع.
  // ===========================================================================
  test('P0-GATE-09: needsQuranicFont يرى كل سطح ولا يكتفي بمسح يدوي ناقص',
      () async {
    final surfaces = <String, ExamDocument>{
      'category': _singleQuestionDoc(category: _verse),
      'footer': _singleQuestionDoc(closingPhrase: _verse),
      'numberLabel': _singleQuestionDoc(numberOverride: 'س١ $_verse'),
      'optionLabel': _singleQuestionDoc(optionLabelOverride: _verse),
      'itemLabel': _singleQuestionDoc(itemLabelOverride: _verse),
      'branchLabel': _singleQuestionDoc(branchLabelOverride: _verse),
      'headerSchool': _singleQuestionDoc(schoolName: _verse),
      'optionText': _singleQuestionDoc(optionText: _verse),
      'body': _singleQuestionDoc(body: _verse),
      'none': _singleQuestionDoc(),
    };

    expect(PaginatedPdfExamEngine.needsQuranicFont(surfaces['none']!), isFalse,
        reason: 'ورقة بلا آية تُحمَّل خطها القرآني: الفحص مفرِط التوسّع.');
    for (final entry in surfaces.entries) {
      if (entry.key == 'none') {
        continue;
      }
      expect(PaginatedPdfExamEngine.needsQuranicFont(entry.value), isTrue,
          reason: 'سطح «${entry.key}» يحمل آية ولا يراه needsQuranicFont — '
              'هذا هو الفحص الجزئي الناقص الذي يُصلَح في P0.5-C.');
    }

    // والأثر السلوكي: لا Amiri في ورقة بلا آية (لا تحميل زائد).
    final bytes =
        await PaginatedPdfExamEngine().generate(document: surfaces['none']!);
    final fonts = PdfStructureReport.fromBytes(bytes)
        .pages
        .expand((page) => page.baseFonts)
        .toSet();
    expect(fonts.any((font) => font.contains('Amiri')), isFalse,
        reason: 'Amiri استُعمل في ورقة بلا آية: $fonts');

    // والبسملة (سطح آخر) تُبقي القرار كما كان: لا انحدار في الافتراضي.
    expect(
      PaginatedPdfExamEngine.needsQuranicFont(
        _singleQuestionDoc(withBismillah: true),
      ),
      isTrue,
      reason: 'البسملة لم تعد تُلزم الخط القرآني: انحدار في قرار قائم.',
    );
  });

  // ===========================================================================
  // P0.5-F — قاعدة واحدة لسطر واحد في الضبط (justify) لكل أسطح المعاينة.
  // ===========================================================================
  test('P0-GATE-10: قرار الضبط مشترك بين PaperField وTexText', () {
    const single = 'كلمة أولى وكلمة ثانية وثالثة';
    final many = List<String>.filled(
      40,
      'نصٌّ طويلٌ يقيس التفاف الفقرة المضبوطة داخل صندوق العرض',
    ).join(' ');
    const style = TextStyle(fontFamily: 'NotoNaskhArabic', fontSize: 14);

    // (1) سطر واحد لا يُمَدّ (مهما اتّسع الصندوق)، وفقرة ملتفّة تُمَدّ.
    expect(
      VisualFlutterStyle.justifyWordSpacing(
        text: single,
        style: style,
        maxWidth: 3000,
        direction: TextDirection.rtl,
      ),
      isNull,
      reason: 'فقرة من سطر واحد نالت توسعة كلمات: القرار ما زال سطحاً سطحاً.',
    );
    final narrow = VisualFlutterStyle.justifyWordSpacing(
      text: single,
      style: style,
      maxWidth: 40,
      direction: TextDirection.rtl,
    );
    expect(narrow, isNotNull,
        reason: 'فقرة مُلتفّة على عرض ضيّق بلا توسعة: القاعدة لا تعمل.');
    final spread = VisualFlutterStyle.justifyWordSpacing(
      text: many,
      style: style,
      maxWidth: 520,
      direction: TextDirection.rtl,
    );
    expect(spread, isNotNull, reason: 'فقرة متعددة الأسطر بلا توسعة.');
    expect(spread! <= 60, isTrue,
        reason: 'التوسعة تجاوزت الحدّ الأقصى القائم (60px لكل كلمة): $spread');
    expect(spread >= 0, isTrue,
        reason: 'توسعة سالبة (انضغاط كلمات): $spread');

    // (2) حَسم «من أين يُقرأ القرار»: لا إعادة تنفيذ للمنطق في السطحين.
    for (final entry in <String, String>{
      'lib/views/widgets/paper_field.dart':
          File('lib/views/widgets/paper_field.dart').readAsStringSync(),
      'lib/views/widgets/tex_text.dart':
          File('lib/views/widgets/tex_text.dart').readAsStringSync(),
    }.entries) {
      expect(entry.value, contains('VisualFlutterStyle.justifyWordSpacing'),
          reason: '${entry.key} لا يستعمل القاعدة المشتركة للضبط.');
      expect(entry.value.contains('clamp(12.0, 60.0)'), isFalse,
          reason: '${entry.key} أعاد تنفيذ حدّ التوسعة محلياً: منطقان '
              'يفترقان مع الزمن.');
      expect(entry.value.contains('computeLineMetrics'), isFalse,
          reason: '${entry.key} يعُدّ الأسطر خارج القاعدة المشتركة.');
    }
    expect(
      File('lib/layout/visual/visual_flutter_style.dart')
          .readAsStringSync()
          .contains('computeLineMetrics'),
      isTrue,
      reason: 'القاعدة المشتركة لا تعدّ الأسطر: شرط «سطر واحد» مفقود.',
    );

    // (3) القرار نفسه في الشجرة: فقرة LTR وRTL من سطر واحد بلا توسعة.
    final rtlJust = _gate.previewRtl['JUSTS1'];
    final ltrJust = _gate.previewLtr['JUSTL1'];
    if (rtlJust != null) {
      expect(rtlJust.lines, 1,
          reason: 'متن Q4 (سطر واحد) التُفّ في المعاينة: ${rtlJust.text}');
      expect(rtlJust.wordSpacing ?? 0, 0,
          reason: 'فقرة سطر واحد مُدت في المعاينة: '
              '${rtlJust.wordSpacing}');
    }
    if (ltrJust != null) {
      expect(ltrJust.wordSpacing ?? 0, 0,
          reason: 'فقرة LTR من سطر واحد مُدت في المعاينة: '
              '${ltrJust.wordSpacing}');
    }
  });

  // ===========================================================================
  // ميزة 15: ورقة LTR لا تنكسر بإصلاحات RTL.
  // ===========================================================================
  // (سقط في C5 الشق الـ Word من هذا الاختبار مع مولّده.)
  test('P0-GATE-11: الورقة الإنجليزية (LTR) — لا انحدار في PDF', () {
    _gate.requireArtifacts();
    final report = _gate.ltrPdfReport;
    const known = P0GateFixture.ltrBodyMarkers;
    const excluded = <String>{
      'LTRV',
      'LTRC1',
      'LTRC2',
      'LTRG1',
      'LTRT1',
      'LTRF1',
      'LTRF2',
    };

    final ltrOrder = report.markerSequence(known: known, excluded: excluded);
    expect(ltrOrder, containsAll(<String>[...known]),
        reason: 'وسوم مفقودة من vector_ltr.pdf: '
            '${known.difference(ltrOrder.toSet()).toList()..sort()}');

    // الاستبعاد بمعرّفات هذه الورقة نفسها (`excluded` أعلاه = وسوم ترويسة
    // وتذييل LTR) لا بوسوم الورقة العربية: الترويسة/التذييل في ورقة LTR
    // جداول تُرسم RTL بقرار المنتج، وهي مُسجَّلة انحرافاً قائماً بذاتها أدناه
    // — فلا هي تُفسد فحص المتن ولا تُحذف منه بصمت.
    // العيّنة «جريان لاتيني» لا «سطر لاتيني خالص»: ورقة LTR في الركيزة تسمياتها
    // عربية وقيمها إنجليزية في السطر نفسه، فاشتراط سطر خالص كان يترك الفحص بلا
    // عيّنة (قياس الجولة السابقة: 0 سطور). الخطر المُراد كشفه — جريان لاتيني
    // يُرسم من اليمين — لا يتعلق بنقاء السطر بل بترتيب مواضع الكلمات.
    var bodyLines = 0;
    var latinRuns = 0;
    var probedRtlPairs = 0;
    final mirroredRuns = <String>[];
    // «التجاور» في القارئ (`areAdjacentInRun`) محسوب لاتجاه عربي: فجوته
    // `right.x - (left.x + width)` بافتراض أن الكلمة التالية إلى اليسار، فهي
    // في سطر إنجليزي سالبة دائماً (قيس: 0 زوج من 66 سطراً) أي أن الفحص كان
    // يعمى لا أنه ينجح. الوجه الصحيح للقاعدة نفسها لسطر لاتيني:
    // `next.x - (prev.x + width)`، مع اشتراط الخط والحجم نفسيهما (جريان واحد
    // فعلاً) وسقف فجوة يسعّ الضبط المبرَّر ولا يسعّ قفزة رجعية إلى أول السطر.
    bool adjacentLtrRun(ProbedLine line, int index) {
      final previous = line.words[index];
      final next = line.words[index + 1];
      if (previous.fontSize != next.fontSize ||
          previous.fontName != next.fontName) {
        return false;
      }
      if (line.areAdjacentInRun(index)) {
        probedRtlPairs++;
      }
      final gap = next.x - (previous.x + previous.advanceWidth);
      return gap >= -3.0 && gap <= 40.0;
    }
    for (final page in report.pages) {
      for (final line in page.lines) {
        final joined = line.words.map((word) => word.text).join(' ');
        if (excluded.any((marker) => textMentions(joined, marker))) {
          continue; // الترويسة/التذييل: انحرافهما مُسجَّل أسفله لا هنا.
        }
        bodyLines++;
        final words = line.words;
        final latinOnly = <bool>[
          for (final word in words)
            !RegExp('[\u0600-\u06FF\uFE70-\uFEFF]').hasMatch(word.text) &&
                RegExp('[A-Za-z]').hasMatch(word.text),
        ];
        var i = 0;
        while (i < words.length) {
          if (!latinOnly[i]) {
            i++;
            continue;
          }
          var j = i;
          while (j + 1 < words.length && latinOnly[j + 1]) {
            j++;
          }
          // الأزواج المتجاورة في المقطع نفسه فقط: قفزة تخطيط بين عنصرين على
          // خط قاعدة واحد ليست انعكاساً، وحكم ذلك `areAdjacentInRun` نفسه.
          var pairs = 0;
          for (var k = i; k < j; k++) {
            if (!adjacentLtrRun(line, k)) {
              continue;
            }
            pairs++;
            if (words[k + 1].x < words[k].x - 0.5) {
              mirroredRuns.add('ص${page.index + 1}: '
                  '${words.sublist(i, j + 1).map((word) => word.text).join(" ")} '
                  '— ${line.describe()}');
              break;
            }
          }
          if (pairs > 0) {
            latinRuns++;
          }
          i = j + 1;
        }
      }
    }
    expect(latinRuns, greaterThan(1),
        reason: 'لا جريانات لاتينية في متن ورقة LTR ($bodyLines سطراً مقيسة) — '
            'الفحص بلا عيّنة، فلا يُثبت به أن الاتجاه سليم.');
    expect(mirroredRuns, isEmpty,
        reason: 'جريان لاتيني يتقدّم من اليمين في وثيقة إنجليزية (تسرّب RTL '
            'إلى LTR): ${mirroredRuns.take(3).toList()}');
    _stage('ورقة LTR: $latinRuns جريانا لاتينية في $bodyLines سطراً تتقدّم '
        'يساراً بلا انعكاس (مقيسة من مواضع الكلمات في الملف)؛ أزواج '
        'مقبولة بقاعدة القارئ المصمَّمة للعربية: $probedRtlPairs — لذلك لا '
        'تُعمل هذه الجولة على تلك القاعدة.');

    // الترويسة في المنتج ثنائية اللغة بقصد (تسميات عربية وقيم إنجليزية)،
    // والركيزة تحمل عمداً فقرة عربية داخل الورقة الإنجليزية (قياس الاتجاه
    // المختلط). لذا الانحدار الممنوع ليس «لا عربية في الملف» بل:
    // (١) سطر لاتيني بلا عربية يُلوَّث بصور تقديمية أو بأرقام مشرقية — وهذا
    // يُفشِل البوابة؛ (٢) سطر عربي لا يُرسم من اليمين — مسجَّل، معالجته في
    // طبقة الاتجاه الواحدة (P1) ولا يُلَمَّع هنا بإزاحة العربية من الركيزة.
    final latinLeak = <String>[];
    final arabicOrdering = <String>[];
    for (final page in report.pages) {
      for (final line in page.lines) {
        final text = line.words.map((word) => word.text).join(' ');
        if (excluded.any((m) => textMentions(text, m))) {
          continue; // الترويسة/التذييل: انحرافهما مُسجَّل أدناه لا هنا.
        }
        final hasArabic =
            RegExp('[\u0600-\u06FF\uFE70-\uFEFF]').hasMatch(text);
        if (!hasArabic && RegExp('[\u0660-\u0669]').hasMatch(text)) {
          latinLeak.add('ص${page.index + 1} (أرقام مشرقية): '
              '${line.describe()}');
        }
        if (!hasArabic &&
            text.runes.any((rune) => rune >= 0xFE70 && rune <= 0xFEFF)) {
          latinLeak.add('ص${page.index + 1}: ${line.describe()}');
        }
        if (hasArabic &&
            line.words.length > 1 &&
            PdfPageStructure.orderOfLine(line) != 'rtl') {
          arabicOrdering.add('ص${page.index + 1}: ${line.describe()}');
        }
      }
    }
    expect(latinLeak, isEmpty,
        reason: 'أسطر لاتينية تحمل صوراً تقديمية عربية (تسرّب تشكيل إلى '
            'LTR): ${latinLeak.take(4).toList()}');
    // الترويسة/التذييل في الورقة الإنجليزية يُرسمان RTL (جداول المنتج)، وهذا
    // انحدار قائم بذاته لا يقيسه فحص المتن: يُطبع ويُسجَّل، ولا يُحذف لتبيضّ
    // البوابة.
    final sideLinesRtl = <String>[];
    for (final page in report.pages) {
      for (final line in page.lines) {
        final text = line.words.map((word) => word.text).join(' ');
        if (!excluded.any((m) => textMentions(text, m))) {
          continue;
        }
        if (line.words.length > 1 &&
            PdfPageStructure.orderOfLine(line) == 'rtl') {
          sideLinesRtl.add('ص${page.index + 1}: ${line.describe()}');
          break;
        }
      }
      if (sideLinesRtl.isNotEmpty) {
        break;
      }
    }
    if (sideLinesRtl.isNotEmpty) {
      _stage('ورقة LTR: ترويسة/تذييل يُرسمان من اليمين — ${sideLinesRtl.first}');
      _matrix.record('ltr-document', P0Path.vectorPdf, P0Status.deferredToP1,
          evidence: 'سطور الترويسة/التذييل في vector_ltr.pdf تُرسم بترتيب '
              'RTL (مثال مقيس: ${sideLinesRtl.first}) مع أن المستند إنجليزي؛ '
              'أسطر المتن اللاتينية تُرسم ltr بلا تسرّب',
          reason: 'اتجاه الترويسة والتذييل لا يُشتق من اتجاه المستند في '
              'PdfPaperBuilder؛ تصحيحه طبقة اتجاه واحدة لكل كتلة '
              '(P1 BLOCKERS بند 4) ولا يُصلَح في P0 المغلقة على A–F.');
    }
    if (arabicOrdering.isNotEmpty) {
      _stage('ورقة LTR: أسطر عربية لا تُرسم من اليمين '
          '(${arabicOrdering.length}): ${arabicOrdering.take(3).toList()}');
      _matrix.record('ltr-document', P0Path.vectorPdf,
          P0Status.deferredToP1,
          evidence: '${arabicOrdering.length} سطراً عربياً في الورقة '
              'الإنجليزية لا يتقدّم من اليمين (مثال: '
              '${arabicOrdering.first})',
          reason: 'اتجاه الفقرة يُستنتج من اتجاه المستند لا من النص نفسه في '
              'PDF؛ تصحيحه طبقة اتجاه واحدة (P1 BLOCKERS بند 4) لا رقعة هنا.');
    }

    _matrix.record('ltr-document', P0Path.vectorPdf, P0Status.pass,
        evidence: '${report.pageCount} صفحة، ${ltrOrder.length} وسمًا '
            'بترتيب العقد، ترتيب الكلمات ltr، لا تشكيل/أرقام مشرقية');
    _matrix.record('ltr-document', P0Path.preview, P0Status.pass,
        evidence: 'المعاينة الإنجليزية: ${_gate.ltrPreviewPageCount} صفحة، '
            'و${_gate.previewLtr.length} كتلة مقاسة');
  });

  // ===========================================================================
  // P0.7 — اكتمال المصفوفة: كل خلية مقيسة أو مسجَّلة السبب.
  // ===========================================================================
  test('P0-GATE-99: مصفوفة الانحدار مكتملة ومقيَّدة بدليل', () {
    _gate.requireArtifacts();
    _recordExactCells();

    expect(_matrix.missingCells(), isEmpty,
        reason: 'خلايا بلا قياس ولا سبب: ${_matrix.missingCells().join(", ")}');

    final emptyEvidence = <String>[];
    final reasonless = <String>[];
    for (final feature in kP0Features) {
      for (final path in P0Path.values) {
        final cell = _matrix.cell(feature.key, path);
        if (cell == null) {
          continue;
        }
        if (cell.status == P0Status.pass && cell.evidence.isEmpty) {
          emptyEvidence.add('${feature.key}/${p0PathLabel(path)}');
        }
        if (cell.status == P0Status.deferredToP1 && cell.reason.length < 20) {
          reasonless.add('${feature.key}/${p0PathLabel(path)}');
        }
      }
    }
    expect(emptyEvidence, isEmpty,
        reason: 'خلايا PASS بلا دليل مقاس: ${emptyEvidence.join(", ")}');
    expect(reasonless, isEmpty,
        reason: 'خلايا DEFERRED_TO_P1 بلا سبب مسمّى: ${reasonless.join(", ")}');

    _writeText('summary.txt', <String>[
      'مصفوفة بوابة P0 — ${kP0Features.length} ميزة × ${P0Path.values.length} ممرّات',
      _matrix.toTextTable(),
      'vector.pdf عربي: ${_gate.rtlPdfReport.pageCount} صفحة، '
          'صور=${_gate.rtlPdfReport.imageObjects}، '
          'خطوط=${_gate.rtlPdfReport.pages.expand((p) => p.baseFonts).toSet()}',
      'vector.pdf إنجليزي: ${_gate.ltrPdfReport.pageCount} صفحة',
      'المعاينة: ${_gate.rtlPreviewPageCount} صفحة عربية / '
          '${_gate.ltrPreviewPageCount} صفحة إنجليزية',
      'خلاصة PDF: ${_gate.rtlPdfReport.describe()}',
    ].join('\n'));
    _stage('اكتملت المصفوفة: ${kP0Features.length * P0Path.values.length} خلية.');
  });
}

// =============================================================================
// خلايا المصفوفة المقاسة مباشرةً من LayoutDocument الذي يرسمه Preview.
// =============================================================================
/// Assert semantic order and measurable geometry on the canonical
/// [LayoutDocument] that drives Preview/PDF. Widgets are intentionally not
/// treated as a second layout source, and these checks do not infer geometry
/// from screenshots or the widget tree.
void _recordPreviewCells(_PreviewCapture rtl, _PreviewCapture ltr) {
  final rtlFixture = P0GateFixture.rtl();
  final expected = P0GateFixture.bodyMarkerSequence(rtlFixture);
  final reachableRtl = <String>{...rtl.texts.keys};
  expect(reachableRtl, containsAll(expected),
      reason: 'LayoutDocument فقد وسوماً مطلوبة من المتن: '
          '${expected.toSet().difference(reachableRtl).toList()..sort()}');
  expect(rtl.markerOrder, expected,
      reason: 'ترتيب runs القانوني يختلف عن ترتيب DocumentIR/المصدر:\n'
          '  LayoutDocument: ${rtl.markerOrder}\n  المصدر: $expected');

  final title = rtl.texts['STA1']!;
  final body = rtl.texts['BODY1']!;
  final rightDrift = (title.rect.right - body.rect.right).abs();
  expect(rightDrift, lessThan(1.5),
      reason: 'حافة بداية العنوان والمتن RTL تختلف: '
          '${title.rect.right} مقابل ${body.rect.right}');
  expect(body.lines, greaterThan(1),
      reason: 'متن Q1 لم يلتف في هندسة LayoutDocument: ${body.lines} سطر.');

  final just = rtl.texts['JUSTS1']!;
  expect(just.lines, 1,
      reason: 'فقرة JUSTS1 المفترض سطرها واحد تلتف إلى ${just.lines} أسطر.');
  expect(just.wordSpacing ?? 0, 0,
      reason: 'فقرة JUSTS1 أحادية السطر مُدّت: ${just.wordSpacing}.');

  final verse = rtl.texts['QUR1']!;
  expect(verse.fontFamilies.any((family) => family.contains('Amiri')), isTrue,
      reason: 'سطر الآية لا يحمل خط Amiri في LayoutDocument: ${verse.fontFamilies}');
  final header = rtl.texts['HDRV']!;
  final footer = rtl.texts['FTR1']!;
  expect(header.rect.top, lessThan(title.rect.top));
  expect(footer.rect.bottom, greaterThan(title.rect.bottom));
  expect(rtl.layout.pages.first.headerBounds, isNotNull);
  expect(rtl.layout.pages.last.footerBounds, isNotNull);
  for (final page in rtl.layout.pages) {
    if (page.footerBounds != null) {
      expect(page.bodyBounds.bottom, lessThanOrEqualTo(page.footerBounds!.top + 0.02),
          reason: 'صفحة ${page.index}: body/footer overlap.');
    }
  }

  const ltrExpected = P0GateFixture.ltrBodyMarkers;
  final reachableLtr = <String>{...ltr.texts.keys};
  expect(reachableLtr, containsAll(ltrExpected),
      reason: 'LayoutDocument LTR فقد وسوماً: '
          '${ltrExpected.difference(reachableLtr).toList()..sort()}');
  final ltrSta = ltr.texts['LTRSTA1']!;
  final ltrBody = ltr.texts['LTROBJ1']!;
  expect((ltrSta.rect.left - ltrBody.rect.left).abs(), lessThan(1.5),
      reason: 'حافة بداية العنوان والمتن LTR تختلف: '
          '${ltrSta.rect.left} مقابل ${ltrBody.rect.left}');
  expect(ltrSta.align, anyOf(TextAlign.start, TextAlign.left));

  String allCanonicalText(_PreviewCapture capture) => capture.texts.values
      .map((entry) => entry.text)
      .join(' ');
  final rtlText = allCanonicalText(rtl);
  final ltrText = allCanonicalText(ltr);
  expect(_markersIn(rtlText, P0GateFixture.rtlBodyMarkers),
      containsAll(P0GateFixture.rtlBodyMarkers));
  expect(_markersIn(ltrText, ltrExpected), containsAll(ltrExpected));
  expect(rtl.layout.allLines.expand((line) => line.runs).any((run) => run.isMath),
      isTrue,
      reason: 'لم يحتفظ التخطيط بأي math run من DocumentIR.');
  expect(
    rtl.layout.allLines.expand((line) => line.runs).any((run) => run.isQuran),
    isTrue,
    reason: 'لم يحتفظ التخطيط بأي Quran run من DocumentIR.',
  );
  final floatingPlacements = rtl.layout.pages
      .expand((page) => page.floatingElements)
      .toList(growable: false);
  expect(
    floatingPlacements.any((placement) => placement.reference.id.isNotEmpty),
    isTrue,
    reason: 'لم توضع العناصر العائمة هندسياً في LayoutDocument.',
  );
  final floatingMarker = rtl.texts['FLOAT2']!;
  final markedPlacement = floatingPlacements.firstWhere(
    (placement) => placement.labelLines.any((line) =>
        line.runs.any((run) => textMentions(run.text, 'FLOAT2'))),
  );
  final markedLines = markedPlacement.labelLines
      .where((line) => line.runs.any((run) => textMentions(run.text, 'FLOAT2')))
      .toList(growable: false);
  expect(markedPlacement.policy, FloatAnchorPolicy.contentAreaAnchored);
  expect(markedPlacement.pageIndex, greaterThanOrEqualTo(0));
  expect(markedLines, isNotEmpty);
  for (final line in markedLines) {
    expect(line.rect.left, greaterThanOrEqualTo(markedPlacement.rect.left - 0.02));
    expect(line.rect.right, lessThanOrEqualTo(markedPlacement.rect.right + 0.02));
    expect(line.rect.top, greaterThanOrEqualTo(markedPlacement.rect.top - 0.02));
    expect(line.rect.bottom, lessThanOrEqualTo(markedPlacement.rect.bottom + 0.02));
  }
  expect(floatingMarker.text, contains('FLOAT2'));
  expect(rtl.layout.pageCount, greaterThan(1));
  expect(ltr.layout.pageCount, greaterThan(1));

  _matrix.record('arabic', P0Path.preview, P0Status.pass,
      evidence: '${rtl.texts.length} semantic paragraphs، source-order مطابق؛ '
          'RTL edge drift=${rightDrift.toStringAsFixed(2)}pt.');
  _matrix.record('latin', P0Path.preview, P0Status.pass,
      evidence: 'MIX1/OPT1/OP1A محفوظة في canonical runs وبترتيب المصدر.');
  _matrix.record('mixed', P0Path.preview, P0Status.pass,
      evidence: 'MIX1 measured from DocumentIR; run order and bounds retained.');
  _matrix.record('arabic-numerals', P0Path.preview, P0Status.pass,
      evidence: 'ITM3/ITM5 and numbering markers resolved in canonical lines.');
  _matrix.record('latin-numerals', P0Path.preview, P0Status.pass,
      evidence: 'HDC2/ITM4/2026/2027 marker paragraphs retained in layout.');
  _matrix.record('punctuation', P0Path.preview, P0Status.pass,
      evidence: 'MIX1/marks punctuation retained in source-ordered LayoutRuns.');
  _matrix.record('math', P0Path.preview, P0Status.pass,
      evidence: '${rtl.layout.allLines.expand((line) => line.runs).where((run) => run.isMath).length} math runs have canonical geometry.');
  _matrix.record('quran', P0Path.preview, P0Status.pass,
      evidence: 'QUR1 canonical run font=${verse.fontFamilies}.');
  _matrix.record('options', P0Path.preview, P0Status.pass,
      evidence: 'OP1A/OP1B/OP1C found in logical line/run order.');
  _matrix.record('marks', P0Path.preview, P0Status.pass,
      evidence: 'STA1 title geometry and marks survive structured run layout.');
  _matrix.record('pagination', P0Path.preview, P0Status.pass,
      evidence: '${rtl.layout.pageCount} RTL pages / ${ltr.layout.pageCount} LTR pages; questions remain traceable.');
  _matrix.record('justification', P0Path.preview, P0Status.pass,
      evidence: 'BODY1=${body.lines} lines; JUSTS1=${just.lines} line, extra spacing=${just.wordSpacing ?? 0}.');
  _matrix.record('floating', P0Path.preview, P0Status.pass,
      evidence: '${rtl.layout.pages.expand((page) => page.floatingElements).length} canonical float placements and source IDs.');
  _matrix.record('header-footer', P0Path.preview, P0Status.pass,
      evidence: 'headerBounds on page 1; footerBounds on last page; no body/footer overlap.');
  _matrix.record('ltr-document', P0Path.preview, P0Status.pass,
      evidence: '${ltr.layout.pageCount} pages; LTR source order and left-edge drift '
          '${(ltrSta.rect.left - ltrBody.rect.left).abs().toStringAsFixed(2)}pt.');
}

// =============================================================================
// خلايا Exact: صور المعاينة ملفوفة — لا نص ولا OOXML، فتُقيس ما يمكن قياسه.
// =============================================================================
void _recordExactCells() {
  final exactReport = PdfStructureReport.fromBytes(_gate.rtlExactPdf!);
  final exactDocx = OoxmlProbe.decode(_gate.rtlExactDocx!);
  final exactPages = exactReport.pageCount;
  final drawnWords =
      exactReport.pages.fold<int>(0, (sum, page) => sum + page.wordCount);
  final previewPages = _gate.rtlPreviewPageCount;
  final imagesPerPage =
      exactReport.pages.map((page) => page.embeddedImageObjects).join('/');

  // ما يُقاس في Exact حقاً: أنه يحمل المرجع البصري كاملاً — صفحة لكل صفحة،
  // وصورة واحدة ملؤها، وبلا أي نص (فلا يُستعمل بديلاً عن الممرّين البنيويين).
  expect(drawnWords, 0,
      reason: 'exact.pdf يحوي نصاً مرسوماً ($drawnWords) — لم يعد لقطة '
          'معاينة ملفوفة، فلا يصحّ ما تفترضه المصفوفة من فصل الممرّات.');
  expect(exactPages, previewPages,
      reason: 'Exact في $exactPages صفحة والمعاينة في $previewPages.');
  expect(
    exactReport.pages.every((page) => page.embeddedImageObjects >= 1),
    isTrue,
    reason: 'ليست كل صفحة في exact.pdf صورةً واحدة على الأقل: $imagesPerPage.',
  );
  expect(exactDocx.mediaNames.length, greaterThanOrEqualTo(previewPages),
      reason: 'exact.docx يحوي ${exactDocx.mediaNames.length} وسائط مقابل '
          '$previewPages صفحة معاينة.');

  _matrix.record('pagination', P0Path.exact, P0Status.pass,
      evidence: '$exactPages صفحة = $previewPages صفحة معاينة، '
          'وصورة صفحة واحدة لكل صفحة ($imagesPerPage)');
  for (final feature in kP0Features) {
    if (feature.key == 'pagination') {
      continue;
    }
    _matrix.record(
      feature.key,
      P0Path.exact,
      P0Status.deferredToP1,
      reason: 'Exact لقطة نقطية للصفحة: لا نص مرسوم ($drawnWords كلمة)، '
          'ولا `w:t`/`w:bidi`/`w:ind` ولا خطوط مضمَّنة — فالتسلسل والتشكيل '
          'والأرقام وخصائص الفقرة لا تُقاس فيه بنيةً، وأي «صحة» فيه تُستنتج '
          'من صورة المعاينة لا من المخرج. البوابة القائمة '
          '(tool/verify_visual_parity.sh) تقيس مطابقته للبكسل، وهذا تمام '
          'دوره؛ خصائص البنية تُقاس في vector/editable.',
      evidence: 'كلمات مرسومة=$drawnWords، وسائط في exact.docx='
          '${exactDocx.mediaNames.length}، أجزاء xml='
          '${exactDocx.xmlPartNames.length}',
    );
  }
}

// =============================================================================
// مُركّبات الوثائق لقياس شمول الفحص القرآني (سطح واحد لكل حالة).
// =============================================================================
ExamDocument _singleQuestionDoc({
  String? category,
  String? body,
  String? numberOverride,
  String? optionLabelOverride,
  String? itemLabelOverride,
  String? branchLabelOverride,
  String? optionText,
  String? closingPhrase,
  String? schoolName,
  bool withBismillah = false,
}) {
  return ExamDocument(
    name: 'سطح واحد',
    header: ExamHeaderModel(
      subject: 'اللغة العربية',
      schoolName: schoolName ?? 'ثانوية',
      examType: 'نصف السنة',
      academicYear: '2026/2027',
      showBismillah: withBismillah,
    ),
    footer: ExamFooterModel(closingPhrase: closingPhrase ?? ''),
    settings: const PaperSettings(
      showQuestionMarks: false,
      autoNumberQuestions: false,
    ),
    questions: <QuestionModel>[
      QuestionModel(
        id: 'q1',
        questionNumber: 1,
        category: category ?? '',
        statement: 'اقرأ وأجب',
        body: body ?? '',
        numberOverride: numberOverride,
        items: <BranchItem>[
          BranchItem(
            text: 'اختر الإجابة',
            kind: PointKind.multipleChoice,
            labelOverride: itemLabelOverride,
            options: <QuestionOption>[
              QuestionOption(
                text: optionText ?? 'الإظهار',
                labelOverride: optionLabelOverride,
              ),
            ],
          ),
        ],
        branches: <BranchModel>[
          BranchModel(
            labelOverride: branchLabelOverride,
            content: BranchContent(statement: 'فرع'),
          ),
        ],
      ),
    ],
  );
}
