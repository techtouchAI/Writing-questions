import 'package:flutter/foundation.dart';
import '../models/question.dart';
import '../models/question_type.dart';
import '../models/difficulty.dart';
import '../services/storage_service.dart';

class QuestionProvider with ChangeNotifier {
  final StorageService _storageService = StorageService();

  List<Question> _questions = [];
  bool _isLoading = false;

  // Filter state
  String _searchQuery = '';
  QuestionType? _selectedTypeFilter;
  Difficulty? _selectedDifficultyFilter;
  String _selectedSubjectFilter = 'الكل';

  List<Question> get questions => _questions;
  bool get isLoading => _isLoading;
  String get searchQuery => _searchQuery;
  QuestionType? get selectedTypeFilter => _selectedTypeFilter;
  Difficulty? get selectedDifficultyFilter => _selectedDifficultyFilter;
  String get selectedSubjectFilter => _selectedSubjectFilter;

  List<String> get availableSubjects {
    final set = {'الكل'};
    for (final q in _questions) {
      if (q.subject.trim().isNotEmpty) {
        set.add(q.subject.trim());
      }
    }
    return set.toList();
  }

  List<Question> get filteredQuestions {
    return _questions.where((q) {
      if (_searchQuery.isNotEmpty) {
        final matchesTitle = q.title.toLowerCase().contains(_searchQuery.toLowerCase());
        final matchesTopic = q.topic.toLowerCase().contains(_searchQuery.toLowerCase());
        if (!matchesTitle && !matchesTopic) return false;
      }
      if (_selectedTypeFilter != null && q.type != _selectedTypeFilter) {
        return false;
      }
      if (_selectedDifficultyFilter != null && q.difficulty != _selectedDifficultyFilter) {
        return false;
      }
      if (_selectedSubjectFilter != 'الكل' && q.subject != _selectedSubjectFilter) {
        return false;
      }
      return true;
    }).toList();
  }

  Future<void> loadQuestions() async {
    _isLoading = true;
    notifyListeners();
    _questions = await _storageService.loadQuestions();
    
    // If empty on first launch, add some sample questions
    if (_questions.isEmpty) {
      _initSampleQuestions();
      await _storageService.saveQuestions(_questions);
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> addQuestion(Question question) async {
    _questions.insert(0, question);
    await _storageService.saveQuestions(_questions);
    notifyListeners();
  }

  Future<void> updateQuestion(Question question) async {
    final index = _questions.indexWhere((q) => q.id == question.id);
    if (index != -1) {
      _questions[index] = question;
      await _storageService.saveQuestions(_questions);
      notifyListeners();
    }
  }

  Future<void> deleteQuestion(String id) async {
    _questions.removeWhere((q) => q.id == id);
    await _storageService.saveQuestions(_questions);
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void setTypeFilter(QuestionType? type) {
    _selectedTypeFilter = type;
    notifyListeners();
  }

  void setDifficultyFilter(Difficulty? difficulty) {
    _selectedDifficultyFilter = difficulty;
    notifyListeners();
  }

  void setSubjectFilter(String subject) {
    _selectedSubjectFilter = subject;
    notifyListeners();
  }

  void resetFilters() {
    _searchQuery = '';
    _selectedTypeFilter = null;
    _selectedDifficultyFilter = null;
    _selectedSubjectFilter = 'الكل';
    notifyListeners();
  }

  void _initSampleQuestions() {
    _questions = [
      Question(
        title: 'ما هي عاصمة جمهورية العراق؟',
        type: QuestionType.multipleChoice,
        difficulty: Difficulty.easy,
        marks: 2.0,
        subject: 'الجغرافيا والتاريخ',
        topic: 'عواصم العالم العربي',
        options: [
          QuestionOption(text: 'بغداد', isCorrect: true),
          QuestionOption(text: 'البصرة', isCorrect: false),
          QuestionOption(text: 'الموصل', isCorrect: false),
          QuestionOption(text: 'أربيل', isCorrect: false),
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
        options: [
          QuestionOption(text: 'صح', isCorrect: false),
          QuestionOption(text: 'خطأ', isCorrect: true),
        ],
        explanation: 'مدار الأرض حول الشمس إهليلجي (بيضاوي) وليس دائرياً تماماً.',
      ),
      Question(
        title: 'تُعرف وحدة قياس شدة التيار الكهربائي في النظام الدولي بـ _____.',
        type: QuestionType.fillInTheBlank,
        difficulty: Difficulty.easy,
        marks: 2.0,
        subject: 'الفيزياء',
        topic: 'الكهرباء والمغناطيسية',
        modelAnswer: 'الأمبير (Ampere)',
        explanation: 'يقاس التيار الكهربائي بوحدة الأمبير تكريماً للعالم أندريه ماري أمبير.',
      ),
      Question(
        title: 'ناقش أثر الطاقة الشمسية في تقليل الانبعاثات الكربونية ودورها في استدامة الشبكة الكهربائية الوطنية.',
        type: QuestionType.essay,
        difficulty: Difficulty.hard,
        marks: 5.0,
        subject: 'العلوم والبيئة',
        topic: 'الطاقة المتجددة',
        modelAnswer: '1- تقليل الاعتماد على الوقود الأحفوري\n2- خفض الانبعاثات الكربونية\n3- تخفيف الحمل على الشبكة وقت الذروة.',
        explanation: 'يتم توزيع الدرجات بناء على ذكر العناصر الثلاثة واستيفاء الشرح العلمي.',
      ),
    ];
  }
}
