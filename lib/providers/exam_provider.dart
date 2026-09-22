import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../models/exam.dart';
import '../models/exam_header.dart';
import '../services/storage_service.dart';

class ExamProvider extends ChangeNotifier {
  ExamProvider({StorageService? storageService})
      : _storageService = storageService ?? StorageService();

  final StorageService _storageService;

  List<Exam> _exams = <Exam>[];
  ExamHeader _defaultHeader = ExamHeader();
  bool _isLoading = false;
  String? _errorMessage;
  String? _recoveryMessage;

  UnmodifiableListView<Exam> get exams => UnmodifiableListView(_exams);
  ExamHeader get defaultHeader => _defaultHeader;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String? get recoveryMessage => _recoveryMessage;

  Future<void> loadData() async {
    _isLoading = true;
    _errorMessage = null;
    _recoveryMessage = null;
    notifyListeners();

    try {
      final examsResult = await _storageService.loadExams();
      _exams = examsResult.items.map((exam) => exam.copyWith()).toList();
      _defaultHeader = await _storageService.loadDefaultHeader();

      if (examsResult.recoveredFromCorruption) {
        _recoveryMessage =
            'تم تجاهل ${examsResult.discardedEntries} اختبار غير صالح أثناء استعادة البيانات.';
      }
    } catch (_) {
      _exams = <Exam>[];
      _defaultHeader = ExamHeader();
      _errorMessage =
          'تعذر تحميل الاختبارات المحفوظة من مساحة التخزين المحلية.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> saveExam(Exam exam) async {
    final previousExams = List<Exam>.from(_exams);
    final index = _exams.indexWhere((item) => item.id == exam.id);
    if (index == -1) {
      _exams.insert(0, exam.copyWith());
    } else {
      _exams[index] = exam.copyWith();
    }
    _errorMessage = null;
    notifyListeners();

    try {
      await _storageService.saveExams(_exams);
    } catch (_) {
      _exams = previousExams;
      _errorMessage = 'تعذر حفظ الاختبار. حاول مرة أخرى.';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> deleteExam(String id) async {
    final index = _exams.indexWhere((exam) => exam.id == id);
    if (index == -1) {
      return;
    }

    final previousExams = List<Exam>.from(_exams);
    _exams.removeAt(index);
    _errorMessage = null;
    notifyListeners();

    try {
      await _storageService.saveExams(_exams);
    } catch (_) {
      _exams = previousExams;
      _errorMessage = 'تعذر حذف الاختبار من مساحة التخزين. حاول مرة أخرى.';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> updateDefaultHeader(ExamHeader header) async {
    final previousHeader = _defaultHeader;
    _defaultHeader = header;
    _errorMessage = null;
    notifyListeners();

    try {
      await _storageService.saveDefaultHeader(header);
    } catch (_) {
      _defaultHeader = previousHeader;
      _errorMessage = 'تعذر حفظ الترويسة الافتراضية. حاول مرة أخرى.';
      notifyListeners();
      rethrow;
    }
  }

  void clearMessages() {
    if (_errorMessage == null && _recoveryMessage == null) {
      return;
    }
    _errorMessage = null;
    _recoveryMessage = null;
    notifyListeners();
  }
}
