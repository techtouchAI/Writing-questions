import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../models/exam_document.dart';
import '../services/storage_service.dart';

/// مخزن النماذج الوزارية المنشأة عبر المعالج المتسلسل، مع حفظ ذري
/// وتراجع عند فشل الكتابة.
class ExamDocumentProvider extends ChangeNotifier {
  ExamDocumentProvider({StorageService? storageService})
      : _storageService = storageService ?? StorageService();

  final StorageService _storageService;

  List<ExamDocument> _documents = <ExamDocument>[];
  bool _isLoading = false;
  String? _errorMessage;
  String? _recoveryMessage;
  String? _lastOpenDocumentId;

  UnmodifiableListView<ExamDocument> get documents => UnmodifiableListView(_documents);
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String? get recoveryMessage => _recoveryMessage;

  /// هوية آخر ورقة فُتحت في المحرر (لمتابعة العمل من حيث توقف المدرس).
  String? get lastOpenDocumentId => _lastOpenDocumentId;

  /// آخر ورقة فُتحت — `null` إن حُذفت أو لم تُفتح أي ورقة بعد.
  ExamDocument? get lastOpenDocument =>
      _lastOpenDocumentId == null ? null : documentById(_lastOpenDocumentId!);

  Future<void> loadDocuments() async {
    _isLoading = true;
    _errorMessage = null;
    _recoveryMessage = null;
    notifyListeners();

    try {
      final result = await _storageService.loadExamDocuments();
      _documents = List<ExamDocument>.of(result.items);
      if (result.recoveredFromCorruption) {
        _recoveryMessage =
            'تم تجاهل ${result.discardedEntries} نموذج غير صالح أثناء استعادة البيانات.';
      }
      try {
        _lastOpenDocumentId = await _storageService.loadLastOpenDocumentId();
      } catch (_) {
        _lastOpenDocumentId = null;
      }
    } catch (_) {
      _documents = <ExamDocument>[];
      _errorMessage = 'تعذر تحميل النماذج الوزارية المحفوظة من مساحة التخزين.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> saveDocument(ExamDocument document) async {
    final previous = List<ExamDocument>.of(_documents);
    final index = _documents.indexWhere((item) => item.id == document.id);
    if (index == -1) {
      _documents.insert(0, document);
    } else {
      _documents[index] = document;
    }
    _errorMessage = null;
    notifyListeners();

    try {
      await _storageService.saveExamDocuments(_documents);
    } catch (_) {
      _documents = previous;
      _errorMessage = 'تعذر حفظ النموذج. حاول مرة أخرى.';
      notifyListeners();
      rethrow;
    }
  }

  /// ينسخ ورقة كاملة بهوية جديدة (لـ«نسخ» في المكتبة) ويعيد النسخة.
  Future<ExamDocument> duplicateDocument(String id) async {
    final index = _documents.indexWhere((item) => item.id == id);
    if (index == -1) {
      throw StateError('الورقة غير موجودة.');
    }
    final copy = _documents[index].duplicated();
    await saveDocument(copy);
    return copy;
  }

  /// يعيد تسمية ورقة في المكتبة.
  Future<void> renameDocument(String id, String name) async {
    final index = _documents.indexWhere((item) => item.id == id);
    if (index == -1) {
      return;
    }
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == _documents[index].name) {
      return;
    }
    await saveDocument(_documents[index].renamed(trimmed));
  }

  ExamDocument? documentById(String id) {
    for (final document in _documents) {
      if (document.id == id) {
        return document;
      }
    }
    return null;
  }

  /// يحفظ هوية آخر ورقة فُتحت (لافتة «متابعة العمل» في الرئيسية).
  ///
  /// صامت: الفشل هنا لا يقطع التحرير ولا يُظهر خطأ للمدرس.
  Future<void> saveLastOpenDocumentId(String? id) async {
    _lastOpenDocumentId = id;
    notifyListeners();
    try {
      await _storageService.saveLastOpenDocumentId(id);
    } catch (_) {
      // تجاهل صامت — استعادة الجلسة تحسين اختياري لا يمنع العمل.
    }
  }

  Future<void> deleteDocument(String id) async {
    final index = _documents.indexWhere((item) => item.id == id);
    if (index == -1) {
      return;
    }
    final previous = List<ExamDocument>.of(_documents);
    _documents.removeAt(index);
    if (_lastOpenDocumentId == id) {
      _lastOpenDocumentId = null;
      try {
        await _storageService.saveLastOpenDocumentId(null);
      } catch (_) {
        // تجاهل صامت.
      }
    }
    _errorMessage = null;
    notifyListeners();

    try {
      await _storageService.saveExamDocuments(_documents);
    } catch (_) {
      _documents = previous;
      _errorMessage = 'تعذر حذف النموذج من مساحة التخزين. حاول مرة أخرى.';
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
