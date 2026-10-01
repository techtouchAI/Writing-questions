import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// تخزين صورة إطار الصفحة (PNG شفاف) كملف في مساحة التطبيق.
///
/// الصورة لا تُدمج في JSON الورقة (فالحفظ التلقائي يعيد كتابة المكتبة كاملة
/// كل ثانيتين)؛ يُحفظ **مسارها** فقط في `PaperSettings.frameImagePath`،
/// ويقرؤها المعاينة مباشرةً من الملف، ويقرؤها التصدير عبر [read].
abstract final class PageFrameStore {
  static const String _directoryName = 'page_frames';

  /// يحفظ بايتات صورة الإطار في ملف جديد ويعيد مساره.
  static Future<String> save(List<int> bytes, {Directory? directory}) async {
    final root = directory ?? await _defaultDirectory();
    final folder = Directory('${root.path}${Platform.pathSeparator}$_directoryName');
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    final file = File(
      '${folder.path}${Platform.pathSeparator}${const Uuid().v4()}.png',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// يقرأ بايتات الإطار من [path]؛ `null` إن غاب المسار أو الملف أو تعذّرت القراءة
  /// (فيرتد التصدير إلى الإطار المتجه بدل أن يفشل).
  static Future<Uint8List?> read(String? path) async {
    if (path == null || path.isEmpty) {
      return null;
    }
    try {
      final file = File(path);
      if (!await file.exists()) {
        return null;
      }
      final bytes = await file.readAsBytes();
      return bytes.isEmpty ? null : bytes;
    } catch (_) {
      return null;
    }
  }

  /// يحذف ملف الإطار القديم إن وُجد (الفشل صامت: الملف يتيم فحسب).
  static Future<void> delete(String? path) async {
    if (path == null || path.isEmpty) {
      return;
    }
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // ملف يتيم لا يضرّ؛ لا يُسقط تغيير الإطار.
    }
  }

  static Future<Directory> _defaultDirectory() => getApplicationDocumentsDirectory();
}
