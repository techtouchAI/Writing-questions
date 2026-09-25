import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/models/branch_item.dart';
import 'package:writing_questions_app/models/branch_model.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/floating_element.dart';
import 'package:writing_questions_app/models/paper_divider.dart';
import 'package:writing_questions_app/models/paper_font.dart';
import 'package:writing_questions_app/models/paper_settings.dart';
import 'package:writing_questions_app/models/paper_text_style.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/models/question_type.dart';
import 'package:writing_questions_app/pdf_engine/paginated_pdf_exam_engine.dart';
import 'package:writing_questions_app/providers/exam_wizard_controller.dart';
import 'package:writing_questions_app/services/docx_document_export_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Scenario Point 59: Complete Exam Paper Lifecycle Test', () {
    test('Builds, modifies, reorders, formats, preserves, and exports full 6-question paper', () async {
      // 1. ترويسة متكاملة
      final header = ExamHeaderModel(
        subject: 'اللغة العربية',
        title: 'أسئلة امتحان مادة اللغة العربية للعام الدراسي 2025-2026 — الدور الأول',
        right: HeaderColumn(const <String>['التاريخ:      /      /', 'المادة: اللغة العربية', 'الصف الثالث المتوسط']),
        center: HeaderColumn(const <String>['وزارة التربية — مديرية تربية الكرخ', 'امتحان نصف السنة 2025-2026', 'الدور الأول']),
        left: HeaderColumn(const <String>['الوقت: ساعتان', 'اسم الطالب:', 'الرقم الامتحاني:']),
        instructions: 'ملاحظة: أجب عن جميع الأسئلة الآتية.',
        notes: 'الدرجة الكلية: 100 درجة',
        style: const PaperTextStyle(font: PaperFont.naskh, fontSize: 10.5, align: PaperAlign.center),
      );

      // 1-بكسل شفاف كصورة تجريبية
      final dummyImageBytes = Uint8List.fromList(<int>[
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
        0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
        0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
        0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
        0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
      ]);

      // 6 أسئلة مطابقة للسيناريو:
      // س1: 4 فروع
      final q1 = QuestionModel(
        questionNumber: 1,
        prompt: 'س1/ قال تعالى: "إنا فتحنا لك فتحاً مبيناً"',
        branches: <BranchModel>[
          BranchModel(content: BranchContent(type: QuestionType.essay, text: 'استخرج الأفعال وبين نوعها.'), marks: 4),
          BranchModel(content: BranchContent(type: QuestionType.essay, text: 'هات مصادر الأفعال الآتية.'), marks: 4),
          BranchModel(content: BranchContent(type: QuestionType.essay, text: 'أعرب ما تحته خط إعراباً مفصلاً.'), marks: 4),
          BranchModel(content: BranchContent(type: QuestionType.essay, text: 'ما المعنى المستفاد من حرف التوكيد؟'), marks: 3),
        ],
      );

      // س2: 3 فروع
      final q2 = QuestionModel(
        questionNumber: 2,
        prompt: 'س2/ أجب عما يأتي:',
        branches: <BranchModel>[
          BranchModel(content: BranchContent(type: QuestionType.essay, text: 'عرف اسم التفضيل واذكر أركانه.'), marks: 5),
          BranchModel(content: BranchContent(type: QuestionType.essay, text: 'كيف يصاغ اسم الفاعل من غير الثلاثي؟'), marks: 5),
          BranchModel(content: BranchContent(type: QuestionType.essay, text: 'مثل بجملة مفيدة لاسم مفعول عامل.'), marks: 5),
        ],
      );

      // س3: فراغات من 10 نقاط
      final q3 = QuestionModel(
        questionNumber: 3,
        prompt: 'س3/ أكمل الفراغات الآتية بما يناسبها:',
        branches: <BranchModel>[
          BranchModel(
            content: BranchContent(
              type: QuestionType.fillInTheBlank,
              text: 'املأ الفراغات بالكلمات الصحيحة:',
              items: List<BranchItem>.generate(
                10,
                (i) => BranchItem(text: 'فراغ النقطة رقم ${i + 1} هو ..............', marks: 1),
              ),
            ),
            marks: 10,
          ),
        ],
      );

      // س4: صح وخطأ من 7 نقاط
      final q4 = QuestionModel(
        questionNumber: 4,
        prompt: 'س4/ ضع كلمة (صح) أو (خطأ) أمام العبارات الآتية:',
        branches: <BranchModel>[
          BranchModel(
            content: BranchContent(
              type: QuestionType.trueFalse,
              text: 'اختر صح أو خطأ:',
              items: List<BranchItem>.generate(
                7,
                (i) => BranchItem(text: 'العبارة رقم ${i + 1} عن قواعد اللغة العربية.', marks: 1),
              ),
            ),
            marks: 7,
          ),
        ],
      );

      // س5: أجب عن فرعين من 4
      final q5 = QuestionModel(
        questionNumber: 5,
        prompt: 'س5/ أجب عن فرعين فقط مما يأتي:',
        branches: <BranchModel>[
          BranchModel(content: BranchContent(type: QuestionType.essay, text: 'اشرح بيت الشعر الأول شرحاً أدبياً.'), marks: 5),
          BranchModel(content: BranchContent(type: QuestionType.essay, text: 'اكتب ما تحفظه من قصيدة الشاعر.'), marks: 5),
          BranchModel(content: BranchContent(type: QuestionType.essay, text: 'اذكر حياة الشاعر ومؤلفاته.'), marks: 5),
          BranchModel(content: BranchContent(type: QuestionType.essay, text: 'ما الغرض البلاغي من الاستفهام في البيت؟'), marks: 5),
        ],
      );

      // س6: سؤال مقالي مع صورة
      final q6 = QuestionModel(
        questionNumber: 6,
        prompt: 'س6/ تأمل الشكل التوضيحي ثم أجب عما يليه:',
        attachments: <FloatingElement>[
          FloatingElement(
            type: FloatingElementType.image,
            bytes: dummyImageBytes,
            dx: 20,
            dy: 20,
            width: 120,
            height: 120,
            label: 'الشكل التوضيحي للسؤال السادس',
          ),
        ],
        branches: <BranchModel>[
          BranchModel(
            content: BranchContent(type: QuestionType.essay, text: 'اشرح ما تدل عليه الصورة بالتفصيل.'),
            marks: 10,
          ),
        ],
      );

      // إنشاء المستند الأولي
      var doc = ExamDocument(
        name: 'امتحان اللغة العربية النهائي 2026',
        header: header,
        questions: <QuestionModel>[q1, q2, q3, q4, q5, q6],
        settings: const PaperSettings(
          defaultFont: PaperFont.naskh,
          baseFontSize: 11,
          autoNumberQuestions: true,
          pageBorder: true,
        ),
      );

      final controller = ExamWizardController(document: doc);

      // التحقق من العدد الأولي
      expect(controller.questions.length, 6);
      expect(controller.questions[0].branches.length, 4);
      expect(controller.questions[1].branches.length, 3);
      expect(controller.questions[2].branches[0].content.items.length, 10);
      expect(controller.questions[3].branches[0].content.items.length, 7);
      expect(controller.questions[4].branches.length, 4);
      expect(controller.questions[5].attachments.length, 1);

      // 1. تعديل س1
      controller.updateQuestionPrompt(0, 'س1/ قال تعالى بعد بسم الله الرحمن الرحيم: "إنا فتحنا لك فتحاً مبيناً" صدق الله العظيم');
      expect(controller.questions[0].prompt, contains('صدق الله العظيم'));

      // 2. حذف فرع من س1
      final q1BranchRefToDelete = const BranchRef(questionIndex: 0, branchIndex: 3);
      controller.removeBranch(q1BranchRefToDelete);
      expect(controller.questions[0].branches.length, 3);

      // 3. إضافة فرع جديد إلى س1
      controller.addBranch(0, type: QuestionType.essay);
      expect(controller.questions[0].branches.length, 4);

      // 4. نقل س4 إلى مكان س2 (س4 يصبح في الفهرس 1)
      final q4OldPrompt = controller.questions[3].prompt;
      controller.moveQuestion(3, 1);
      expect(controller.questions[1].prompt, q4OldPrompt);

      // 5. نقل فرع داخل السؤال الأول
      final branch0Text = controller.questions[0].branches[0].content.text;
      final branch1Text = controller.questions[0].branches[1].content.text;
      controller.moveBranch(0, 0, 1);
      expect(controller.questions[0].branches[1].content.text, branch0Text);
      expect(controller.questions[0].branches[0].content.text, branch1Text);

      // 6. إضافة صورة
      final addedImage = FloatingElement(
        type: FloatingElementType.image,
        bytes: dummyImageBytes,
        dx: 10,
        dy: 10,
        width: 100,
        height: 100,
        label: 'صورة إضافية',
      );
      controller.addQuestionAttachment(addedImage, questionIndex: 0);
      expect(controller.questions[0].attachments.length, 1);

      // 7. إضافة مربع
      final addedBox = FloatingElement(
        type: FloatingElementType.shape,
        shape: FloatingShapeType.square,
        dx: 50,
        dy: 50,
        width: 80,
        height: 80,
      );
      controller.addQuestionAttachment(addedBox, questionIndex: 1);
      expect(controller.questions[1].attachments.length, 1);

      // 8. إضافة فاصل بعد السؤال الأول
      controller.setQuestionDivider(0, const PaperDivider(thickness: 2, spacingAfter: 12));
      expect(controller.questions[0].dividerAfter, isNotNull);

      // 9. تغيير خط س3
      controller.updateQuestionStyle(
        2,
        controller.questions[2].style.copyWith(font: () => PaperFont.tajawal),
      );
      expect(controller.questions[2].style.font, PaperFont.tajawal);

      // 10. تغيير حجم خط س5
      controller.updateQuestionStyle(
        4,
        controller.questions[4].style.copyWith(fontSize: () => 14),
      );
      expect(controller.questions[4].style.fontSize, 14);

      // 11. توسيط الترويسة
      controller.updateHeaderStyle(
        controller.document.header.style.copyWith(align: () => PaperAlign.center),
      );
      expect(controller.document.header.style.align, PaperAlign.center);

      // 16. حفظ العمل / فحص نموذج المستند المعدل
      final finalDocument = controller.document;

      // 17 & 18. إغلاق التطبيق وإعادة الفتح من التخزين (Serialization & Deserialization)
      final serializedJson = jsonEncode(finalDocument.toMap());
      final restoredMap = jsonDecode(serializedJson) as Map<String, dynamic>;
      final restoredDocument = ExamDocument.fromMap(restoredMap);

      // 19. التأكد التام من عدم فقدان أي محتوى بعد الاستعادة
      expect(restoredDocument.questions.length, 6);
      expect(restoredDocument.questions[0].branches.length, 4);
      expect(restoredDocument.questions[0].prompt, contains('صدق الله العظيم'));
      expect(restoredDocument.questions[0].attachments.length, 1);
      expect(restoredDocument.questions[0].dividerAfter, isNotNull);
      expect(restoredDocument.questions[1].prompt, contains('س4/ ضع كلمة (صح) أو (خطأ)'));
      expect(restoredDocument.questions[1].attachments.length, 1);
      expect(restoredDocument.questions[2].style.font, PaperFont.tajawal);
      expect(restoredDocument.questions[4].style.fontSize, 14);
      expect(restoredDocument.header.style.align, PaperAlign.center);
      expect(restoredDocument.settings.pageBorder, isTrue);

      // 20. تصدير PDF والتأكد من توليد بايتات صالحة
      final pdfEngine = PaginatedPdfExamEngine();
      final pdfBytes = await pdfEngine.generate(document: restoredDocument);
      expect(pdfBytes, isNotNull);
      expect(pdfBytes.length, greaterThan(1000));
      // الترويسة القياسية لملفات PDF تبدأ بـ %PDF
      expect(pdfBytes.sublist(0, 4), <int>[0x25, 0x50, 0x44, 0x46]);

      // 21. تصدير Word (DOCX) والتأكد من توليد ملف docx مضغوط صالح
      final docxBytes = await DocxDocumentExportService.buildDocumentDocxBytes(
        document: restoredDocument,
      );
      expect(docxBytes, isNotNull);
      expect(docxBytes.length, greaterThan(1000));
      // ملفات DOCX هي حزم ZIP تبدأ بـ PK (0x50, 0x4B)
      expect(docxBytes.sublist(0, 2), <int>[0x50, 0x4B]);
    });
  });
}
