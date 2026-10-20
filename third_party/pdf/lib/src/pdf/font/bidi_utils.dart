import 'package:bidi/bidi.dart' as bidi;

import 'arabic.dart' as arabic;
/*
 * Copyright (C) 2017, David PHAM-VAN <dev.nfet.net@gmail.com>
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

const Map<int, int> _arabicDiacritics = <int, int>{
  0x064B: 0x064B, // Fathatan
  0x064C: 0x064C, // Dammatan
  0x064D: 0x064D, // Kasratan
  0x064E: 0x064E, // Fatha
  0x064F: 0x064F, // Damma
  0x0650: 0x0650, // Kasra
  0x0651: 0x0651, // Shadda
  0x0652: 0x0652, // Sukun
  0x0670: 0x0670, // Dagger alif
  0xFC5E: 0xFC5E, // Shadda + Dammatan
  0xFC5F: 0xFC5F, // Shadda + Kasratan
  0xFC60: 0xFC60, // Shadda + Fatha
  0xFC61: 0xFC61, // Shadda + Damma
  0xFC62: 0xFC62, // Shadda + Kasra
  0xFC63: 0xFC63, // Shadda + Dagger alif
  // 1548: 1548,
};

bool isArabicDiacriticValue(int letter) {
  return _arabicDiacritics.containsValue(letter);
}

/// Arabic characters that have different unicode values
/// but should point to the same glyph.
const Map<int, int> basicToIsolatedMappings = {
  0x0627: 0xFE8D, // ا
  0x0628: 0xFE8F, // ب
  0x062A: 0xFE95, // ت
  0x062B: 0xFE99, // ث
  0x062C: 0xFE9D, // ج
  0x062D: 0xFEA1, // ح
  0x062E: 0xFEA5, // خ
  0x062F: 0xFEA9, // د
  0x0630: 0xFEAB, // ذ
  0x0631: 0xFEAD, // ر
  0x0632: 0xFEAF, // ز
  0x0633: 0xFEB1, // س
  0x0634: 0xFEB5, // ش
  0x0635: 0xFEB9, // ص
  0x0636: 0xFEBD, // ض
  0x0637: 0xFEC1, // ط
  0x0638: 0xFEC5, // ظ
  0x0639: 0xFEC9, // ع
  0x063A: 0xFECD, // غ
  0x0641: 0xFED1, // ف
  0x0642: 0xFED5, // ق
  0x0643: 0xFED9, // ك
  0x0644: 0xFEDD, // ل
  0x0645: 0xFEE1, // م
  0x0646: 0xFEE5, // ن
  0x0647: 0xFEE9, // ه
  0x0648: 0xFEED, // و
  0x064A: 0xFEEF, // ي
  0x0621: 0xFE80, // ء
  0x0622: 0xFE81, // آ
  0x0623: 0xFE83, // أ
  0x0624: 0xFE85, // ؤ
  0x0625: 0xFE87, // إ
  0x0626: 0xFE89, // ئ
  0x0629: 0xFE93, // ة
};

/// Visual glyph sequence paired with its aligned `/ToUnicode` character
/// sequence for a single right-to-left run.
class RtlShapedRun {
  const RtlShapedRun({
    required this.glyphText,
    required this.toUnicodeText,
  });

  /// Visual-order characters selecting the rendered font glyphs (including
  /// Unicode UAX #9 Rule L4 `Bidi_Mirrored_Glyph` substitutions at odd
  /// embedding levels).
  final String glyphText;

  /// Visual-order Unicode characters written to the PDF `/ToUnicode` CMap so
  /// text extraction, search, copy/paste, and structural probes preserve the
  /// exact logical bracket characters (`U+0028` / `U+0029`, etc.) while still
  /// keeping Arabic Presentation Forms for joined letters.
  final String toUnicodeText;
}

bool _hasArabicScript(String input) => input.runes.any((rune) =>
    (rune >= 0x0600 && rune <= 0x08FF) ||
    (rune >= 0xFB50 && rune <= 0xFEFF) ||
    (rune >= 0x10E60 && rune <= 0x10E7F) ||
    (rune >= 0x1EC70 && rune <= 0x1EEFF));

String _fallbackArabicShape(String input) => String.fromCharCodes(
      arabic.convert(input).runes.map(
            (rune) => basicToIsolatedMappings[rune] ?? rune,
          ),
    );

const Map<int, int> _rtlMirroredGlyphPairs = <int, int>{
  0x0028: 0x0029, // ( -> )
  0x0029: 0x0028, // ) -> (
  0x003C: 0x003E, // < -> >
  0x003E: 0x003C, // > -> <
  0x005B: 0x005D, // [ -> ]
  0x005D: 0x005B, // ] -> [
  0x007B: 0x007D, // { -> }
  0x007D: 0x007B, // } -> {
  0x00AB: 0x00BB, // « -> »
  0x00BB: 0x00AB, // » -> «
  0x2039: 0x203A, // ‹ -> ›
  0x203A: 0x2039, // › -> ‹
  0xFD3E: 0xFD3F, // ﴾ -> ﴿
  0xFD3F: 0xFD3E, // ﴿ -> ﴾
};

/// Shapes a single right-to-left run using Unicode UAX #9 at an explicit odd
/// RTL paragraph embedding level (`U+202B ... U+202C`, stripped internally by
/// `package:bidi` so no directional formatting characters leak into either
/// [RtlShapedRun.glyphText] or [RtlShapedRun.toUnicodeText]).
///
/// Running UAX #9 in a single pass at `embeddingLevel = 1` solves both:
/// 1. Standalone neutral brackets split into their own word/run tokens (such
///    as `'أ )'`, `'أ ('`, `'( أ )'`, `'(٢٠ درجة)'`, `'1 )'`) receive UAX #9
///    Rule L4 glyph mirroring instead of falling back to LTR `embeddingLevel=0`.
/// 2. Tokens already containing Arabic letters alongside brackets (such as
///    `'أولاً)'` or `'((أ))'`) are reordered and mirrored once in the same UAX #9
///    pass — never double-reversed or double-mirrored — while any embedded
///    even-level LTR sub-runs stay unmirrored automatically.
RtlShapedRun shapeRtlRun(String input) {
  if (input.isEmpty) {
    return const RtlShapedRun(glyphText: '', toUnicodeText: '');
  }

  final bidi.BidiString bidiText;
  try {
    // Pass `U+202B ... U+202C` (RLE ... PDF) to establish RTL paragraph level 1
    // in one UAX #9 pass; `bidi.Paragraph` removes formatting markers from
    // `bidiText` and `indices` automatically after level resolution.
    bidiText = bidi.BidiString.fromLogical('\u202B$input\u202C');
  } on RangeError {
    if (!_hasArabicScript(input)) rethrow;
    final shaped = _fallbackArabicShape(input);
    final mirroredGlyphs = String.fromCharCodes(
      shaped.runes.map((rune) => _rtlMirroredGlyphPairs[rune] ?? rune),
    );
    return RtlShapedRun(glyphText: mirroredGlyphs, toUnicodeText: shaped);
  }

  final glyphBuffer = <int>[];
  final unicodeBuffer = <int>[];
  final paragraphs = bidiText.paragraphs;
  for (var pIdx = 0; pIdx < paragraphs.length; pIdx++) {
    final paragraph = paragraphs[pIdx];
    final endsWithNewLine = paragraph.separator == 10;
    final bidiCodes = paragraph.bidiText;
    final endIndex = bidiCodes.length - (endsWithNewLine ? 1 : 0);
    final origText = paragraph.text;
    final indices = paragraph.indices;

    for (var i = 0; i < endIndex; i++) {
      final glyphRune = bidiCodes[i];
      glyphBuffer.add(glyphRune);

      var unicodeRune = glyphRune;
      if (i < indices.length) {
        final origPos = indices[i];
        if (origPos >= 0 && origPos < origText.length) {
          final origRune = origText[origPos];
          if (_rtlMirroredGlyphPairs[origRune] == glyphRune) {
            unicodeRune = origRune;
          }
        }
      }
      unicodeBuffer.add(unicodeRune);
    }

    if (endsWithNewLine) {
      glyphBuffer.add(10);
      unicodeBuffer.add(10);
    }
  }

  return RtlShapedRun(
    glyphText: String.fromCharCodes(glyphBuffer),
    toUnicodeText: String.fromCharCodes(unicodeBuffer),
  );
}

/// Applies THE BIDIRECTIONAL ALGORITHM using (https://pub.dev/packages/bidi)
String logicalToVisual(String input) {
  final bidi.BidiString bidiText;
  try {
    bidiText = bidi.BidiString.fromLogical(input);
  } on RangeError {
    if (!_hasArabicScript(input)) rethrow;
    // package:bidi's normalization can index past its original-length table
    // when an Arabic character decomposes into several code points. Keep PDF
    // export resilient with the package's Arabic word shaper, then map isolated
    // base letters to their Unicode presentation-form equivalents; canonical
    // run positions remain resolved by LayoutEngine.
    return _fallbackArabicShape(input);
  }
  final buffer = StringBuffer();
  final paragraphs = bidiText.paragraphs;
  for (final paragraph in paragraphs) {
    final endsWithNewLine = paragraph.separator == 10;
    final endIndex = paragraph.bidiText.length - (endsWithNewLine ? 1 : 0);
    final visual = String.fromCharCodes(paragraph.bidiText, 0, endIndex);
    // Legacy `pw.RichText` splits on spaces and reverses word order itself on
    // RTL lines, so word tokens must stay in logical order while glyphs within
    // each word stay visually shaped; canonical emission uses [shapeRtlRun].
    buffer.write(visual.split(' ').reversed.join(' '));
    if (endsWithNewLine) {
      buffer.writeln();
    }
  }
  return buffer.toString();
}
