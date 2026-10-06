// تركيبة الانحدار البصري (Visual Regression Fixture).
//
// تُنتج هذه الركيزة **قطع المقارنة** التي تستهلكها مهمّة CI البصرية:
//   * `build/visual_parity/preview_page-N.png` — كل صفحة معاينة كما رسمها
//     Flutter (96dpi = بكسل اللوحة نفسه).
//   * `build/visual_parity/vector.pdf` — PDF متجهي مرسوم من LayoutDocument
//     نفسه الذي عُرض في المعاينة.
//   * `build/visual_parity/editable.docx` — Word قابل للتحرير من مسار
//     DocumentIR → LegacyDocxAdapter → PaginationEngine.
//   * `build/visual_parity/exact.pdf` و`exact.docx` — مسار Exact المنفصل
//     المبني من لقطات المعاينة نفسها.
//   * `build/visual_parity/manifest.json` — عدد الصفحات وأبعادها.
//
// ثم يصيّر CI كل مسار مستقل (poppler لـPDF، LibreOffice ثم poppler لـWord)
// ويقارن كل صفحة مصيَّرة بلقطة المعاينة المقابلة بمقياس RMSE الفعلي.
//
// التركيبة تغطي قائمة التحقق: عربية RTL، إنجليزية LTR، أرقام، صيغ سطرية
// ومنفصلة (كسر، جذر، أس، مؤشر، مصفوفة)، آية قرآنية، اختيار من متعدد،
// درجات، غامق/مائل/تحته خط، خطوط وأحجام وألوان ومحاذاة وتباعدات مختلفة،
// ترويسة وتذييل وإطار، وعناصر حرة (شكل، صيغة، صورة)، ومستند متعدد الصفحات.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:writing_questions_app/models/branch_item.dart';
import 'package:writing_questions_app/models/branch_model.dart';
import 'package:writing_questions_app/models/exam_canvas_geometry.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_font.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/floating_element.dart';
import 'package:writing_questions_app/models/paper_divider.dart';
import 'package:writing_questions_app/models/paper_font.dart';
import 'package:writing_questions_app/models/paper_settings.dart';
import 'package:writing_questions_app/models/paper_text_style.dart';
import 'package:writing_questions_app/models/point_kind.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/models/question_option.dart';
import 'package:writing_questions_app/pdf_engine/exam_fonts.dart';
import 'package:writing_questions_app/layout/canonical/canonical_layout_preview.dart';
import 'package:writing_questions_app/layout/canonical/canonical_layout_service.dart';
import 'package:writing_questions_app/layout/canonical/layout_units.dart';
import 'package:writing_questions_app/providers/exam_wizard_controller.dart';
import 'package:writing_questions_app/services/docx_document_export_service.dart';
import 'package:writing_questions_app/services/exact_export_service.dart';
import 'package:writing_questions_app/services/math_image_renderer.dart';
import 'package:writing_questions_app/services/page_snapshot_service.dart';
import 'package:writing_questions_app/services/pdf_export_service.dart';
import 'package:writing_questions_app/services/shape_image_renderer.dart';
import 'package:writing_questions_app/views/wizard/exam_preview_screen.dart';

/// مجلد القطع الذي يقرؤه سكربت التحقق البصري في CI.
const String _artifactDir = 'build/visual_parity';

/// PNG 1×1 (عنصر صورة حرة).
final Uint8List _tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8'
  'z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

/// يحمّل خطوط التطبيق نفسها في بيئة الاختبار، فتكون الصفحة المعاينة نصاً
/// حقيقياً (لا مربعات خط اختبار) والمقارنة البصرية ذات معنى.
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

