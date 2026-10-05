import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/layout/adapters/legacy_docx_adapter.dart';
import 'package:writing_questions_app/layout/adapters/legacy_pdf_adapter.dart';
import 'package:writing_questions_app/layout/blueprint/exam_blueprint.dart';
import 'package:writing_questions_app/layout/document_direction.dart';
import 'package:writing_questions_app/layout/document_ir.dart';
import 'package:writing_questions_app/layout/pagination_engine.dart';
import 'package:writing_questions_app/layout/semantic/inline_nodes.dart';
import 'package:writing_questions_app/models/branch_item.dart';
import 'package:writing_questions_app/models/branch_model.dart';
import 'package:writing_questions_app/models/exam_catalog.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_footer_model.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/floating_element.dart';
import 'package:writing_questions_app/models/point_kind.dart';
import 'package:writing_questions_app/models/paper_settings.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/models/question_option.dart';
import 'package:writing_questions_app/providers/exam_wizard_controller.dart';

String _verse(String text) => '\uFD3F$text\uFD3E';

FloatingElement _shape({
  required String id,
  required FloatingShapeType shape,
  String label = '',
  String? ownerQuestionId,
  double dx = 91,
}) =>
    FloatingElement(
      id: id,
      type: FloatingElementType.shape,
      shape: shape,
      dx: dx,
      dy: 37,
      width: 48,
      height: 24,
      label: label,
      ownerQuestionId: ownerQuestionId,
      rotationDegrees: 13,
    );

ExamDocument _richDocument() {
  final globalFormula = FloatingElement(
    id: 'global-formula',
    type: FloatingElementType.formula,
    dx: 111,
    dy: 222,
    pageIndex: 1,
    width: 70,
    height: 28,
    label: r'\frac{س}{٢}',
  );
  final globalTextBox = _shape(
    id: 'global-text-box',
    shape: FloatingShapeType.textBox,
    label: 'ملاحظة ${_verse('اقرأ ثم أجب')}',
  );
  final questionImage = FloatingElement(
    id: 'question-image',
    type: FloatingElementType.image,
    bytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
    dx: 6,
    dy: 29,
    width: 36,
    height: 24,
    ownerQuestionId: 'q-rtl',
  );
  final branchTextBox = _shape(
    id: 'branch-text-box',
    shape: FloatingShapeType.textBox,
    label: 'تعليق على الفرع',
    ownerQuestionId: 'q-rtl',
  );
  final branchFormula = FloatingElement(
    id: 'branch-formula',
    type: FloatingElementType.formula,
    dx: 8,
    dy: 13,
    width: 52,
    height: 24,
    label: r'x^2+1',
    ownerQuestionId: 'q-rtl',
  );

  final branch = BranchModel(
    id: 'branch-a',
    marks: 3,
    content: BranchContent(
      statement: 'الفرع أ: احسب ${r'$\text{س}+٢$'}',
      body: 'تحقق من ${_verse('الجواب الصحيح')}',
      items: <BranchItem>[
        BranchItem(
          id: 'branch-tf',
          kind: PointKind.trueFalse,
          text: 'القيمة موجبة',
          marks: 1,
        ),
      ],
    ),
    attachments: <FloatingElement>[branchTextBox, branchFormula],
  );

  final question = QuestionModel(
    id: 'q-rtl',
    questionNumber: 1,
    category: 'القراءة والنحو',
    statement: 'اقرأ English، ثم احسب ${r'$\text{س}+٢$'}؛ ما الناتج؟',
    body: 'قارن ${r'$\frac{٢}{٣}$'} مع العدد 1 ثم اقرأ ${_verse('النص القرآني')}.',
    marksOverride: 12,
    items: <BranchItem>[
      BranchItem(
        id: 'tf',
        kind: PointKind.trueFalse,
        text: 'الأرض كروية',
        marks: 2,
      ),
      BranchItem(
        id: 'fill',
        kind: PointKind.fillBlank,
        text: 'أكمل العبارة ${r'$x+1$'}',
      ),
      BranchItem(
        id: 'choice',
        kind: PointKind.multipleChoice,
        text: 'اختر الإجابة الصحيحة',
        marks: 1,
        options: <QuestionOption>[
          QuestionOption(id: 'opt-a', text: '٣'),
          QuestionOption(id: 'opt-blank', text: ''),
          QuestionOption(id: 'opt-c', text: 'أربعة', labelOverride: 'ج!'),
        ],
      ),
      BranchItem(
        id: 'custom-label',
        labelOverride: 'أولاً:',
        text: 'نص عربي وEnglish مع فاصلة، ونقطة.',
      ),
    ],
    branches: <BranchModel>[branch],
    attachments: <FloatingElement>[questionImage],
  );

  return ExamDocument(
    id: 'document-rtl',
    name: 'اختبار البنية الدلالية',
    header: ExamHeaderModel(
      schoolName: 'مدرسة ${_verse('العلم')}',
      examType: 'اختبار منتصف الفصل',
      academicYear: '2026/2027',
      subject: 'اللغة العربية',
      grade: 'السادس',
      time: '90 دقيقة',
      showBismillah: true,
    ),
    footer: const ExamFooterModel(
      closingPhrase: 'انتهت الأسئلة، وفقكم الله',
      primary: SignatureModel(title: SignatureTitle.educator, name: 'ليلى'),
      secondary: SignatureModel(title: SignatureTitle.lecturerFemale, name: 'سارة'),
    ),
    questions: <QuestionModel>[question],
    floatingElements: <FloatingElement>[globalFormula, globalTextBox],
  );
}

