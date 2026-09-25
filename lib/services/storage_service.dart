import 'package:shared_preferences/shared_preferences.dart';

import '../models/exam_document.dart';

class StorageLoadResult<T> {
  const StorageLoadResult({
    required this.items,
    required this.hadStoredValue,
    this.discardedEntries = 0,
  });

  final List<T> items;
  final bool hadStoredValue;
  final int discardedEntries;

  bool get recoveredFromCorruption => discardedEntries > 0;
}

class StorageService {
  StorageService({
    SharedPreferences? prefs,
    Future<SharedPreferences> Function()? preferencesLoader,
  })  : assert(prefs == null || preferencesLoader == null),
        _preferencesLoader =
            preferencesLoader ?? _createPreferencesLoader(prefs);

  static const String _examDocumentsKey = 'app_saved_exam_documents';
  static const String _lastOpenDocumentKey = 'app_last_open_document_id';

  final Future<SharedPreferences> Function() _preferencesLoader;
  Future<SharedPreferences>? _preferences;

  static Future<SharedPreferences> Function() _createPreferencesLoader(
    SharedPreferences? prefs,
  ) {
    if (prefs != null) {
      return () => Future<SharedPreferences>.value(prefs);
    }
    return SharedPreferences.getInstance;
  }

  /// النماذج الوزارية المنشأة عبر المعالج المتسلسل (Wizard).
  Future<StorageLoadResult<ExamDocument>> loadExamDocuments() {
    return _loadList(_examDocumentsKey, ExamDocument.fromJson);
  }

  Future<void> saveExamDocuments(List<ExamDocument> documents) {
    return _saveList(
      _examDocumentsKey,
      documents.map((document) => document.toJson()),
    );
  }

  /// هوية آخر نموذج وزاري فُتح (للمتابعة من حيث توقف المدرس).
  Future<String?> loadLastOpenDocumentId() async {
    final preferences = await _getPreferences();
    final id = preferences.getString(_lastOpenDocumentKey);
    return id == null || id.isEmpty ? null : id;
  }

  Future<void> saveLastOpenDocumentId(String? id) async {
    final preferences = await _getPreferences();
    if (id == null || id.isEmpty) {
      await preferences.remove(_lastOpenDocumentKey);
      return;
    }
    final saved = await preferences.setString(_lastOpenDocumentKey, id);
    if (!saved) {
      throw StateError('تعذر حفظ آخر نموذج مفتوح على الجهاز.');
    }
  }

  Future<StorageLoadResult<T>> _loadList<T>(
    String key,
    T Function(String source) decoder,
  ) async {
    final preferences = await _getPreferences();
    final storedItems = preferences.getStringList(key);
    final savedItems = storedItems ?? const <String>[];
    final items = <T>[];
    var discardedEntries = 0;

    for (final savedItem in savedItems) {
      try {
        items.add(decoder(savedItem));
      } catch (_) {
        // Keep valid local records available even if one older/corrupt record fails.
        discardedEntries++;
      }
    }

    return StorageLoadResult<T>(
      items: List<T>.unmodifiable(items),
      hadStoredValue: storedItems != null,
      discardedEntries: discardedEntries,
    );
  }

  Future<void> _saveList(String key, Iterable<String> values) async {
    final preferences = await _getPreferences();
    final saved = await preferences.setStringList(key, values.toList(growable: false));
    if (!saved) {
      throw StateError('تعذر حفظ البيانات على الجهاز.');
    }
  }

  Future<SharedPreferences> _getPreferences() {
    return _preferences ??= _preferencesLoader();
  }
}