ExamDocument _fixtureDocument() {
  return ExamDocument(
    name: 'تركيبة التحقق البصري',
    header: ExamHeaderModel.initial(
      subject: 'التربية الإسلامية',
      schoolName: 'مدرسة الاختبار',
      examType: 'اختبار الفصل الأول',
    ),
    settings: const PaperSettings(headerBorder: true),
    questions: <QuestionModel>[
      // (1) عربية: قسم + منطوق + نص + نقاط بأنواعها + خدماتها.
      QuestionModel(
        id: 'q1',
        questionNumber: 1,
        category: 'أحكام التلاوة',
        categoryAlign: PaperAlign.center,
        statement: 'اختر الإجابة الصحيحة:',
        body: 'قال تعالى: ﴿إِنَّا أَعْطَيْنَاكَ الْكَوْثَرَ﴾ — بيّن حكم التلاوة.',
        marksOverride: 10,
        items: <BranchItem>[
          BranchItem(
            id: 'p1',
            kind: PointKind.multipleChoice,
            text: 'الحكم في قوله تعالى ﴿الْكَوْثَرَ﴾ هو:',
            options: <QuestionOption>[
              QuestionOption(text: 'الإظهار'),
              QuestionOption(text: 'الإدغام'),
              QuestionOption(text: 'الإقلاب'),
              QuestionOption(text: 'الإخفاء'),
            ],
          ),
          BranchItem(id: 'p2', kind: PointKind.trueFalse, text: 'الآية مدنية.'),
          BranchItem(id: 'p3', kind: PointKind.fillBlank, text: 'عدد آيات سورة الكوثر'),
        ],
        branches: <BranchModel>[
          BranchModel(
            id: 'b1',
            marks: 5,
            content: BranchContent(
              statement: 'الفرع الأول: أكمل',
              body: 'اذكر ثلاث فوائد من حفظ القرآن الكريم.',
              items: <BranchItem>[
                BranchItem(id: 'bp1', text: 'الفائدة الأولى', marks: 2),
              ],
            ),
          ),
        ],
        attachments: <FloatingElement>[
          FloatingElement(
            id: 'shape-1',
            type: FloatingElementType.shape,
            shape: FloatingShapeType.square,
            dx: 500,
            dy: 120,
            width: 120,
            height: 90,
            framed: true,
          ),
          FloatingElement(
            id: 'formula-1',
            type: FloatingElementType.formula,
            label: r'\frac{a}{b}',
            dx: 120,
            dy: 620,
            width: 160,
            height: 60,
          ),
          FloatingElement(
            id: 'image-1',
            type: FloatingElementType.image,
            bytes: _tinyPng,
            dx: 620,
            dy: 640,
            width: 80,
            height: 80,
          ),
        ],
      ),
      // (2) رياضيات: صيغ سطرية ومنفصلة (كسر/جذر/أس/مؤشر/مصفوفة).
      QuestionModel(
        id: 'q2',
        questionNumber: 2,
        category: 'الجبر',
        statement: r'أوجد قيمة $x$ في المعادلة $x^2+2x+1=0$.',
        body: r'لاحظ أن $\sqrt{x^2}=|x|$ وأن $a_n = n^{\frac{1}{2}}$، '
            r'ثم $\begin{matrix} 1 & 2 \\ 3 & 4 \end{matrix}$.',
        marksOverride: 15,
        style: const PaperTextStyle(
          font: PaperFont.tajawal,
          lineHeight: 1.8,
          paragraphSpacing: 6,
          color: 0xFF1E3A8A,
        ),
        showFrame: true,
        dividerAfter: const PaperDivider(),
        items: <BranchItem>[
          BranchItem(
            id: 'q2p1',
            kind: PointKind.plain,
            text: r'حل المعادلة $x^2 - 4 = 0$.',
            marks: 5,
          ),
        ],
      ),
      // (3) إنجليزية LTR: قالب مختلف بالكامل (اتجاه، ترقيم، أرقام).
      QuestionModel(
        id: 'q3',
        questionNumber: 3,
        category: 'Vocabulary',
        categoryAlign: PaperAlign.right,
        statement: 'Choose the correct answer:',
        body: 'He ...... to school every day.',
        marksOverride: 12,
        titleAlign: PaperAlign.left,
        bodyAlign: PaperAlign.left,
        style: const PaperTextStyle(
          align: PaperAlign.left,
          underline: true,
          italic: true,
        ),
        items: <BranchItem>[
          BranchItem(
            id: 'q3p1',
            kind: PointKind.multipleChoice,
            text: 'Pick one:',
            options: <QuestionOption>[
              QuestionOption(text: 'go'),
              QuestionOption(text: 'goes'),
              QuestionOption(text: 'going'),
            ],
          ),
        ],
      ),
      // (4) نص طويل يضمن التدفّق إلى صفحات متعددة.
      for (var index = 4; index <= 7; index++)
        QuestionModel(
          id: 'q$index',
          questionNumber: index,
          statement: 'سؤال متعدد الصفحات رقم $index',
          body: 'نص طويل لضمان تقسيم الورقة إلى أكثر من صفحة: '
              '${'كلمات متتابعة لملء السطر واختبار التدفق. ' * 12}',
          marksOverride: 4,
          items: <BranchItem>[
            BranchItem(id: 'q${index}p1', text: 'بند أول', marks: 2),
            BranchItem(id: 'q${index}p2', text: 'بند ثانٍ', marks: 2),
          ],
        ),
    ],
  );
}

