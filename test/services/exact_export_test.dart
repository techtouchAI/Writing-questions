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
final Uint8List _redPixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4'
  'z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==',
);
final Uint8List _bluePixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNg'
  'YPj/HwADAgH/5ncLrgAAAABJRU5ErkJggg==',
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
      // لكل صفحة صورة الصفحة الملتقطة. اللقطة الشفافة تُخزَّن صورةً وقناع
      // شفافية (SMask) فيزداد العدد، فالفحص: لا تقل عن صفحة لكل لقطة،
      // والعدد من مضاعفات عدد اللقطات (لا صور غريبة مضافة).
      final images = RegExp(r'/Subtype\s*/Image').allMatches(text).length;
      expect(images, greaterThanOrEqualTo(3),
          reason: 'لكل صفحة صورة الصفحة الملتقطة (XObject).');
      expect(images % 3, 0,
          reason: 'عدد الصور مضاعف لعدد اللقطات (صورة + قناع لكل صفحة).');
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
      // صورتان، ولكل منهما امتداد الرسم وامتداد الشكل بعرض الورقة نفسه
      // (A4 كاملاً: الصورة تغطي الورقة بلا قصّ).
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

    test('الصورة مثبّتة على الصفحة (anchor) لا سطرية: لا يزحزحها ارتفاع السطر', () {
      final bytes = ExactExportService.buildDocxFromSnapshots(_snapshots(3));
      final xml = utf8.decode(
        ZipDecoder().decodeBytes(bytes).findFile('word/document.xml')!.content
            as List<int>,
      );
      // القياس البصري في CI هو ما كشف انزياح الصورة السطرية في LibreOffice؛
      // هذا الحارس يمنع العودة إلى `wp:inline` بلا قياس جديد.
      expect(xml.contains('<wp:inline'), isFalse,
          reason: 'الصورة السطرية تتأثر بارتفاع السطر وخط الأساس.');
      expect(RegExp(r'<wp:anchor ').allMatches(xml).length, 3,
          reason: 'صورة مثبّتة لكل صفحة.');
      expect(
        RegExp('<wp:positionH relativeFrom=\"page\">'
                '<wp:posOffset>0</wp:posOffset></wp:positionH>')
            .allMatches(xml)
            .length,
        3,
        reason: 'الموضع الأفقي من أصل الصفحة (لا من الفقرة).',
      );
      expect(
        RegExp('<wp:positionV relativeFrom=\"page\">'
                '<wp:posOffset>0</wp:posOffset></wp:positionV>')
            .allMatches(xml)
            .length,
        3,
        reason: 'الموضع الرأسي من أصل الصفحة (لا من الفقرة).',
      );
      // الصورة المثبّتة لا تدفع محتوىً، فيلزم فاصل صريح بين الصفحات.
      expect(RegExp(r'<w:br w:type="page"/>').allMatches(xml).length, 2);
      expect(xml.contains('<w:t'), isFalse);
    });

    test('ترتيب DOCX يتبع فهرس الصفحة لا ترتيب وصول اللقطات', () {
      final bytes = ExactExportService.buildDocxFromSnapshots(<PageSnapshot>[
        PageSnapshot(
          pageIndex: 1,
          pngBytes: _bluePixel,
          widthPx: 794,
          heightPx: 1123,
        ),
        PageSnapshot(
          pageIndex: 0,
          pngBytes: _redPixel,
          widthPx: 794,
          heightPx: 1123,
        ),
      ]);
      final archive = ZipDecoder().decodeBytes(bytes);
      expect(
        archive.findFile('word/media/page1.png')!.content,
        equals(_redPixel),
      );
      expect(
        archive.findFile('word/media/page2.png')!.content,
        equals(_bluePixel),
      );
    });

    test('الفهارس غير المتصلة لا تنتج ترتيب صفحات صامتاً خاطئاً', () {
      expect(
        () => ExactExportService.buildDocxFromSnapshots(<PageSnapshot>[
          _snapshots(1).single,
          PageSnapshot(
            pageIndex: 2,
            pngBytes: _png1x1,
            widthPx: 794,
            heightPx: 1123,
          ),
        ]),
        throwsA(isA<StateError>()),
      );
    });

    test('لا صفحات ⇒ استثناء واضح', () {
      expect(
        () => ExactExportService.buildDocxFromSnapshots(const <PageSnapshot>[]),
        throwsA(isA<StateError>()),
      );
    });
  });
}
