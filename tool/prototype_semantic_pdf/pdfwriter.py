"""Minimal, self-contained Type0 PDF writer for the semantic-encoding prototype.

This is **not** production code and is not imported by the application. It writes
a PDF where every glyph's CID is allocated per (glyph id, `/ToUnicode` payload)
pair, exactly like the vendored `PdfTtfFont._cidForPair`, so the only thing that
differs between experiments is the semantic encoding, never the ink.

Ink invariance: all strategies emit the same glyph ids at the same absolute
positions with the same advances. Strategies only change

* the order of the text-showing operators (visual vs logical),
* the `/ToUnicode` payload assigned to each CID,
* optional marked-content `/ActualText` spans,
* optional invisible (`3 Tr`) logical text.

The writer supports `/CIDToGIDMap` as a stream, `/W` widths and `/ToUnicode`
`bfchar` chunks, which is everything the four extractors need.
"""
from __future__ import annotations

import hashlib
import zlib
from dataclasses import dataclass, field

from shaping import PrototypeFont


def _utf16_hex(text: str) -> str:
    data = text.encode('utf-16-be')
    return data.hex().upper()


@dataclass(frozen=True)
class PlacedGlyph:
    gid: int
    x: float          # absolute glyph origin, points
    y: float
    payload_logical: str
    payload_legacy: str
    cluster: int

    @property
    def cluster_text(self) -> str:
        return self.payload_logical


@dataclass
class Word:
    text: str                 # logical source of the word
    rtl: bool
    glyphs: list[PlacedGlyph]  # visual/drawing order
    x: float                  # left edge of the drawn word
    y: float
    size: float
    clusters: dict[int, str] = field(default_factory=dict)  # cluster -> logical text


class FontEncoder:
    """CID allocation and font object generation for one prototype font."""

    def __init__(self, font: PrototypeFont):
        self.font = font
        self.pairs: list[tuple[int, str]] = []
        self._index: dict[tuple[int, str], int] = {}

    def cid(self, gid: int, payload: str) -> int:
        key = (gid, payload)
        existing = self._index.get(key)
        if existing is not None:
            return existing
        cid = len(self.pairs)
        self.pairs.append(key)
        self._index[key] = cid
        return cid

    def hex_text(self, cids: list[int]) -> str:
        return '<' + ''.join(f'{cid:04X}' for cid in cids) + '>'

    # ---- PDF objects -----------------------------------------------------
    def _to_unicode(self) -> bytes:
        lines = [
            '/CIDInit /ProcSet findresource begin',
            '12 dict begin',
            'begincmap',
            '/CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def',
            '/CMapName /Adobe-Identity-UCS def',
            '/CMapType 2 def',
            '1 begincodespacerange',
            '<0000> <FFFF>',
            'endcodespacerange',
        ]
        entries = [(cid, payload) for cid, (_, payload) in enumerate(self.pairs) if payload]
        for start in range(0, len(entries), 100):
            chunk = entries[start:start + 100]
            lines.append(f'{len(chunk)} beginbfchar')
            for cid, payload in chunk:
                lines.append(f'<{cid:04X}> <{_utf16_hex(payload)}>')
            lines.append('endbfchar')
        lines += ['endcmap', 'CMapName currentdict /CMap defineresource pop', 'end', 'end']
        return ('\n'.join(lines) + '\n').encode('latin-1')

    def _cid_to_gid(self) -> bytes:
        out = bytearray()
        for gid, _ in self.pairs:
            out += gid.to_bytes(2, 'big')
        return bytes(out)

    def _widths(self) -> str:
        parts = []
        for cid, (gid, _) in enumerate(self.pairs):
            width = self.font.advance(gid)
            parts.append(f'{cid} [{round(width * 1000 / self.font.units_per_em)}]')
        return '[' + ' '.join(parts) + ']'

    def font_objects(self) -> list[bytes]:
        upem = self.font.units_per_em
        head = self.font.ttf['head']
        hhea = self.font.ttf['hhea']
        raw_font = open(self.font.path, 'rb').read()
        font_file = zlib.compress(raw_font)
        return [
            b'<< /Type /Font /Subtype /Type0 /BaseFont /ProtoNaskh /Encoding /Identity-H '
            b'/DescendantFonts [4 0 R] /ToUnicode 5 0 R >>',
            b'<< /Type /Font /Subtype /CIDFontType2 /BaseFont /ProtoNaskh '
            b'/CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> '
            b'/FontDescriptor 6 0 R /DW 1000 /W 7 0 R /CIDToGIDMap 8 0 R >>',
            b'__UNUSED__',
            b'__UNUSED__',
            b'__CMAP__',
            (f'<< /Type /FontDescriptor /FontName /ProtoNaskh /Flags 4 '
             f'/FontBBox [{head.xMin} {head.yMin} {head.xMax} {head.yMax}] '
             f'/ItalicAngle 0 /Ascent {hhea.ascent} /Descent {hhea.descent} '
             f'/CapHeight {hhea.ascent} /StemV 80 /FontFile2 9 0 R >>').encode('latin-1'),
            self._widths().encode('latin-1'),
            b'__CID2GID__',
            b'__FONTFILE__',
        ]