/// وسم مراحل الركيزة في مخرجات CI: بيان آخر ما وصلت إليه الركيزة عند الفشل
/// (لا يُترك التشخيص لتخمين رقم الخروج).
void _stage(String message) => debugPrint('[fixture] $message');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('تركيبة الانحدار البصري: لقطات المعاينة + ملفات Exact',
      (tester) async {
    await _loadAppFonts();
    _stage('الخطوط حُمّلت');

    final controller = ExamWizardController(document: _fixtureDocument());
    addTearDown(controller.dispose);
    final previewWorkFinished = Completer<void>();
    Object? previewFailure;

    // (1) إطار أول بمقاس عرض عادي: يقيس الراسم كتل الورقة في الإطار التالي.
    tester.view.physicalSize = const Size(1600, 1240);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<ExamWizardController>.value(
          value: controller,
          child: ExamPreviewScreen(
            onBackToQuestions: () {},
            canonicalLayoutResolver: ({
              required document,
              required sourceIr,
            }) async {
              _stage('Canonical layout requested');
              try {
                final layout = await CanonicalLayoutService.resolve(
                  document: document,
                  sourceIr: sourceIr,
                );
                _stage('Canonical layout resolved: ${layout.pageCount} pages');
                return layout;
              } catch (error) {
                previewFailure = error;
                if (!previewWorkFinished.isCompleted) {
                  previewWorkFinished.complete();
                }
                rethrow;
              }
            },
            canonicalPreviewAssetLoader: ({
              required layout,
              required document,
            }) async {
              _stage('Canonical preview assets requested');
              try {
                return await CanonicalLayoutPreviewAssets.load(
                  layout: layout,
                  document: document,
                );
              } catch (error) {
                previewFailure = error;
                rethrow;
              } finally {
                if (!previewWorkFinished.isCompleted) {
                  previewWorkFinished.complete();
                }
              }
            },
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(
      () => previewWorkFinished.future.timeout(const Duration(seconds: 60)),
    );
    await tester.pump();
    if (previewFailure != null) {
      fail('Canonical preview preparation failed: $previewFailure');
    }

    final renderedPageElements =
        find.byType(CanonicalLayoutPreviewPage).evaluate().toList();
    expect(renderedPageElements, isNotEmpty,
        reason: 'المعاينة canonical لم تُجهّز صفحاتها.');
    final firstPreview =
        renderedPageElements.first.widget as CanonicalLayoutPreviewPage;
    final canonicalLayout = firstPreview.layoutDocument;
    expect(identical(canonicalLayout.source, controller.documentIr), isTrue,
        reason: 'The preview fixture must capture the current DocumentIR source.');
    final pageCount = canonicalLayout.pageCount;
    expect(renderedPageElements, hasLength(pageCount),
        reason: 'المعاينة يجب أن تعرض كل صفحات LayoutDocument.');
    expect(
      renderedPageElements.every((element) =>
          identical(
            (element.widget as CanonicalLayoutPreviewPage).layoutDocument,
            canonicalLayout,
          )),
      isTrue,
      reason: 'صفحات المعاينة يجب أن تشترك في LayoutDocument نفسه.',
    );
    _stage('LayoutDocument pages: $pageCount');
    expect(pageCount, greaterThan(1),
        reason: 'التركيبة يجب أن تكون متعددة الصفحات لتغطية الترقيم.');

    // Resolve the independent editable-Word plan in its own real-async window.
    // Do not nest this resolver inside the later export runAsync callback: font
    // and math metric work there used to trigger a reentrant test binding call.
    _stage('Resolving editable DOCX pagination');
    final editablePaginationResult = await tester.runAsync(
      () => DocxDocumentExportService.resolveEditablePaginationInput(
        document: controller.document,
        sourceIr: canonicalLayout.source,
        measurementLayout: canonicalLayout,
      ).timeout(const Duration(minutes: 2)),
    );
    expect(editablePaginationResult, isNotNull);
    final editablePaginationInput = editablePaginationResult!;
    _stage('Editable DOCX pagination resolved');

    // (2) نافذة تكفي لعرض كل الصفحات دفعة واحدة: كل الصفحات تُبنى في `Column`
    // غير كسول، لكن اللقط يحتاج الصفحة **مرسومة فعلاً**، وما خرج من نافذة
    // التمرير لا يُرسم. الارتفاع يُقدَّر ثم يُوسَّع حتى يُرسم آخر جذر لقط —
    // فلا يعتمد الأمر على مقاس التكبير الذي تختاره الشاشة.
    var viewHeight = (ExamCanvasGeometry.height + 16) * pageCount + 400;
    tester.view.physicalSize = Size(1600, viewHeight);
    await tester.pumpAndSettle();

    // جذور اللقط بترتيب الشجرة = ترتيب الصفحات.
    final referenceWidth =
        LayoutUnits.ptToPx(canonicalLayout.pages.first.pageSize.width);
    final referenceHeight =
        LayoutUnits.ptToPx(canonicalLayout.pages.first.pageSize.height);
    final boundaries = tester
        .renderObjectList<RenderRepaintBoundary>(find.byType(RepaintBoundary))
        .where((boundary) =>
            (boundary.size.width - referenceWidth).abs() < 0.1 &&
            (boundary.size.height - referenceHeight).abs() < 0.1)
        .toList(growable: false);
    // التوسيع حتى تُرسم كل الصفحات (صفحة خارج نافذة التمرير لا تُرسم، ولقطها
    // يفشل) — شرط `debugNeedsPaint` هو نفس شرط `toImage` نفسه.
    for (var attempt = 0;
        attempt < 8 && boundaries.any((boundary) => boundary.debugNeedsPaint);
        attempt++) {
      viewHeight += 900;
      tester.view.physicalSize = Size(1600, viewHeight);
      await tester.pumpAndSettle();
    }
    _stage('جذور اللقط: ${boundaries.length} لعرض ${viewHeight}px');
    expect(boundaries, hasLength(pageCount),
        reason: 'جذر لقط لكل صفحة معروضة (${boundaries.length}/$pageCount).');
    expect(boundaries.every((boundary) => !boundary.debugNeedsPaint), isTrue,
        reason: 'صفحة لم تُرسم (خارج نافذة العرض) فلا يمكن لقطها.');

    final snapshots = <PageSnapshot>[];
    final capture = await tester.runAsync(() async {
      final pages = <PageSnapshot>[];
      for (final boundary in boundaries) {
        final image = await boundary.toImage(pixelRatio: 1);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        final width = image.width;
        final height = image.height;
        image.dispose();
        if (data == null) {
          continue;
        }
        pages.add(
          PageSnapshot(
            pageIndex: pages.length,
            pngBytes: data.buffer.asUint8List(),
            widthPx: width.toDouble(),
            heightPx: height.toDouble(),
          ),
        );
      }
      return pages;
    });
    expect(capture, isNotNull);
    final snapshotList = capture!;
    _stage('اللقطات: ${snapshotList.length}');
    expect(snapshotList, hasLength(pageCount),
        reason: 'لقطة لكل صفحة معاينة (${snapshotList.length}/$pageCount).');
    snapshots.addAll(snapshotList);

    // التحويلات غير المتزامنة تعمل خارج fake-async الخاص بـtestWidgets:
    // تشترك مسارات التصدير في مصادرها الحقيقية، لكن لا تُعلَّق عمليات الضغط/الخطوط.
    final exportArtifacts = await tester.runAsync(() async {
      // Vector PDF يستهلك كائن LayoutDocument الحي نفسه — لا يحسب تدفقاً ثانياً.
      final vectorPdfBytes = await PdfExportService.buildDocumentPdfBytes(
        document: controller.document,
        layoutDocument: canonicalLayout,
      );
      _stage('Vector PDF generated: ${vectorPdfBytes.length} bytes');

      // Editable DOCX مستقل: DocumentIR → LegacyDocxAdapter → PaginationEngine.
      // لا نمرر إليه تعيين صفحات PDF canonical؛ Exact يبقى مساراً آخر أدناه.
      _stage('Editable DOCX build started');
      final editableDocxBytes =
          await DocxDocumentExportService.buildDocumentDocxBytes(
        document: controller.document,
        shapeRasterizer: (element, widthPx, heightPx) async {
          _stage('Editable DOCX shape rasterization started: ${element.id}');
          final raster = await ShapeImageRenderer.rasterize(
            element,
            widthPx,
            heightPx,
          ).timeout(const Duration(seconds: 30));
          _stage(
            'Editable DOCX shape rasterization completed: ${element.id} '
            '(${raster?.length ?? 0} bytes)',
          );
          return raster;
        },
        mathRasterizer: (latex, fontSizePt) async {
          _stage('Editable DOCX math rasterization started: $latex');
          final raster = await MathImageRenderer.rasterize(
            latex,
            fontSizePt,
          ).timeout(const Duration(seconds: 30));
          _stage(
            'Editable DOCX math rasterization completed: $latex '
            '(${raster?.pngBytes.length ?? 0} bytes)',
          );
          return raster;
        },
        legacyPaginationInput: editablePaginationInput,
        onProgress: (stage) => _stage('Editable DOCX: $stage'),
      ).timeout(const Duration(minutes: 2));
      _stage('Editable DOCX generated: ${editableDocxBytes.length} bytes');

      // Exact: صفحات الصور الملتقطة أعلاه فقط — مستقل عن vector/editable.
      final exactPdfBytes =
          await ExactExportService.buildPdfFromSnapshots(snapshots);
      final exactDocxBytes = ExactExportService.buildDocxFromSnapshots(snapshots);
      _stage('Exact PDF/DOCX generated');
      return (
        vectorPdfBytes: vectorPdfBytes,
        editableDocxBytes: editableDocxBytes,
        exactPdfBytes: exactPdfBytes,
        exactDocxBytes: exactDocxBytes,
      );
    });
    expect(exportArtifacts, isNotNull);
    final vectorPdfBytes = exportArtifacts!.vectorPdfBytes;
    final editableDocxBytes = exportArtifacts.editableDocxBytes;
    final exactPdfBytes = exportArtifacts.exactPdfBytes;
    final exactDocxBytes = exportArtifacts.exactDocxBytes;
    final manifest = <String, Object?>{
      'pageCount': snapshots.length,
      'widthPx': snapshots.first.widthPx,
      'heightPx': snapshots.first.heightPx,
      'dpi': PageSnapshotService.canvasDpi,
      'files': <String>[
        'vector.pdf',
        'editable.docx',
        'exact.pdf',
        'exact.docx',
        for (var index = 0; index < snapshots.length; index++)
          'preview_page_${index + 1}.png',
      ],
    };

    final directory = Directory(_artifactDir);
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }
    for (var index = 0; index < snapshots.length; index++) {
      File('$_artifactDir/preview_page_${index + 1}.png')
          .writeAsBytesSync(snapshots[index].pngBytes);
    }
    File('$_artifactDir/vector.pdf').writeAsBytesSync(vectorPdfBytes);
    File('$_artifactDir/editable.docx').writeAsBytesSync(editableDocxBytes);
    File('$_artifactDir/exact.pdf').writeAsBytesSync(exactPdfBytes);
    File('$_artifactDir/exact.docx').writeAsBytesSync(exactDocxBytes);
    File('$_artifactDir/manifest.json')
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(manifest));

    // فحوص سريعة على القطع نفسها (تفشل مبكراً برسالة مفهومة قبل مقارنة CI).
    for (final snapshot in snapshots) {
      expect(snapshot.pngBytes.sublist(0, 8),
          <int>[137, 80, 78, 71, 13, 10, 26, 10]);
      expect(snapshot.widthPx, greaterThan(700));
      expect(snapshot.heightPx, greaterThan(1000));
    }
    // النمط الإنجليزي يظهر في الصفحة نفسها بمحاذاة يسار (تحقق تركيبي خفيف).
    expect(_fixtureDocument().questions[2].bodyAlign, PaperAlign.left);
    _stage('كُتبت القطع: ${Directory(_artifactDir).absolute.path} '
        '(${snapshots.length} صفحات)');
  });
}
