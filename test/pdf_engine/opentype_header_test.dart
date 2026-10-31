import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:writing_questions_app/pdf_engine/exam_fonts.dart';
import 'package:writing_questions_app/pdf_engine/opentype_shaper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Independent HarfBuzz reference over the unchanged Amiri asset. These GIDs
  // are font-specific and many have no Unicode presentation-form cmap entry.
  const reference = {
    'بسم': [4030, 3662, 3639],
    'الله': [1348, 6128, 1346, 55],
    'الرحمن': [1862, 4487, 4469, 3539, 3522, 55],
    'الرحيم': [2162, 2135, 1739, 3539, 3522, 55],
  };
  for (final entry in reference.entries) {
    test('OpenType header emits contextual source glyph IDs for ${entry.key}', () async {
      final font = PdfTtfFont(PdfDocument(), await rootBundle.load(ExamFonts.quranicAsset));
      final originalCmap = font.font.charToGlyphIndexMap.values.toSet();
      final shaped = OpenTypeShaper.shape(font, entry.key, rtl: true);
      expect(shaped.glyphs.map((glyph) => glyph.id).toList(), entry.value);
      expect(shaped.glyphs.any((glyph) => !originalCmap.contains(glyph.id)), isTrue,
        reason: 'This must exercise real GSUB glyphs, not presentation-form replacements.');
      expect(shaped.unicode.join(), String.fromCharCodes(entry.key.runes.toList().reversed));
      for (final glyph in shaped.glyphs) {
        expect(font.font.charToGlyphIndexMap[glyph.alias], glyph.id);
      }
    });
  }
  test('OpenType diacritic positions retain zero advances and GPOS offsets', () async {
    final font = PdfTtfFont(PdfDocument(), await rootBundle.load(ExamFonts.quranicAsset));
    const source = 'بِسْمِ';
    final shaped = OpenTypeShaper.shape(font, source, rtl: true);
    expect(shaped.glyphs.any((glyph) => glyph.advance == 0 && glyph.xOffset != 0), isTrue);
    expect(shaped.unicode.join().runes.toList()..sort(), source.runes.toList()..sort(),
      reason: 'Cluster aliases may not duplicate or discard source text.');
  });
}
