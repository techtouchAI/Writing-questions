// =============================================================================
// NBSP (U+00A0) في المحرك القانوني — قياس، وكسر أسطر، وتوزيع صفحات.
//
// المطلوب ليس «الزوج يبدو ملتصقاً» بل إثبات ثلاث خصائص على نفس المصدر الذي
// يقرأه Preview وPDF:
//   1. القياس: للفراغ غير الفاصل تقدّم مقيس من الخط، والزوج يُقاس وحدةً واحدة.
//   2. كسر الأسطر: عازل الأسطر لا يكسر الزوج عند أي عرض — ينزلق كاملاً، بينما
//      الفراغ العادي عند العرض نفسه يكسر الزوج: المقارنة هي الدليل.
//   3. توزيع الصفحات: تقسيم الصفحات يقصّ على حدود الأسطر لا داخل السطر، فلا
//      يُفصل الزوج بين صفحتين ولو وقع حدّ الصفحة في منطقه.
//
// الحكم على `LayoutDocument` نفسه (لا صورة ولا نصّ مُستخرَج)، وكل النصوص هنا
// من الاختبار لا من ركيزة منتج.
//
// الحِمل: خطوط التطبيق تُحمَّل مرة واحدة في `setUpAll` قبل الاختبارات (النمط
// نفسه المستعمل في test/pdf_engine/arabic_word_spacing_test.dart)، فلا يحملها
// كل اختبار داخل جسمه؛ والمهل صريحة لأن كل اختبار يقيس مسحاً كاملاً.
// =============================================================================
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/layout/blueprint/exam_blueprint.dart';
import 'package:writing_questions_app/layout/canonical/exam_document_layout_adapter.dart';
import 'package:writing_questions_app/layout/canonical/flutter_text_metrics.dart';
import 'package:writing_questions_app/layout/canonical/font_metrics.dart';
import 'package:writing_questions_app/layout/canonical/layout_document.dart';
import 'package:writing_questions_app/layout/canonical/layout_engine.dart';
import 'package:writing_questions_app/layout/canonical/layout_units.dart';
import 'package:writing_questions_app/layout/document_direction.dart';
import 'package:writing_questions_app/layout/document_ir.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/paper_font.dart';
import 'package:writing_questions_app/models/paper_settings.dart';
import 'package:writing_questions_app/models/paper_text_style.dart';
import 'package:writing_questions_app/models/question_model.dart';

const String _nbsp = '\u00A0';

/// كلمات عربية بلا أرقام: لا يمسّها أي تطبيع أرقام في أي ممرّ.
const String _first = 'زينب';
const String _second = 'خالد';

/// اثنا عشر زوجاً بكلمات **فريدة**: كل كلمة تظهر مرة واحدة في المتن، فيصحّ
/// قياس «الكلمة على أي صفحة» و«الزوج لم ينقسم» بلا لبس مع تكرار.
const List<List<String>> _pairs = <List<String>>[
  <String>['أحمد', 'بكر'],
  <String>['سعيد', 'جميل'],
  <String>['ليلى', 'هناد'],
  <String>['مريم', 'وليد'],
  <String>['يوسف', 'كريم'],
  <String>['هدى', 'سليم'],
  <String>['عمر', 'رشيد'],
  <String>['نورة', 'فهد'],
  <String>['خديجة', 'ماجد'],
  <String>['طارق', 'نجيب'],
  <String>['سلمى', 'أمين'],
  <String>['زيد', 'نبيل'],
];

const LayoutTextStyle _style = LayoutTextStyle(
  font: PaperFont.naskh,
  fontSizePt: 12,
  lineHeightFactor: 1.45,
);

/// المهل صريحة كي يفشل الاختبار برسالة تقول «تجاوز المدة» لا أن يُبتلع في
/// مهلة المنصة الافتراضية؛ والحساب نفسه لا يعتمد عليها.
const Timeout _budget = Timeout(Duration(minutes: 3));

/// وحدة تعبئة بلا فراغ زائد في الطرفين.
String _filler([int repeat = 1]) =>
    List<String>.filled(repeat, 'نصٌّ عربي طويل للتغطية والقياس').join(' ');

MetricSpan _span(String id, String text) => MetricSpan(
      semanticNodeId: id,
      semanticNode: null,
      text: text,
      contentKind: LayoutContentKind.text,
      semanticRole: LayoutSemanticRole.text,
      style: _style,
      direction: DocumentDirection.rtl,
      logicalIndex: 0,
    );