String _inlineText(InlineContent content) =>
    content.nodes.map((node) => node.legacyText).join();

List<Object?> _irPointSignature(PointBlock point) => <Object?>[
      point.kind.name,
      _inlineText(point.labelContent),
      _inlineText(point.content),
      point.trailer == null ? null : _inlineText(point.trailer!),
      point.marks?.legacyText,
      <Object?>[
        for (final option in point.options?.options.where((option) => option.isPrintable) ??
            const <OptionNode>[])
          <String>[
            _inlineText(option.labelContent),
            _inlineText(option.content),
          ],
      ],
    ];

List<Object?> _irBranchSignature(BranchBlock branch) => <Object?>[
      _inlineText(branch.title.labelContent),
      _inlineText(branch.content),
      branch.title.marks?.legacyText,
      branch.body == null ? null : _inlineText(branch.body!.content),
      <Object?>[
        for (final point in branch.points.where((point) => point.isPrintable))
          _irPointSignature(point),
      ],
    ];

List<Object?> _irPrintableSignature(DocumentIR ir) => <Object?>[
      <Object?>[
        ir.header.showBismillah,
        <String>[
          for (final line in ir.header.rightColumn) _inlineText(line.content),
        ],
        <String>[
          for (final line in ir.header.centerColumn) _inlineText(line.content),
        ],
        <String>[
          for (final line in ir.header.leftColumn) _inlineText(line.content),
        ],
      ],
      <Object?>[
        ir.footer.closingPhrase == null
            ? null
            : _inlineText(ir.footer.closingPhrase!.content),
        ir.footer.primary.title.legacyText,
        _inlineText(ir.footer.primary.name),
        ir.footer.secondary?.title.legacyText,
        ir.footer.secondary == null ? null : _inlineText(ir.footer.secondary!.name),
      ],
      <Object?>[
        for (final question in ir.questions)
          <Object?>[
            question.id,
            question.category == null ? null : _inlineText(question.category!.content),
            _inlineText(question.title.labelContent),
            _inlineText(question.title.statement),
            question.title.marks?.legacyText,
            question.body == null ? null : _inlineText(question.body!.content),
            <Object?>[
              for (final point in question.points.where((point) => point.isPrintable))
                _irPointSignature(point),
            ],
            <Object?>[
              for (final branch in question.branches.where((branch) => branch.isPrintable))
                _irBranchSignature(branch),
            ],
          ],
      ],
    ];