def _stream(data: bytes, compress: bool = True) -> tuple[bytes, bytes]:
    if compress:
        packed = zlib.compress(data)
        return (f'<< /Length {len(packed)} /Filter /FlateDecode >>'.encode(),
                f'stream\n'.encode() + packed + b'\nendstream')
    return (f'<< /Length {len(data)} >>'.encode(), b'stream\n' + data + b'\nendstream')


class PdfWriter:
    def __init__(self, encoder: FontEncoder):
        self.encoder = encoder

    def _object(self, body: bytes, extra: bytes = b'') -> bytes:
        return body

    def build(self, page_contents: list[str], compress_font: bool = True) -> bytes:
        """Serialize a PDF with one page per content stream string."""
        objs: list[bytes] = []
        # 1 catalog, 2 pages tree, then per page: page object + content stream.
        n_pages = len(page_contents)
        page_ids = []
        next_id = 10
        page_objs: dict[int, bytes] = {}
        content_objs: dict[int, bytes] = {}

        enc = self.encoder
        cmap_data = enc._to_unicode()
        cid2gid_data = enc._cid_to_gid()
        raw_font = open(enc.font.path, 'rb').read()
        font_file_data = raw_font  # stream_obj() applies the Flate filter

        for index, content in enumerate(page_contents):
            page_id = next_id
            next_id += 1
            content_id = next_id
            next_id += 1
            page_ids.append(page_id)
            page_objs[page_id] = (
                f'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] '
                f'/Resources << /Font << /F1 3 0 R >> >> /Contents {content_id} 0 R >>'
            ).encode('latin-1')
            dict_part, stream_part = _stream(content.encode('latin-1'))
            content_objs[content_id] = dict_part + b'\n' + stream_part

        head = enc.font.ttf['head']
        hhea = enc.font.ttf['hhea']
        font_objects = enc.font_objects()
        descendants = font_objects[1]
        font = font_objects[0]
        descriptor = (f'<< /Type /FontDescriptor /FontName /ProtoNaskh /Flags 4 '
                      f'/FontBBox [{head.xMin} {head.yMin} {head.xMax} {head.yMax}] '
                      f'/ItalicAngle 0 /Ascent {hhea.ascent} /Descent {hhea.descent} '
                      f'/CapHeight {hhea.ascent} /StemV 80 /FontFile2 9 0 R >>').encode('latin-1')

        def stream_obj(data: bytes) -> bytes:
            packed = zlib.compress(data)
            return (f'<< /Length {len(packed)} /Filter /FlateDecode >>\n'.encode()
                    + b'stream\n' + packed + b'\nendstream')

        objs.append(b'<< /Type /Catalog /Pages 2 0 R >>')                      # 1
        kids = ' '.join(f'{pid} 0 R' for pid in page_ids)
        objs.append(f'<< /Type /Pages /Count {n_pages} /Kids [{kids}] >>'.encode())  # 2
        objs.append(font)                                                       # 3
        objs.append(descendants)                                                # 4
        objs.append(stream_obj(cmap_data))                                      # 5 ToUnicode
        objs.append(descriptor)                                                 # 6
        objs.append(enc._widths().encode('latin-1'))                            # 7 W
        objs.append(stream_obj(cid2gid_data))                                   # 8 CIDToGIDMap
        packed = zlib.compress(font_file_data)
        objs.append((f'<< /Length {len(packed)} /Length1 {len(font_file_data)} '
                     f'/Filter /FlateDecode >>\nstream\n'.encode()
                     + packed + b'\nendstream'))                                # 9 FontFile2
        for page_id in sorted(page_objs):
            objs.append(page_objs[page_id])
            content_id = page_id + 1
            objs.append(content_objs[content_id])

        out = bytearray(b'%PDF-1.7\n%\xe2\xe3\xcf\xd3\n')
        offsets = [0]
        for number, body in enumerate(objs, start=1):
            offsets.append(len(out))
            out += f'{number} 0 obj\n'.encode() + body + b'\nendobj\n'
        xref = len(out)
        out += f'xref\n0 {len(objs) + 1}\n'.encode()
        out += b'0000000000 65535 f \n'
        for offset in offsets[1:]:
            out += f'{offset:010d} 00000 n \n'.encode()
        out += (f'trailer\n<< /Size {len(objs) + 1} /Root 1 0 R >>\nstartxref\n'
                f'{xref}\n%%EOF\n').encode()
        return bytes(out)


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()
