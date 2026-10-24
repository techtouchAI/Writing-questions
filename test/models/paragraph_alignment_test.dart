// المحاذاة خاصية **فقرة** لا خاصية محارف ولا خاصية عنصر كامل:
//
// - فقرة عنوان السؤال (`titleAlign`) وفقرة نصّه (`bodyAlign`) مستقلتان.
// - فقرة عنوان الفرع (`BranchModel.titleAlign`) وفقرة نصّه (`bodyAlign`)
//   مستقلتان، بدل المحاذاة الوحيدة المشتركة في `style.align`.
// - تغيير إحداهما لا يحرّك الأخرى، والتراجع خطوة واحدة، والحفظ يحفظ الاثنتين.
import 'package:flutter_test/flutter_test.dart';

import 'package:writing_questions_app/models/branch_item.dart';
import 'package:writing_questions_app/models/branch_model.dart';
import 'package:writing_questions_app/models/exam_document.dart';
import 'package:writing_questions_app/models/exam_header_model.dart';
import 'package:writing_questions_app/models/paper_text_style.dart';
import 'package:writing_questions_app/models/question_model.dart';
import 'package:writing_questions_app/providers/exam_wizard_controller.dart';

ExamDocument _document() => ExamDocument(
      name: 'محاذاة الفقرات',
      header: ExamHeaderModel.initial(subject: 'الرياضيات'),
      questions: <QuestionModel>[
        QuestionModel(
          id: 'q1',
          questionNumber: 1,
          statement: 'نص السؤال',
          body: 'متن السؤال',
          items: <BranchItem>[BranchItem(id: 'i1', text: 'نقطة')],
          branches: <BranchModel>[
            BranchModel(
              id: 'b1',
              content: BranchContent(statement: 'منطوق الفرع', body: 'نص الفرع'),
            ),
          ],
        ),
      ],
    );

void main() {
  test('محاذاة متن السؤال لا تحرّك محاذاة عنوانه', () {
    final controller = ExamWizardController(document: _document());
    addTearDown(controller.dispose);

    controller.updateQuestionBodyAlign(0, PaperAlign.center);
    final question = controller.questions.single;
    expect(question.bodyAlign, PaperAlign.center);
    expect(question.titleAlign, isNull,
        reason: 'محاذاة النصّ كُتبت على محاذاة العنوان.');
    expect(question.titleAlign ?? question.style.align, isNull,
        reason: 'العنوان ورث محاذاة النصّ عبر style.align.');

    // والتراجع خطوة واحدة يعيد النصّ إلى ما كان.
    controller.undo();
    expect(controller.questions.single.bodyAlign, isNull);
  });

  test('محاذاة عنوان الفرع ونصّه مستقلتان (ولا تعتمد على style وحده)', () {
    final controller = ExamWizardController(document: _document());
    addTearDown(controller.dispose);
    const ref = BranchRef(questionIndex: 0, branchIndex: 0);

    controller.updateBranchBodyAlign(ref, PaperAlign.center);
    var branch = controller.document.branchAt(ref);
    expect(branch.bodyAlign, PaperAlign.center);
    expect(branch.titleAlign, isNull,
        reason: 'محاذاة نصّ الفرع كُتبت على عنوانه.');
    expect(branch.titleAlign ?? branch.style.align, isNull,
        reason: 'عنوان الفرع ورث محاذاة نصّه.');

    controller.updateBranchTitleAlign(ref, PaperAlign.left);
    branch = controller.document.branchAt(ref);
    expect(branch.titleAlign, PaperAlign.left);
    expect(branch.bodyAlign, PaperAlign.center,
        reason: 'محاذاة عنوان الفرع محت نصّه.');

    // حفظ وإعادة قراءة: الحقلان مستقلان كما هما.
    final restored = ExamDocument.fromMap(controller.document.toMap());
    final restoredBranch = restored.branchAt(ref);
    expect(restoredBranch.titleAlign, PaperAlign.left);
    expect(restoredBranch.bodyAlign, PaperAlign.center);
  });

  test('مستند قديم بلا حقول محاذاة فقرة يقرأ بمحاذاة النمط (توافق)', () {
    final map = _document().toMap();
    final branchMap =
        ((map['questions'] as List).first as Map)['branches'] as List;
    final first = Map<String, dynamic>.from(branchMap.first as Map);
    first.remove('titleAlign');
    first.remove('bodyAlign');
    first['style'] = <String, dynamic>{'align': 'center'};
    final restored = BranchModel.fromMap(first);
    expect(restored.titleAlign, isNull);
    expect(restored.bodyAlign, isNull);
    expect(restored.titleAlign ?? restored.style.align, PaperAlign.center);
    expect(restored.bodyAlign ?? restored.style.align, PaperAlign.center);
  });
}
