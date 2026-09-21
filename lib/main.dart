import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'providers/exam_provider.dart';
import 'providers/question_provider.dart';
import 'views/home_screen.dart';

Future<void> main() async {
  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Surface framework errors to the console/aggregate crash reporting
    // without taking the whole app down.
    FlutterError.onError = FlutterError.presentError;

    final questionProvider = QuestionProvider();
    final examProvider = ExamProvider();

    // Load persisted data before the first frame so the UI starts settled.
    await Future.wait([
      questionProvider.loadQuestions(),
      examProvider.loadData(),
    ]);

    runApp(
      WritingQuestionsApp(
        questionProvider: questionProvider,
        examProvider: examProvider,
      ),
    );
  }, (error, stackTrace) {
    if (kDebugMode) {
      FlutterError.presentError(
        FlutterErrorDetails(exception: error, stack: stackTrace, library: 'app'),
      );
    }
  });
}

class WritingQuestionsApp extends StatelessWidget {
  const WritingQuestionsApp({
    super.key,
    required this.questionProvider,
    required this.examProvider,
  });

  final QuestionProvider questionProvider;
  final ExamProvider examProvider;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF1E3A8A),
      brightness: Brightness.light,
    );

    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: questionProvider),
        ChangeNotifierProvider.value(value: examProvider),
      ],
      child: MaterialApp(
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
          colorScheme: colorScheme,
          appBarTheme: AppBarTheme(
            centerTitle: true,
            elevation: 0,
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
          ),
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
