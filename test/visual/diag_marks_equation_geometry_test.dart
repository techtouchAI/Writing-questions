// مسبار هندسي: موضع الدرجة والمسافة حول المعادلة المستقلة في المسارات الثلاثة.
//
// يقيس الحالة نفسها ثلاث مرات على مستند واحد:
//   (A) السطح القانوني المرسوم من LayoutDocument (المرجع المطبوع — نفس ما
//       يرسمه PDF بايتاً بإحداثياته).
//   (B) سطح الإنتاج التفاعلي (`ExamPreviewScreen` بلا حقن — ما يراه المدرس
//       ويحرّر عليه في الإصدار).
//   (C) ملف PDF للنموذج نفسه، يُكتب على القرص للمعاينة البصرية.
//
// لا يحكم على شيء ولا يعدّل سلوكاً؛ يكتب قياساته في
// `build/visual_parity/element-geometry/` لتُنقل عبر الناقل المتحقّق.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart' show MathStyle;
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../support/production_evidence_fonts.dart';

import 'package:writing_questions_app/layout/canonical/canonical_layout_preview.dart';
import 'package:writing_questions_app/layout/canonical/canonical_layout_service.dart';
import 'package:writing_questions_app/layout/canonical/layout_document.dart';
import 'package:writing_questions_app/layout/canonical/layout_units.dart';
import 'package:writing_questions_app/layout/document_direction.dart';
import 'package:writing_questions_app/models/branch_item.dart';
import 'package:writing_questions_app/models/branch_model.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/paper_settings.dart';
import 'package:writing_questions_app/models/point_kind.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/models/question_option.dart';
import 'package:writing_questions_app/providers/exam_wizard_controller.dart';
import 'package:writing_questions_app/services/pdf_export_service.dart';
import 'package:writing_questions_app/views/widgets/math_snapshot_host.dart';
import 'package:writing_questions_app/views/widgets/safe_math_tex.dart';
import 'package:writing_questions_app/views/wizard/exam_preview_screen.dart';

const String _output = 'build/visual_parity/element-geometry';
const ValueKey<String> _screenKey = ValueKey<String>('element-geometry-screen');

/// السؤال المقيس: منطوق طويل (يلتفّ)، درجة، ثلاث معادلات إحداها مستقلة،
/// فروع بدرجات، ومشكّل عربي، ثم نقاط وخيارات وسؤال تالٍ.
ExamDocument _document() => ExamDocument(
      name: 'قياس موضع الدرجة والمعادلة',
      header: ExamHeaderModel.initial(
        subject: 'الرياضيات',
        schoolName: 'مدرسة القياس',
        examType: 'اختبار الفصل الأول',
      ),
      settings: const PaperSettings(headerBorder: true),
      questions: <QuestionModel>[
        QuestionModel(
          id: 'q-marks',
          questionNumber: 1,
          category: 'الجبر',
          statement: r'أوجد قيمة $x$ في المعادلة $x^{2}+2x+1=0$ ثم بيّن '
              r'أثرَ التَشْكِيلِ على قراءة النص العربي في الفقرة التالية.',
          marksOverride: 10,
          body: r'لاحظ أن $\sqrt{x^2}=|x|$ وأن $\frac{1}{2}$ نصفٌ، ثم:' '\n'
              r'$$\frac{a}{b}=\sqrt{x^{2}+1}$$' '\n'
              r'ثم أكمل الحل: $x=\frac{-b}{2a}$.',
          items: <BranchItem>[
            BranchItem(
              id: 'p1',
              kind: PointKind.multipleChoice,
              text: 'اختر الصيغة الصحيحة:',
              options: <QuestionOption>[
                QuestionOption(text: r'$x^{2}$'),
                QuestionOption(text: r'$\sqrt{x}$'),
                QuestionOption(text: r'$\frac{x}{2}$'),
                QuestionOption(text: 'لا شيء ممّا سبق'),
              ],
            ),
          ],
          branches: <BranchModel>[
            BranchModel(
              id: 'b1',
              marks: 5,
              content: BranchContent(
                statement: 'الفرع الأول:',
                body: r'سَلَامٌ عَلَيْكُمْ — أثبت أن $\sqrt{x^{2}}=|x|$.' '\n'
                    r'$$\int_{0}^{1} x\,dx=\frac{1}{2}$$',
              ),
            ),
            BranchModel(
              id: 'b2',
              marks: 3,
              content: BranchContent(
                statement: 'الفرع الثاني:',
                body: r'اكتب الصيغة $a_n=n^{\frac{1}{2}}$ بالشكل الجذري.',
              ),
            ),
          ],
        ),
        QuestionModel(
          id: 'q-next',
          questionNumber: 2,
          statement: 'سؤال تالٍ قصير.',
          marksOverride: 7,
        ),
      ],
    );

