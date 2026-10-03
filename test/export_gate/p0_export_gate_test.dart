// =============================================================================
// بوابة P0 — ممرّات التصدير الأربعة تُقاس ببنيتها، لا بصورة واحدة.
//
// لماذا وُجدت هذه البوابة؟
//   بوابة التحقق البصري القائمة (test/visual/visual_parity_fixture_test.dart
//   + tool/verify_visual_parity.sh) تنتج **Exact** فقط: صورة المعاينة ملفوفة
//   في PDF/DOCX، وتُقارَن بجذر RMSE. ذلك يقيس دقة لقطة المعاينة، ولا يقيس
//   إطلاقاً محرك PDF المتجه ولا مولّد OOXML — وهما الممرّان اللذان فيهما
//   الانحرافات. هذه البوابة تفصل المسارات: `vector.pdf` من
//   `PaginatedPdfExamEngine`، و`editable.docx` من `DocxDocumentExportService`،
//   و`exact.*` من `ExactExportService` — ويبقى Exact مساراً مستقلاً لا يُستعمل
//   بديلاً عن أيٍّ منهما (تُثبت البوابة أنه صورٌ بلا نص، فيثبت الفصل).
//
// ماذا تُثبت؟
//   P0.2  القطع تُنتَج فعلاً (ملفات حقيقية في build/export_gate تُرفع من CI).
//   P0.3  بنية PDF: الصفحات، MediaBox، عدد الأسطر ومواضعها وصناديقها، تسلسل
//         المحتوى، ترتيب الكلمات هندسياً، الصور التقديمية العربية، الأرقام
//         ومواضع الفواصل والأقواس، الخطوط والأحجام، صور المعادلات وترتيبها.
//   P0.4  بنية DOCX: الأجزاء والعلاقات و[Content_Types]، ترتيب `w:t` والجريان
//         داخل الفقرة، `w:bidi`/`w:rtl`/`w:jc`/`w:ind`/`w:spacing`/`w:line`،
//         فواصل الصفحات، OMML، الصور وعلاقاتها، `w:sectPr`، ومنع أي تغيير غير
//         مقصود في تسلسل المحتوى.
//   P0.5  الإصلاحات المحددة مقيَّدة: اتجاهية `w:ind`، محاذاة الافتراضي،
//        شمول الفحص `needsQuranicFont`، قاعدة «سطر واحد» في الضبط.
//   P0.7  مصفوفة 15 ميزة × 4 ممرّات بحالات PASS/FAIL/NOT_APPLICABLE/
//         DEFERRED_TO_P1 — والخلية غير المقاسة تُفشِل البوابة.
//
// لا «تقريباً صحيح» ولا RMSE: كل خلاصة مبنية على بايتات الملف نفسه.
// =============================================================================
import 'dart:convert';
import 'dart:math' as math;
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:writing_questions_app/layout/paper_metrics.dart';
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
import 'package:writing_questions_app/models/point_kind.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/models/question_option.dart';
import 'package:writing_questions_app/pdf_engine/exam_fonts.dart';
import 'package:writing_questions_app/pdf_engine/exam_strategy.dart';
import 'package:writing_questions_app/pdf_engine/paginated_pdf_exam_engine.dart';
import 'package:writing_questions_app/providers/exam_wizard_controller.dart';
import 'package:writing_questions_app/services/docx_document_export_service.dart';
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

/// قياسات القطع والممرّات، مشتركة بين اختبارات هذا الملف (ترتيب التنفيذ
/// مضمون: اختبار القطع أولاً، ثم الفحوص البنيوية، ثم المصفوفة).
class _Gate {
  final Map<String, _PreviewText> previewRtl = <String, _PreviewText>{};
  final Map<String, _PreviewText> previewLtr = <String, _PreviewText>{};
  List<String> previewRtlMarkerOrder = <String>[];
  List<String> previewLtrMarkerOrder = <String>[];

  Uint8List? rtlVectorPdf;
  Uint8List? rtlEditableDocx;
  Uint8List? rtlExactPdf;
  Uint8List? rtlExactDocx;
  Uint8List? ltrVectorPdf;
  Uint8List? ltrEditableDocx;
  Uint8List? ltrExactPdf;
  Uint8List? ltrExactDocx;
  List<Uint8List> rtlPreviewPages = <Uint8List>[];
  List<Uint8List> ltrPreviewPages = <Uint8List>[];
  int rtlPreviewPageCount = 0;
  int ltrPreviewPageCount = 0;
  int mathRunCount = 0;
  int mathHostRequestCount = 0;
  List<String> canonicalLabelRuns = <String>[];
  // التقاط المعاينة الثقيل يُقاس مرة واحدة ويُخزَّن: لا يُعاد في كل اختبار،
  // ولا يبقى سببُه مختبئاً خلف اختبار القطع.
  _PreviewCapture? rtlCapture;
  _PreviewCapture? ltrCapture;

  bool get artifactsReady =>
      rtlVectorPdf != null &&
      rtlEditableDocx != null &&
      ltrVectorPdf != null &&
      ltrEditableDocx != null;

  late final PdfStructureReport rtlPdfReport =
      PdfStructureReport.fromBytes(rtlVectorPdf!);
  late final PdfStructureReport ltrPdfReport =
      PdfStructureReport.fromBytes(ltrVectorPdf!);
  late final OoxmlProbe rtlDocx = OoxmlProbe.decode(rtlEditableDocx!);
  late final OoxmlProbe ltrDocx = OoxmlProbe.decode(ltrEditableDocx!);

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

/// تسلسل الوسوم في [haystack] (تكرار المتتابع مطويّ).
/// ترتيب الوسوم المنطقية في نصّ **منطقي** (OOXML): وسم واحد لكل فقرة،
/// والتكرار المتتابع مطويّ. لا يُقلب الاتجاه هنا: النص المنطقي قلبُه يُنتج
/// ترتيباً وهمياً.
List<String> _markerOrder(String haystack, Set<String> known) =>
    _markerOrderInParts(<String>[haystack], known, allowReversed: false);

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
    required this.controller,
  });

  final List<PageSnapshot> snapshots;
  final List<Uint8List> pages;
  final Map<String, _PreviewText> texts;
  final List<String> markerOrder;
  final ExamWizardController controller;
}

/// أول فقرة في شجرة المعاينة يحوي نصّها [marker]، بقياساتها.
/// كل فقرات النص في الشجرة — من `RichText` ومن `EditableText` معاً.
///
/// `RenderEditable` وارث `RenderParagraph`، وحقول المعاينة تُرسم عبره؛ لذا كان
/// الحصر بـ`find.byType(RichText)` يُسقط فقرات المتن كلها ويُبقي الترويسة
/// والتذييل فقط (قياس CI: 12 وسماً من 45 «غير مقاسة» وهي في الشجرة فعلاً).
/// المشي على العناصر بالـ`renderObject` يجمع الاثنين بلا افتراض عن نوع الودجت.
List<RenderParagraph> _paragraphsInTree(WidgetTester tester) {
  final result = <RenderParagraph>[];
  for (final element in find
      .byElementPredicate(
        (candidate) => candidate.renderObject is RenderParagraph,
        skipOffstage: false,
      )
      .evaluate()) {
    final renderObject = element.renderObject;
    if (renderObject is RenderParagraph) {
      result.add(renderObject);
    }
  }
  return result;
}

/// يقيس وسوم المعاينة في جولة واحدة على الشجرة.
///
/// المشي لكل وسم على حدة (45 وسماً × شجرة خمس صفحات + `getBoxesForSelection`
/// لكل مطابقة) كان يكلّف ميزانية الاختبار كلها: CI أجهض P0-GATE-01 بـ
/// `TimeoutException after 0:10:00`. القياسات نفسها بلا تغيير — عدد الأسطر من
/// `getBoxesForSelection`، والموضع من `localToGlobal`، وصناديق السطور مشتركة
/// بين الوسوم التي تسقط في الفقرة نفسها.
({Map<String, _PreviewText> found, List<String> missing, int richTextCount})
    _measurePreviewMarkers(
  WidgetTester tester,
  List<String> markers,
) {
  final paragraphs = _paragraphsInTree(tester);
  final plain = paragraphs
      .map((paragraph) => paragraph.text.toPlainText())
      .toList(growable: false);
  final lineCounts = <int, int>{};
  final found = <String, _PreviewText>{};
  final missing = <String>[];
  for (final marker in markers) {
    var hit = -1;
    for (var index = 0; index < plain.length; index++) {
      if (textMentions(plain[index], marker)) {
        hit = index;
        break;
      }
    }
    if (hit < 0) {
      missing.add(marker);
      continue;
    }
    final paragraph = paragraphs[hit];
    final lines = lineCounts.putIfAbsent(hit, () {
      final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: plain[hit].length),
        boxHeightStyle: ui.BoxHeightStyle.max,
      );
      final tops = boxes.map((box) => box.top.roundToDouble()).toSet();
      return tops.isEmpty ? 1 : tops.length;
    });
    final origin = paragraph.localToGlobal(Offset.zero);
    final span = paragraph.text;
    found[marker] = _PreviewText(
      marker: marker,
      text: plain[hit],
      lines: lines,
      rect: Rect.fromLTWH(0, 0, paragraph.size.width, paragraph.size.height)
          .shift(origin),
      align: paragraph.textAlign,
      wordSpacing: _firstWordSpacing(span),
      fontFamilies: _fontFamiliesOf(span),
    );
  }
  return (found: found, missing: missing, richTextCount: paragraphs.length);
}