List<Object?> _blueprintPointSignature(PointBlueprint point) => <Object?>[
      point.kind.name,
      point.label,
      point.text,
      point.trailer,
      point.marks,
      <Object?>[
        for (final option in point.options)
          <String>[option.label, option.text],
      ],
    ];

List<Object?> _blueprintSignature(ExamBlueprint blueprint) => <Object?>[
      <Object?>[
        blueprint.header.showBismillah,
        blueprint.header.rightLines,
        blueprint.header.centerLines,
        blueprint.header.leftLines,
      ],
      <Object?>[
        blueprint.footer.closingPhrase,
        blueprint.footer.primary.title,
        blueprint.footer.primary.nameLine,
        blueprint.footer.secondary?.title,
        blueprint.footer.secondary?.nameLine,
      ],
      <Object?>[
        for (final question in blueprint.questions)
          <Object?>[
            question.model.id,
            question.section,
            question.title.number,
            question.title.statement,
            question.title.marks,
            question.body,
            <Object?>[
              for (final point in question.points.where((point) => point.isPrintable))
                _blueprintPointSignature(point),
            ],
            <Object?>[
              for (final branch in question.branches.where(
                (branch) => branch.isPrintable(),
              ))
                <Object?>[
                  branch.title.number,
                  branch.title.statement,
                  branch.title.marks,
                  branch.body,
                  <Object?>[
                    for (final point in branch.points.where((point) => point.isPrintable))
                      _blueprintPointSignature(point),
                  ],
                ],
            ],
          ],
      ],
    ];

