import 'dart:developer' as developer;
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'export_file_name.dart';

/// A user-facing export failure carrying an already-localized message.
class ExportException implements Exception {
  const ExportException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Common file-system and sharing operations for generated exports.
abstract final class ExportFileService {
  static String sanitizeFileName(String raw) {
    return ExportFileName.fileStem(value: raw, fallbackStem: 'export');
  }

  static String sanitizeSheetName(String raw) {
    return ExportFileName.excelSheetName(raw, fallback: 'Sheet1');
  }

  /// Writes [bytes] to [destination], or to the application documents
  /// directory when a destination is not supplied. The timestamp avoids
  /// overwriting a previous export with the same user-facing name.
  static Future<File> writeExportFile({
    required String baseName,
    required String extension,
    required List<int> bytes,
    Directory? destination,
  }) async {
    final directory = destination ?? await getApplicationDocumentsDirectory();
    await directory.create(recursive: true);

    final normalizedExtension =
        extension.startsWith('.') ? extension.toLowerCase() : '.${extension.toLowerCase()}';
    final trimmedBaseName = baseName.trim();
    final baseStem = trimmedBaseName.toLowerCase().endsWith(normalizedExtension)
        ? trimmedBaseName.substring(
            0,
            trimmedBaseName.length - normalizedExtension.length,
          )
        : trimmedBaseName;
    final fileName = ExportFileName.fileName(
      value: '${baseStem}_${DateTime.now().millisecondsSinceEpoch}',
      extension: normalizedExtension,
      fallbackStem: 'export',
    );
    final file = File('${directory.path}${Platform.pathSeparator}$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// Opens the system share sheet for a generated file.
  static Future<void> shareExportFile(
    File file, {
    required String mimeType,
    String? subject,
  }) {
    return Share.shareXFiles(
      <XFile>[XFile(file.path, mimeType: mimeType)],
      subject: subject,
      text: subject,
    );
  }

  /// Logs diagnostics without interrupting the export user experience.
  static void logError(String context, Object error, StackTrace stackTrace) {
    developer.log(
      '$context: $error',
      name: 'ExportFileService',
      error: error,
      stackTrace: stackTrace,
    );
  }
}