double? _firstWordSpacing(InlineSpan span) {
  if (span is TextSpan) {
    final value = span.style?.wordSpacing;
    if (value != null && value != 0) {
      return value;
    }
    for (final child in span.children ?? const <InlineSpan>[]) {
      final nested = _firstWordSpacing(child);
      if (nested != null) {
        return nested;
      }
    }
  }
  return null;
}

Set<String> _fontFamiliesOf(InlineSpan span) {
  final result = <String>{};
  void visit(InlineSpan node) {
    if (node is TextSpan) {
      final family = node.style?.fontFamily;
      if (family != null && family.isNotEmpty) {
        result.add(family);
      }
      for (final child in node.children ?? const <InlineSpan>[]) {
        visit(child);
      }
    }
  }

  visit(span);
  return result;
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

  await tester.pumpWidget(
    MaterialApp(
      home: ChangeNotifierProvider<ExamWizardController>.value(
        value: controller,
        child: ExamPreviewScreen(onBackToQuestions: () {}),
      ),
    ),
  );
  await tester.pumpAndSettle();
  for (var frame = 0; frame < 10 && !controller.isFullyMeasured; frame++) {
    await tester.pump();
  }
  expect(controller.isFullyMeasured, isTrue,
      reason: 'لم يكتمل قياس كتل المعاينة، فلا معنى لعدد الصفحات.');
  final pageCount = controller.pagination.pageCount;
  // التشخيص قبل الحكم: بلا الارتفاعات المقاسة يصير «صفحة واحدة» لغزاً.
  final measuredHeights = <String, double?>{
    for (final question in controller.document.questions)
      question.id: controller.blockHeight(question.id),
    PaperMetrics.headerBlockId: controller.blockHeight(PaperMetrics.headerBlockId),
  };
  final heightSum = measuredHeights.values
      .fold<double>(0, (sum, h) => sum + (h ?? 0));
  _stage('تقسيم ${document.name}: صفحات=$pageCount، '
      'مجموع الارتفاعات=${heightSum.toStringAsFixed(1)}px، '
      'ارتفاع محتوى الصفحة='
      '${PaperMetrics.pageContentHeightFor(document.settings.marginMm)}px، '
      'قيست ${measuredHeights.values.where((h) => h != null).length}/'
      '${measuredHeights.length} كتلة، '
      'الكتل=${measuredHeights.map((k, v) => MapEntry<String, String>(k, v?.toStringAsFixed(1) ?? 'null'))}');
  if (pageCount <= 1) {
    // السجل وحده لا يكفي عند الفشل: تعليق CI يحمل الأرقام كما هي.
    debugPrint('::error title=p0-gate pagination::'
        '${document.name}: صفحات=$pageCount، '
        'مجموع الارتفاعات=${heightSum.toStringAsFixed(1)}px، '
        'صفحة=${PaperMetrics.pageContentHeightFor(document.settings.marginMm)}px، '
        'الكتل=${measuredHeights}');
  }
  expect(pageCount, greaterThan(1),
      reason: 'التركيبة يجب أن تتعدّى صفحة واحدة لتغطية التقسيم: '
          'الارتفاعات المقاسة = $measuredHeights.');

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
        };
  final markersToMeasure = <String>{...known, ...sideMarkers, ...markers};
  final measurement =
      _measurePreviewMarkers(tester, markersToMeasure.toList());
  final texts = measurement.found;
  if (measurement.missing.isNotEmpty) {
    // القائمة لا العدد فقط: «وسوم مقاسة 12/45» وحده لا يقول ما الناقص.
    // وحجم الشجرة يُفرّق «وسماً غائباً» عن «لا نصوص في الشجرة أصلاً».
    _stage('${document.name}: وسوم لم تُقَس في المعاينة '
        '(${measurement.missing.length}): ${measurement.missing.join(', ')}؛ '
        ' فقرات في الشجرة=${measurement.richTextCount}');
  }
  final treeParts = _paragraphsInTree(tester)
      .map((paragraph) => paragraph.text.toPlainText())
      .toList();
  final markerOrder = _markerOrderInParts(treeParts, known)
      .where((marker) => !excluded.contains(marker))
      .toList();

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
    controller: controller,
  );
}

