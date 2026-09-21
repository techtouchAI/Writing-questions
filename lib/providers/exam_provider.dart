import 'package:flutter/foundation.dart';
import '../models/exam.dart';
import '../models/exam_header.dart';
import '../services/storage_service.dart';

class ExamProvider with ChangeNotifier {
  final StorageService _storageService = StorageService();

  List<Exam> _exams = [];
  ExamHeader _defaultHeader = ExamHeader();
  bool _isLoading = false;

  List<Exam> get exams => _exams;
  ExamHeader get defaultHeader => _defaultHeader;
  bool get isLoading => _isLoading;

  Future<void> loadData() async {
    _isLoading = true;
    notifyListeners();
    _exams = await _storageService.loadExams();
    _defaultHeader = await _storageService.loadDefaultHeader();
    _isLoading = false;
    notifyListeners();
  }

  Future<void> saveExam(Exam exam) async {
    final index = _exams.indexWhere((e) => e.id == exam.id);
    if (index != -1) {
      _exams[index] = exam;
    } else {
      _exams.insert(0, exam);
    }
    await _storageService.saveExams(_exams);
    notifyListeners();
  }

  Future<void> deleteExam(String id) async {
    _exams.removeWhere((e) => e.id == id);
    await _storageService.saveExams(_exams);
    notifyListeners();
  }

  Future<void> updateDefaultHeader(ExamHeader header) async {
    _defaultHeader = header;
    await _storageService.saveDefaultHeader(header);
    notifyListeners();
  }
}
