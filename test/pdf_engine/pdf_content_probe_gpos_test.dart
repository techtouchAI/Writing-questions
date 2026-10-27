// Preserve the original Quran/P0 assertions: these independent raw-PDF cases
// prove the measuring reader executes ALL TJ arrays, including number-only
// trailing corrections, and distinguishes explicit empty mappings from missing.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'pdf_content_probe.dart';

Uint8List _pdf(String content) {
  const cmap = '<0001><0041>\n<0002><>\n<0003><0042>';
  return Uint8List.fromList(latin1.encode('''%PDF-1.7
1 0 obj
<</Type/Page/Resources<</Font<</F1 2 0 R>>>>/Contents 3 0 R>>
endobj
2 0 obj
<</BaseFont/Probe/W[0 4 0 R]/ToUnicode 5 0 R>>
endobj
3 0 obj
<</Length ${content.length}>>
stream
$content
endstream
endobj
4 0 obj
[500 600 700 800]
endobj
5 0 obj
<</Length ${cmap.length}>>
stream
$cmap
endstream
endobj
'''));
}

void main() {
  test('all Ts-separated TJ arrays and number-only trailing correction count', () {
    final probe = PdfContentProbe.fromBytes(_pdf(
      'BT /F1 10 Tf 50 100 Td [<0001>]TJ 2 Ts [<0002>700]TJ '
      '0 Ts [<0003>]TJ [100]TJ ET'));
    expect(probe.words, hasLength(1));
    final word = probe.words.single;
    expect(word.text, 'AB');
    expect(word.x, 50);
    expect(word.y, 100);
    // 6 + (7 - 7) + 8 - 1 = 13pt; the old reader reported only 6pt.
    expect(word.advanceWidth, closeTo(13, 1e-9));
  });
  test('a second text object remains a separately positioned word', () {
    final words = PdfContentProbe.fromBytes(_pdf(
      'BT /F1 10 Tf 50 100 Td [<0001>]TJ ET '
      'BT /F1 10 Tf 70 100 Td [<0003>]TJ ET')).words;
    expect(words.map((word) => word.text), ['A', 'B']);
    expect(words.map((word) => word.x), [50, 70]);
    expect(words.map((word) => word.advanceWidth), [6, 8]);
  });
  test('an unmapped CID still reports replacement, never silently disappears', () {
    final word = PdfContentProbe.fromBytes(_pdf(
      'BT /F1 10 Tf 50 100 Td [<0009>]TJ ET')).words.single;
    expect(word.text, '\uFFFD');
    expect(word.advanceWidth, 10);
  });
}
