import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:writing_questions_app/pdf_engine/exam_fonts.dart';
import 'package:writing_questions_app/pdf_engine/canonical_text.dart';
import 'package:writing_questions_app/pdf_engine/opentype_shaper.dart';

import 'pdf_content_probe.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('real decomposed Arabic glyphs retain source ActualText and full executed advance', () async {
    const source = 'رَّبِّ';
    final document = pw.Document(compress: false);
    final font = pw.Font.ttf(await rootBundle.load(ExamFonts.quranicAsset));
    document.addPage(pw.Page(build: (context) => pw.CustomPaint(size: const PdfPoint(100, 100),
      painter: (canvas, size) {
        final actualFont = font.getFont(context) as PdfTtfFont;
        final shaped = OpenTypeShaper.shape(actualFont, source, rtl: true);
        expect(shaped.glyphs.every((glyph) => glyph.id > 0), isTrue,
          reason: 'Empty component mappings must never hide an actual .notdef glyph.');
        expect(shaped.unicode.any((text) => text.isEmpty), isTrue);
        expect(shaped.unicode.join().runes.toList()..sort(), source.runes.toList()..sort());
        canvas.drawString(actualFont, 17, shaped.glyphText, 20, 50,
          toUnicodeChars: shaped.unicode, glyphPlacements: shaped.placements(actualFont, 17),
          trailingTj: (shaped.advance * 17 - 40) * 1000 / 17, actualText: source);
      })));
    final bytes = await document.save();
    final hex = source.codeUnits.map((unit) => unit.toRadixString(16).padLeft(4, '0')).join();
    expect(latin1.decode(bytes).contains('/ActualText<FEFF$hex>'), isTrue,
      reason: 'PDF-standard logical source semantics, not encoder aliases or duplicated cluster text.');
    final word = PdfContentProbe.fromBytes(bytes).words.single;
    expect(word.text.contains('\uFFFD'), isFalse);
    expect(word.advanceWidth, closeTo(40, 1e-4));
    Directory('build/production_fragment_repro').createSync(recursive: true);
    File('build/production_fragment_repro/opentype-clusters.pdf').writeAsBytesSync(bytes);
  });

  for (final asset in [ExamFonts.regularAsset, ExamFonts.boldAsset]) {
    test('actual canonical Naskh $asset rejects the reader-reversing whole-word wrapper and retains advance', () async {
      const source = 'سَلَامٌ';
      final document = pw.Document(compress: false);
      final font = pw.Font.ttf(await rootBundle.load(asset));
      document.addPage(pw.Page(build: (_) => CanonicalText(
        text: source, font: font, fontSizePt: 17, color: PdfColors.black,
        canonicalAdvancePt: 40, rtl: true, underline: false)));
      final bytes = await document.save();
      expect(latin1.decode(bytes).contains('/ActualText'), isFalse,
        reason: 'The rejected global wrapper reverses existing plain Arabic in '
            'the real reader. Retain the prior ToUnicode path until an '
            'interoperable source repair is proved on original PDFs.');
      final word = PdfContentProbe.fromBytes(bytes).words.single;
      expect(word.advanceWidth, closeTo(40, 1e-4));
      expect(word.text.contains('\uFFFD'), isFalse);
      // This is regression containment, not diacritized-source acceptance.
      // The unchanged actual Android PDF reader gate must still pass.
    });
  }

}