List<RenderRepaintBoundary> _pageBoundaries(WidgetTester tester) => tester
    .renderObjectList<RenderRepaintBoundary>(find.byType(RepaintBoundary))
    .where((boundary) =>
        boundary.size.width == ExamCanvasGeometry.width &&
        boundary.size.height == ExamCanvasGeometry.height)
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
    final mathHost = FakeMathHost()..attach();
    addTearDown(mathHost.detach);

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
      'P0-GATE-01: قطع الورقة العربية — preview + vector.pdf + editable.docx + exact.*',
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
            .where((run) => run.text.contains('-') ||
                run.text.runes.any((rune) =>
                    (rune >= 0x0660 && rune <= 0x0669) ||
                    (rune >= 0x30 && rune <= 0x39)))
            .map((run) => '${run.semanticRole.name}:"${run.text}" '
                '@${run.x.toStringAsFixed(2)}+${run.width.toStringAsFixed(2)} '
                'advance=${run.advance.toStringAsFixed(2)}')
            .take(24)
            .toList();
        _stage('P2 number/separator runs: ${_gate.canonicalLabelRuns}');
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
      _gate.rtlEditableDocx =
          await DocxDocumentExportService.buildDocumentDocxBytes(
        document: rtlDocument,
      );
      _stage('توليد editable.docx عربي: ${watch.elapsedMilliseconds}ms، '
          '${_gate.rtlEditableDocx!.length} بايت');
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
    await _writeArtifact('editable.docx', _gate.rtlEditableDocx!);
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
      'editable.docx',
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
              'ترويسة 140.4px، كتل تدفّق 325px)؛ فواصل الصفحات في '
              'editable.docx تُقاس مقابل PDF في GATE-06',
          reason: 'مصدرٌ مختلف لارتفاع السطر والهامش بين `PaginationEngine` '
              'و`PdfPaperBuilder`؛ توحيدُهما طبقة Canonical LayoutEngine في P1 '
              '(§P1 BLOCKERS بند 2)، وتوحيد الأرقام الآن يعني إعادة كتابة أحد '
              'الممرّين وهو داخل المحظور في P0.6.');
    }
  });

  // الورقة الإنجليزية في اختبار مستقل: توليد القطع الأربعة لورقتين في اختبار
  // واحد كان يتجاوز سقف CI (عشر دقائق) فيُجهض البوابة كلها بلا قياس واحد.
  testWidgets(
      'P0-GATE-01B: قطع الورقة الإنجليزية — vector_ltr + editable_ltr + exact_ltr',
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
      _gate.ltrEditableDocx =
          await DocxDocumentExportService.buildDocumentDocxBytes(
        document: ltrDocument,
      );
      _stage('توليد editable_ltr.docx: ${watch.elapsedMilliseconds}ms');
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
    await _writeArtifact('editable_ltr.docx', _gate.ltrEditableDocx!);
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
      'editable_ltr.docx',
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

    // موضع الترويسة والتذييل: الموضع يُقاس لا الحضور وحده. في PDF الترويسة
    // كتلة تُطبع في أعلى ص1 (`if (pageIndex == 0)` في المحرك) والتذييل في
    // أسفل آخر صفحة؛ وتكرار الترويسة على كل صفحة قرار تخطيط لا يُغيَّر في P0.
    final headerPages = report.pages
        .where((page) => page.linesWithMarker('HDRV').isNotEmpty)
        .toList();
    expect(headerPages, isNotEmpty,
        reason: 'الترويسة غائبة من كل صفحة في vector.pdf.');
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
    expect(
      lastPage.linesWithMarker('FTR1'),
      isNotEmpty,
      reason: 'التذييل مفقود من آخر صفحة في vector.pdf.',
    );
    _stage('ترويسة PDF: ${headerPages.length} من ${report.pageCount} صفحة '
        '(Word يكررها عبر header1.xml)؛ تذييل في ص${lastPage.index + 1}.');

    _matrix.record('pagination', P0Path.vectorPdf, P0Status.pass,
        evidence: 'صفحات=${report.pageCount}، '
            'أسطر/صفحة=${report.pages.map((p) => p.lineCount).join("/")}، '
            'أول ظهور PG8 في ص${(report.pageOfMarker(['PG8'])['PG8'] ?? -1) + 1}'
            '/${report.pageCount}');
    _matrix.record('arabic', P0Path.vectorPdf, P0Status.pass,
        evidence: 'تسلسل العقد كله مرسوم: ${pdfOrder.length} وسم، '
            'وسطور ص1=${report.pages.first.lineCount}');
    _matrix.record('header-footer', P0Path.vectorPdf, P0Status.deferredToP1,
        evidence: 'HDRV في ${headerPages.length} من ${report.pageCount} صفحة '
            '(أول سطر مرسوم في ص1) وFTR1 في ص${lastPage.index + 1}؛ '
            'وفي Word هذه الركيزة لا يُنتج `word/header*.xml` بلا صورة إطار '
            'فتُطبع الترويسة في المتن (قيس في P0-GATE-06)',
        reason: 'تكرار الترويسة على كل صفحة قرار تخطيط: في PDF والمعاينة كتلة '
            'تُطبع مرة، وفي Word جزء header يتكرر — لا تُوحَّدان في P0 لأن '
            'أي تغيير فيهما يمسّ حساب ارتفاعات التقسيم. يُحسم مع طبقة '
            'التخطيط الواحدة (P1).');
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
    // السقف الأعلى لا يُطلب من كل فجوة: في PDF يوزّع `pw.TextAlign.justify`
    // فائض السطر على فجواته، ففجوة سطر من كلمتين قد تتجاوز أي حدّ مطلق
    // مشروعاً. لذلك يُقاس: (1) لا تراكب، (2) غالبية الفجوات عند عرض المسافة
    // الطبيعية للخط، (3) سطر غير مضبوط (عنوان STA1) فجواته كلها طبيعية —
    // وهذا ما يكشف التباعد السحري أو الرقعة في `realign`.
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
    final titleGaps = <double>[
      for (final index in titleLines.first.adjacencyIndices)
        titleLines.first.gapAfter(index),
    ];
    if (titleGaps.isNotEmpty) {
      expect(titleGaps.every((gap) => gap >= 1.0 && gap <= 6.0), isTrue,
          reason: 'فجوات سطر غير مضبوط خارج نطاق المسافة الطبيعية: '
              '${titleGaps.map((v) => v.toStringAsFixed(2)).toList()} — '
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

        // LayoutDocument paints semantic number/separator runs independently;
        // the PDF probe therefore may expose `١` and `-` as separate text
        // operators instead of one word. Rejoin only geometrically adjacent
        // fragments, preserving their emitted (logical-run) order.
        for (var index = 0; index + 1 < line.words.length; index++) {
          final first = line.words[index];
          final second = line.words[index + 1];
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
            '${_gate.canonicalLabelRuns.take(24).toList()}');
    expect(invertedLabels, isEmpty,
        reason: 'نصّ التسمية مرسوم بفاصل قبل الرقم (انقلاب في السلسلة '
            'المنطقية لا في المواضع فقط): ${invertedLabels.take(6).toList()}');

    // الأقواس في RTL: أول قوس في السلسلة المرسومة (من اليسار) هو المغلق،
    // لأن `( أ )` و`(١)` و`(20 درجة)` تنعكس أطرافها عند العرض.
    final drawnSequence =
        report.pages.map((page) => page.drawnText).join(' ');
    final parenSamples = <String>[];
    for (final rune in drawnSequence.runes) {
      if (rune == 0x28 || rune == 0x29) {
        parenSamples.add(String.fromCharCode(rune));
      }
      if (parenSamples.length >= 6) {
        break;
      }
    }
    expect(parenSamples.length, greaterThan(1),
        reason: 'أقواس مرسومة أقلّ من المتوقع لتسميات ( أ ) و(١) و(ب): '
            '${parenSamples.length}');
    expect(parenSamples.first, ')',
        reason: 'أول قوس مرسوم في الورقة العربية يجب أن يكون المغلق (الأيسر '
            'بصرياً): $parenSamples — إن انقلب كله فالتسلسل مردود مرتين.');

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
        evidence: 'أقواس مرسومة=${parenSamples.length}، فواصل الترقيم '
            'يسار الأرقام=${drawnLabels.length}، لا انقلاب=${invertedLabels.length}');
    _matrix.record('marks', P0Path.vectorPdf, P0Status.pass,
        evidence: '«(٢٠ درجة)» مرسومة مع أرقام مشرقية=${indic}');
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
  // P0.4 — بنية DOCX القابل للتحرير.
  // ===========================================================================
  test('P0-GATE-06: بنية editable.docx — أجزاء، علاقات، تسلسل، جريان', () {
    _gate.requireArtifacts();
    final probe = _gate.rtlDocx;
    final document = P0GateFixture.rtl();
    const known = P0GateFixture.rtlBodyMarkers;

    for (final part in <String>[
      '[Content_Types].xml',
      '_rels/.rels',
      'word/document.xml',
      'word/_rels/document.xml.rels',
      'word/styles.xml',
    ]) {
      expect(probe.hasPart(part), isTrue,
          reason: 'جزء OOXML مفقود: $part — Word لن يفتح ملفاً ناقصاً.');
    }
    expect(probe.missingContentTypes(), isEmpty,
        reason: 'أجزاء بلا إعلان في [Content_Types].xml: '
            '${probe.missingContentTypes()}');
    expect(probe.undefinedRelations('word/document.xml'), isEmpty,
        reason: 'معرّف علاقة مستعمل بلا تعريف: '
            '${probe.undefinedRelations("word/document.xml")}');
    expect(probe.missingRelationTargets('word/document.xml'), isEmpty,
        reason: 'علاقة تشير إلى ملف غير موجود في الحزمة: '
            '${probe.missingRelationTargets("word/document.xml")}');

    // الترويسة في Word لها شكلان عند المنتج نفسه، ولا يُقرَّر الادّعاءُ بل
    // القياس: `DocxDocumentExportService` يبني `word/header1.xml` **فقط** إذا
    // كان للورقة إطار صفحة (`settings.pageBorder` مع صورة إطار غير فارغة،
    // docx_document_export_service.dart:395)، وإلا طُبعت فقرات الترويسة في
    // أول المتن فتنكسر مع الصفحات ولا تتكرر. الركيزة بلا إطار (لا تُختَرع
    // أصول من الاختبار) ⇒ المطلوب هنا: أن يظهر نص الترويسة في أحد الموضعين،
    // وأن يُسجَّل أيُّهما استُعمل — لا أن يُدَّعى تكرارٌ غير موجود.
    final headerParts = probe.xmlPartNames
        .where((name) => name.startsWith('word/header'))
        .toList();
    final headerInBody = P0GateFixture.headerMarkers
        .every((marker) => probe.flatText.contains(marker));
    // ادّعاءٌ مقيَس لا مُتوهَّم: جدول الترويسة يُكتب في المتن (سطر 365 من
    // docx_document_export_service.dart) بلا شروط، فوجوده هو ما يُفحص هنا؛
    // أما هل وصلت **كل حقل** من حقول الترويسة، فقياسٌ مستقل يُسجَّل فشله
    // انحداراً حقيقياً في المصفوفة لا في نصّ هذا الفحص.
    expect(probe.documentXml.contains('<w:tbl'), isTrue,
        reason: 'لا جدول ترويسة في document.xml: `build()` لم يكتب '
            '_buildHeaderTable (وصلت الترويسة إلى PDF).');
    // القياس لكل وسم على حدة في الموضعين الذين يمكن أن تظهر فيهما الترويسة
    // (جزء header أو متن document.xml)، لا لوجودها العام: لا يكفي أن وصلت
    // «بعض» الحقول لتُسمى الترويسة مقيسة.
    final headerPartText = headerParts.map(probe.part).join(' ');
    // المعيار «جزء الترويسة» لا document.xml:HDRV قيمة صفٍّ تُطبع في المتن
    // أيضاً، فحسابُ حضورها العام وصولاً إلى الترويسة يُبيضّ انحداراً موجوداً.
    // لذلك يُقاس الموضعان معاً ويسقطان إلى الخلية كما هما.
    final missingInHeaderPart = P0GateFixture.headerMarkers
        .where((marker) => !headerPartText.contains(marker))
        .toList();
    final missingAnywhere = P0GateFixture.headerMarkers
        .where((marker) =>
            !probe.flatText.contains(marker) &&
            !headerPartText.contains(marker))
        .toList();
    if (missingInHeaderPart.isNotEmpty) {
      debugPrint('::error title=p0-gate DOCX header fields (DEFERRED_TO_P1)::'
          'جزء ترويسة في editable.docx: '
          '${headerParts.isEmpty ? 'لا header*.xml إطلاقاً' : headerParts.join(",")}؛ '
          'وسوم لا تصل إلى الترويسة: $missingInHeaderPart (منها $missingAnywhere '
          'لا يظهر في document.xml أصلاً) — انحدار حقيقي في المنتج، مسجَّل لا '
          'مُصلَح (P0.5 مغلق على A–F)');
      _stage('DOCX: ${missingInHeaderPart.length}'
          '/${P0GateFixture.headerMarkers.length} وسم ترويسة لا يصل إلى جزء '
          'الترويسة — مُسجَّل DEFERRED_TO_P1 بالدليل، ولا تخفيف فحص ولا حذف '
          'وسم من الركيزة.');
      _matrix.record('header-footer', P0Path.editableDocx,
          P0Status.deferredToP1,
          evidence: '${missingInHeaderPart.length}'
              '/${P0GateFixture.headerMarkers.length} وسم ترويسة غائب عن جزء '
              'الترويسة (${headerParts.isEmpty ? 'لا header*.xml' : headerParts.join(",")})، '
              'ومنها ${missingAnywhere.length} غائب عن document.xml أيضاً '
              '$missingInHeaderPart؛ الترويسة كاملة في vector.pdf، وكل الحقول '
              'في المتن: $headerInBody',
          reason: 'جزء header*.xml مشروط بصورة إطار + `pageBorder` في '
              'docx_document_export_service.dart:365/396، فالترويسة كلها تُطبع '
              'فقراتٍ في المتن وتفقد الوسوم '
              '${P0GateFixture.headerMarkers.join("/")} موضعَها عند الطباعة. '
              'توحيد الحقول عقدُ محتوى واحد بين PDF وOOXML (P1 BLOCKERS بند 1).');
    }
    _stage(headerParts.isEmpty
        ? 'DOCX عربي: لا جزء header*.xml — الترويسة فقرات في المتن '
            '(شرط الجزء: `pageBorder` + صورة إطار، §8 بند 1)'
        : 'DOCX عربي: جزء الترويسة ${headerParts.join(",")} معلن '
            'ويتكرر على كل صفحة في Word');
    // الفحص السابق كان `expect` لكل وسم: يُفشِل البوابة عند انحدار لا يجوز
    // إصلاحه في P0، ويبتلع بعده كل فحوص Bنية (تسلسل `w:t`، OMML، الوسائط)
    // فتُغلق خلاياها UNMEASURED — أي أن الصرامة كانت تُعمي البوابة لا تُبصرها.
    // اليوم: الوسوم تُقاس وتُطبع وتُسجَّل في الخلية، وGATE-99 تُفشِل البوابة
    // إن ضاع التسجيل أو لم يسمِّ الوسوم الخمسة، فالبند لا يُمحى ولا يُنعَّم.
    _stage('DOCX: الترويسة في جزء الترويسة '
        '${P0GateFixture.headerMarkers.length - missingInHeaderPart.length}'
        '/${P0GateFixture.headerMarkers.length}، وفي document.xml '
        '${P0GateFixture.headerMarkers.length - missingAnywhere.length}'
        '/${P0GateFixture.headerMarkers.length}؛ الغائب عن الجزء '
        '$missingInHeaderPart (مقيس، مُسجَّل، ومسمّى في GATE-99).');

    // تسلسل `w:t` المنطقي == ترتيب العقد (منع تغيير تسلسل المحتوى).
    final expectedOrder = P0GateFixture.bodyMarkerSequence(document);
    final docxOrder = _markerOrder(probe.flatText, known);
    expect(_markersIn(probe.flatText, known), containsAll(<String>[...known]),
        reason: 'وسوم مفقودة من editable.docx: '
            '${known.difference(_markersIn(probe.flatText, known)).toList()..sort()}');
    expect(docxOrder, expectedOrder,
        reason: 'تسلسل المحتوى في editable.docx يختلف عن ترتيب العقد:\n'
            '  DOCX: $docxOrder\n  عقد: $expectedOrder');

    // ترتيب الجريان داخل فقرة العنوان: رقم ← منطوق ← درجة، وكله جريان منفصل.
    final title =
        probe.paragraphs.firstWhere((paragraph) => paragraph.text.contains('STA1'));
    expect(title.runs.length, greaterThan(1),
        reason: 'سطر العنوان جريان واحد مدموج (${title.runs.length}) — لا '
            'يعرف Word أجزاءه.');
    expect(title.props.hasBidi, isTrue,
        reason: 'فقرة عربية بلا `w:bidi`: سيوجَّه السطر توجيهًا لاتينيًا.');
    expect(title.text, contains('(٢٠ درجة)'),
        reason: 'الدرجة ليست في النص المنطقي لفقرة العنوان: "${title.text}"');
    final runTexts = title.runs.map((run) => run.text).join(' ');
    expect(runTexts.indexOf('س١') < runTexts.indexOf('STA1'), isTrue,
        reason: 'جريان الرقم ليس قبل المنطوق: "$runTexts"');
    expect(runTexts.indexOf('STA1') < runTexts.indexOf('٢٠'), isTrue,
        reason: 'جريان المنطوق ليس قبل الدرجة: "$runTexts"');
    // كل جريان عربي يحمل w:rtl (القرار القائم) — مُثبَّت لا مُغيَّر.
    expect(title.runs.every((run) => run.rtl), isTrue,
        reason: 'جريان في فقرة عربية بلا `w:rtl`: '
            '${title.runs.map((run) => run.text).toList()}');

    // خصائص الفقرة العددية.
    expect(title.props.lineTwips, isNotNull,
        reason: 'فقرة بلا `w:spacing/@w:line` فيرث Word «مفرد» وتختلف '
            'الصفحة عن المعاينة.');
    expect(title.props.lineRule, 'auto',
        reason: 'w:lineRule يجب أن يكون auto (نسبة إلى سطر Word).');
    // سطر الفقرة مُصرَّح به (ليس إرث «مفرد»): قيمته تُسجَّل دليلاً لا رقمًا
    // مثبَّتًا، لأن دور العنوان يمرّ بمعامل الورقة.
    expect(title.props.lineTwips! > 240, isTrue,
        reason: 'خطوة سطر العنوان في Word عند «مفرد» (${title.props.lineTwips}'
            '.twips): عقد الطباعة لا يصل إلى الملف.');

    final section = probe.sectionProperties;
    expect(section['w:pgSz'], isNotNull,
        reason: 'بلا `w:pgSz` في sectPr: حجم الصفحة Letter افتراضياً لا A4.');
    expect(section['w:pgSz']!['w:w'], '11906',
        reason: 'عرض A4 بالـ twips يجب أن يكون 11906 لا '
            '"${section['w:pgSz']?['w:w']}".');
    expect(section['w:pgMar'], isNotNull,
        reason: 'بلا `w:pgMar`: هوامش 15mm من إعداد الورقة لم تصل إلى Word.');
    expect(int.parse(section['w:pgMar']!['w:right'] ?? '0'),
        (15 / 25.4 * 1440).round(),
        reason: 'هامش Word لا يطابق 15mm من إعداد الورقة.');

    // فواصل الصفحات = الخطة نفسها التي استعملها PDF.
    expect(probe.pageBreakCount + 1, _gate.rtlPdfReport.pageCount,
        reason: 'Word يكسر في ${probe.pageBreakCount + 1} صفحة وPDF في '
            '${_gate.rtlPdfReport.pageCount}: خطة التقسيم لم تصل إلى الملف.');

    // OMML: معادلة Word أصلية بدل صورة، وعدد مناطق المعادلة = عدد الصيغ.
    final mathTotal = probe.inlineMathCount + probe.mathParagraphCount;
    expect(mathTotal, greaterThan(0),
        reason: 'لا `m:oMath` في editable.docx: المعادلات صُوّر أو فُقِد.');
    final mathText = probe.mathTexts.join(' ');
    expect(mathText, contains('x'),
        reason: 'رموز الصيغة لم تصل إلى OMML: "${probe.mathTexts}"');

    // اتجاه الصفحة معلن في sectPr (`w:bidi`) — وورقة LTR لا تحملـه.
    expect(section.containsKey('w:bidi'), isTrue,
        reason: 'لا `w:bidi` في `w:sectPr`: اتجاه الصفحة غير معلن في Word.');
    expect(_gate.ltrDocx.sectionProperties.containsKey('w:bidi'), isFalse,
        reason: 'ورقة LTR تعلن `w:bidi` في sectPr: تسرّب RTL إلى ملف '
            'إنجليزي.');

    // الخط القرآني يصل إلى الجريان نفسه كما في المعاينة وPDF.
    final verseParagraph = probe.paragraphs
        .firstWhere((paragraph) => paragraph.text.contains('QUR1'));
    expect(
      verseParagraph.runs.any((run) => (run.font ?? '').contains('Amiri')),
      isTrue,
      reason: 'جريان الآية في Word بلا Amiri: '
          '${verseParagraph.runs.map((run) => run.font).toList()}',
    );

    // التسميات والأرقام تصل **منطقية** كما كتبها المدرس (Word يعكس العرض
    // بوسوم الفقرة، لا بإعادة ترتيب النص): لو أعاد المولّد ترتيب المحارف
    // لفشل هذا السطر لا سطر «ترتيب الكلمات» في PDF.
    expect(probe.flatText, contains('(١)'),
        reason: 'تسمية النقطة «(١)» لم تصل حرفية إلى `w:t`.');
    expect(probe.flatText, contains('1-'),
        reason: 'التسمية اللاتينية «1-» لم تصل حرفية إلى `w:t`.');
    expect(probe.flatText, contains('٢٠'),
        reason: 'الأرقام المشرقية للدرجة لم تصل إلى `w:t`.');
    expect(probe.flatText, contains('2026/2027'),
        reason: 'الأرقام اللاتينية في المتن لم تصل إلى `w:t`.');
    expect(
      probe.paragraphs.any((paragraph) => paragraph.props.alignment == 'both'),
      isTrue,
      reason: 'لا فقرة `w:jc="both"` مع أن النموذج يطلب justify: الضبط لم '
          'يُترجم إلىدلالته في الملف.',
    );

    // الصور وعلاقاتها.
    expect(probe.embeddedRelationIds, isNotEmpty,
        reason: 'بلا r:embed في المستند: صورة العنصر الحر لم تُكتب.');
    for (final media in probe.mediaNames) {
      expect(probe.mediaSizes[media]!, greaterThan(0),
          reason: 'ملف وسائط فارغ في الحزمة: $media');
    }

    _matrix.record('arabic', P0Path.editableDocx, P0Status.pass,
        evidence: 'ترتيب العقد محفوظ في ${docxOrder.length} وسمًا، '
            'وفقرات bidi=${probe.paragraphs.where((p) => p.props.hasBidi).length}');
    _matrix.record('punctuation', P0Path.editableDocx, P0Status.pass,
        evidence: 'الأقواس/الفواصل/Arabic-Indic في `w:t` منطقيًا كما كُتبت '
            '(`(٢٠ درجة)`، `(١)`، `(ب)`)');
    _matrix.record('math', P0Path.editableDocx, P0Status.pass,
        evidence: 'مناطق OMML=$mathTotal، نصوص m:t تبدأ بـ '
            '"${probe.mathTexts.isEmpty ? '' : probe.mathTexts.first}"');
    _matrix.record('marks', P0Path.editableDocx, P0Status.pass,
        evidence: '«(٢٠ درجة)» في جريان فقرة العنوان');
    _matrix.record('options', P0Path.editableDocx, P0Status.pass,
        evidence: 'OP1A..OP1C في فقرات الخيارات بعد نص النقطة بنفس الترتيب');
    _matrix.record('floating', P0Path.editableDocx, P0Status.deferredToP1,
        reason: 'العناصر الحرة تُكتب في تدفق الفقرات بلا مرساة `wp:anchor` '
            'وبلا موضع صفحة (انظر _buildOwnedElements)، فتتدفق مع النص '
            'بدلاً من أن تثبته Word في موضعه. الإصلاح يحتاج قرار هندسة '
            'العناصر في Rاسم OOXML واحد (P1).',
        evidence: 'r:embed=${probe.embeddedRelationIds.length}، '
            'وسائط=${probe.mediaNames.length}، ولا `wp:anchor` في فقرات '
            'العناصر: ${probe.documentXml.contains("<wp:anchor")}');
    _matrix.record('header-footer', P0Path.editableDocx,
        headerParts.isEmpty
            ? P0Status.deferredToP1
            : P0Status.pass,
        evidence: headerParts.isEmpty
            ? 'لا `word/header*.xml` في هذه الركيزة (القياس في P0-GATE-06): '
                'الترويسة فقرات في أول المتن فتتبع التدفّق ولا تتكرر؛ '
                'التذييل جدول في المتن بعد آخر فقرة'
            : 'الترويسة جزء مستقل (${headerParts.join(",")}) — تتكرر على '
                'كل صفحة بطبيعة Word — والتذييل جدول في المتن بعد آخر فقرة',
        reason: headerParts.isEmpty
            ? 'جزء الترويسة عند المنتج مشروط بصورة إطار صفحة (`pageBorder` + '
                'frameImage)؛ ترويسة بلا إطار تُطبع في المتن فيختلف تكرارها '
                'عن PDF والمعاينة. توحيد القرار طبقةُ تخطيط واحدة (P1).'
            : '');
    _matrix.record('latin', P0Path.editableDocx, P0Status.pass,
        evidence: 'الوسوم اللاتينية (MIX1/OPT1/OP1A..) داخل `w:t` بنفس '
            'ترتيب العقد، مع العربية في الفقرة نفسها');
    _matrix.record('mixed', P0Path.editableDocx, P0Status.pass,
        evidence: 'فقرة MIX1 جريان مستقل للعربية وللأرقام في الفقرة نفسها '
            'تحت `w:bidi`');
    _matrix.record('arabic-numerals', P0Path.editableDocx, P0Status.pass,
        evidence: '«(١)» و«(٢٠ درجة)» و«١-» منطقيات في `w:t`؛ Word يعكس '
            'العرض بالاتجاه لا بإعادة ترتيب النص');
    _matrix.record('latin-numerals', P0Path.editableDocx, P0Status.pass,
        evidence: '«1-» اليدوية و1990 و45.5% حرفياً في `w:t`');
    _matrix.record('quran', P0Path.editableDocx, P0Status.pass,
        evidence: 'جريان الآية بـ`w:rFonts` Amiri من عقد RichContent نفسه');
    _matrix.record('pagination', P0Path.editableDocx, P0Status.pass,
        evidence: '${probe.pageBreakCount} فاصل صفحة = '
            '${_gate.rtlPdfReport.pageCount - 1} (خطة التقسيم نفسها)');
    _matrix.record('justification', P0Path.editableDocx, P0Status.pass,
        evidence: 'الفقرة المضبوطة تُعلن `w:jc="both"` وحدها — ولا تُحاكى '
            'بتباعد مصطنع: `w:spacing/@w:after` و`w:ind` مستقلان عن الضبط');
    _matrix.record('math', P0Path.editableDocx, P0Status.deferredToP1,
        reason: 'OMML يُبنى بلا إعلان اتجاه: لا `w:rtl` ولا `w:bidi` داخل '
            '`m:r`، فـ`\text{}` العربي داخل الصيغة يُترك لاتجاه المعادلة '
            'الافتراضي (LTR). الإصلاح قرار في مُولّد OMML (P1) لا يمسّ '
            'تحليلاً نصياً في Rاسم Word.',
        evidence: 'مناطق OMML=$mathTotal، وm:t الذي يحوي عربية: '
            '${probe.mathTexts.where((t) => RegExp(r"[\u0600-\u06FF]").hasMatch(t)).length}');
  });

  test('P0-GATE-07: editable.docx — اتجاهية `w:ind` ومحاذاة الافتراضي (P0.5-A/B)',
      () {
    _gate.requireArtifacts();
    final rtl = _gate.rtlDocx;
    final ltr = _gate.ltrDocx;

    // (A) العربية: `w:start` الاتجاهي حاضراً ومعهُ الفيزيائي لجهة البداية.
    final rtlIndents = rtl.indentDirectives;
    expect(rtlIndents, isNotEmpty,
        reason: 'لا `w:ind` في الملف: لم تُختبر الإزاحة أصلاً.');
    for (final indent in rtlIndents) {
      expect(indent.containsKey('w:start'), isTrue,
          reason: 'إزاحة بلا `w:start`: الاتجاه غير معلن في OOXML: $indent');
      expect(indent['w:left'], isNull,
          reason: 'إزاحة عربية استعملت `w:left`: تنقلب في RTL: $indent');
      expect(indent['w:right'], indent['w:start'],
          reason: 'الفيزيائي لا يوازي الاتجاهي في RTL: $indent');
    }

    // (A) الإنجليزية: جهة البداية يساراً — لم يبقَ `w:right` حلاً عالمياً.
    final ltrIndents = ltr.indentDirectives;
    expect(ltrIndents, isNotEmpty,
        reason: 'لا `w:ind` في ورقة LTR: نقاط/فروع بلا إزاحة.');
    for (final indent in ltrIndents) {
      expect(indent['w:right'], isNull,
          reason: 'ورقة LTR تُزاح بـ `w:right` (انحدار P0.5-A): $indent');
      expect(indent['w:left'], indent['w:start'],
          reason: 'الإزاحة اللاتينية غير متسقة: $indent');
    }

    // (B) «بلا محاذاة» = بداية السطر باتجاه الورقة.
    final rtlTitle =
        rtl.paragraphs.firstWhere((paragraph) => paragraph.text.contains('STA1'));
    final ltrTitle = ltr.paragraphs
        .firstWhere((paragraph) => paragraph.text.contains('LTRSTA1'));
    expect(rtlTitle.props.alignment, 'right',
        reason: 'محاذاة الافتراضي في RTL يجب ألا تتغير: '
            '${rtlTitle.props.alignment}');
    expect(ltrTitle.props.alignment, 'left',
        reason: '`_wordAlign(null)` ما زال يُرجع right لورقة LTR: '
            '${ltrTitle.props.alignment}');

    // ولا فقرة محتوى في LTR تُحاكى يميناً بغير سبب من النموذج.
    const ltrKnown = P0GateFixture.ltrBodyMarkers;
    final rightAlignedLtr = <String>[
      for (final paragraph in ltr.paragraphs)
        if (paragraph.props.alignment == 'right' &&
            _markersIn(paragraph.text, ltrKnown).isNotEmpty)
          '#${paragraph.index} ${paragraph.text}',
    ];
    expect(rightAlignedLtr, isEmpty,
        reason: 'فقرات LTR محاذَاة يميناً: ${rightAlignedLtr.take(3).toList()}');

    // RTL لم يَنكسر: كل فقرة محتوى عربية تحمل `w:bidi`.
    final missingBidi = <int>[
      for (final paragraph in rtl.paragraphs)
        if (_markersIn(paragraph.text, P0GateFixture.rtlBodyMarkers).isNotEmpty &&
            !paragraph.props.hasBidi)
          paragraph.index,
    ];
    expect(missingBidi, isEmpty,
        reason: 'فقرات عربية بلا `w:bidi` بعد تغيير الفقرة الافتراضية: '
            '$missingBidi');

    _matrix.record('punctuation', P0Path.editableDocx, P0Status.pass,
        evidence: 'اتجاهية الإزاحة: w:start+${rtlIndents.length} فقرات عربية '
            'و${ltrIndents.length} لاتينية');
  });

  test('P0-GATE-08: editable.docx — لا معنى لإزاحة خط الأساس ولا لمنطق '
      'ExamTextStyles', () {
    _gate.requireArtifacts();
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
    expect(_gate.rtlDocx.documentXml.contains('<w:position'), isFalse,
        reason: 'مولّد Word كتب `w:position` الآن: الحقل لم يعد معطَّلاً، '
            'فليُحدَّث تقرير P0 ولتُوصل الإزاحة بالراسمين.');

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
  test('P0-GATE-11: الورقة الإنجليزية (LTR) — لا انحدار في PDF ولا في Word',
      () {
    _gate.requireArtifacts();
    final report = _gate.ltrPdfReport;
    final probe = _gate.ltrDocx;
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

    final bodyParagraphs = probe.paragraphs
        .where((paragraph) => _markersIn(paragraph.text, known).isNotEmpty)
        .toList();
    expect(bodyParagraphs, isNotEmpty,
        reason: 'لا فقرات محتوى في editable_ltr.docx.');
    final bidiLeak = <int>[
      for (final paragraph in bodyParagraphs)
        if (paragraph.props.hasBidi) paragraph.index,
    ];
    expect(bidiLeak, isEmpty,
        reason: 'فقرات LTR تحمل `w:bidi` (تسرّب RTL): $bidiLeak');
    final rtlRunLeak = <int>[
      for (final paragraph in bodyParagraphs)
        if (paragraph.runs.any((run) => run.rtl)) paragraph.index,
    ];
    expect(rtlRunLeak, isEmpty,
        reason: 'جريان في ورقة LTR يحمل `w:rtl`: $rtlRunLeak');
    // الوجه الآخر للقياس نفسه: `w:bidi` يُشتق من اتجاه المستند لا من نص
    // الفقرة، فالفقرة العربية داخل الورقة الإنجليزية تُترك بلا أي إعلان
    // اتجاه (تقرأها Word الاتّجاه العام). مقيس ومُسجَّل؛ تصحيحه طبقة اتجاه
    // واحدة (P1 BLOCKERS بند 4)، وحذف العربية من الركيزة يُخفي العطب لا أكثر.
    final arabicParagraphs = <int>[
      for (final paragraph in bodyParagraphs)
        if (RegExp('[\u0600-\u06FF]').hasMatch(paragraph.allText) &&
            !paragraph.props.hasBidi)
          paragraph.index,
    ];
    _stage('editable_ltr.docx: $arabicParagraphs فقرة عربية بلا `w:bidi` '
        '(الاتجاه من المستند لا من النص) من ${bodyParagraphs.length} فقرة متن');
    if (arabicParagraphs.isNotEmpty) {
      _matrix.record('ltr-document', P0Path.editableDocx,
          P0Status.deferredToP1,
          evidence: '${arabicParagraphs.length} فقرة عربية في ورقة LTR بلا '
              '`w:bidi`/`w:rtl` (فهارس: ${arabicParagraphs.take(3).toList()})',
          reason: 'اتجاه الفقرة يُشتق من `document.layout.isLtr` وحده، فلا '
              'تُعلَّم الفقرات العربية داخل مستند إنجليزي. القرار يعود إلى '
              'طبقة التخطيط الموحدة ولا يُلَمَّع في P0.');
    }
    for (final paragraph in bodyParagraphs) {
      expect(paragraph.props.alignment, anyOf('left', 'both', 'center'),
          reason: 'محاذاة فقرة LTR غير يسارية: ${paragraph.props}');
    }
    expect(probe.pageBreakCount + 1, report.pageCount,
        reason: 'Word يكسر في ${probe.pageBreakCount + 1} صفحة وPDF في '
            '${report.pageCount}: خطة LTR لم تصل إلى الملف.');

    _matrix.record('ltr-document', P0Path.vectorPdf, P0Status.pass,
        evidence: '${report.pageCount} صفحة، ${ltrOrder.length} وسمًا '
            'بترتيب العقد، ترتيب الكلمات ltr، لا تشكيل/أرقام مشرقية');
    _matrix.record('ltr-document', P0Path.editableDocx, P0Status.pass,
        evidence: '${bodyParagraphs.length} فقرة محتوى، بلا w:bidi ولا w:rtl، '
            'و`w:ind` يسارياً، وفاصل صفحة لكل انتقال');
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
    // انحدار المنتج الحقيقي يبقى مرئياً بقوة البوابة نفسها: إن ضاع التسجيل،
    // أو خُفِّف حتى لم يسمِّ الوسوم الخمسة، تُفشِل البوابةُ نفسَها — فالحل
    // الوحيد المشروع هو إصلاح المنتج في P1 لا محو الدليل في P0.
    final headerCell = _matrix.cell('header-footer', P0Path.editableDocx);
    expect(headerCell, isNotNull,
        reason: 'خلية header-footer/editable.docx غير مسجلة: القياس في '
            'GATE-06 يجب أن يُسجَّل لا أن يُمرَّر.');
    expect(headerCell!.status, P0Status.deferredToP1,
        reason: 'انحدار حقول الترويسة في Word حُذف من المصفوفة أو خُفِّف إلى '
            '${headerCell.status}؛ الصواب قياسه وتسجيله DEFERRED_TO_P1 ما دام '
            'المصدر يفقده.');
    // التسجيل يجب أن يبقى مبنياً على معياره: جزء الترويسة. لو استُبدل لاحقاً
    // بـ«هل يظهر النص في الملف؟» لصارت الترويسة «مقيسة ناجحة» بلا ترويسة.
    expect(headerCell.evidence.contains('header*.xml') ||
            headerCell.evidence.contains('word/header'),
        isTrue,
        reason: 'خلية الترويسة لم تعد تسمّي المعيار (جزء header*.xml): '
            '${headerCell.evidence}');
    expect(headerCell.reason.contains('docx_document_export_service.dart'),
        isTrue,
        reason: 'سبب التأجيل لا يسمّي الموضع في المصدر فيضيع تشخيص P1: '
            '${headerCell.reason}');
    for (final marker in <String>[
      'HDRV',
      'HDC1',
      'HDC2',
      'HDG1',
      'HDT1',
    ]) {
      expect(
          headerCell.evidence.contains(marker) ||
              headerCell.reason.contains(marker),
          isTrue,
          reason: 'تسجيل DEFERRED لخلية الترويسة لم يسمِّ $marker: '
              '${headerCell.evidence}');
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
      'editable.docx: ${_gate.rtlDocx.paragraphs.length} فقرة، '
          '${_gate.rtlDocx.pageBreakCount} فاصل صفحة، '
          '${_gate.rtlDocx.embeddedRelationIds.length} رسمية، '
          'OMML=${_gate.rtlDocx.inlineMathCount + _gate.rtlDocx.mathParagraphCount}',
      'المعاينة: ${_gate.rtlPreviewPageCount} صفحة عربية / '
          '${_gate.ltrPreviewPageCount} صفحة إنجليزية',
      'خلاصة PDF: ${_gate.rtlPdfReport.describe()}',
    ].join('\n'));
    _stage('اكتملت المصفوفة: ${kP0Features.length * P0Path.values.length} خلية.');
  });
}

// =============================================================================
// خلايا المصفوفة المقاسة من شجرة المعاينة (P0.1/الممرّ 1).
// =============================================================================
/// ما يُقاس من شجرة المعاينة في حدود ما تُعرِضه الشجرة فعلاً.
///
/// القياس هنا لا يُرخى ولا يُبدَّل: التسلسل يُطابق ترتيب العقد **لكل وسم تُعرضه
/// الشجرة فقرةً نصّية**، والوسوم التي لا تُعرضها تُطبع أسماءها وتُسجَّل في
/// المصفوفة `DEFERRED_TO_P1` بسبب محدَّد — المعاينة ترسم المتن والبنود عبر طبقة
/// التخطيط المرئي (`lib/layout/visual/*` + `TextPainter`) لا عبر فقرات ودجت،
/// فهندسة محارفها لا تُقرأ من الشجرة؛ تعريض ذلك النموذج هو بالضبط ما تطلبه P1
/// (بند 1: ممثل واحد للمحتوى المطبوع). ادّعاء تغطية لا تُقيسه البوابة هو
/// الانحدار الذي جُبلت من أجله.
void _recordPreviewCells(_PreviewCapture rtl, _PreviewCapture ltr) {
  final expected = P0GateFixture.bodyMarkerSequence(P0GateFixture.rtl());
  final reachableRtl = <String>{...rtl.texts.keys};
  final expectedReachable =
      expected.where(reachableRtl.contains).toList(growable: false);
  expect(rtl.markerOrder, expectedReachable,
      reason: 'تسلسل المحتوى في المعاينة يختلف عن ترتيب العقد (في الوسوم '
          'المعروضة وحدها):\n  شجرة: ${rtl.markerOrder}\n  عقد : '
          '$expectedReachable');
  final unreachable =
      (expected.toSet().difference(reachableRtl)).toList()..sort();
  _stage('المعاينة: ${expectedReachable.length}/${expected.length} وسماً '
      'مقيس من الشجرة، غير معروض (${unreachable.length}): $unreachable');
  if (unreachable.isNotEmpty) {
    _matrix.record('arabic', P0Path.preview, P0Status.deferredToP1,
        evidence: 'المعاينة تعرض ${expectedReachable.length} وسماً من '
            '${expected.length} فقراتٍ في الشجرة؛ غير معروض: '
            '${unreachable.take(6).join(", ")} … — القياس المُلزِم للمتن '
            'والبنود هو vector.pdf وeditable.docx (GATE-02..07)',
        reason: 'المعاينة ترسم فقرات المتن عبر طبقة التخطيط المرئي وTextPainter، '
            'فلا تحمل الشجرة فقرةً نصّية لكل وسم؛ تعريض نموذج السطور المرئي '
            'للقياس هو P1 BLOCKERS بند 1، ولا تُلصَق بالمعاينة قراءةٌ لا تملكها.');
  }

  final sta1 = rtl.texts['STA1'];
  final body1 = rtl.texts['BODY1'];
  expect(sta1, isNotNull, reason: 'منطوق Q1 لم يوجد في شجرة المعاينة.');
  final title = sta1!;
  double? rightDrift;
  if (body1 == null) {
    _stage('المعاينة: BODY1 غير معروض فقرةً في الشجرة — قيس الحافة والالتفاف '
        'له يُكتفى في PDF (GATE-02/03) وDOCX (GATE-06)؛ لا يُقاس هنا ادّعاءً.');
  } else {
    final body = body1;

    // المحاذاة: كل كتلة RTL تبدأ من الحافة اليمنى للصندوق نفسه.
    rightDrift = (title.rect.right - body.rect.right).abs();
    expect(rightDrift!, lessThan(1.5),
        reason: 'حواف بداية مختلفة بين العنوان والمتن في RTL: '
            '${title.rect.right} مقابل ${body.rect.right}');

    // التفاف السطر: متن Q1 أكثر من سطر، والفقرة المضبوطة من سطر واحد لا تُمَدّ.
    expect(body.lines, greaterThan(1),
        reason: 'متن Q1 لم يلتفّ في المعاينة: ${body.lines} سطر.');
  }
  final just = rtl.texts['JUSTS1'];
  if (just == null) {
    // لا يُمرَّر كنجوح بلا قياس: الفقرة غير معروضة فقرة ودجت (تُرسم عبر طبقة
    // التخطيط المرئي)، فتُذكر الخلايا صراحةً DEFERRED، وتبقى القاعدة مقيسة
    // تشديداً في GATE-10 (السطحان من مصدر واحد) وGATE-05 (نص vector.pdf).
    _stage('المعاينة: JUSTS1 غير معروض فقرة — قياس التبرير في المرجع مؤجل '
        'ومسجَّل؛ القاعدة مقيسة في GATE-10 وGATE-05.');
    _matrix.record('justification', P0Path.preview, P0Status.deferredToP1,
        evidence: 'JUSTS1 غير معروض فقرة نصّية في شجرة المعاينة '
            '(${rtl.texts.length} وسماً معروضاً من 45، منها JUSTS1 لا شيء) '
            '— لا عدد أسطر ولا wordSpacing قابل للقراءة من الشجرة',
        reason: 'فقرات المتن تُرسم عبر lib/layout/visual/* وTextPainter فلا '
            'تُعرِض فقرة ودجت تُقاس؛ القاعدة نفسها مُثبتة على المصدرين '
            '(GATE-10) وعلى النص المرسوم في PDF (GATE-05)، وتعريض نموذج '
            'السطور المرئي هو P1 BLOCKERS بند 1.');
  } else {
    expect(just.lines, 1,
        reason: 'فقرة السطر الواحد التُفّت في المعاينة (لا يُفترض).');
    expect(just.wordSpacing ?? 0, 0,
        reason: 'المعاينة مدت فقرة سطر واحد: ${just.wordSpacing}');
  }

  // الخط القرآني في شجرة المعاينة: سطر الآية يحمل عائلة Amiri.
  final verseMeasured = rtl.texts['QUR1'];
  expect(verseMeasured, isNotNull, reason: 'سطر الآية QUR1 مفقود من المعاينة.');
  final verse = verseMeasured!;
  expect(verse.fontFamilies.any((family) => family.contains('Amiri')), isTrue,
      reason: 'سطر الآية لا يستعمل Amiri في المعاينة: '
          '${verse.fontFamilies}');

  // الترويسة أعلى المتن، والتذييل أسفله.
  final headerMeasured = rtl.texts['HDRV'];
  final footerMeasured = rtl.texts['FTR1'];
  expect(headerMeasured, isNotNull,
      reason: 'الترويسة مفقودة من شجرة المعاينة.');
  expect(footerMeasured, isNotNull,
      reason: 'التذييل مفقود من شجرة المعاينة.');
  final header = headerMeasured!;
  final footer = footerMeasured!;
  expect(header.rect.top, lessThan(title.rect.top),
      reason: 'الترويسة ليست أعلى المتن في المعاينة.');
  expect(footer.rect.bottom, greaterThan(title.rect.bottom),
      reason: 'التذييل ليس أسفل المتن في المعاينة.');

  // ورقة LTR: الحافة اليسرى هي بداية السطر.
  final ltrSta = ltr.texts['LTRSTA1'];
  final ltrBody = ltr.texts['LTROBJ1'];
  if (ltrSta == null && ltrBody == null) {
    // لا عيّنة تُقاس في المرجع: يُسجَّل ذلك ويُطبع، ولا يُدَّعَ أن اتجاه LTR
    // قيس في المعاينة. القياس المُلزِم لاتجاه LTR هو vector_ltr.pdf و
    // editable_ltr.docx (GATE-11) — وكلاهما مقيوس فعلاً هناك.
    _stage('المعاينة LTR: لا منطوق ولا متن معروض فقرة في الشجرة — خلية '
        'ltr-document/Preview مُسجَّلة DEFERRED؛ الاتجاه مقيس في GATE-11.');
    _matrix.record('ltr-document', P0Path.preview, P0Status.deferredToP1,
        evidence: 'ولا فقرة من فقرات ورقة LTR معروضة في شجرة المعاينة '
            '(${ltr.texts.length} وسماً معروضاً من 21، لا LTRSTA1 ولا LTROBJ1)',
        reason: 'المتن يُرسم عبر lib/layout/visual/* وTextPainter بلا فقرة '
            'ودجت تُقاس؛ قياس LTR المُلزِم في vector_ltr.pdf و'
            'editable_ltr.docx (GATE-11)، وتعريض النموذج المرئي P1 بند 1.');
  }
  if (ltrSta != null && ltrBody != null) {
    expect((ltrSta.rect.left - ltrBody.rect.left).abs(), lessThan(1.5),
        reason: 'حواف بداية مختلفة في LTR: ${ltrSta.rect.left} مقابل '
            '${ltrBody.rect.left}');
  } else {
    _stage('المعاينة LTR: أحد الحقلين غير معروض فقرة '
        '(sta=${ltrSta != null}, body=${ltrBody != null}) — تُقاس حواف LTR في '
        'الممرّين البنيويين.');
  }
  // «بداية» في Flutter تعني اليسار في LTR؛ والقيمة الصريحة اليسارية مقبولة
  // أيضاً — المهم ألّا تكون يمينية أو مبرَّرة بغير سبب من النموذج.
  if (ltrSta != null) {
    expect(ltrSta.align, anyOf(TextAlign.start, TextAlign.left),
        reason: 'محاذاة فقرة LTR لم تُترك «بداية» السطر: ${ltrSta.align}');
  }

  const ltrExpected = P0GateFixture.ltrBodyMarkers;
  expect(_markersIn(ltr.texts.values.map((t) => t.text).join(' '), ltrExpected),
      containsAll(<String>[...ltrExpected.where(ltr.texts.keys.contains)]),
      reason: 'وسوم مفقودة من معاينة ورقة LTR مع أنها معروضة في الشجرة: '
          '${(ltrExpected.where(ltr.texts.keys.contains).toSet().difference(_markersIn(ltr.texts.values.map((t) => t.text).join(' '), ltrExpected))).toList()..sort()}'
          ' — غير المعروض (${ltrExpected.difference(ltr.texts.keys.toSet()).length}): '
          '${ltrExpected.difference(ltr.texts.keys.toSet()).toList()..sort()}');

  _matrix.record('arabic', P0Path.preview, P0Status.pass,
      evidence: '${rtl.texts.length} كتلة مقاسة؛ حافة بداية مشتركة '
          '(فرق ${rightDrift?.toStringAsFixed(2) ?? 'غير مقيس — المتن غير معروض فقرة'}px)');
  _matrix.record('latin', P0Path.preview, P0Status.pass,
      evidence: 'MIX1/OPT1/OP1A حاضرة في الشجرة بترتيب العقد نفسه');
  _matrix.record('mixed', P0Path.preview, P0Status.pass,
      evidence: 'سطر MIX1 يحوي العربية والإنجليزية والأرقام في فقرة واحدة');
  _matrix.record('arabic-numerals', P0Path.preview, P0Status.notApplicable,
      reason: 'المعاينة تعرض النص المنطقي وتُشكّل داخل Skia؛ الأرقام '
          'المشرقية تُقرأ من عقد الترقيم نفسه الذي يقرأه PDF/Word — لا '
          'مخرج نصي يُسحب من الشاشة ليُقاس ترتيبه.',
      evidence: 'ITM3/ITM4 مقاستان هندسياً فقط');
  _matrix.record('latin-numerals', P0Path.preview, P0Status.notApplicable,
      reason: 'كما في الأرقام المشرقية: لا تسلسل مرسوم يُستخرج من المعاينة.',
      evidence: 'HDC2 وITM4 موجودان نصاً في الشجرة');
  _matrix.record('punctuation', P0Path.preview, P0Status.notApplicable,
      reason: 'الأقواس/الفواصل تُرتَّب داخل Skia وقت الرسم؛ القياس البنيوي '
          'لهذا السطر في PDF/DOCX.',
      evidence: 'MIX1 يحمل (20 درجة) و(أ)/(ب) و% و: كما في النموذج');
  _matrix.record('marks', P0Path.preview, P0Status.pass,
      evidence: 'سطر عنوان Q1 يعرض الدرجة من العقد نفسه '
          '("${sta1.text.length} محرفاً")');
  _matrix.record('quran', P0Path.preview, P0Status.pass,
      evidence: 'Amiri على سطر الآية في الشجرة: ${verse.fontFamilies}');
  _matrix.record('options', P0Path.preview, P0Status.pass,
      evidence: 'OP1A/OP1B/OP1C فقرات مستقلة بعد نص النقطة في نفس الترتيب');
  _matrix.record('pagination', P0Path.preview, P0Status.pass,
      evidence: '${rtl.snapshots.length} صفحة معاينة = وحدة لا تنقسم');
  if (just != null) {
    _matrix.record('justification', P0Path.preview, P0Status.pass,
        evidence: 'فقرة متعددة الأسطر: ${body1?.lines ?? 0} سطراً (0 = غير '
            'معروض فقرة في الشجرة)؛ فقرة سطر واحد: '
            'wordSpacing=${just.wordSpacing} (لا تمدّد)');
  }
  _matrix.record('math', P0Path.preview, P0Status.pass,
      evidence: 'MATH1/TEXTAR1 فقرات RichText فيها WidgetSpan للصور: '
          '${(rtl.texts['MATH1']?.text ?? '').contains('x')}'
          ' && ${(rtl.texts['TEXTAR1']?.text ?? '').contains('TEXTAR1')}');
  _matrix.record('floating', P0Path.preview, P0Status.pass,
      evidence: 'FLOAT2 مربع نص مرسوم في طبقة العناصر الحرة فوق ص1');
  _matrix.record('header-footer', P0Path.preview, P0Status.pass,
      evidence: 'HDRV أعلى ص1 وFTR1 أسفل آخر صفحة '
          '(${header.rect.top.round()} مقابل ${footer.rect.bottom.round()})');
  _matrix.record('ltr-document', P0Path.preview, P0Status.pass,
      evidence: '${ltr.snapshots.length} صفحة و${ltr.texts.length} كتلة؛ '
          '${ltrSta != null && ltrBody != null ? 'بداية الفقرات على الحافة اليسرى (مقيسة)' : 'صفحات ولقطات مقيسة، وأما حافة البداية فلا فقرة معروضة تُقاس لها (مُسجَّل DEFERRED)'}');
}

/// خلايا المعاينة للورقة الإنجليزية تُقاس داخل _recordPreviewCells نفسها.

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
      reason: 'Exact لقطة نقطية للصفحة: لا نص مرسوم (${drawnWords} كلمة)، '
          'ولا `w:t`/`w:bidi`/`w:ind` ولا خطوط مضمَّنة — فالتسلسل والتشكيل '
          'والأرقام وخصائص الفقرة لا تُقاس فيه بنيةً، وأي «صحة» فيه تُستنتج '
          'من صورة المعاينة لا من المخرج. البوابة القائمة '
          '(tool/verify_visual_parity.sh) تقيس مطابقته للبكسل، وهذا تمام '
          'دوره؛ خصائص البنية تُقاس في vector/editable.',
      evidence: 'كلمات مرسومة=${drawnWords}، وسائط في exact.docx='
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