/// نص السطر كما قِيس: شرائح المنبع بترتيبها المرئي (نصّها نصُّ المنبع).
String _lineText(MeasuredLine line) =>
    line.fragments.map((fragment) => fragment.text).join();

String _pageText(LayoutPage page) => <String>[
      for (final block in page.blocks)
        for (final line in block.allLines)
          for (final run in line.runs) run.text,
    ].join(' ');

ExamDocument _document(String body) => ExamDocument(
      name: 'ركيزة NBSP',
      header: ExamHeaderModel(subject: 'اللغة العربية'),
      settings: const PaperSettings(
        marginMm: 15,
        defaultFont: PaperFont.naskh,
        baseFontSize: 12,
        lineSpacing: 1.45,
        numerals: PaperNumerals.latin,
        showQuestionMarks: false,
        autoNumberQuestions: true,
      ),
      questions: <QuestionModel>[
        QuestionModel(
          id: 'nbsp-q1',
          questionNumber: 1,
          statement: 'اقرأ ثم أجب',
          body: body,
        ),
      ],
    );

LayoutDocument _layout(ExamDocument document, double pageHeightPt) {
  final blueprint = ExamBlueprint.from(document);
  final ir = DocumentIR.fromBlueprint(blueprint: blueprint, document: document);
  final configuration = ExamDocumentLayoutAdapter.configurationFor(
    document,
    pageSize: LayoutSize(
      width: LayoutUnits.a4.width,
      height: pageHeightPt,
    ),
  );
  return const LayoutEngine().layout(
    document: ir,
    configuration: configuration,
    fontMetrics: const FlutterTextMetrics(),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await FlutterTextMetrics.ensureFontsLoaded();
  });

  test(
    'P2-NBSP-01: قياس الفراغ غير الفاصل، والزوج وحدةٌ واحدة، والضبط لا يوسّعه',
    () async {
      const metrics = FlutterTextMetrics();

      final space = metrics.whitespaceAdvance(_style, DocumentDirection.rtl);
      final nonBreaking = metrics.whitespaceAdvance(
        _style,
        DocumentDirection.rtl,
        nonBreaking: true,
      );
      expect(space, greaterThan(0));
      expect(nonBreaking, greaterThan(0),
          reason: 'لا تقدّم مقيس لـNBSP: صار صفراً فينلتصق الزوج بلا هندسة، '
              'وتُكسر «وحدة الكلمتين» لاحقاً بلا قياس.');
      expect(nonBreaking, lessThan(space * 2),
          reason: 'تقدّم NBSP=$nonBreaking يقارب ضعف تقدّم الفراغ العادي '
              '$space: ليس وحدة الفراغ نفسها.');

      final first = metrics
          .measureText(_first, _style, DocumentDirection.rtl)
          .advance;
      final second = metrics
          .measureText(_second, _style, DocumentDirection.rtl)
          .advance;
      final pair = '$_first$_nbsp$_second';
      final pairAdvance =
          metrics.measureText(pair, _style, DocumentDirection.rtl).advance;
      expect(pairAdvance, greaterThanOrEqualTo(first + second),
          reason: 'قياس الزوج $pairAdvance أصغر من مجموع الكلمتين '
              '${first + second}: كلمةٌ ضاعت في القياس.');
      expect(pairAdvance, lessThanOrEqualTo(first + second + nonBreaking + 1),
          reason: 'قياس الزوج $pairAdvance يتجاوز الكلمتين + وحدة NBSP '
              '${first + second + nonBreaking} بأكثر من نقطة: فراغٌ مضاعف '
              'أو تقدّم مُختَرع.');

      // مسح عروض مع الضبط: أول سطر مضبوط لا يجوز أن يعدّ NBSP فرصة توسيع،
      // ولا أن يوسّع شريحة الزوج (توسيع فجوة داخل زوج = كسر دلالي).
      final text = '$pair ${_filler(4)}';
      final natural =
          metrics.measureText(text, _style, DocumentDirection.rtl).advance;
      var justifiedLines = 0;
      for (var step = 0; step <= 20; step++) {
        final width = natural * (0.45 + step * 0.03);
        final paragraph = metrics.layoutParagraph(
          spans: <MetricSpan>[_span('nbsp-justify', text)],
          width: width,
          direction: DocumentDirection.rtl,
          alignment: PaperAlign.justify,
          resolveJustification: true,
        );
        final line = paragraph.lines.first;
        if (!line.isJustified) continue;
        justifiedLines++;
        final lineText = _lineText(line);
        final ordinarySpaces = ' '.allMatches(lineText).length;
        expect(line.justificationOpportunityCount, ordinarySpaces,
            reason: 'عند عرض $width: فرص الضبط='
                '${line.justificationOpportunityCount} وفراغات السطر '
                'العادية=$ordinarySpaces — NBSP عُدَّت فرصة توسيع.');
        expect(line.extraSpacePerOpportunity, greaterThan(0));
        final pairFragment = line.fragments.firstWhere(
          (fragment) =>
              fragment.text.contains(_first) &&
              fragment.text.contains(_second),
          orElse: () =>
              throw StateError('عرض $width: شريحة الزوج غير موجودة في السطر '
                  '«$lineText».'),
        );
        expect(pairFragment.text.contains(pair), isTrue,
            reason: 'عرض $width: شريحة الزوج «${pairFragment.text}» لا تحمل '
                'الزوج متصلاً بـNBSP.');
        expect(pairFragment.width, closeTo(pairAdvance, 1),
            reason: 'عرض $width: عرض شريحة الزوج=${pairFragment.width} '
                'وتقدّم الزوج المقيس=$pairAdvance — الضبط وسّع داخل الزوج.');
      }
      expect(justifiedLines, greaterThan(0),
          reason: 'لم يتحقق سطر مضبوط في أي عرض ممسوح: الفحص لم يقس الضبط.');
      debugPrint('::notice title=P2-NBSP-01::space='
          '${space.toStringAsFixed(3)} nbsp=${nonBreaking.toStringAsFixed(3)} '
          'pair=${pairAdvance.toStringAsFixed(3)} '
          'sum=${(first + second).toStringAsFixed(3)} '
          'justifiedLines=$justifiedLines/21');
    },
    timeout: _budget,
  );

  test(
    'P2-NBSP-02: NBSP يمنع كسر الزوج حيث يكسره الفراغ العادي',
    () async {
      const metrics = FlutterTextMetrics();

      final firstAdvance = metrics
          .measureText(_first, _style, DocumentDirection.rtl)
          .advance;
      final secondAdvance = metrics
          .measureText(_second, _style, DocumentDirection.rtl)
          .advance;
      final nbspAdvance = metrics.whitespaceAdvance(
        _style,
        DocumentDirection.rtl,
        nonBreaking: true,
      );
      final prefix = '${_filler(2)} ';
      final prefixAdvance =
          metrics.measureText(prefix, _style, DocumentDirection.rtl).advance;
      final pairAdvance = firstAdvance + nbspAdvance + secondAdvance;

      MeasuredParagraph layout(String text, double width) =>
          metrics.layoutParagraph(
            spans: <MetricSpan>[_span('nbsp-body', text)],
            width: width,
            direction: DocumentDirection.rtl,
            alignment: PaperAlign.right,
            resolveJustification: false,
          );

      var spaceSplitWidths = 0;
      var nbspMovedAsUnit = 0;
      final nbspLineCounts = <int>{};
      for (var step = 0; step <= 12; step++) {
        final width = prefixAdvance + pairAdvance * (0.55 + step * 0.05);
        final spaceLines = layout('$prefix$_first $_second', width)
            .lines
            .map(_lineText)
            .toList(growable: false);
        final nbspLines = layout('$prefix$_first$_nbsp$_second', width)
            .lines
            .map(_lineText)
            .toList(growable: false);

        // (1) الفراغ العادي يكسر عند هذا العرض: الكلمتان في سطرين.
        final spaceSplit = spaceLines.any((line) =>
                line.contains(_first) && !line.contains(_second)) &&
            spaceLines.any((line) =>
                line.contains(_second) && !line.contains(_first));
        if (spaceSplit) spaceSplitWidths++;

        // (2) عند العرض نفسه لا يُكسر الزوج بالـNBSP، ولا يقف NBSP في طرف سطر.
        for (final line in nbspLines) {
          final hasFirst = line.contains(_first);
          final hasSecond = line.contains(_second);
          expect(hasFirst, hasSecond,
              reason: 'كُسر الزوج عند عرض $width (فراغ عادي كُسر هنا: '
                  '$spaceSplit): السطر «$line» يحمل '
                  '${hasFirst ? _first : _second} وحده.');
          expect(line.startsWith(_nbsp), isFalse,
              reason: 'بدأ سطر بـNBSP عند عرض $width (كسر قبل الزوج): «$line»');
          expect(line.endsWith(_nbsp), isFalse,
              reason: 'انتهى سطر بـNBSP عند عرض $width (كسر بعد الزوج): «$line»');
        }
        final carried = nbspLines.indexWhere(
            (line) => line.contains(_first) && line.contains(_second));
        expect(carried, isNonNegative,
            reason: 'الزوج غير موجود في أي سطر عند عرض $width: '
                '${nbspLines.toList()}');
        if (carried > 0) nbspMovedAsUnit++;
        nbspLineCounts.add(nbspLines.length);
      }
      expect(spaceSplitWidths, greaterThan(0),
          reason: 'لم يكسر الفراغ العادي الزوج في أي عرض ممسوح: المسح لا يمرّ '
              'على نقطة الكسر، فلا يقيس فرق NBSP.');
      expect(nbspMovedAsUnit, greaterThan(0),
          reason: 'لم ينتقل الزوج كوحدة إلى سطر تالٍ في أي عرض: المسح لا '
              'يمرّ على الحافة التي يلزم فيها الانزلاق.');
      debugPrint('::notice title=P2-NBSP-02::widths=13 '
          'spaceSplitWidths=$spaceSplitWidths nbspMovedAsUnit=$nbspMovedAsUnit '
          'nbspLineCounts=${nbspLineCounts.toList()..sort()}');
    },
    timeout: _budget,
  );

  test(
    'P2-NBSP-03: حدّ الصفحة لا يفصل الزوج، والسؤال يُقسَّم فعلاً',
    () async {
      // متن طويل بقياس صريح: أطول صفحة ممسوحة 520pt، وهوامش 15مم. كل زوج
      // بكلمات فريدة، فيُقاس مالك الصفحة لكل كلمة بلا تكرار.
      final body = <String>[
        for (var group = 0; group < _pairs.length; group++) ...<String>[
          _filler(20),
          '${_pairs[group][0]}$_nbsp${_pairs[group][1]}',
        ],
        _filler(20),
      ].join(' ');
      final document = _document(body);

      const heights = <double>[240, 320, 420, 520];
      final pagesByHeight = <double, int>{};
      var anySplitQuestion = false;
      for (final height in heights) {
        final layout = _layout(document, height);
        pagesByHeight[height] = layout.pageCount;
        expect(layout.pageCount, greaterThan(1),
            reason: 'ارتفاع الصفحة $height لم يُنتج أكثر من صفحة: التقسيم '
                'غير مقيس.');
        final splitQuestion = layout.allBlocks.any((block) =>
            block.kind == LayoutBlockKind.question && block.split.isSplit);
        anySplitQuestion = anySplitQuestion || splitQuestion;
        expect(splitQuestion, isTrue,
            reason: 'ارتفاع $height: السؤال لم يُقسَّم في أي صفحة، فحدّ '
                'الصفحة لم يلمس المتن ولا يقيس الاختبار واقع التقسيم.');
        final pageTexts = <int, String>{
          for (final page in layout.pages) page.index: _pageText(page),
        };
        for (final words in _pairs) {
          final firstPages = <int>[
            for (final entry in pageTexts.entries)
              if (entry.value.contains(words[0])) entry.key,
          ];
          final secondPages = <int>[
            for (final entry in pageTexts.entries)
              if (entry.value.contains(words[1])) entry.key,
          ];
          expect(firstPages, hasLength(1),
              reason: '«${words[0]}» ظهر على صفحات $firstPages عند ارتفاع '
                  '$height: التقسيم كرّر النصّ أو أضاعه.');
          expect(secondPages, hasLength(1),
              reason: '«${words[1]}» ظهر على صفحات $secondPages عند ارتفاع '
                  '$height: التقسيم كرّر النصّ أو أضاعه.');
          expect(firstPages.single, secondPages.single,
              reason: 'انقسم الزوج «${words[0]}$_nbsp${words[1]}» بين '
                  'صفحتين عند ارتفاع $height: ${words[0]} في '
                  'ص${firstPages.single} و${words[1]} في '
                  'ص${secondPages.single}.');
        }
      }
      expect(anySplitQuestion, isTrue,
          reason: 'لا سؤال مُقسَّم في أي ارتفاع ممسوح.');
      final heightsText = heights
          .map((height) => '${height.toInt()}pt→${pagesByHeight[height]}ص')
          .join(' ');
      debugPrint('::notice title=P2-NBSP-03::$heightsText '
          'splitQuestion=$anySplitQuestion pairs=${_pairs.length}');
    },
    timeout: _budget,
  );
}
