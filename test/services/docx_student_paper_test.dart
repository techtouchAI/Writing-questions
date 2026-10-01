import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/layout/paper_metrics.dart';
import 'package:writing_questions_app/models/branch_item.dart';
import 'package:writing_questions_app/models/branch_model.dart';
import 'package:writing_questions_app/models/exam_catalog.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_footer_model.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/paper_settings.dart';
import 'package:writing_questions_app/models/paper_text_style.dart';
import 'package:writing_questions_app/models/point_kind.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/models/question_option.dart';
import 'package:writing_questions_app/services/docx_document_export_service.dart';

/// صورة PNG شفافة بحجم 1×1 (تكفي لاختبار حزمة صورة الإطار).
final Uint8List _framePng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

ExamDocument _document({PaperSettings? settings}) => ExamDocument(
      name: 'اختبار',
      settings: settings,
      header: ExamHeaderModel(
        schoolName: 'متوسطة حليف القرآن',
        examType: 'نصف السنة',
        academicYear: '2026/2027',
        subject: 'الرياضيات',
        grade: 'الثالث',
        time: 'ساعتان',
      ),
      footer: const ExamFooterModel(
        closingPhrase: 'انتهت الأسئلة',
        primary: SignatureModel(name: 'أحمد'),
        secondary: SignatureModel(title: SignatureTitle.educator, name: 'علي'),
      ),
      questions: <QuestionModel>[
        QuestionModel(
          id: 'q1',
          questionNumber: 1,
          category: 'القسم الأول',
          statement: 'ما ناتج ٢ + ٢؟',
          marksOverride: 10,
          items: <BranchItem>[
            BranchItem(id: 'qi1', text: 'نقطة السؤال الأولى'),
            BranchItem(id: 'qi2', text: 'نقطة السؤال الثانية'),
          ],
          branches: <BranchModel>[
            BranchModel(
              id: 'b1',
              marks: 5,
              content: BranchContent(
                statement: 'اختر الإجابة',
                items: <BranchItem>[
                  BranchItem(id: 'bi1', text: 'نص الفرع بعنصر'),
                  BranchItem(
                    id: 'bi2',
                    kind: PointKind.multipleChoice,
                    text: 'سؤال الخيارات',
                    options: <QuestionOption>[
                      QuestionOption(text: 'أربعة'),
                      QuestionOption(text: 'خمسة'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        QuestionModel(
          id: 'q2',
          questionNumber: 2,
          statement: 'ضع علامة صح أو خطأ',
          marksOverride: 6,
          branches: <BranchModel>[
            BranchModel(
              id: 'b2',
              marks: 3,
              content: BranchContent(
                items: <BranchItem>[
                  BranchItem(id: 'bi3', kind: PointKind.trueFalse, text: '١ + ١ = ٢'),
                  BranchItem(id: 'bi4', kind: PointKind.trueFalse, text: '١ + ١ = ٣'),
                ],
              ),
            ),
          ],
        ),
        QuestionModel(
          id: 'q3',
          questionNumber: 3,
          statement: 'اكتب مقالاً قصيراً',
          marksOverride: 4,
          branches: <BranchModel>[
            BranchModel(id: 'b3', marks: 4, content: BranchContent()),
          ],
        ),
      ],
    );

Future<Archive> _archive(
  ExamDocument document, {
  List<List<String>>? pageAssignments,
  Uint8List? frameImage,
}) async {
  final bytes = await DocxDocumentExportService.buildDocumentDocxBytes(
    document: document,
    pageAssignments: pageAssignments,
    frameImage: frameImage,
  );
  return ZipDecoder().decodeBytes(bytes);
}

String _text(Archive archive, String path) {
  final file = archive.findFile(path);
  expect(file, isNotNull, reason: path);
  return utf8.decode(file!.content as List<int>);
}

Future<String> _documentXml(
  ExamDocument document, {
  List<List<String>>? pageAssignments,
}) async {
  return _text(await _archive(document, pageAssignments: pageAssignments), 'word/document.xml');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('الأسئلة: الرقم ← المنطوق ← الدرجة ← النص ← النقاط بترقيم تلقائي متصل', () async {
    final document = _document();
    final xml = await _documentXml(document);

    // سطر العنوان: الرقم التلقائي + المنطوق + الدرجة الخام مطبوعة «(١٠ درجة)».
    expect(xml.contains('السؤال الأول/ ما ناتج ٢ + ٢؟ (١٠ درجة)'), isTrue);
    expect(xml.contains('أ) اختر الإجابة (٥ درجة)'), isTrue);

    // نقاط السؤال داخل السؤال مع الترقيم التلقائي من نموذج المستند نفسه.
    expect(xml.contains('${document.autoItemLabel(0)} نقطة السؤال الأولى'), isTrue);
    expect(xml.contains('${document.autoItemLabel(1)} نقطة السؤال الثانية'), isTrue);
    // ونقاط الفرع بالترقيم المتصل نفسه (الاختيار من متعدد نقطتها الثانية).
    expect(xml.contains('${document.autoItemLabel(0)} نص الفرع بعنصر'), isTrue);
    expect(xml.contains('${document.autoItemLabel(1)} سؤال الخيارات'), isTrue);

    // خيارات «اختيار من متعدد» تحت نقطتها بتسمياتها.
    expect(xml.contains('( أ ) أربعة'), isTrue);
    expect(xml.contains('( ب ) خمسة'), isTrue);

    // عبارات صح/خطأ يليها قوسا الإجابة الفارغان.
    expect(xml.contains('١- ١ + ١ = ٢ ${ExamCatalog.trueFalseSlot}'), isTrue);

    // الترتيب: القسم ثم العنوان ثم نقطة السؤال تسبق الفرع.
    final section = xml.indexOf('القسم الأول');
    final qi = xml.indexOf('نقطة السؤال الأولى');
    final bi = xml.indexOf('نص الفرع بعنصر');
    expect(section, greaterThan(-1));
    expect(qi, greaterThan(section));
    expect(bi, greaterThan(qi));

    // لا أي أثر لإجابة أو لعدّادات عامة على الورقة.
    expect(xml.contains('الدرجة الكلية'), isFalse);
    expect(xml.contains('عدد الأسئلة'), isFalse);
    expect(xml.contains('(صح)'), isFalse);
    expect(xml.contains('الإجابة:'), isFalse);
    expect(xml.contains('الإجابة النموذجية'), isFalse);
    expect(xml.contains('........................................'), isFalse);
  });

  test('الترويسة: جدول من ثلاثة أعمدة بالنصوص الحرفية والبسملة بخط Amiri', () async {
    final xml = await _documentXml(_document());

    expect(xml.contains('<w:bidiVisual/>'), isTrue);
    for (final line in <String>[
      'ادارة',
      'متوسطة حليف القرآن',
      'للبنين',
      'اسئلة امتحان نصف السنة',
      'للعام الدراسي ٢٠٢٦/٢٠٢٧',
      'الدور الأول',
      'المادة: الرياضيات',
      'الصف: الثالث',
      'الوقت: ساعتان',
      'اسم الطالب: ${ExamCatalog.blankLine}',
    ]) {
      expect(xml.contains(line), isTrue, reason: line);
    }
    // الترتيب في الملف = ترتيب الجدول من اليمين: المدرسة ← الامتحان ← المادة.
    final right = xml.indexOf('ادارة');
    final center = xml.indexOf('اسئلة امتحان');
    final left = xml.indexOf('المادة:');
    expect(right, lessThan(center));
    expect(center, lessThan(left));

    // البسملة بخط خطّي (Amiri) قبل بقية سطور الوسط.
    final bismillah = xml.indexOf(ExamCatalog.bismillah);
    expect(bismillah, greaterThan(-1));
    expect(bismillah, lessThan(center));
    expect(xml.contains('w:cs="Amiri"'), isTrue);
  });

  test('البسملة وحقول الترويسة الاختيارية تختفي عند تعطيلها', () async {
    final document = _document().copyWith(
      header: ExamHeaderModel(showBismillah: false, schoolGender: SchoolGender.none),
    );
    final xml = await _documentXml(document);

    expect(xml.contains(ExamCatalog.bismillah), isFalse);
    expect(xml.contains('للبنين'), isFalse);
    // الحقول الفارغة تُطبع خطاً منقطاً.
    expect(xml.contains('المادة: ${ExamCatalog.blankLine}'), isTrue);
    expect(xml.contains('الصف: ${ExamCatalog.blankLine}'), isTrue);
    expect(xml.contains('الوقت: ${ExamCatalog.blankLine}'), isTrue);
  });

  test('التذييل: جدول مثبّت أسفل الصفحة بعد آخر سؤال بلا ترقيم صفحات', () async {
    final archive = await _archive(_document());
    final xml = _text(archive, 'word/document.xml');

    expect(xml.contains('w:tblpYSpec="bottom"'), isTrue);
    expect(xml.contains('w:vertAnchor="margin"'), isTrue);
    for (final text in <String>['انتهت الأسئلة', 'مدرس المادة', 'أحمد', 'معلم المادة', 'علي']) {
      expect(xml.contains(text), isTrue, reason: text);
    }
    // بعد نص آخر سؤال، والثاني (يمين) قبل الأساسي (يسار) في جدول bidiVisual.
    final lastQuestion = xml.indexOf('اكتب مقالاً قصيراً');
    final footerTable = xml.indexOf('w:tblpYSpec="bottom"');
    expect(footerTable, greaterThan(lastQuestion));
    expect(xml.indexOf('علي'), lessThan(xml.indexOf('أحمد')));

    // لا جزء تذييل ولا حقول PAGE/NUMPAGES ولا كلمة «صفحة».
    expect(archive.findFile('word/footer1.xml'), isNull);
    expect(xml.contains('footerReference'), isFalse);
    expect(xml.contains('PAGE'), isFalse);
    expect(xml.contains('NUMPAGES'), isFalse);
    expect(xml.contains('صفحة'), isFalse);
    expect(_text(archive, '[Content_Types].xml').contains('footer'), isFalse);
  });

  test('التوقيع الثاني لا يظهر إلا إذا أُضيف صراحةً', () async {
    final document = _document().copyWith(
      footer: const ExamFooterModel(
        closingPhrase: '',
        primary: SignatureModel(name: 'أحمد'),
      ),
    );
    final xml = await _documentXml(document);
    expect(xml.contains('أحمد'), isTrue);
    expect(xml.contains('معلم المادة'), isFalse);
    expect(xml.contains('علي'), isFalse);
    expect(xml.contains('انتهت الأسئلة'), isFalse);
  });

  test('الإطار: صورة PNG في ترويسة الصفحة خلف النص بدل حدود متجهة', () async {
    final document = _document(settings: const PaperSettings(pageBorder: true));
    final archive = await _archive(document, frameImage: _framePng);
    final xml = _text(archive, 'word/document.xml');

    expect(archive.findFile('word/header1.xml'), isNotNull);
    expect(archive.findFile('word/_rels/header1.xml.rels'), isNotNull);
    expect(archive.findFile('word/media/frame.png'), isNotNull);
    expect(xml.contains('headerReference'), isTrue);
    expect(xml.contains('w:pgBorders'), isFalse);

    final header = _text(archive, 'word/header1.xml');
    expect(header.contains('behindDoc="1"'), isTrue);
    expect(header.contains('relativeFrom="page"'), isTrue);
    expect(header.contains('cx="7560310" cy="10692130"'), isTrue);
    expect(_text(archive, '[Content_Types].xml').contains('header+xml'), isTrue);
    expect(_text(archive, 'word/_rels/document.xml.rels').contains('relationships/header'), isTrue);
  });

  test('الإطار المتجه: حدود الصفحة تتبع الهامش ولا صورة بدونها', () async {
    final archive = await _archive(
      _document(settings: const PaperSettings(pageBorder: true)),
    );
    final xml = _text(archive, 'word/document.xml');
    expect(archive.findFile('word/header1.xml'), isNull);
    expect(xml.contains('w:pgBorders'), isTrue);
    // هامش 15 مم ⇒ نصف الهامش بالنقاط ≈ 21.
    expect(xml.contains('w:space="21"'), isTrue);

    final wide = await _archive(
      _document(settings: const PaperSettings(pageBorder: true, marginMm: 25)),
    );
    expect(_text(wide, 'word/document.xml').contains('w:space="31"'), isTrue);

    // الإطار معطّل: لا حدود ولا صورة حتى لو مُرّرت.
    final off = await _archive(_document(), frameImage: _framePng);
    expect(off.findFile('word/header1.xml'), isNull);
    expect(_text(off, 'word/document.xml').contains('w:pgBorders'), isFalse);
  });

  test('هامش Word يتبع إعداد الهامش', () async {
    final xml = await _documentXml(
      _document(settings: const PaperSettings(marginMm: 20)),
    );
    final twips = (20 / 25.4 * 1440).round();
    expect(xml.contains('w:top="$twips"'), isTrue);
    expect(xml.contains('w:left="$twips"'), isTrue);
  });

  test('uses paragraph spacing and line height while coloring only the title', () async {
    final document = ExamDocument(
      name: 'تنسيق مستقل',
      header: ExamHeaderModel.initial(subject: 'الرياضيات'),
      questions: <QuestionModel>[
        QuestionModel(
          id: 'styled',
          questionNumber: 1,
          statement: 'متن السؤال غير الملوّن',
          style: const PaperTextStyle(
            color: 0xFF12AB34,
            lineHeight: 1.5,
            paragraphSpacing: 6,
          ),
          items: <BranchItem>[BranchItem(id: 'item', text: 'نقطة السؤال')],
          branches: <BranchModel>[
            BranchModel(
              id: 'choices',
              style: const PaperTextStyle(lineHeight: 1.25, paragraphSpacing: 12),
              content: BranchContent(
                statement: 'اختر الإجابة',
                items: <BranchItem>[
                  BranchItem(
                    kind: PointKind.multipleChoice,
                    text: 'السؤال',
                    options: <QuestionOption>[QuestionOption(text: 'الخيار الأول')],
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
    final xml = await _documentXml(document);
    final questionSpacingTwips = (PaperMetrics.pt(6) * 20).round();
    final optionSpacingTwips = (PaperMetrics.pt(12) * 20).round();

    expect(RegExp('w:color w:val="12AB34"').allMatches(xml), hasLength(1));
    expect(xml.contains('متن السؤال غير الملوّن'), isTrue);
    expect(xml.contains('نقطة السؤال'), isTrue);
    expect(xml.contains('w:line="360"'), isTrue);
    expect(xml.contains('w:line="300"'), isTrue);
    expect(xml.contains('w:after="$questionSpacingTwips"'), isTrue);
    expect(xml.contains('w:after="$optionSpacingTwips"'), isTrue);
  });

  test('omits empty editable questions and rejects stale page assignments', () async {
    final document = ExamDocument(
      name: 'أسئلة قابلة للطباعة',
      header: ExamHeaderModel.initial(subject: 'الرياضيات'),
      questions: <QuestionModel>[
        QuestionModel(
          id: 'empty',
          questionNumber: 1,
          category: 'لا ينبغي تصدير هذا القسم',
        ),
        QuestionModel(
          id: 'visible',
          questionNumber: 2,
          statement: 'السؤال الذي يظهر في الملف',
        ),
      ],
    );
    final xml = await _documentXml(
      document,
      pageAssignments: const <List<String>>[
        <String>['empty', 'visible'],
      ],
    );

    expect(xml.contains('لا ينبغي تصدير هذا القسم'), isFalse);
    expect(xml.contains('السؤال الذي يظهر في الملف'), isTrue);
    expect(xml.contains('<w:br w:type="page"/>'), isFalse);
  });
}
