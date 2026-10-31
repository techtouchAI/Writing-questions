/// OpenType glyph emission for Amiri. Canonical layout still owns word origins,
/// dimensions and page breaks. HarfBuzz supplies only intra-word GSUB/GPOS.
/// No replacement font, raster screenshot or presentation-form approximation.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:pdf/pdf.dart';

final class _Glyph extends Struct {
  @Uint32()
  external int id;
  @Uint32()
  external int cluster;
  @Int32()
  external int xAdvance;
  @Int32()
  external int yAdvance;
  @Int32()
  external int xOffset;
  @Int32()
  external int yOffset;
}

class OpenTypeGlyph {
  const OpenTypeGlyph({required this.id, required this.alias, required this.unicode,
    required this.advance, required this.xOffset, required this.yOffset});
  final int id;
  // Private PDF-encoder alias, NOT a source-text or source-font substitution.
  // TtfWriter subsets this entry's original GID. ToUnicode retains source text.
  final int alias;
  final String unicode;
  final double advance;
  final double xOffset;
  final double yOffset;
}

class OpenTypeWord {
  const OpenTypeWord(this.glyphs);
  final List<OpenTypeGlyph> glyphs;
  String get glyphText => String.fromCharCodes(glyphs.map((glyph) => glyph.alias));
  List<String> get unicode => [for (final glyph in glyphs) glyph.unicode];
  double get advance => glyphs.fold<double>(0, (sum, glyph) => sum + glyph.advance);

  List<PdfGlyphPlacement> placements(PdfTtfFont font, double size) => [
    for (final glyph in glyphs) PdfGlyphPlacement(
      beforeTj: -glyph.xOffset * 1000,
      // /W stores integer thousandths; use its exact executed advance.
      afterTj: (font.glyphMetrics(glyph.alias).advanceWidth * 1000).toInt()
          - (glyph.advance - glyph.xOffset) * 1000,
      rise: glyph.yOffset * size,
    ),
  ];
}

abstract final class OpenTypeShaper {
  static final _fonts = Expando<_FaceFont>();

  // Scope the repair to the affected complex face. Other font renderers retain
  // their existing contract and regressions, not an unreviewed global rewrite.
  static bool applies(PdfFont font, String text) => font is PdfTtfFont &&
      font.fontName.startsWith('Amiri') &&
      text.runes.any((rune) => rune >= 0x0600 && rune <= 0x08ff ||
          rune >= 0xfb50 && rune <= 0xfeff);

  static OpenTypeWord shape(PdfTtfFont font, String text, {required bool rtl}) {
    final face = _fonts[font] ??= _FaceFont(font);
    return face.shape(font, text, rtl);
  }
}

final class _Bindings {
  _Bindings() : library = DynamicLibrary.open(Platform.isAndroid
      ? 'libwriting_harfbuzz.so'
      : '${Directory.current.path}/build/native/libwriting_harfbuzz.so');
  static final instance = _Bindings();
  final DynamicLibrary library;
  late final create = library.lookupFunction<
      Pointer<Void> Function(Pointer<Uint8>, Uint32, Pointer<Uint32>),
      Pointer<Void> Function(Pointer<Uint8>, int, Pointer<Uint32>)>('writing_font_create');
  late final destroy = library.lookup<NativeFunction<Void Function(Pointer<Void>)>>('writing_font_destroy');
  late final shape = library.lookupFunction<
      Pointer<_Glyph> Function(Pointer<Void>, Pointer<Uint16>, Uint32, Int32, Pointer<Uint32>),
      Pointer<_Glyph> Function(Pointer<Void>, Pointer<Uint16>, int, int, Pointer<Uint32>)>('writing_shape');
  late final free = library.lookupFunction<Void Function(Pointer<_Glyph>),
      void Function(Pointer<_Glyph>)>('writing_glyphs_free');
  late final finalizer = NativeFinalizer(destroy);
}

final class _FaceFont implements Finalizable {
  _FaceFont(PdfTtfFont font) {
    final data = font.font.bytes;
    final bytes = calloc<Uint8>(data.lengthInBytes);
    final upem = calloc<Uint32>();
    try {
      bytes.asTypedList(data.lengthInBytes).setAll(0,
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      handle = _Bindings.instance.create(bytes, data.lengthInBytes, upem);
      unitsPerEm = upem.value;
      if (handle == nullptr || unitsPerEm <= 0) {
        throw StateError('OpenType font initialization failed: ${font.fontName}');
      }
      _Bindings.instance.finalizer.attach(this, handle);
    } finally {
      calloc.free(bytes);
      calloc.free(upem);
    }
  }
  late final Pointer<Void> handle;
  late final int unitsPerEm;
  final _aliases = <int, int>{};
  var _nextAlias = 0xe000;

  int _alias(PdfTtfFont font, int gid) => _aliases.putIfAbsent(gid, () {
    // Allocate an unused BMP private encoder key. Source font BYTES stay intact;
    // this parser-local CID→GID registration reaches the unmodified TtfWriter.
    final cmap = font.font.charToGlyphIndexMap;
    while (_nextAlias <= 0xf8ff && cmap.containsKey(_nextAlias)) { _nextAlias++; }
    if (_nextAlias > 0xf8ff) throw StateError('OpenType PDF glyph alias space exhausted');
    final alias = _nextAlias++;
    cmap[alias] = gid;
    return alias;
  });

  OpenTypeWord shape(PdfTtfFont font, String text, bool rtl) {
    final input = calloc<Uint16>(text.length);
    final count = calloc<Uint32>();
    Pointer<_Glyph> result = nullptr;
    try {
      input.asTypedList(text.length).setAll(0, text.codeUnits);
      result = _Bindings.instance.shape(handle, input, text.length, rtl ? 1 : 0, count);
      if (result == nullptr || count.value == 0) throw StateError('OpenType shaping failed');
      final clusters = {text.length, for (var i = 0; i < count.value; i++) result[i].cluster}.toList()..sort();
      final seen = <int>{};
      final glyphs = <OpenTypeGlyph>[];
      for (var i = 0; i < count.value; i++) {
        final glyph = result[i];
        final cluster = glyph.cluster;
        if (cluster < 0 || cluster >= text.length || glyph.yAdvance != 0) {
          throw StateError('Unsupported OpenType horizontal cluster');
        }
        final end = clusters[clusters.indexOf(cluster) + 1];
        glyphs.add(OpenTypeGlyph(id: glyph.id, alias: _alias(font, glyph.id),
          unicode: seen.add(cluster) ? text.substring(cluster, end) : '',
          advance: glyph.xAdvance / unitsPerEm,
          xOffset: glyph.xOffset / unitsPerEm, yOffset: glyph.yOffset / unitsPerEm));
      }
      return OpenTypeWord(List.unmodifiable(glyphs));
    } finally {
      if (result != nullptr) _Bindings.instance.free(result);
      calloc.free(input);
      calloc.free(count);
    }
  }
}
