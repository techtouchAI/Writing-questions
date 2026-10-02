// التصدير الدقيق (Exact): PDF وWord من **صور صفحات المعاينة** نفسها.
//
// المقصود أن يُثبَت أن ناتج Exact لا يعيد حساب layout إطلاقاً:
//   * PDF: عدد الصفحات = عدد اللقطات، ومقاس كل صفحة A4 كامل، وكل صفحة تحمل
//     صورة صفحة المعاينة (ولا نصوصاً معاد تخطيطها).
//   * Word: كل صفحة صورة بحجم A4 بالضبط داخل مستند بلا هوامش — غير قابل
//     للتحرير، وهذا معلن في الواجهة (DOCX Exact مقابل DOCX Editable).
//   * الفشل برسالة واضحة: لا صفحات ⇒ استثناء صريح، لا ملف فارغ.
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writing_questions_app/services/exact_export_service.dart';
import 'package:writing_questions_app/services/page_snapshot_service.dart';

/// صورة PNG صغرى صالحة (1×1) — تكفي لإثبات مسار التضمين كاملاً.
final Uint8List _png1x1 = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

List<PageSnapshot> _snapshots(int count) => <PageSnapshot>[
      for (var index = 0; index < count; index++)
        PageSnapshot(
          pageIndex: index,
          pngBytes: _png1x1,
          widthPx: 794,
          heightPx: 1123,
        ),
    ];

void main() {
  group('PDF دقيق', () {
    test('كل لقطة = صفحة A4 كاملة، والعدد مطابق', () async {
      final bytes = await ExactExportService.buildPdfFromSnapshots(_snapshots(3));
      final text = latin1.decode(bytes, allowInvalid: true);
      // عدد صفحات PDF = عدد كائنات /Type /Page (بلا /Pages الأب).
      final pageObjects = RegExp(r'/Type\s*/Page[^s]').allMatches(text).length;
      expect(pageObjects, 3, reason: 'عدد صفحات PDF يجب أن يساوي عدد اللقطات.');
      expect(
        RegExp(r'MediaBox \[0 0 595\.[0-9]+ 841\.[0-9]+\]').hasMatch(text),
        isTrue,
        reason: 'مقاس الصفحة يجب أن يكون A4 كاملاً (595.28×841.89 نقطة).',
      );
      // الصور مضمّنة في الملف (XObject لكل صفحة).
      expect(RegExp(r'/Subtype\s*/Image').allMatches(text).length, 3);
    });

    test('لا صفحات ⇒ استثناء واضح لا ملف فارغ', () async {
      expect(
        () => ExactExportService.buildPdfFromSnapshots(const <PageSnapshot>[]),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('Word دقيق', () {
    test('كل لقطة = صورة صفحة كاملة بمقاس A4 وبلا هوامش', () {
      final bytes = ExactExportService.buildDocxFromSnapshots(_snapshots(2));
      final archive = ZipDecoder().decodeBytes(bytes);
      final document = archive.findFile('word/document.xml');
      expect(document, isNotNull);
      final xml = utf8.decode(document!.content as List<int>);

      // مقاس الورقة A4 وتوينب الهوامش صفر: الصورة تغطي الورقة كاملة.
      expect(xml.contains('<w:pgSz w:w="11906" w:h="16838"/>'), isTrue);
      expect(
        xml.contains(
          '<w:pgMar w:top="0" w:right="0" w:bottom="0" w:left="0" '
          'w:header="0" w:footer="0" w:gutter="0"/>',
        ),
        isTrue,
      );
      // صورتان بحجم EMU الكامل لـ A4 (210×297 مم).
      final drawings = RegExp(r'<w:drawing>').allMatches(xml).length;
      expect(drawings, 2);
      expect(RegExp(r'cx="7560000" cy="10692000"').allMatches(xml).length, 2);
      // الصور موجودة فعلاً في الحزمة.
      expect(archive.findFile('word/media/page1.png'), isNotNull);
      expect(archive.findFile('word/media/page2.png'), isNotNull);
      // وعلاقات الصور معلنة.
      final rels = archive.findFile('word/_rels/document.xml.rels');
      final relsXml = utf8.decode(rels!.content as List<int>);
      expect(relsXml.contains('rIdPage1'), isTrue);
      expect(relsXml.contains('rIdPage2'), isTrue);
    });

    test('لا نصوص ولا معادلات OMML في النمط الدقيق (صور فقط)', () {
      final bytes = ExactExportService.buildDocxFromSnapshots(_snapshots(1));
      final archive = ZipDecoder().decodeBytes(bytes);
      final xml = utf8.decode(
        archive.findFile('word/document.xml')!.content as List<int>,
      );
      expect(xml.contains('<m:oMath'), isFalse,
          reason: 'DOCX Exact لا يستعمل OMML: صور الصفحات فقط.');
      expect(xml.contains('<w:t'), isFalse,
          reason: 'DOCX Exact لا يحمل نصاً قابلاً للتحرير (معلن في الواجهة).');
    });

    test('لا صفحات ⇒ استثناء واضح', () {
      expect(
        () => ExactExportService.buildDocxFromSnapshots(const <PageSnapshot>[]),
        throwsA(isA<StateError>()),
      );
    });
  });
}