List<double> _rect(LayoutRect rect) =>
    <double>[rect.left, rect.top, rect.width, rect.height];

List<double> _px(Rect rect, double scale) => <double>[
      rect.left * scale,
      rect.top * scale,
      rect.width * scale,
      rect.height * scale,
    ];

/// مقاطع الدرجة في المستند القانوني: أي جريان دوره `marks` مع سطره.
Map<String, Object> _canonicalMarks(LayoutDocument layout) {
  final entries = <Map<String, Object>>[];
  for (final page in layout.pages) {
    final lines = page.blocks.expand((block) => block.allLines);
    for (final line in lines) {
      final marks = line.runs.where(
        (run) => run.semanticRole == LayoutSemanticRole.marks ||
            run.contentKind == LayoutContentKind.marks,
      );
      if (marks.isEmpty) continue;
      final textRuns = line.runs.where(
        (run) =>
            run.semanticRole == LayoutSemanticRole.text &&
            run.text.trim().isNotEmpty,
      );
      if (textRuns.isEmpty) continue;
      // RTL: نهاية المنطوق هي أصغر x على السطر؛ LTR: أكبرها.
      final statementEnd = line.direction == DocumentDirection.rtl
          ? textRuns.map((run) => run.x).reduce((a, b) => a < b ? a : b)
          : textRuns
              .map((run) => run.x + run.advance)
              .reduce((a, b) => a > b ? a : b);
      final marksStart =
          marks.map((run) => run.x).reduce((a, b) => a < b ? a : b);
      entries.add(<String, Object>{
        'page': page.index,
        'lineId': line.id,
        'lineIndex': line.lineIndex,
        'paragraphIndex': line.paragraphIndex,
        'lineRect': _rect(line.rect),
        'lineBaseline': line.baseline,
        'statementEndX': statementEnd,
        'marksStartX': marksStart,
        'marksEndX':
            marks.map((run) => run.x + run.advance).reduce((a, b) => a > b ? a : b),
        'marksTopPt': marks.map((run) => line.rect.top).reduce((a, b) => a > b ? a : b),
        'gapPt': (statementEnd - marksStart).abs(),
        'trueEnd': line.logicalRunIds.isNotEmpty &&
            line.logicalRunIds.last == marks.last.id,
        'marksText': marks.map((run) => run.text).join(),
      });
    }
  }
  return <String, Object>{'count': entries.length, 'entries': entries};
}

/// كتل المعادلات المستقلة في المستند القانوني مع الفجوة عن الجار السابق/اللاحق.
Map<String, Object> _canonicalBlockMath(LayoutDocument layout) {
  final entries = <Map<String, Object>>[];
  for (final page in layout.pages) {
    for (final block in page.blocks) {
      final all = <LayoutBlock>[block, ...block.descendants];
      for (var index = 0; index < all.length; index++) {
        final current = all[index];
        if (!current.id.contains('/block-math/')) continue;
        final previous = index > 0 ? all[index - 1] : null;
        final next = index + 1 < all.length ? all[index + 1] : null;
        entries.add(<String, Object>{
          'page': page.index,
          'blockId': current.id,
          'rect': _rect(current.rect),
          'gapBeforePt':
              previous == null ? -1 : current.rect.top - previous.rect.bottom,
          'gapAfterPt': next == null ? -1 : next.rect.top - current.rect.bottom,
          'lineCount': current.lines.length,
          'measurementSource': current.lines.isEmpty
              ? 'none'
              : current.lines.first.runs
                  .map((run) => run.measurementSource)
                  .toSet()
                  .join(','),
        });
      }
    }
  }
  return <String, Object>{'count': entries.length, 'entries': entries};
}

Future<void> _writeImage(
  WidgetTester tester,
  String name,
  RenderRepaintBoundary boundary,
) async {
  final image = (await tester.runAsync(() => boundary.toImage()))!;
  try {
    final png = (await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.png),
    ))!;
    Directory(_output).createSync(recursive: true);
    File('$_output/$name.png').writeAsBytesSync(png.buffer.asUint8List());
  } finally {
    image.dispose();
  }
}

void _writeJson(String name, Map<String, Object?> data) {
  Directory(_output).createSync(recursive: true);
  File('$_output/$name')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(data));
}

Widget _app(ExamWizardController controller, {ExamPreviewScreen? screen}) =>
    RepaintBoundary(
      key: _screenKey,
      child: MaterialApp(
        // Production installs this host in main.dart: without it the engine
        // falls back to estimated math metrics and both sides drift.
        builder: (_, child) => MathSnapshotHost(child: child),
        home: ChangeNotifierProvider<ExamWizardController>.value(
          value: controller,
          child: screen ?? ExamPreviewScreen(onBackToQuestions: () {}),
        ),
      ),
    );


