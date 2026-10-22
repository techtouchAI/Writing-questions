// تنسيق النقاط والخيارات: هل يخصّ التحديد نفسه فقط؟
//
// السؤال الذي يجيب عنه هذا الملف: حين يلوّن المدرس كلمةً داخل نقطة أو خيار،
// هل يتغيّر شيء آخر في المستند؟ المسار واحد مع السؤال والفرع (نطاقات
// `TextFormatSpan` مخزَّنة على العنصر نفسه، لا حالة عرض مؤقتة)، وهذا الملف
// يقيس ثلاث حلقات منه:
//
//   1. النموذج: النطاقات تبقى بعد الحفظ/التحميل، وتحرير النص يزيحها ولا يمدّها.
//   2. المتحكّم: تنسيق نقطة/خيار لا يمسّ النقاط الأخرى ولا الخيارات الأخرى
//      ولا حقول السؤال، وتغييره يُسجّل خطوة تراجع فعلية لا خطوة فارغة.
//   3. التخطيط وPDF: الكلمة المنسَّقة وحدها تحمل النمط (وتُطبع بالخط العريض
//      وحده في ملف PDF)، وليست النقطة كلها ولا الخيارات الأخرى.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/layout/blueprint/exam_blueprint.dart';
import 'package:writing_questions_app/layout/canonical/exam_document_layout_adapter.dart';
import 'package:writing_questions_app/layout/canonical/flutter_text_metrics.dart';
import 'package:writing_questions_app/layout/canonical/layout_document.dart';
import 'package:writing_questions_app/layout/canonical/layout_engine.dart';
import 'package:writing_questions_app/layout/document_direction.dart';
import 'package:writing_questions_app/layout/document_ir.dart';
import 'package:writing_questions_app/models/branch_item.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/point_kind.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/models/question_option.dart';
import 'package:writing_questions_app/models/text_format_span.dart';
import 'package:writing_questions_app/pdf_engine/exam_fonts.dart';
import 'package:writing_questions_app/pdf_engine/paginated_pdf_exam_engine.dart';
import 'package:writing_questions_app/providers/exam_wizard_controller.dart';

import '../../pdf_engine/pdf_content_probe.dart';

const String _pointText = 'أجب عن السؤال';
const String _otherPointText = 'اشرح الفكرة';
const String _optionText = 'الخيار الأول';
const String _otherOptionText = 'الخيار الثاني';

/// موضع «عن» داخل [_pointText] (٤..٦ بوحدات UTF-16).
const int _onStart = 4;
const int _onEnd = 6;

/// موضع «الأول» داخل [_optionText].
const int _firstStart = 7;
const int _firstEnd = 12;

const int _red = 0xFFCC0000;

ExamDocument _document({
  List<TextFormatSpan> pointFormats = const <TextFormatSpan>[],
  List<TextFormatSpan> optionFormats = const <TextFormatSpan>[],
}) {
  return ExamDocument(
    name: 'تنسيق النقاط والخيارات',
    header: ExamHeaderModel(
      schoolName: 'مدرسة',
      examType: 'نصف السنة',
      academicYear: '2026/2027',
      subject: 'اللغة العربية',
      showBismillah: false,
    ),
    questions: <QuestionModel>[
      QuestionModel(
        id: 'q1',
        questionNumber: 1,
        statement: 'حل الأسئلة التالية',
        marksOverride: 20,
        items: <BranchItem>[
          BranchItem(
            id: 'i1',
            text: _pointText,
            textFormats: pointFormats,
          ),
          BranchItem(id: 'i2', text: _otherPointText),
          BranchItem(
            id: 'i3',
            kind: PointKind.multipleChoice,
            text: 'اختر',
            options: <QuestionOption>[
              QuestionOption(text: _optionText, formats: optionFormats),
              QuestionOption(text: _otherOptionText),
            ],
          ),
        ],
      ),
    ],
  );
}

LayoutDocument _layout(ExamDocument document) {
  final ir = DocumentIR.fromBlueprint(
    blueprint: ExamBlueprint.from(document),
    document: document,
  );
  return const LayoutEngine().layout(
    document: ir,
    configuration: ExamDocumentLayoutAdapter.configurationFor(document),
    fontMetrics: const FlutterTextMetrics(),
  );
}

Iterable<LayoutBlock> _allBlocks(Iterable<LayoutBlock> blocks) sync* {
  for (final block in blocks) {
    yield block;
    yield* _allBlocks(block.children);
  }
}

