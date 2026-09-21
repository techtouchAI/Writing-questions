import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'providers/question_provider.dart';
import 'providers/exam_provider.dart';
import 'views/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final questionProvider = QuestionProvider();
  final examProvider = ExamProvider();

  // Load local data
  await questionProvider.loadQuestions();
  await examProvider.loadData();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: questionProvider),
        ChangeNotifierProvider.value(value: examProvider),
      ],
      child: const WritingQuestionsApp(),
    ),
  );
}

class WritingQuestionsApp extends StatelessWidget {
  const WritingQuestionsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'صانع ومحرر الأسئلة',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar', 'SA'),
      supportedLocales: const [
        Locale('ar', 'SA'),
        Locale('en', 'US'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Roboto',
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E3A8A),
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