/// Settles without depending on a quiet frame count.
///
/// The released surface shows a pending-plan spinner while the engine works,
/// and `pumpAndSettle` throws on a timeout (a spinner schedules frames for as
/// long as the plan is unresolved), so the probe pumps a bounded number of
/// frames and records the timeout instead of dying inside the harness.
Future<void> _settle(WidgetTester tester, {int frames = 90}) async {
  for (var frame = 0; frame < frames; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadProductionEvidenceFonts);

  testWidgets('[element-geometry] marks and display-math placement, 3 surfaces',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // A probe must still hand over what it measured. Widget-tree errors
    // (an overflow in the released surface is itself a finding) are recorded
    // and printed instead of aborting before the evidence is written.
    final problems = <String>[];
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      problems.add(details.exceptionAsString());
    };
    var hookRestored = false;
    void restoreHook() {
      if (hookRestored) return;
      hookRestored = true;
      FlutterError.onError = previousOnError;
    }

    addTearDown(restoreHook);
    void note(String message) =>
        // ignore: avoid_print
        print('::warning title=ELEMENT-GEOMETRY::$message');

    final document = _document();
    final controller = ExamWizardController(document: document);
    addTearDown(controller.dispose);

    // ---------- (B) سطح الإنتاج: ما يراه المدرس ويحرّر عليه ----------
    await tester.pumpWidget(_app(controller));
    await _settle(tester);
    final screen = tester.renderObject<RenderRepaintBoundary>(find.byKey(_screenKey));
    await _writeImage(tester, 'edit_surface', screen);

    // Evidence goes down before the next stage, so a hang in a later stage
    // cannot erase what was already measured.
    _writeJson('geometry.json', <String, Object?>{'stage': 'surface'});
    _writeJson('manifest.json', <String, Object?>{
      'files': <String>[
        if (File('$_output/edit_surface.png').existsSync()) 'edit_surface.png',
        'geometry.json',
        'manifest.json',
      ],
      'pageCount': 1,
    });

    const pageKey = ValueKey<String>('a4-page-0');
    if (find.byKey(pageKey).evaluate().isEmpty) {
      problems.add('production surface drew no page (plan pending)');
      note('surface الإنتاج لم يرسم صفحة: لا قياس هندسي على هذه المرحلة.');
    }
    final pageRect = find.byKey(pageKey).evaluate().isEmpty
        ? Rect.zero
        : tester.getRect(find.byKey(pageKey));
    // مقياس التكبير الحالي للورقة داخل النافذة (px/px).
    final zoom = pageRect.width / LayoutUnits.ptToPx(LayoutUnits.a4.width);
    final scale = LayoutUnits.ptToPx(1) * zoom;

    Rect? rectOf(Finder finder) {
      if (finder.evaluate().isEmpty) return null;
      return tester.getRect(finder.first);
    }

    final marksFinder = find.byTooltip('انقر لتعديل الدرجة');
    final statementRect = rectOf(find.byKey(const ValueKey<String>('statement-q-marks')));
    final bodyRect = rectOf(find.byKey(const ValueKey<String>('body-q-marks')));
    final marksRects = <List<double>>[
      for (final element in marksFinder.evaluate())
        _px(tester.getRect(find.byWidget(element.widget)), scale),
    ];
    final marksDetail = <Map<String, Object?>>[
      for (final element in marksFinder.evaluate())
        <String, Object?>{
          'rectPt': _px(tester.getRect(find.byWidget(element.widget)), scale),
          'widgetType': element.widget.runtimeType.toString(),
        },
    ];
    final displayMaths = <Map<String, Object>>[];
    for (final element in find.byType(SafeMathTex).evaluate()) {
      final widget = element.widget as SafeMathTex;
      if (widget.mathStyle != MathStyle.display) continue;
      displayMaths.add(<String, Object>{
        'latex': widget.latex,
        'rectPt': _px(tester.getRect(find.byWidget(widget)), scale),
      });
    }

    final production = <String, Object?>{
      'pageRectPt': _px(pageRect, scale),
      'zoom': zoom,
      'pxToPt': LayoutUnits.pxToPt(1),
      'statementRectPt': statementRect == null ? null : _px(statementRect, scale),
      'bodyRectPt': bodyRect == null ? null : _px(bodyRect, scale),
      'marksRectPt': marksRects,
      'marksDetail': marksDetail,
      'displayMathCount': displayMaths.length,
      'displayMath': displayMaths,
    };

    // ---------- (A) السطح القانوني: نفس ما يرسمه PDF ----------
    LayoutDocument? captured;
    await tester.pumpWidget(const SizedBox.shrink());
    await _settle(tester, frames: 8);
    final controller2 = ExamWizardController(document: document);
    addTearDown(controller2.dispose);
    await tester.pumpWidget(
      _app(
        controller2,
        screen: ExamPreviewScreen(
          onBackToQuestions: () {},
          canonicalLayoutResolver: ({required document, required sourceIr}) async {
            final layout = await CanonicalLayoutService.resolve(
              document: document,
              sourceIr: sourceIr,
            );
            captured = layout;
            return layout;
          },
          canonicalPreviewAssetLoader: ({required layout, required document}) =>
              CanonicalLayoutPreviewAssets.load(layout: layout, document: document),
        ),
      ),
    );
    for (var attempt = 0; attempt < 120 && captured == null; attempt++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await _settle(tester, frames: 12);
    final canonicalScreen =
        tester.renderObject<RenderRepaintBoundary>(find.byKey(_screenKey));
    await _writeImage(tester, 'reference_preview', canonicalScreen);

    // The harness asserts that onError is restored before anything else can
    // throw; widget-tree errors from here on belong to the probe's report.
    restoreHook();
    final layout = captured;
    if (layout == null) {
      problems.add('canonical layout was never resolved');
      note('لم يُحسم التخطيط القانوني: لا مقارنة ولا PDF.');
      _writeJson('geometry.json', <String, Object?>{
        'complete': false,
        'problems': problems,
        'production': production,
      });
      _writeJson('manifest.json', <String, Object?>{
        'files': <String>['geometry.json', 'manifest.json'],
        'pageCount': 1,
      });
      fail('مسبار الهندسة: ${problems.join(' | ')}');
    }

    // ---------- (C) PDF للنموذج نفسه ----------
    // Export is driven by pumps, not runAsync: the math raster pass completes
    // through frames, and inside runAsync it never completes (the fixture
    // records the same trap). A hard frame cap keeps the probe from hanging.
    Uint8List? pdf;
    try {
      var finished = false;
      Object? failure;
      unawaited(
        PdfExportService.buildDocumentPdfBytes(
          document: document,
          layoutDocument: layout,
        ).then<void>((bytes) {
          pdf = bytes;
        }).catchError((Object error) {
          failure = error;
        }).whenComplete(() {
          finished = true;
        }),
      );
      for (var frame = 0; frame < 240 && !finished; frame++) {
        await tester.pump(const Duration(milliseconds: 1));
      }
      if (!finished) {
        problems.add('pdf export did not finish within 240 pumps');
        note('تصدير PDF لم ينتهِ ضمن 240 إطارًا.');
      } else if (failure != null) {
        problems.add('pdf export failed: $failure');
        note('فشل تصدير PDF: $failure');
      } else if (pdf != null) {
        Directory(_output).createSync(recursive: true);
        File('$_output/document.pdf').writeAsBytesSync(pdf!);
      }
    } catch (error) {
      problems.add('pdf build threw: $error');
      note('تعذّر بناء PDF النموذج: $error');
    }

    final canonicalMarks = _canonicalMarks(layout);
    final canonicalMath = _canonicalBlockMath(layout);
    _writeJson('geometry.json', <String, Object?>{
      'document': document.name,
      'pageCount': layout.pageCount,
      'canonical': <String, Object?>{
        'marks': canonicalMarks,
        'blockMath': canonicalMath,
        'titleBlocks': <Map<String, Object?>>[
          for (final page in layout.pages)
            for (final block in page.blocks)
              for (final child in <LayoutBlock>[block, ...block.descendants])
                if (child.kind == LayoutBlockKind.title)
                  <String, Object?>{
                    'page': page.index,
                    'id': child.id,
                    'rect': _rect(child.rect),
                    'lines': child.lines.length,
                  },
        ],
      },
      'production': production,
    });
    _writeJson('manifest.json', <String, Object?>{
      'files': <String>[
        if (File('$_output/document.pdf').existsSync()) 'document.pdf',
        if (File('$_output/edit_surface.png').existsSync()) 'edit_surface.png',
        'geometry.json',
        if (File('$_output/reference_preview.png').existsSync())
          'reference_preview.png',
        'manifest.json',
      ],
      'pageCount': layout.pageCount,
    });
    if (problems.isNotEmpty) {
      note('problems: ${problems.join(' | ')}');
    }
    // A measurement that published a partial inventory would be rejected by
    // the transport anyway; fail loudly but after the evidence is written.
    expect(problems, isEmpty, reason: 'المسبار لقي بقيود مسجّلة أعلاه.');
  }, timeout: const Timeout(Duration(minutes: 6)));
}
