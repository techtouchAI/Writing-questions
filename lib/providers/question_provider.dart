import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../models/difficulty.dart';
import '../models/question.dart';
import '../models/question_type.dart';
import '../services/storage_service.dart';

class QuestionProvider extends ChangeNotifier {
  QuestionProvider({StorageService? storageService})
      : _storageService = storageService ?? StorageService();

  final StorageService _storageService;

  List<Question> _questions = <Question>[];
  bool _isLoading = false;
  String? _errorMessage;
  String? _recoveryMessage;

  String _searchQuery = '';
  QuestionType? _selectedTypeFilter;
  Difficulty? _selectedDifficultyFilter;
  String? _selectedSubjectFilter;

  UnmodifiableListView<Question> get questions => UnmodifiableListView(_questions);
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String? get recoveryMessage => _recoveryMessage;
  String get searchQuery => _searchQuery;
  QuestionType? get selectedTypeFilter => _selectedTypeFilter;
  Difficulty? get selectedDifficultyFilter => _selectedDifficultyFilter;
  String? get selectedSubjectFilter => _selectedSubjectFilter;

  List<String> get availableSubjects {
    final subjects = _questions
        .map((question) => question.subject.trim())
        .where((subject) => subject.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return List<String>.unmodifiable(subjects);
  }

  List<Question> get filteredQuestions {
    final normalizedQuery = _searchQuery.trim().toLowerCase();
    return List<Question>.unmodifiable(
      _questions.where((question) {
        if (normalizedQuery.isNotEmpty) {
          final matchesQuery = <String>[
            question.title,
            question.topic,
            question.subject,
          ].any((value) => value.toLowerCase().contains(normalizedQuery));
          if (!matchesQuery) {
            return false;
          }
        }

        if (_selectedTypeFilter != null && question.type != _selectedTypeFilter) {
          return false;
        }
        if (_selectedDifficultyFilter != null &&
            question.difficulty != _selectedDifficultyFilter) {
          return false;
        }
        if (_selectedSubjectFilter != null &&
            question.subject != _selectedSubjectFilter) {
          return false;
        }
        return true;
      }),
    );
  }

  Future<void> loadQuestions() async {
    _isLoading = true;
    _errorMessage = null;
    _recoveryMessage = null;
    notifyListeners();

    try {
      final result = await _storageService.loadQuestions();
      _questions = result.items.map((question) => question.copyWith()).toList();

      if (_questions.isEmpty && !result.hadStoredValue) {
        _initSampleQuestions();
        await _storageService.saveQuestions(_questions);
      }

      if (result.recoveredFromCorruption) {
        _recoveryMessage =
            'تم تجاهل ${result.discardedEntries} سجل غير صالح أثناء استعادة بنك الأسئلة.';
      }
      _ensureSelectedSubjectIsAvailable();
    } catch (_) {
      _questions = <Question>[];
      _errorMessage =
          'تعذر تحميل بنك الأسئلة من مساحة التخزين المحلية. حاول إعادة تشغيل التطبيق.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> addQuestion(Question question) async {
    final previousQuestions = List<Question>.from(_questions);
    _questions.insert(0, question.copyWith());
    _errorMessage = null;
    notifyListeners();

    try {
      await _storageService.saveQuestions(_questions);
    } catch (_) {
      _questions = previousQuestions;
      _errorMessage = 'تعذر حفظ السؤال. تحقق من مساحة التخزين ثم أعد المحاولة.';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> updateQuestion(Question question) async {
    final index = _questions.indexWhere((item) => item.id == question.id);
    if (index == -1) {
      throw StateError('لا يمكن العثور على السؤال المطلوب تعديله.');
    }

    final previousQuestions = List<Question>.from(_questions);
    _questions[index] = question.copyWith();
    _errorMessage = null;
    _ensureSelectedSubjectIsAvailable();
    notifyListeners();

    try {
      await _storageService.saveQuestions(_questions);
    } catch (_) {
      _questions = previousQuestions;
      _ensureSelectedSubjectIsAvailable();
      _errorMessage = 'تعذر حفظ تعديلات السؤال. حاول مرة أخرى.';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> deleteQuestion(String id) async {
    final index = _questions.indexWhere((question) => question.id == id);
    if (index == -1) {
      return;
    }

    final previousQuestions = List<Question>.from(_questions);
    _questions.removeAt(index);
    _errorMessage = null;
    _ensureSelectedSubjectIsAvailable();
    notifyListeners();

    try {
      await _storageService.saveQuestions(_questions);
    } catch (_) {
      _questions = previousQuestions;
      _ensureSelectedSubjectIsAvailable();
      _errorMessage = 'تعذر حذف السؤال من مساحة التخزين. حاول مرة أخرى.';
      notifyListeners();
      rethrow;
    }
  }

  void setSearchQuery(String query) {
    if (_searchQuery == query) {
      return;
    }
    _searchQuery = query;
    notifyListeners();
  }

  void setTypeFilter(QuestionType? type) {
    if (_selectedTypeFilter == type) {
      return;
    }
    _selectedTypeFilter = type;
    notifyListeners();
  }

  void setDifficultyFilter(Difficulty? difficulty) {
    if (_selectedDifficultyFilter == difficulty) {
      return;
    }
    _selectedDifficultyFilter = difficulty;
    notifyListeners();
  }

  void setSubjectFilter(String? subject) {
    if (_selectedSubjectFilter == subject) {
      return;
    }
    _selectedSubjectFilter = subject;
    notifyListeners();
  }

  void resetFilters() {
    _searchQuery = '';
    _selectedTypeFilter = null;
    _selectedDifficultyFilter = null;
    _selectedSubjectFilter = null;
    notifyListeners();
  }

  void clearMessages() {
    if (_errorMessage == null && _recoveryMessage == null) {
      return;
    }
    _errorMessage = null;
    _recoveryMessage = null;
    notifyListeners();
  }

  void _ensureSelectedSubjectIsAvailable() {
    if (_selectedSubjectFilter != null &&
        !availableSubjects.contains(_selectedSubjectFilter)) {
      _selectedSubjectFilter = null;
    }
  }

  void _initSampleQuestions() {
    _questions = <Question>[
      Question(
        title: 'ما هي عاصمة جمهورية العراق؟',
        type: QuestionType.multipleChoice,
        difficulty: Difficulty.easy,
        marks: 2,
        subject: 'الجغرافيا والتاريخ',
        topic: 'عواصم العالم العربي',
        options: <QuestionOption>[
          QuestionOption(text: 'بغداد', isCorrect: true),
          QuestionOption(text: 'البصرة'),
          QuestionOption(text: 'الموصل'),
          QuestionOption(text: 'أربيل'),
        ],
        explanation: 'بغداد هي العاصمة الرسمية وأكبر مدن العراق.',
      ),
      Question(
        title: 'تدور الأرض حول الشمس في مدار دائري تماماً.',
        type: QuestionType.trueFalse,
        difficulty: Difficulty.medium,
        marks: 1.5,
        subject: 'العلوم العامة',
        topic: 'النظام الشمسي',
        options: <QuestionOption>[
          QuestionOption(text: 'صح'),
          QuestionOption(text: 'خطأ', isCorrect: true),
        ],
        explanation: 'مدار الأرض حول الشمس إهليلجي (بيضاوي) وليس دائرياً تماماً.',
      ),
      Question(
        title: 'تُعرف وحدة قياس شدة التيار الكهربائي في النظام الدولي بـ _____.',
        type: QuestionType.fillInTheBlank,
        difficulty: Difficulty.easy,
        marks: 2,
        subject: 'الفيزياء',
        topic: 'الكهرباء والمغناطيسية',
        modelAnswer: 'الأمبير (Ampere)',
        explanation: 'يقاس التيار الكهربائي بوحدة الأمبير تكريماً للعالم أندريه ماري أمبير.',
      ),
      Question(
        title:
            'ناقش أثر الطاقة الشمسية في تقليل الانبعاثات الكربونية ودورها في استدامة الشبكة الكهربائية الوطنية.',
        type: QuestionType.essay,
        difficulty: Difficulty.hard,
        marks: 5,
        subject: 'العلوم والبيئة',
        topic: 'الطاقة المتجددة',
        modelAnswer:
            '1- تقليل الاعتماد على الوقود الأحفوري\n2- خفض الانبعاثات الكربونية\n3- تخفيف الحمل على الشبكة وقت الذروة.',
        explanation: 'يتم توزيع الدرجات بناء على ذكر العناصر الثلاثة واستيفاء الشرح العلمي.',
      ),
    ];
  }
}
