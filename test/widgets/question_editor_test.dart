import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:writing_questions_app/models/question_type.dart';
import 'package:writing_questions_app/providers/question_provider.dart';
import 'package:writing_questions_app/views/question_editor_screen.dart';

Widget _wrap(Widget child, QuestionProvider provider) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<QuestionProvider>.value(value: provider),
    ],
    child: MaterialApp(
      locale: const Locale('ar', 'SA'),
      supportedLocales: const [Locale('ar', 'SA')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: child,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('rejects saving an empty question', (tester) async {
    final provider = QuestionProvider();
    await provider.loadQuestions();
    final baseline = provider.questions.length;

    await tester.pumpWidget(_wrap(const QuestionEditorScreen(), provider));
    await tester.tap(find.byIcon(Icons.check));
    await tester.pump();

    expect(provider.questions, hasLength(baseline));
    expect(find.text('يرجى إدخال نص السؤال.'), findsOneWidget);
  });

  testWidgets('saves a true/false question into the bank', (tester) async {
    final provider = QuestionProvider();
    await provider.loadQuestions();
    final baseline = provider.questions.length;

    await tester.pumpWidget(_wrap(const QuestionEditorScreen(), provider));

    // Fill the question text.
    await tester.enterText(find.byType(TextFormField).first, 'الشمس نجم ثابت');

    // Switch the question type to true/false through the dropdown.
    await tester.tap(find.byType(DropdownButtonFormField<QuestionType>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('صح أو خطأ').last);
    await tester.pumpAndSettle();

    // Save from the app bar action.
    await tester.tap(find.byIcon(Icons.check));
    await tester.pump();

    expect(provider.questions, hasLength(baseline + 1));
    expect(provider.questions.first.title, 'الشمس نجم ثابت');
    expect(provider.questions.first.type, QuestionType.trueFalse);
    expect(provider.questions.first.options.map((o) => o.text).toSet(), {'صح', 'خطأ'});
    expect(provider.questions.first.options.where((o) => o.isCorrect).single.text, 'صح');
  });
}
