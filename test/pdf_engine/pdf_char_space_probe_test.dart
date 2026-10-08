// The content probe must apply Tc char spacing with viewer semantics:
// thousandths of an em per shown glyph, scoped by the q/Q graphics-state
// stack. A synthetic minimal PDF keeps this independent of font assets.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'pdf_content_probe.dart';

Uint8List _syntheticPdf(String content) {
  final contentBytes = latin1.encode(content);
  final buffer = StringBuffer()
    ..writeln('%PDF-1.4')
    ..writeln('1 0 obj <</Type /Catalog /Pages 2 0 R>> endobj')
    ..writeln('2 0 obj <</Type /Pages /Kids [3 0 R] /Count 1>> endobj')
    ..writeln(
      '3 0 obj <</Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] '
      '/Contents 4 0 R /Resources <</Font <</F1 5 0 R>>>>>> endobj',
    )
    ..writeln('4 0 obj <</Length ${contentBytes.length}>> stream');
  final head = latin1.encode(buffer.toString());
  final tail = latin1.encode(
    '\nendstream endobj\n'
    '5 0 obj <</Type /Font /Subtype /Type0 /BaseFont /TestFont '
    '/W [0 7 0 R] /ToUnicode 6 0 R>> endobj\n'
    '6 0 obj <</Length 51>> stream\n'
    '1 beginbfchar <0000> <0041> <0001> <0042> endbfchar\n'
    'endstream endobj\n'
    '7 0 obj [500 600] endobj\n',
  );
  return Uint8List.fromList(<int>[
    ...head,
    ...contentBytes,
    ...tail,
  ]);
}

void main() {
  test('probe applies Tc per shown glyph with q/Q scoping', () {
    const content = 'BT /F1 10 Tf 100 Tc 20 100 Td <00000001> Tj ET '
        'BT q 200 Tc /F1 10 Tf 20 80 Td <0000> Tj Q ET '
        'BT /F1 10 Tf 20 60 Td <0000> Tj ET';
    final probe = PdfContentProbe.fromBytes(_syntheticPdf(content));

    expect(probe.lines, hasLength(3));

    final first = probe.lines[0].words.single;
    expect(first.text, 'AB');
    expect(first.x, closeTo(20, 1e-9));
    // /W sum (500 + 600) at 10pt = 11pt, plus Tc 100/1000em x 10pt x 2 glyphs.
    expect(first.advanceWidth, closeTo(13.0, 1e-9));

    final second = probe.lines[1].words.single;
    expect(second.text, 'A');
    // 500 at 10pt = 5pt, plus Tc 200/1000em x 10pt x 1 glyph inside q.
    expect(second.advanceWidth, closeTo(7.0, 1e-9));

    final third = probe.lines[2].words.single;
    expect(third.text, 'A');
    // Q restores Tc 100: 5pt + 100/1000em x 10pt x 1 glyph.
    expect(third.advanceWidth, closeTo(6.0, 1e-9));
  });

  test('probe keeps raw /W advances when no Tc is emitted', () {
    const content = 'BT /F1 10 Tf 20 100 Td <00000001> Tj ET';
    final probe = PdfContentProbe.fromBytes(_syntheticPdf(content));

    final word = probe.lines.single.words.single;
    expect(word.text, 'AB');
    expect(word.advanceWidth, closeTo(11.0, 1e-9));
  });
}
