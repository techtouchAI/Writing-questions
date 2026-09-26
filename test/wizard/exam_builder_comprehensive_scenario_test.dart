import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/floating_element.dart';
import 'package:writing_questions_app/models/paper_divider.dart';
import 'package:writing_questions_app/models/paper_font.dart';
import 'package:writing_questions_app/models/paper_text_style.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/models/question_type.dart';
import 'package:writing_questions_app/providers/exam_wizard_controller.dart';
import 'package:writing_questions_app/services/docx_document_export_service.dart';
import 'package:writing_questions_app/services/pdf_export_service.dart';
import 'package:writing_questions_app/services/storage_service.dart';

/// صورة PNG صالحة 1×1 (شفافة) لتضمينها في سيناريو الاختبار.
const String _tinyPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

ExamDocument _seedDocument() {
  return ExamDocument(
    name: 'امتحان نصف السنة — اللغة العربية',
    header: ExamHeaderModel.ministerialDefault(subject: 'اللغة العربية'),
    questions: <QuestionModel>[QuestionModel(questionNumber: 1)],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('سيناريو بناء الورقة الشامل (دورة العمل الكاملة)', () {
    test('يبني ورقة من 6 أسئلة ويحررها ويحفظها ويصدّرها دون فقدان', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = ExamWizardController(document: _seedDocument());

      // ─── 1) بناء ورقة كاملة: ترويسة وزارية + 6 أسئلة ───
      for (var i = 0; i < 5; i++) {
        controller.addQuestion();
      }
      expect(controller.questions, hasLength(6));

      // س1: 4 فروع بنصوص مميزة.
      for (var i = 0; i < 3; i++) {
        controller.addBranch(0);
      }
      for (var b = 0; b < 4; b++) {
        final ref = BranchRef(questionIndex: 0, branchIndex: b);
        controller.updateBranchContent(
          ref,
          controller.document.branchAt(ref).content.copyWith(text: 'نص الفرع ${b + 1}'),
        );
        controller.updateBranchMarks(ref, 5);
      }

      // س2: 3 فروع.
      controller.addBranch(1);
      controller.addBranch(1);
      expect(controller.questions[1].branches, hasLength(3));

      // س3: فراغات من 10 نقاط.
      const q3 = BranchRef(questionIndex: 2, branchIndex: 0);
      controller.updateBranchType(q3, QuestionType.fillInTheBlank);
      controller.setBranchItemCount(q3, 10);
      for (var i = 0; i < 10; i++) {
        controller.updateBranchItemText(q3, i, 'فراغ رقم ${i + 1} _____');
      }

      // س4: صح وخطأ من 7 نقاط مع إجابات نموذج المعلم.
      const q4 = BranchRef(questionIndex: 3, branchIndex: 0);
      controller.updateBranchType(q4, QuestionType.trueFalse);
      controller.setBranchItemCount(q4, 7);
      for (var i = 0; i < 7; i++) {
        controller.updateBranchItemText(q4, i, 'عبارة رقم ${i + 1}');
        controller.updateBranchItemAnswer(q4, i, i.isEven);
      }
      controller.updateQuestionPrompt(3, 'سؤال صح وخطأ');

      // س5: «أجب عن فرعين فقط» من 4 فروع.
      controller.updateQuestionPrompt(4, 'أجب عن فرعين فقط:');
      for (var i = 0; i < 3; i++) {
        controller.addBranch(4);
      }

      // س6: مقالي مع صورة مرفقة.
      final pngBytes = base64Decode(_tinyPngBase64);
      controller.addQuestionAttachment(
        FloatingElement(
          type: FloatingElementType.image,
          bytes: pngBytes,
          dx: 12,
          dy: 12,
          width: 120,
          height: 90,
        ),
        questionIndex: 5,
      );
      expect(controller.questions[5].attachments, hasLength(1));

      // ─── 2) تعديل نص س1 ───
      controller.updateBranchContent(
        const BranchRef(questionIndex: 0, branchIndex: 0),
        controller.document
            .branchAt(const BranchRef(questionIndex: 0, branchIndex: 0))
            .content
            .copyWith(text: 'نص الفرع الأول بعد التعديل'),
      );
      expect(
        controller.document.branchAt(const BranchRef(questionIndex: 0, branchIndex: 0)).content.text,
        'نص الفرع الأول بعد التعديل',
      );

      // ─── 3) حذف فرع من س1 ───
      controller.removeBranch(const BranchRef(questionIndex: 0, branchIndex: 3));
      expect(controller.questions[0].branches, hasLength(3));

      // ─── 4) إضافة فرع جديد إلى س1 ───
      controller.addBranch(0);
      expect(controller.questions[0].branches, hasLength(4));

      // ─── 5) نقل س4 إلى مكان س2 ───
      controller.moveQuestion(3, 1);
      expect(controller.questions[1].prompt, 'سؤال صح وخطأ');
      expect(controller.questions, hasLength(6));

      // ─── 6) نقل فرع داخل س1 ───
      controller.moveBranch(0, 0, 1);
      expect(
        controller.document.branchAt(const BranchRef(questionIndex: 0, branchIndex: 1)).content.text,
        'نص الفرع الأول بعد التعديل',
      );

      // ─── 7) إضافة صورة جديدة إلى السؤال ───
      controller.addAttachment(
        FloatingElement(
          type: FloatingElementType.image,
          bytes: pngBytes,
          dx: 8,
          dy: 8,
          width: 100,
          height: 80,
        ),
        ref: const BranchRef(questionIndex: 0, branchIndex: 0),
      );
      // ─── 8) إضافة شكل مربع ───
      controller.addQuestionAttachment(
        FloatingElement(
          type: FloatingElementType.shape,
          shape: FloatingShapeType.square,
          dx: 20,
          dy: 40,
          width: 90,
          height: 90,
        ),
        questionIndex: 0,
      );

      // ─── 9) إضافة فاصل بعد السؤال الأول ───
      controller.setQuestionDivider(0, const PaperDivider(thickness: 2));
      expect(controller.questions[0].dividerAfter, isNotNull);

      // ─── 10) تغيير خط س3 إلى Tajawal ───
      // (س3 الآن في الفهرس 3 بعد نقل س4 أمامه).
      final q3Now = BranchRef(questionIndex: 3, branchIndex: 0);
      expect(
        controller.document.branchAt(q3Now).content.type,
        QuestionType.fillInTheBlank,
      );
      controller.updateBranchStyle(q3Now, const PaperTextStyle(font: PaperFont.tajawal));
      expect(
        controller.document.branchAt(q3Now).style.font,
        PaperFont.tajawal,
      );

      // ─── 11) تغيير حجم خط س5 إلى 14 ───
      // (س5 الآن في الفهرس 4 — لم يتأثر بالنقل).
      const q5Now = BranchRef(questionIndex: 4, branchIndex: 0);
      controller.updateBranchStyle(q5Now, const PaperTextStyle(fontSize: 14));
      expect(
        controller.document.branchAt(q5Now).style.fontSize,
        14,
      );

      // ─── 12) توسيط الترويسة ───
      controller.updateHeaderStyle(
        controller.document.header.style.copyWith(align: () => PaperAlign.center),
      );
      expect(controller.document.header.style.align, PaperAlign.center);

      final document = controller.document;
      expect(document.questions, hasLength(6));

      // ─── 13) حفظ المستند وتحويله إلى صيغة التخزين JSON ───
      final jsonString = jsonEncode(document.toMap());
      expect(jsonString, isNotEmpty);

      final storage = StorageService(prefs: prefs);
      await storage.saveExamDocuments([document]);

      // ─── 14) استعادة المستند ومطابقة كل شيء ───
      final restored = ExamDocument.fromMap(
        jsonDecode(jsonString) as Map<String, dynamic>,
      );
      // مطابقة عميقة: الأسئلة والفروع والنقاط والتنسيقات والمرفقات والفواصل.
      expect(restored.toMap(), document.toMap());
      expect(restored.questions, hasLength(6));
      expect(restored.questions[0].branches, hasLength(4));
      expect(restored.questions[0].dividerAfter?.thickness, 2);
      expect(restored.questions[4].prompt, 'أجب عن فرعين فقط:');
      final restoredItems =
          restored.branchAt(const BranchRef(questionIndex: 1, branchIndex: 0)).content.items;
      expect(restoredItems, hasLength(7));
      expect(restoredItems.first.isCorrect, isTrue);
      expect(restored.header.style.align, PaperAlign.center);

      final loaded = await storage.loadExamDocuments();
      expect(loaded.items, hasLength(1));
      expect(loaded.items.first.toMap(), document.toMap());

      // ─── 15) توليد PDF صالح ───
      final pdfBytes = await PdfExportService.buildDocumentPdfBytes(document: document);
      expect(pdfBytes.length, greaterThan(1000));
      expect(String.fromCharCodes(pdfBytes.take(4)), '%PDF');

      // ─── 16) توليد Word صالح ───
      final docxBytes =
          await DocxDocumentExportService.buildDocumentDocxBytes(document: document);
      expect(docxBytes.length, greaterThan(1000));
      expect(docxBytes[0], 0x50); // 'P'
      expect(docxBytes[1], 0x4B); // 'K'
    });
  });
}
