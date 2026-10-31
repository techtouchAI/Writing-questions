"""Glyph outline -> PDF path operators (prototype helper).

A combining mark whose character is already carried by a ligature's semantic
payload must not appear in the text channel a second time (an empty `/ToUnicode`
destination is emitted as `(cid:N)` by pdfminer and as a raw control byte by the
other three engines). Drawing that one glyph as a filled outline keeps its ink
and removes it from the text channel. This module builds the path so the
prototype can measure whether the ink stays pixel-identical.
"""
from __future__ import annotations

from fontTools.misc.transform import Transform
from fontTools.pens.basePen import BasePen
from fontTools.pens.qu2cuPen import Qu2CuPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont


class PdfPathPen(BasePen):
    def __init__(self, glyph_set, transform: Transform):
        super().__init__(glyph_set)
        self._t = transform
        self.ops: list[str] = []

    def _pt(self, point):
        x, y = self._t.transformPoint(point)
        return f'{x:.4f} {y:.4f}'

    def _moveTo(self, point):
        self.ops.append(f'{self._pt(point)} m')

    def _lineTo(self, point):
        self.ops.append(f'{self._pt(point)} l')

    def _curveToOne(self, p1, p2, p3):
        self.ops.append(f'{self._pt(p1)} {self._pt(p2)} {self._pt(p3)} c')

    def _closePath(self):
        self.ops.append('h')

    def _endPath(self):
        self.ops.append('h')


def glyph_path(font_path: str, gid: int, x: float, y: float, size: float) -> str:
    """PDF path operators for one glyph, placed at (x, y) and scaled to `size`."""
    ttf = TTFont(font_path)
    glyph_set = ttf.getGlyphSet()
    name = ttf.getGlyphOrder()[gid]
    scale = size / ttf['head'].unitsPerEm
    transform = Transform(scale, 0, 0, scale, x, y)
    pen = PdfPathPen(glyph_set, transform)
    quadratic = Qu2CuPen(pen, max_err=0.01, all_cubic=True)
    glyph_set[name].draw(quadratic)
    return '\n'.join(pen.ops)