/// كل جريانات الصفحة التي يبدأ معرّفها الدلالي بـ[prefix].
List<LayoutRun> _runs(LayoutDocument layout, String prefix) => <LayoutRun>[
      for (final page in layout.pages)
        for (final block in _allBlocks(page.blocks))
          for (final line in block.allLines)
            ...line.runs.where(
              (run) => !run.isMath && run.semanticNodeId.startsWith(prefix),
            ),
    ];

String _joined(List<LayoutRun> runs) {
  if (runs.isEmpty) return '';
  final rtl = runs.first.direction == DocumentDirection.rtl;
  final ordered = <LayoutRun>[...runs];
  ordered.sort((a, b) => rtl ? b.x.compareTo(a.x) : a.x.compareTo(b.x));
  return ordered.map((run) => run.text).join().replaceAll('\u00A0', ' ').trim();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await FlutterTextMetrics.ensureFontsLoaded();
  });

  group('النموذج: النطاقات تُحفظ وتُقرأ', () {
    test('نطاقات النقطة تعود كما هي بعد الحفظ والتحميل', () {
      final item = BranchItem(
        id: 'i1',
        text: _pointText,
        textFormats: const <TextFormatSpan>[
          TextFormatSpan(start: _onStart, end: _onEnd, bold: true),
        ],
      );
      final restored = BranchItem.fromMap(item.toMap());
      expect(restored.text, _pointText);
      expect(restored.textFormats, item.textFormats);
      expect(restored.sameContentAs(item), isTrue);
    });

    test('نطاقات الخيار تعود كما هي بعد الحفظ والتحميل', () {
      final option = QuestionOption(
        text: _optionText,
        formats: const <TextFormatSpan>[
          TextFormatSpan(start: _firstStart, end: _firstEnd, color: _red),
        ],
      );
      final restored = QuestionOption.fromMap(option.toMap());
      expect(restored.text, _optionText);
      expect(restored.formats, option.formats);
    });

    test('نقطتان بنصّ واحد وتنسيق مختلف ليستا متطابقتين', () {
      // وإلا عُدّ تغيير التنسيق «لا تغيير» فلم يُسجَّل في التراجع.
      final plain = BranchItem(id: 'i1', text: _pointText);
      final bold = BranchItem(
        id: 'i1',
        text: _pointText,
        textFormats: const <TextFormatSpan>[
          TextFormatSpan(start: _onStart, end: _onEnd, bold: true),
        ],
      );
      expect(plain.sameContentAs(bold), isFalse);
      expect(bold.sameContentAs(plain), isFalse);
    });

    test('أي مسار تحرير للنص في النموذج يُعيد تأسيس الإزاحات', () {
      // القاعدة في `copyWith` نفسه لا في متحكّم واحد: محرر النقاط في شاشة
      // التحرير يكتب النص بـ`copyWith(text:)` مباشرةً، فلو كانت الإعادة في
      // مسار المعاينة وحده لفسدت النطاقات من هناك.
      final item = BranchItem(
        id: 'i1',
        text: _pointText,
        textFormats: const <TextFormatSpan>[
          TextFormatSpan(start: _onStart, end: _onEnd, bold: true),
        ],
      );
      final shifted = item.copyWith(text: 'من فضلك $_pointText');
      final span = shifted.textFormats.single;
      expect(shifted.text.substring(span.start, span.end), 'عن');
      // والحذف يعيد الإزاحة إلى موضعها.
      final restored = shifted.copyWith(text: _pointText);
      final back = restored.textFormats.single;
      expect(restored.text.substring(back.start, back.end), 'عن');

      final option = QuestionOption(
        text: _optionText,
        formats: const <TextFormatSpan>[
          TextFormatSpan(start: _firstStart, end: _firstEnd, color: _red),
        ],
      );
      final edited = option.copyWith(text: '$_optionText جدًا');
      final optionSpan = edited.formats.single;
      expect(edited.text.substring(optionSpan.start, optionSpan.end), 'الأول');

      // نصّ قصير: النطاق يُقصّ على الطول الجديد ولا يتجاوزه.
      final truncated = option.copyWith(text: 'الخيار');
      expect(
        truncated.formats.every((s) => s.end <= truncated.text.length),
        isTrue,
        reason: 'نطاق يتجاوز طول النص بعد التحرير: ${truncated.formats}',
      );
    });

    test('النسخ المتكرّر يحمل نطاقات النقطة والخيار', () {
      final item = BranchItem(
        text: _pointText,
        textFormats: const <TextFormatSpan>[
          TextFormatSpan(start: _onStart, end: _onEnd, bold: true),
        ],
        kind: PointKind.multipleChoice,
        options: <QuestionOption>[
          QuestionOption(
            text: _optionText,
            formats: const <TextFormatSpan>[
              TextFormatSpan(start: _firstStart, end: _firstEnd, color: _red),
            ],
          ),
        ],
      );
      final copy = item.duplicated();
      expect(copy.textFormats, item.textFormats);
      expect(copy.options.single.formats, item.options.single.formats);
    });
  });

  group('المتحكّم: التنسيق على العنصر المحدَّد وحده', () {
    const owner = PointsOwner.question(0);

    ExamWizardController controllerWithPoints() {
      final controller = ExamWizardController();
      controller.setPoints(owner, <BranchItem>[
        BranchItem(id: 'i1', text: _pointText),
        BranchItem(id: 'i2', text: _otherPointText),
        BranchItem(
          id: 'i3',
          kind: PointKind.multipleChoice,
          text: 'اختر',
          options: <QuestionOption>[
            QuestionOption(text: _optionText),
            QuestionOption(text: _otherOptionText),
          ],
        ),
      ]);
      return controller;
    }

    test('تنسيق نصّ نقطة لا يمسّ النقاط الأخرى ولا حقول السؤال', () {
      final controller = controllerWithPoints();
      final before = controller.questions.single;
      controller.updatePointTextFormats(owner, 'i1', const <TextFormatSpan>[
        TextFormatSpan(start: _onStart, end: _onEnd, bold: true),
      ]);

      final points = controller.questions.single.items;
      expect(points[0].textFormats, hasLength(1));
      expect(points[0].textFormats.single.start, _onStart);
      expect(points[1].textFormats, isEmpty,
          reason: 'تنسيق نقطة تسرّب إلى النقطة التالية.');
      expect(points[2].textFormats, isEmpty);
      expect(points[2].options[0].formats, isEmpty,
          reason: 'تنسيق نصّ النقطة تسرّب إلى خياراتها.');
      expect(controller.questions.single.statementFormats, isEmpty);
      expect(controller.questions.single.bodyFormats, isEmpty);
      expect(before.statement, controller.questions.single.statement);
    });

    test('تنسيق خيار لا يمسّ الخيار الآخر ولا نصّ النقطة', () {
      final controller = controllerWithPoints();
      controller.updatePointOptionFormats(owner, 'i3', 0,
          const <TextFormatSpan>[
        TextFormatSpan(start: _firstStart, end: _firstEnd, color: _red),
      ]);

      final point = controller.questions.single.items[2];
      expect(point.options[0].formats, hasLength(1));
      expect(point.options[0].formats.single.color, _red);
      expect(point.options[1].formats, isEmpty,
          reason: 'تنسيق خيار تسرّب إلى الخيار التالي.');
      expect(point.textFormats, isEmpty,
          reason: 'تنسيق خيار تسرّب إلى نصّ النقطة.');
      expect(controller.questions.single.items[0].textFormats, isEmpty);
    });

    test('تغيير التنسيق خطوة تراجع واحدة، وتكراره بلا خطوة', () {
      final controller = controllerWithPoints();
      final steps = controller.canUndo;
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.updatePointTextFormats(owner, 'i1', const <TextFormatSpan>[
        TextFormatSpan(start: _onStart, end: _onEnd, bold: true),
      ]);
      final afterFirst = notifications;
      expect(afterFirst, greaterThan(0));

      // نفس التنسيق مرة ثانية: لا حالة جديدة ولا إشعار.
      controller.updatePointTextFormats(owner, 'i1', const <TextFormatSpan>[
        TextFormatSpan(start: _onStart, end: _onEnd, bold: true),
      ]);
      expect(notifications, afterFirst,
          reason: 'إعادة تطبيق التنسيق نفسه أنتجت خطوة/بناءً جديدًا.');

      controller.undo();
      expect(controller.questions.single.items[0].textFormats, isEmpty,
          reason: 'التراجع لم يُعِد التنسيق (steps before=$steps).');
    });

    test('تحرير نصّ النقطة يزيح النطاق ولا يمدّه على النصّ الجديد', () {
      final controller = controllerWithPoints();
      controller.updatePointTextFormats(owner, 'i1', const <TextFormatSpan>[
        TextFormatSpan(start: _onStart, end: _onEnd, bold: true),
      ]);
      // إدخال كلمة في البداية: النطاق يُزاح بمقدارها ويبقى على «عن».
      controller.updatePointText(owner, 'i1', 'من فضلك $_pointText');
      final shifted = controller.questions.single.items[0].textFormats.single;
      expect('من فضلك $_pointText'.substring(shifted.start, shifted.end), 'عن');
      // حذف الكلمة نفسها: يعود النطاق إلى موضعه الأول.
      controller.updatePointText(owner, 'i1', _pointText);
      final back = controller.questions.single.items[0].textFormats.single;
      expect(_pointText.substring(back.start, back.end), 'عن');
    });

    test('تحرير نصّ الخيار يزيح نطاقه ولا يمسّ الخيار الآخر', () {
      final controller = controllerWithPoints();
      controller.updatePointOptionFormats(owner, 'i3', 0,
          const <TextFormatSpan>[
        TextFormatSpan(start: _firstStart, end: _firstEnd, color: _red),
      ]);
      controller.updatePointOptionText(owner, 'i3', 0, '$_optionText جدًا');
      final option = controller.questions.single.items[2].options[0];
      expect(option.text, '$_optionText جدًا');
      expect(
        option.text.substring(
            option.formats.single.start, option.formats.single.end),
        'الأول',
      );
      expect(controller.questions.single.items[2].options[1].formats, isEmpty);
    });
  });

  group('التخطيط: النمط على الكلمة المحدَّدة وحدها', () {
    test('تعريض كلمة في نقطة يصل إلى جريان واحد فيها', () {
      final layout = _layout(_document(
        pointFormats: const <TextFormatSpan>[
          TextFormatSpan(start: _onStart, end: _onEnd, bold: true),
        ],
      ));
      final runs = _runs(layout, 'i1/content');
      expect(_joined(runs), _pointText,
          reason: 'تنسيق النقطة غيّر النصّ المرسوم: ${_joined(runs)}');
      final bold = runs.where((run) => run.style.bold == true).toList();
      expect(bold, hasLength(1),
          reason: 'التعريض أصاب ${bold.length} جريانًا بدل واحد: '
              '${runs.map((run) => '"${run.text}" bold=${run.style.bold}').toList()}');
      expect(bold.single.text.trim(), 'عن');

      // النقطة الأخرى بقيت بلا تعريض.
      final other = _runs(layout, 'i2/content');
      expect(other, isNotEmpty);
      for (final run in other) {
        expect(run.style.bold, isNot(true),
            reason: 'جريان في النقطة الأخرى أخذ التعريض: "${run.text}"');
      }
    });

    test('لون كلمة في خيار لا يتسرّب إلى الخيار الآخر', () {
      final layout = _layout(_document(
        optionFormats: const <TextFormatSpan>[
          TextFormatSpan(start: _firstStart, end: _firstEnd, color: _red),
        ],
      ));
      final optionRuns = _runs(layout, 'i3/').where((run) => run.semanticNodeId
          .contains('/content')).toList();
      expect(optionRuns, isNotEmpty);
      final colored = optionRuns.where((run) => run.style.colorArgb == _red).toList();
      expect(colored, hasLength(1),
          reason: 'اللون أصاب ${colored.length} جريانًا: '
              '${optionRuns.map((run) => '"${run.text}" ${run.style.colorArgb}').toList()}');
      expect(colored.single.text.trim(), 'الأول');
      for (final run in optionRuns) {
        if (identical(run, colored.single)) continue;
        expect(run.style.colorArgb, isNot(_red),
            reason: 'جريان خيار آخر أخذ اللون: "${run.text}"');
      }
      // ونصّ النقطة والخيار الثاني لم يتغيّرا.
      final optionTexts = optionRuns.map((run) => run.text).join();
      expect(optionTexts, contains('الخيار'));
      expect(optionTexts, contains('الثاني'));
    });
  });

  group('PDF: النمط يصل إلى الملف فعليًا', () {
    late ExamFonts fonts;

    setUpAll(() async {
      fonts = await ExamFonts.load();
    });

    Future<Uint8List> export(ExamDocument document) =>
        PaginatedPdfExamEngine().generate(document: document, fonts: fonts);

    int boldSpans(Uint8List bytes) {
      final probe = PdfContentProbe.fromBytes(bytes, pageIndex: 0);
      return probe.words
          .where((word) => word.baseFont.toUpperCase().contains('BOLD'))
          .length;
    }

    test('تعريض كلمة في نقطة يضيف كلمة عريضة واحدة في PDF', () async {
      final plain = await export(_document());
      final formatted = await export(_document(
        pointFormats: const <TextFormatSpan>[
          TextFormatSpan(start: _onStart, end: _onEnd, bold: true),
        ],
      ));
      expect(boldSpans(formatted) - boldSpans(plain), 1,
          reason: 'التعريض الجزئي في نقطة غيّر عدد الكلمات العريضة بأكثر من '
              'كلمة واحدة.');
    });
  });
}
