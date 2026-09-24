import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:writing_questions_app/main.dart';
import 'package:writing_questions_app/providers/exam_document_provider.dart';
import 'package:writing_questions_app/providers/exam_provider.dart';
import 'package:writing_questions_app/providers/question_provider.dart';

void main() {
  testWidgets('renders the Arabic dashboard with empty in-memory providers', (
    tester,
  ) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<QuestionProvider>(
            create: (_) => QuestionProvider(),
          ),
          ChangeNotifierProvider<ExamProvider>(create: (_) => ExamProvider()),
          ChangeNotifierProvider<ExamDocumentProvider>(
            create: (_) => ExamDocumentProvider(),
          ),
        ],
        child: const WritingQuestionsApp(),
      ),
    );

    expect(find.text('صانع ومحرر الأسئلة'), findsOneWidget);
    expect(find.text('الإجراءات السريعة'), findsOneWidget);
    expect(find.text('نموذج وزاري جديد (معالج متسلسل)'), findsOneWidget);
  });
}
