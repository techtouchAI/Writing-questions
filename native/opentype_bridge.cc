// Thin ownership/ABI bridge to the unmodified vendored HarfBuzz library.
// No font substitution, bidi, line breaking, pagination or layout here.
#include <cstdlib>
#include <cstdint>
#include <hb.h>
#include <hb-ot.h>

struct WritingGlyph {
  uint32_t id, cluster;
  int32_t x_advance, y_advance, x_offset, y_offset;
};

extern "C" {
__attribute__((visibility("default")))
void* writing_font_create(const char* bytes, uint32_t length, uint32_t* upem) {
  hb_blob_t* blob = hb_blob_create(bytes, length, HB_MEMORY_MODE_DUPLICATE, nullptr, nullptr);
  hb_face_t* face = hb_face_create(blob, 0);
  hb_blob_destroy(blob);
  *upem = hb_face_get_upem(face);
  if (!*upem || !hb_face_get_glyph_count(face)) {
    hb_face_destroy(face);
    return nullptr;
  }
  hb_font_t* font = hb_font_create(face);
  hb_face_destroy(face);
  hb_ot_font_set_funcs(font);
  hb_font_set_scale(font, *upem, *upem);
  return font;
}

__attribute__((visibility("default")))
void writing_font_destroy(void* font) {
  hb_font_destroy(static_cast<hb_font_t*>(font));
}

__attribute__((visibility("default")))
WritingGlyph* writing_shape(void* font, const uint16_t* text, uint32_t length,
                            int rtl, uint32_t* count) {
  *count = 0;
  hb_buffer_t* buffer = hb_buffer_create();
  hb_buffer_add_utf16(buffer, text, length, 0, length);
  hb_buffer_set_direction(buffer, rtl ? HB_DIRECTION_RTL : HB_DIRECTION_LTR);
  hb_buffer_guess_segment_properties(buffer);
  hb_shape(static_cast<hb_font_t*>(font), buffer, nullptr, 0);
  unsigned n = 0;
  const hb_glyph_info_t* info = hb_buffer_get_glyph_infos(buffer, &n);
  const hb_glyph_position_t* pos = hb_buffer_get_glyph_positions(buffer, nullptr);
  auto* out = static_cast<WritingGlyph*>(std::malloc(sizeof(WritingGlyph) * n));
  if (out && hb_buffer_allocation_successful(buffer)) {
    for (unsigned i = 0; i < n; ++i) {
      out[i] = {info[i].codepoint, info[i].cluster, pos[i].x_advance,
                pos[i].y_advance, pos[i].x_offset, pos[i].y_offset};
    }
    *count = n;
  } else {
    std::free(out);
    out = nullptr;
  }
  hb_buffer_destroy(buffer);
  return out;
}

__attribute__((visibility("default")))
void writing_glyphs_free(WritingGlyph* glyphs) { std::free(glyphs); }
}