void main() {
  group('DocumentIR semantic structure', () {
    test('separates Arabic labels, separators, marks and mixed inline runs', () {
      final document = _richDocument();
      final ir = DocumentIR.fromBlueprint(
        blueprint: ExamBlueprint.from(document),
        document: document,
      );
      final question = ir.questions.single;

      expect(ir.direction, DocumentDirection.rtl);
      expect(question.direction, DocumentDirection.rtl);
      expect(question.title.label, isA<NumberNode>());
      expect((question.number as NumberNode).role, NumberRole.question);
      expect((question.number as NumberNode).value, 1);
      expect(question.separator, isA<SeparatorNode>());
      expect(question.separator!.role, SeparatorRole.question);
      expect(question.separator!.text, '/');
      expect(question.title.statement.nodes.map((node) => node.runtimeType), <Type>[
        TextNode,
        MathNode,
        TextNode,
      ]);
      expect(question.title.statement.nodes.first.direction, DocumentDirection.auto);
      expect((question.title.statement.nodes[1] as MathNode).source, r'\text{س}+٢');
      expect(question.title.statement.nodes.last.legacyText, '؛ ما الناتج؟');
      expect(question.title.marks, isA<MarksNode>());
      expect(question.title.marks!.value, 12);
      expect(question.title.marks!.number.role, NumberRole.marks);
      expect(question.title.marks!.opening.text, '(');
      expect(question.title.marks!.closing.text, ')');
      expect(question.title.marks!.unit.legacyText, 'درجة');
      expect(question.category, isA<CategoryBlock>());
      expect(_inlineText(question.category!.content), 'القراءة والنحو');
      expect(question.body!.content.nodes.whereType<MathNode>(), hasLength(1));
      expect(question.body!.content.nodes.whereType<QuranNode>(), hasLength(1));
      expect(ir.hasQuranContent, isTrue);
    });

    test('preserves point kinds, generated and manual labels, options, and branches', () {
      final document = _richDocument();
      final ir = DocumentIR.fromBlueprint(
        blueprint: ExamBlueprint.from(document),
        document: document,
      );
      final question = ir.questions.single;
      final trueFalse = question.points.first;
      final fillBlank = question.points[1];
      final multipleChoice = question.points[2];
      final custom = question.points[3];

      expect(trueFalse.kind, PointKind.trueFalse);
      expect(trueFalse.number!.role, NumberRole.item);
      expect(trueFalse.separator!.text, '-');
      expect(trueFalse.trailer, isNotNull);
      expect(_inlineText(trueFalse.trailer!), ExamCatalog.trueFalseSlot);
      expect(fillBlank.kind, PointKind.fillBlank);
      expect(_inlineText(fillBlank.trailer!), ExamCatalog.fillBlank);
      expect(multipleChoice.kind, PointKind.multipleChoice);
      expect(multipleChoice.options, isA<OptionsBlock>());
      expect(multipleChoice.options!.options, hasLength(3));
      expect(multipleChoice.options!.options.map((option) => option.index), <int>[0, 1, 2]);
      expect(multipleChoice.options!.options.map((option) => option.isPrintable), <bool>[
        true,
        false,
        true,
      ]);
      expect(multipleChoice.options!.options.first.labelPrefix.first.text, '(');
      expect(
        multipleChoice.options!.options.first.labelSuffix.last.text,
        ')',
      );
      expect(multipleChoice.options!.options.last.label.legacyText, 'ج!');
      expect(custom.label, isA<LabelNode>());
      expect(custom.separator, isNull);
      expect(_inlineText(custom.labelContent), 'أولاً:');

      expect(question.branches, hasLength(1));
      final branch = question.branches.single;
      expect(branch.id, 'branch-a');
      expect(branch.label.role, LabelRole.branch);
      expect(branch.separator!.role, SeparatorRole.branch);
      expect(branch.separator!.text, ')');
      expect(branch.title.marks!.value, 3);
      expect(branch.content.nodes.whereType<MathNode>(), hasLength(1));
      expect(branch.body!.content.nodes.whereType<QuranNode>(), hasLength(1));
      expect(branch.points.single.kind, PointKind.trueFalse);
      expect(branch.points.single.trailer, isNotNull);
    });

    test('retains header fields, footer signatures, and inline direction metadata', () {
      final inheritedContent = InlineContent.fromSource(
        'وراثة الاتجاه',
        direction: DocumentDirection.inherit,
      );
      final inheritedParagraph = ParagraphBlock(
        content: inheritedContent,
        direction: DocumentDirection.inherit,
      );
      expect(inheritedParagraph.direction, DocumentDirection.inherit);
      expect(inheritedContent.nodes.single.direction, DocumentDirection.inherit);

      final document = _richDocument();
      final ir = DocumentIR.fromBlueprint(
        blueprint: ExamBlueprint.from(document),
        document: document,
      );

      expect(ir.header.showBismillah, isTrue);
      expect(ir.header.direction, DocumentDirection.rtl);
      expect(ir.header.rightColumn.map((line) => line.field), <HeaderFieldKind>[
        HeaderFieldKind.administration,
        HeaderFieldKind.schoolName,
        HeaderFieldKind.schoolGender,
      ]);
      expect(ir.header.centerColumn.map((line) => line.field), contains(HeaderFieldKind.academicYear));
      expect(ir.header.leftColumn.map((line) => line.field), contains(HeaderFieldKind.subject));
      expect(
        ir.header.rightColumn[1].content.nodes.whereType<QuranNode>(),
        hasLength(1),
      );
      expect(ir.header.leftColumn.first.content.nodes.first.direction, DocumentDirection.rtl);
      expect(ir.header.leftColumn.first.content.nodes.last.direction, DocumentDirection.auto);

      expect(ir.footer.closingPhrase, isNotNull);
      expect(ir.footer.closingPhrase!.content.nodes.whereType<TextNode>(), isNotEmpty);
      expect(ir.footer.primary.title.role, LabelRole.signature);
      expect(_inlineText(ir.footer.primary.name), 'ليلى');
      expect(ir.footer.secondary, isNotNull);
      expect(ir.footer.secondary!.title.legacyText, 'مدرسة المادة');
      expect(_inlineText(ir.footer.secondary!.name), 'سارة');
    });

    test('keeps floating and local attachment references semantic and geometry-free', () {
      final document = _richDocument();
      final ir = DocumentIR.fromBlueprint(
        blueprint: ExamBlueprint.from(document),
        document: document,
      );
      final globals = ir.floatingElements!.elements;
      final question = ir.questions.single;
      final branch = question.branches.single;

      expect(globals.map((element) => element.id), <String>[
        'global-formula',
        'global-text-box',
      ]);
      expect(globals.first.kind, FloatingReferenceKind.formula);
      expect(globals.first.label!.nodes.single, isA<MathNode>());
      expect(globals.last.kind, FloatingReferenceKind.textBox);
      expect(globals.last.label!.nodes.whereType<QuranNode>(), hasLength(1));
      expect(ir.floatingElementById('branch-formula')?.kind, FloatingReferenceKind.formula);
      final projectedFormula = LegacyPdfAdapter.adaptFloatingElement(
        documentIr: ir,
        sourceElement: document.floatingElements.singleWhere(
          (element) => element.id == 'global-formula',
        ),
      );
      expect(projectedFormula.label, r'\frac{س}{٢}');
      final projectedTextBox = LegacyDocxAdapter.adaptFloatingElement(
        documentIr: ir,
        sourceElement: document.floatingElements.singleWhere(
          (element) => element.id == 'global-text-box',
        ),
      );
      expect(projectedTextBox.label, globals.last.label!.legacyText);
      expect(question.attachments!.elements.single.id, 'question-image');
      expect(question.attachments!.elements.single.kind, FloatingReferenceKind.image);
      expect(question.attachments!.elements.single.ownerQuestionId, 'q-rtl');
      expect(branch.attachments!.elements.map((element) => element.id), <String>[
        'branch-text-box',
        'branch-formula',
      ]);
      expect(branch.attachments!.elements.first.ownerBranchId, 'branch-a');
      expect(ir.blocks.first, isA<HeaderBlock>());
      expect(ir.blocks[1], isA<QuestionBlock>());
      expect(ir.blocks[2], isA<FloatingElementsBlock>());
      expect(ir.blocks.last, isA<FooterBlock>());
      expect(ir.blocks.whereType<PageBlock>(), isEmpty);
      expect(globals.every((element) => element is! FloatingElement), isTrue);
    });

    test('supports an LTR paper and mixed LTR/RTL text without bidi controls', () {
      final document = ExamDocument(
        id: 'document-ltr',
        name: 'English test',
        header: ExamHeaderModel(
          subject: 'English',
          showBismillah: false,
          schoolName: 'North School',
        ),
        settings: const PaperSettings(numerals: PaperNumerals.latin),
        questions: <QuestionModel>[
          QuestionModel(
            id: 'q-ltr',
            questionNumber: 1,
            statement: 'Translate كلمة, then calculate ${r'$x+1$'}!',
            items: <BranchItem>[
              BranchItem(id: 'ltr-item', text: 'Write English and عربي.'),
            ],
          ),
        ],
      );
      final ir = DocumentIR.fromBlueprint(
        blueprint: ExamBlueprint.from(document),
        document: document,
      );
      final question = ir.questions.single;
      final renderedSources = <String>[
        for (final node in question.title.statement.nodes) node.legacyText,
        for (final node in question.points.single.content.nodes) node.legacyText,
      ].join();

      expect(ir.direction, DocumentDirection.ltr);
      expect(question.title.direction, DocumentDirection.ltr);
      expect(question.number, isA<NumberNode>());
      expect((question.number as NumberNode).displayText, 'Q1');
      expect(question.separator!.text, '.');
      expect(question.title.statement.nodes.first.direction, DocumentDirection.auto);
      expect(question.title.statement.nodes.whereType<MathNode>().single.source, 'x+1');
      expect(renderedSources, contains('كلمة'));
      expect(renderedSources, contains('English'));
      expect(renderedSources, contains('عربي'));
      expect(RegExp(r'[\u202A-\u202E\u2066-\u2069]').hasMatch(renderedSources), isFalse);
    });

    test('orders long documents deterministically without truncating questions', () {
      final document = ExamDocument(
        id: 'long-document',
        name: 'Long test',
        header: ExamHeaderModel(subject: 'اللغة العربية', showBismillah: false),
        questions: <QuestionModel>[
          for (var index = 0; index < 84; index++)
            QuestionModel(
              id: 'q-$index',
              questionNumber: index + 1,
              statement: 'السؤال رقم ${index + 1}',
              items: <BranchItem>[
                BranchItem(id: 'item-$index', text: 'نص النقطة ${index + 1}'),
              ],
            ),
        ],
      );
      DocumentIR build() => DocumentIR.fromBlueprint(
            blueprint: ExamBlueprint.from(document),
            document: document,
          );

      final first = build();
      final second = build();
      expect(first.questions, hasLength(84));
      expect(first.questions.map((question) => question.index),
          List<int>.generate(84, (index) => index));
      expect(first.questions.map((question) => question.id),
          List<String>.generate(84, (index) => 'q-$index'));
      expect(first.questionById('q-83')!.title.statement.nodes.first.legacyText,
          'السؤال رقم 84');
      expect(
        first.questions.map((question) => question.title.labelContent.legacyText),
        second.questions.map((question) => question.title.labelContent.legacyText),
      );
      expect(first.blocks, hasLength(86)); // header + 84 questions + footer
    });

    test('Preview, PDF adapter, and DOCX adapter expose equivalent printable semantics', () {
      final document = _richDocument();
      final controller = ExamWizardController(document: document);
      final previewIr = controller.documentIr;
      final sourceBlueprint = ExamBlueprint.from(document);
      final pdfBlueprint = LegacyPdfAdapter.adapt(
        documentIr: previewIr,
        sourceDocument: document,
      );
      final docxBlueprint = LegacyDocxAdapter.adapt(
        documentIr: previewIr,
        sourceDocument: document,
      );

      expect(previewIr.questions.single.id, 'q-rtl');
      expect(
        _blueprintSignature(pdfBlueprint),
        _blueprintSignature(docxBlueprint),
      );
      expect(_blueprintSignature(pdfBlueprint), _irPrintableSignature(previewIr));
      expect(_blueprintSignature(sourceBlueprint), _irPrintableSignature(previewIr));
      final projectedTitle = docxBlueprint.questions.single.title;
      expect(projectedTitle.numberNode?.direction, DocumentDirection.rtl);
      expect(projectedTitle.separatorNode?.direction, DocumentDirection.rtl);
      expect(
        projectedTitle.statementContent!.nodes.first.direction,
        DocumentDirection.auto,
      );
      expect(
        docxBlueprint.questions.single.bodyContent!.nodes.first.direction,
        DocumentDirection.auto,
      );
      controller.dispose();
    });

    test('controller invalidates the semantic Preview cache after an edit', () {
      final controller = ExamWizardController(document: _richDocument());
      final before = controller.documentIr;
      controller.updateQuestionStatement(0, r'نص جديد $x$');

      final after = controller.documentIr;
      expect(identical(after, before), isFalse);
      expect(after.questions.single.content.nodes.whereType<MathNode>(), hasLength(1));
      expect(after.questions.single.content.nodes.first.legacyText, 'نص جديد ');
      controller.dispose();
    });

    test('contains no injected bidi controls in its inline text', () {
      final document = _richDocument();
      final ir = DocumentIR.fromBlueprint(
        blueprint: ExamBlueprint.from(document),
        document: document,
      );
      final nodes = <InlineNode>[
        for (final question in ir.questions) ...question.title.labelContent.nodes,
        for (final question in ir.questions) ...question.content.nodes,
        for (final question in ir.questions)
          for (final point in question.points) ...point.content.nodes,
      ];
      expect(
        nodes.any((node) => RegExp(r'[\u202A-\u202E\u2066-\u2069]').hasMatch(node.legacyText)),
        isFalse,
      );
    });
  });
}
