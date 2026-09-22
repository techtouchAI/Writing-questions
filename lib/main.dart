import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'providers/exam_provider.dart';
import 'providers/question_provider.dart';
import 'views/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final questionProvider = QuestionProvider();
  final examProvider = ExamProvider();
  await Future.wait<void>(<Future<void>>[
    questionProvider.loadQuestions(),
    examProvider.loadData(),
  ]);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<QuestionProvider>.value(value: questionProvider),
        ChangeNotifierProvider<ExamProvider>.value(value: examProvider),
      ],
      child: const WritingQuestionsApp(),
    ),
  );
}

class WritingQuestionsApp extends StatelessWidget {
  const WritingQuestionsApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF1E3A8A),
      brightness: Brightness.light,
    );

    return MaterialApp(
      title: 'صانع ومحرر الأسئلة',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const <Locale>[
        Locale('ar'),
        Locale('en'),
      ],
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        appBarTheme: AppBarTheme(
          centerTitle: true,
          elevation: 0,
          backgroundColor: colorScheme.surface,
          foregroundColor: colorScheme.onSurface,
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
