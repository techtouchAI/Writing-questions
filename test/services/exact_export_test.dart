// التصدير الدقيق (Exact): الصفحة صورة الصفحة نفسها — لا إعادة layout.
//
//   * PDF: عدد صفحات = عدد اللقطات، كل صفحة A4 كاملة، وفيها صورة (XObject).
//   * Word: كل لقطة صورة A4 كاملة (بلا هوامش) وبلا أي نص/OMML — أي أنه
//     **غير قابل للتحرير**، وهذا معلن في الواجهة (DOCX Exact مقابل Editable).
//   * الفشل واضح: لا صفحات ⇒ استثناء صريح لا ملف فارغ.
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writing_questions_app/services/exact_export_service.dart';
import 'package:writing_questions_app/services/page_snapshot_service.dart';

/// PNG 1×1 شفاف (بايتات حقيقية يقرؤها مُرمِّز الصور في حزمة pdf).
final Uint8List _png1x1 = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
  'YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
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
      final bytes = await ExactExportService.buildPdfFromSnapshots(
        _snapshots(3),
      );
      final text = latin1.decode(bytes, allowInvalid: true);
      expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
      expect(
        RegExp(r'/Type\s*/Page[^s]').allMatches(text).length,
        3,
        reason: 'عدد صفحات PDF = عدد اللقطات.',
      );
      expect(
        RegExp(r'MediaBox\s*\[0 0 595\.[0-9]+ 841\.[0-9]+\]').hasMatch(text),
        isTrue,
        reason: 'مقاس A4 كامل: صورة الصفحة تغطي الورقة.',
      );
      expect(
        RegExp(r'/Subtype\s*/Image').allMatches(text).length,
        3,
        reason: 'لكل صفحة صورة الصفحة الملتقطة (XObject).',
      );
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
      final xml = utf8.decode(
        archive.findFile('word/document.xml')!.content as List<int>,
      );

      expect(xml.contains('<w:pgSz w:w="11906" w:h="16838"/>'), isTrue,
          reason: 'مقاس A4 كاملاً (210×297مم) بالتويب.');
      expect(
        xml.contains(
          '<w:pgMar w:top="0" w:right="0" w:bottom="0" w:left="0" '
          'w:header="0" w:footer="0" w:gutter="0"/>',
        ),
        isTrue,
        reason: 'هوامش صفر: الصورة تغطي الورقة كاملة.',
      );
      // صورتان، ولكل منهما امتداد الرسم وامتداد الشكل بعرض الورقة نفسه.
      expect(RegExp(r'<wp:extent cx="7560000" cy="10692000"/>').allMatches(xml).length, 2);
      expect(RegExp(r'cx="7560000" cy="10692000"').allMatches(xml).length, 4);
      // الصور نفسها مضمّنة، وعلاقاتها معلنة.
      expect(archive.findFile('word/media/page1.png'), isNotNull);
      expect(archive.findFile('word/media/page2.png'), isNotNull);
      final rels = utf8.decode(
        archive.findFile('word/_rels/document.xml.rels')!.content as List<int>,
      );
      expect(rels.contains('rIdPage1'), isTrue);
      expect(rels.contains('rIdPage2'), isTrue);
      // والبايتات هي بايتات اللقطة بالضبط (لا إعادة ترميز).
      expect(
        archive.findFile('word/media/page1.png')!.content,
        equals(_png1x1),
      );
    });

    test('صور فقط: لا نص ولا OMML (غير قابل للتحرير — معلن في الواجهة)', () {
      final bytes = ExactExportService.buildDocxFromSnapshots(_snapshots(1));
      final xml = utf8.decode(
        ZipDecoder().decodeBytes(bytes).findFile('word/document.xml')!.content
            as List<int>,
      );
      expect(xml.contains('<w:t'), isFalse,
          reason: 'لا نص قابل للتحرير في النمط الدقيق.');
      expect(xml.contains('<m:oMath'), isFalse,
          reason: 'لا معادلات OMML في النمط الدقيق.');
    });

    test('لا صفحات ⇒ استثناء واضح', () {
      expect(
        () => ExactExportService.buildDocxFromSnapshots(const <PageSnapshot>[]),
        throwsA(isA<StateError>()),
      );
    });
  });
}
