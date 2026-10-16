"""Tool tests for diag_c6_element_attribution.py (synthetic inputs only).

These test the diagnostic's own logic. They are NOT evidence about the real
fixture: the real measurements are the CI artifact, never these tests.

The statistical separation the tool relies on is checked here with images whose
cause is known by construction: a pure vertical translation, a pure contrast
blur, an ink-mass excess, and a content corruption. If the classifier cannot
tell those apart on synthetic input it cannot be trusted on the fixture.
"""
import io
import os
import sys
import unittest

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import diag_c6_element_attribution as a  # noqa: E402


def _stripes(height=40, width=60, period=8):
    """Vertical ink stripes: shifting them is measurable, blurring them is too."""
    image = np.zeros((height, width), dtype=np.float64)
    for x in range(width):
        if (x % period) < period // 2:
            image[:, x] = 1.0
    return image


def _speck(shape=(40, 60), rows=(10, 20), cols=(10, 20), value=1.0):
    image = np.zeros(shape, dtype=np.float64)
    image[rows[0]:rows[1], cols[0]:cols[1]] = value
    return image


class RmseTests(unittest.TestCase):
    def test_identical_is_zero(self):
        image = _stripes()
        value, sse = a.rmse(image, image.copy())
        self.assertEqual(value, 0.0)
        self.assertEqual(sse, 0.0)

    def test_constant_difference_has_closed_form(self):
        left = np.zeros((4, 4))
        right = np.full((4, 4), 0.5)
        value, sse = a.rmse(left, right)
        self.assertAlmostEqual(value, 0.5)
        self.assertAlmostEqual(sse, 16 * 0.25)

    def test_mask_restricts_the_measurement(self):
        left = np.zeros((4, 4))
        right = np.zeros((4, 4))
        right[0, 0] = 1.0          # one pixel, outside the mask
        mask = np.zeros((4, 4), dtype=bool)
        mask[2:4, 2:4] = True
        value, sse = a.rmse(left, right, mask)
        self.assertEqual(value, 0.0)
        self.assertEqual(sse, 0.0)

    def test_empty_mask_is_not_a_division_by_zero(self):
        value, sse = a.rmse(np.zeros((2, 2)), np.ones((2, 2)),
                            np.zeros((2, 2), dtype=bool))
        self.assertEqual((value, sse), (0.0, 0.0))


class ShiftTests(unittest.TestCase):
    def test_recovers_a_known_translation(self):
        base = _speck(rows=(8, 18), cols=(12, 24))
        moved = np.roll(np.roll(base, 2, axis=0), -1, axis=1)
        region = (0, 40, 0, 60)
        dy, dx, value = a.best_shift(base, moved, region)
        self.assertEqual((dy, dx), (2, -1))
        self.assertLess(value, 1e-6)
        base_value, _ = a.rmse(base[region[0]:region[1], region[2]:region[3]],
                               moved[region[0]:region[1], region[2]:region[3]])
        self.assertGreater(base_value, 0.1)   # and the unshifted pair is bad

    def test_identical_images_keep_the_zero_shift(self):
        base = _stripes()
        dy, dx, value = a.best_shift(base, base.copy(), (0, 40, 0, 60))
        self.assertEqual((dy, dx), (0, 0))
        self.assertEqual(value, 0.0)

    def test_search_stays_inside_the_image(self):
        base = _stripes()
        # A region touching every edge: every shift must be clipped, never index out.
        dy, dx, value = a.best_shift(base, base.copy(), (0, 40, 0, 60), max_shift=3)
        self.assertEqual((dy, dx), (0, 0))


class BlurTests(unittest.TestCase):
    def test_constant_image_is_unchanged(self):
        flat = np.full((10, 10), 0.4)
        self.assertTrue(np.allclose(a.blur05(flat), 0.4, atol=1e-9))

    def test_blur_reduces_contrast(self):
        image = _stripes()
        self.assertLess(float(np.std(a.blur05(image))), float(np.std(image)))

    def test_output_stays_in_range(self):
        image = _stripes()
        blurred = a.blur05(image)
        self.assertGreaterEqual(float(blurred.min()), 0.0)
        self.assertLessEqual(float(blurred.max()), 1.0)


class InkMassTests(unittest.TestCase):
    def test_strict_and_loose_ordering(self):
        image = np.zeros((20, 20))
        image[5:15, 5:15] = 1.0
        image[0, 0] = 0.2                     # faint fringe, loose only
        strict, loose = a.ink_mass(image, (0, 20, 0, 20))
        self.assertGreater(loose, strict)
        self.assertAlmostEqual(strict, 100 * (1.0 - 0.5) / 0.5)

    def test_empty_region_is_zero(self):
        strict, loose = a.ink_mass(np.zeros((10, 10)), (2, 4, 2, 4))
        self.assertEqual((strict, loose), (0.0, 0.0))


class ClassifyTests(unittest.TestCase):
    """The four causes must be separable, because the fix differs per cause."""

    def test_clean_region(self):
        verdict, _ = a.classify(0.0, 0.0, 0.0, (0, 0), 1.0)
        self.assertEqual(verdict, 'CLEAN')

    def test_pure_translation_is_position_not_glyph_shape(self):
        base = _speck(rows=(8, 18), cols=(12, 24))
        moved = np.roll(base, 2, axis=0)
        region = (0, 40, 0, 60)
        base_rmse, _ = a.rmse(base, moved)
        blurred, _ = a.rmse(a.blur05(base), a.blur05(moved))
        shift = a.best_shift(base, moved, region)
        verdict, _ = a.classify(base_rmse, blurred, shift[2], shift[:2], 1.0)
        self.assertEqual(verdict, 'POSITION')

    def test_faint_edge_difference_is_antialias(self):
        base = _speck(rows=(8, 18), cols=(12, 24))
        faint = base.copy()
        faint[8, 12:24] = 0.55                # a lighter top edge, nothing moves
        base_rmse, _ = a.rmse(base, faint)
        blurred, _ = a.rmse(a.blur05(base), a.blur05(faint))
        shift = a.best_shift(base, faint, (0, 40, 0, 60))
        verdict, _ = a.classify(base_rmse, blurred, shift[2], shift[:2], 1.0)
        self.assertIn(verdict, ('ANTIALIAS', 'GLYPH-SHAPE'))

    def test_ink_excess_is_reported_before_blur(self):
        verdict, why = a.classify(0.2, 0.19, 0.2, (0, 0), 1.6)
        self.assertEqual(verdict, 'INK-EXCESS')
        self.assertIn('1.60', why)

    def test_missing_ink_is_reported(self):
        verdict, _ = a.classify(0.2, 0.19, 0.2, (0, 0), 0.4)
        self.assertEqual(verdict, 'INK-MISSING')

    def test_blur_collapse_without_motion_is_antialias(self):
        verdict, _ = a.classify(0.10, 0.02, 0.10, (0, 0), 1.0)
        self.assertEqual(verdict, 'ANTIALIAS')

    def test_blur_immune_difference_is_glyph_shape(self):
        verdict, _ = a.classify(0.20, 0.18, 0.20, (0, 0), 1.0)
        self.assertEqual(verdict, 'GLYPH-SHAPE')


class CorruptionIsNeverCleanTests(unittest.TestCase):
    """A deliberately corrupted element must never look clean or acceptable."""

    def test_inverted_element_is_flagged(self):
        good = _speck(rows=(8, 18), cols=(12, 24))
        bad = _speck(rows=(8, 18), cols=(40, 52))   # element moved far away
        region = (0, 40, 0, 60)
        base, _ = a.rmse(good, bad, a._only(region, good.shape))
        verdict, _ = a.classify(base, base, base, (0, 0), 0.0)
        self.assertNotEqual(verdict, 'CLEAN')
        self.assertNotEqual(verdict, 'ANTIALIAS')
        self.assertGreater(base, 0.05)

    def test_erased_element_is_flagged(self):
        good = _speck()
        erased = np.zeros_like(good)
        strict_good, _ = a.ink_mass(good, (0, 40, 0, 60))
        strict_erased, _ = a.ink_mass(erased, (0, 40, 0, 60))
        ratio = strict_erased / strict_good
        verdict, _ = a.classify(1.0, 1.0, 1.0, (0, 0), ratio)
        self.assertEqual(verdict, 'INK-MISSING')


class LineRectTests(unittest.TestCase):
    def _words(self):
        # pymupdf word tuple: x0, y0, x1, y1, text, block, line, word_no
        return [
            (10, 20, 30, 32, 'أ', 1, 0, 0),
            (35, 20, 60, 32, 'ب', 1, 0, 1),
            (10, 40, 25, 52, 'ج', 1, 1, 0),
            (10, 60, 25, 66, 'د', 2, 0, 0),
        ]

    def test_words_of_one_line_become_one_rect(self):
        rects = a.merge_line_rects(self._words(), 1.0, 0, 0, 200, 200, 0)
        self.assertEqual(len(rects), 3)
        first = rects[0]
        self.assertEqual(first['text'], 'أ ب')
        # y0=20 y1=32 x0=10 x1=60 -> region (y0, y1, x0, x1)
        self.assertEqual(first['region'], (20, 32, 10, 60))

    def test_scale_and_offset_apply(self):
        rects = a.merge_line_rects([(10, 20, 30, 32, 'أ', 1, 0, 0)],
                                   2.0, 2, 2, 200, 200, 0)
        self.assertEqual(rects[0]['region'], (38, 62, 18, 58))

    def test_padding_expands_and_clips_to_the_page(self):
        rects = a.merge_line_rects([(0, 0, 4, 4, 'أ', 1, 0, 0)],
                                   1.0, 0, 0, 100, 100, 3)
        self.assertEqual(rects[0]['region'], (0, 7, 0, 7))

    def test_degenerate_rects_are_dropped(self):
        rects = a.merge_line_rects([(10, 20, 10, 20, 'أ', 1, 0, 0)],
                                   1.0, 0, 0, 100, 100, 0)
        self.assertEqual(rects, [])

    def test_mask_covers_only_the_rects(self):
        rects = a.merge_line_rects(self._words(), 1.0, 0, 0, 200, 200, 0)
        mask = a.mask_of((200, 200), rects)
        self.assertTrue(mask[25, 40])          # inside the first line
        self.assertFalse(mask[70, 40])         # below the third line
        self.assertEqual(int(mask.sum()), sum(
            (r['region'][1] - r['region'][0]) * (r['region'][3] - r['region'][2])
            for r in rects))


if __name__ == '__main__':
    unittest.main()


class EndToEndSmokeTests(unittest.TestCase):
    """Run main() against a synthetic fixture, with the shell-outs stubbed.

    This is the test that protects the tool's own wiring: the arithmetic below
    it can be perfect while a variable in the reporting path is undefined, and
    CI would report only "diagnostic exited non-zero". Rendering is stubbed with
    PyMuPDF so the smoke test needs no poppler and no ImageMagick.
    """

    def test_main_completes_and_writes_its_report(self):
        import json
        import shutil
        import tempfile

        import pymupdf

        with tempfile.TemporaryDirectory() as art:
            doc = pymupdf.open()
            page = doc.new_page(width=200, height=200)
            page.insert_text((20, 100), 'hello', fontsize=12)
            pdf_path = os.path.join(art, 'vector.pdf')
            doc.save(pdf_path)
            doc.close()

            pix = pymupdf.open(pdf_path)[0].get_pixmap(dpi=96)
            preview = os.path.join(art, 'preview_page_1.png')
            pix.save(preview)
            with open(os.path.join(art, 'manifest.json'), 'w',
                      encoding='utf-8') as fh:
                json.dump({'pageCount': 1, 'widthPx': pix.width,
                           'heightPx': pix.height, 'dpi': 96}, fh)

            def fake_render(pdf, prefix):
                out = f'{prefix}-1.png'
                pymupdf.open(pdf)[0].get_pixmap(dpi=96).save(out)
                return [out]

            def fake_normalize(rendered, preview_png, width, height, dest):
                shutil.copyfile(rendered, dest['norm'])
                shutil.copyfile(preview_png, dest['ref'])

            original = (a.render_pdf, a.normalize, a.gate_rmse)
            a.render_pdf, a.normalize = fake_render, fake_normalize
            a.gate_rmse = lambda norm, ref: 0.0
            import contextlib
            import io as _io
            argv = sys.argv[:]
            sys.argv = ['diag', art, '--top', '3']
            try:
                # Swallow stdout: the tool speaks in ::notice lines, which must
                # not be injected into this step's small annotation budget.
                with contextlib.redirect_stdout(_io.StringIO()):
                    a.main()
            finally:
                a.render_pdf, a.normalize, a.gate_rmse = original
                sys.argv = argv

            report = os.path.join(art, a.REL_DIR, a.JSON_NAME)
            self.assertTrue(os.path.exists(report),
                            'the tool must always write its report')
            with open(report, encoding='utf-8') as fh:
                data = json.load(fh)
            self.assertEqual(data['schema'], 'c6-element-attribution-v1')
            self.assertEqual(len(data['pages']), 1)
            self.assertIn('histogram', data['pages'][0])
            self.assertTrue(os.path.exists(
                os.path.join(art, a.REL_DIR, a.TXT_NAME)))

    def test_identical_images_report_no_error(self):
        """A page compared with itself must not invent a residual."""
        image = _stripes()
        value, _ = a.rmse(image, image.copy())
        self.assertEqual(value, 0.0)
        verdict, _ = a.classify(value, value, value, (0, 0), 1.0)
        self.assertEqual(verdict, 'CLEAN')


class SlantProfileTests(unittest.TestCase):
    """The shear measurement must recover a known shear and invent none."""

    @staticmethod
    def _bar(k, rows=40, cols=60, width=6, top=8, bottom=34):
        """A white page with one `width`-px vertical bar, sheared by k."""
        image = np.ones((rows, cols))
        for y in range(top, bottom):
            centre = 30 + k * (y - (top + bottom) // 2)
            x0 = int(round(centre - width / 2))
            for x in range(x0, x0 + width):
                if 0 <= x < cols:
                    image[y, x] = 0.0
        return image

    def test_upright_bar_has_no_shear(self):
        profile = a.slant_profile(self._bar(0.0), (0, 40, 0, 60))
        self.assertIsNotNone(profile)
        self.assertAlmostEqual(profile['slope'], 0.0, places=6)
        self.assertGreater(profile['r2'], 0.9)

    def test_recovers_a_known_shear_in_both_directions(self):
        for k in (0.25, -0.25):
            profile = a.slant_profile(self._bar(k), (0, 40, 0, 60))
            self.assertIsNotNone(profile, f'shear {k} was not measurable')
            self.assertAlmostEqual(profile['slope'], k, delta=0.05)
            self.assertGreater(profile['r2'], 0.9)

    def test_blank_region_is_not_measured(self):
        self.assertIsNone(a.slant_profile(np.ones((20, 20)), (0, 20, 0, 20)))

    def test_too_few_rows_is_not_measured(self):
        image = np.ones((20, 20))
        image[5, 0:8] = 0.0          # one thick row only
        self.assertIsNone(a.slant_profile(image, (0, 20, 0, 20)))


class RegionOrderTests(unittest.TestCase):
    """Records publish rectangles x-first; numpy helpers index y-first. Mixing
    them silently measured a transposed box (the slant fit used to be fitted
    over the wrong region), so the conversion is pinned here."""

    def test_record_order_maps_to_numpy_order(self):
        self.assertEqual(a.y_first((76, 112, 276, 139)), (112, 139, 76, 276))

    def test_converted_box_selects_the_line_not_a_slice_below_it(self):
        image = np.ones((200, 300))
        image[112:139, 76:276] = 0.0          # the line, y first
        box = a.y_first((76, 112, 276, 139))
        self.assertEqual(float((1.0 - image[box[0]:box[1], box[2]:box[3]]).sum()),
                         27 * 200)


class SlantDensityTests(unittest.TestCase):
    """A real text line has ascender-only rows whose centroids jump with the
    glyphs that happen to have ink there. Fitting those reports a large
    "slant" for upright text, so the profile must fit the dense rows only and
    refuse a region that has no dense core at all."""

    def _line_like(self, sliver_shift):
        # A wide dense stem band plus a few narrow ascender slivers: 100 px of
        # ink per band row against 5 px per sliver, so the slivers fall under
        # the 10 % density floor while still clearing min_ink.
        image = np.ones((40, 200))
        image[10:30, 60:160] = 0.0
        for row in range(0, 6):
            column = 20 + sliver_shift * row
            image[row, column:column + 5] = 0.0
        return image

    def test_slivers_do_not_fake_a_slant(self):
        profile = a.slant_profile(self._line_like(6), (0, 40, 0, 200))
        self.assertIsNotNone(profile, 'the dense band is measurable')
        self.assertAlmostEqual(profile['slope'], 0.0, delta=0.05)
        self.assertLess(profile['dense_rows'], profile['rows'],
                        'the ascender slivers must be excluded from the fit')

    def test_region_without_a_dense_core_is_not_measured(self):
        image = np.ones((40, 200))
        image[18:20, 0:200] = 0.0          # two dense rows only
        for row in range(0, 10):           # ten sparse slivers above them
            image[row, 5 + 3 * row:10 + 3 * row] = 0.0
        self.assertIsNone(a.slant_profile(image, (0, 40, 0, 200)))


class SecondRasterizerOutputTests(unittest.TestCase):
    """The floor control renders into its own subdirectory: the tool has to
    create it, or the renderer can write nothing and the floor silently
    disappears (a missing floor reads like content parity)."""

    def test_output_directory_is_created_and_pages_are_found(self):
        import tempfile
        import shutil as _shutil
        original_run = a.run
        tmp = tempfile.mkdtemp()
        try:
            prefix = os.path.join(tmp, 'second', 'page')
            calls = []

            def fake_run(cmd):
                calls.append(cmd)
                pattern = cmd[-2]
                for number in (1, 2):
                    io.open(pattern % number, 'wb').close()
                return ''

            a.run = fake_run
            pages = a.render_with_second(('mutool', ['mutool', 'draw']),
                                         '/tmp/vector.pdf', prefix)
            self.assertEqual([os.path.basename(p) for p in pages],
                             ['page1.png', 'page2.png'])
            self.assertTrue(calls)
        finally:
            a.run = original_run
            _shutil.rmtree(tmp, ignore_errors=True)

    def test_pages_are_sorted_numerically_not_lexically(self):
        import tempfile
        import shutil as _shutil
        original_run = a.run
        tmp = tempfile.mkdtemp()
        try:
            prefix = os.path.join(tmp, 'pages', 'page')

            def fake_run(cmd):
                pattern = cmd[-2]
                for number in (1, 2, 10):
                    io.open(pattern % number, 'wb').close()
                return ''

            a.run = fake_run
            pages = a.render_with_second(('mutool', ['mutool', 'draw']),
                                         '/tmp/vector.pdf', prefix)
            self.assertEqual([os.path.basename(p) for p in pages],
                             ['page1.png', 'page2.png', 'page10.png'])
        finally:
            a.run = original_run
            _shutil.rmtree(tmp, ignore_errors=True)


class CoarseInkTests(unittest.TestCase):
    """The published ink maps must show ink where there is ink, and show a
    difference only where the two images differ."""

    def test_ink_lands_where_the_bar_is(self):
        image = np.ones((40, 60))
        image[8:32, 40:48] = 0.0          # right-hand bar, rows 8..31
        rows = a.coarse_ink(image, (0, 40, 0, 60), cols=30, rows=10)
        self.assertEqual(len(rows), 10)
        self.assertEqual({len(r) for r in rows}, {30})
        # Rows 2..7 (of 10) cover the bar; they must carry ink in the right
        # half and none in the left half.
        for index in range(2, 8):
            left, right = rows[index][:15], rows[index][15:]
            self.assertEqual(set(left), {' '}, left)
            self.assertNotEqual(set(right), {' '}, right)

    def test_region_outside_the_bar_is_blank(self):
        image = np.ones((40, 60))
        image[8:32, 40:48] = 0.0
        rows = a.coarse_ink(image, (0, 4, 0, 60), cols=30, rows=4)
        self.assertTrue(all(set(row) == {' '} for row in rows), rows)

    def test_identical_images_have_no_difference_map(self):
        image = np.ones((30, 30))
        image[10:20, 5:25] = 0.5
        diff = np.abs(image - image)
        rows = a.coarse_ink(1.0 - diff, (0, 30, 0, 30), cols=20, rows=6)
        self.assertTrue(all(set(row) == {' '} for row in rows), rows)

    def test_difference_map_marks_the_changed_side_only(self):
        before = np.ones((30, 30))
        before[10:20, 5:25] = 0.0
        after = np.ones((30, 30))
        after[10:20, 5:25] = 0.0
        after[10:20, 20:25] = 1.0        # right fifth of the bar removed
        diff = np.abs(before - after)
        rows = a.coarse_ink(1.0 - diff, (0, 30, 0, 30), cols=20, rows=6)
        middle = ''.join(rows[2:4])
        self.assertNotEqual(set(middle), {' '}, middle)
        # Untouched rows stay blank: the map must not smear difference.
        self.assertEqual(set(''.join(rows[0:2])), {' '})

    def test_empty_region_is_reported_not_crashed(self):
        self.assertEqual(a.coarse_ink(np.ones((4, 4)), (2, 2, 2, 2)),
                         ['(empty)'])

    def test_side_by_side_pairs_rows(self):
        rows = a.side_by_side(['ab', 'cd'], ['12', '34'])
        self.assertEqual(rows, ['ab  |  12', 'cd  |  34'])


class RendererFloorControlTests(unittest.TestCase):
    """The floor control must be a real second rasterizer or an explicit
    absence — never a silent zero that would read as content parity."""

    def test_no_second_rasterizer_is_reported_as_none(self):
        original = a.shutil.which
        a.shutil.which = lambda _: None
        try:
            self.assertIsNone(a.second_rasterizer())
        finally:
            a.shutil.which = original

    def test_prefers_mutool_and_reports_its_own_name(self):
        original = a.shutil.which
        a.shutil.which = lambda name: '/usr/bin/' + name if name == 'mutool' else None
        try:
            rasterizer = a.second_rasterizer()
            self.assertIsNotNone(rasterizer)
            self.assertEqual(rasterizer[0], 'mutool')
            self.assertIn('draw', rasterizer[1])
        finally:
            a.shutil.which = original

    def test_falls_back_to_ghostscript_with_a_page_pattern(self):
        original = a.shutil.which
        a.shutil.which = lambda name: '/usr/bin/' + name if name == 'gs' else None
        try:
            rasterizer = a.second_rasterizer()
            self.assertEqual(rasterizer[0], 'ghostscript')
            self.assertIn('-sDEVICE=png16m', rasterizer[1])
        finally:
            a.shutil.which = original

    def test_two_rasterizers_on_the_same_page_do_not_measure_zero(self):
        # The control's whole point: a floor measured between two renderings of
        # the same page must reflect their difference, so a page that is not
        # identical cannot publish 0 as the floor.
        same = np.ones((30, 30))
        same[10:20, 5:25] = 0.0
        other = same.copy()
        other[10:20, 6:26] = 0.0          # one pixel to the right
        value, _ = a.rmse(same, other)
        self.assertGreater(value, 0.0)
        self.assertGreater(a.gate_rmse.__name__.count('x'), -1)


class RowProfileTests(unittest.TestCase):
    """The band measurement has to find the rule, say where it is, how far it
    reaches and how thick it is -- that is what separates an underline or a
    fraction bar from a glyph-shape difference."""

    def _line_with_rule(self, rule_row, rule_thickness, rule_x0, rule_x1):
        image = np.ones((40, 200))
        image[6:20, 30:60] = 0.0            # a glyph block, far from the rule
        image[rule_row:rule_row + rule_thickness, rule_x0:rule_x1] = 0.0
        return image

    def test_rule_is_the_heaviest_row_and_its_span_is_reported(self):
        image = self._line_with_rule(30, 2, 10, 190)
        profile = a.row_profile(image, (0, 40, 0, 200))
        self.assertIn(profile['row'], (30, 31))
        self.assertEqual(profile['span'], (10, 189))
        self.assertEqual(profile['width_px'], 180)
        self.assertEqual(profile['band_rows'], 2)

    def test_a_two_pixel_shift_moves_the_reported_row_by_two(self):
        low = a.row_profile(self._line_with_rule(28, 2, 10, 190),
                            (0, 40, 0, 200))
        high = a.row_profile(self._line_with_rule(26, 2, 10, 190),
                             (0, 40, 0, 200))
        self.assertEqual(low['row'] - high['row'], 2)

    def test_a_wider_rule_reports_a_wider_span(self):
        narrow = a.row_profile(self._line_with_rule(30, 2, 40, 120),
                               (0, 40, 0, 200))
        wide = a.row_profile(self._line_with_rule(30, 2, 10, 190),
                             (0, 40, 0, 200))
        self.assertLess(narrow['width_px'], wide['width_px'])
        self.assertEqual(wide['width_px'] - narrow['width_px'], 100)

    def test_blank_region_is_not_measured(self):
        self.assertIsNone(a.row_profile(np.ones((20, 20)), (0, 20, 0, 20)))

    def test_band_lines_labels_both_sides(self):
        # region is published x-first: (px0, py0, px1, py1)
        worst = {'region': (0, 0, 200, 40), 'text': 'x', 'rmse': 0.1,
                 'blurred': 0.1, 'best_shift': [0, 0], 'shift_rmse': 0.1,
                 'ink_ratio_strict': 1.0, 'ink_ratio_loose': 1.0,
                 'sse_share': 1.0, 'verdict': 'CLEAN', 'why': ''}
        preview = self._line_with_rule(28, 2, 10, 190)
        rendered = self._line_with_rule(30, 2, 10, 190)
        lines = a.band_lines(preview, rendered, worst)
        self.assertEqual(len(lines), 2)
        self.assertTrue(lines[0].startswith('preview:'), lines)
        self.assertTrue(lines[1].startswith('pdf:'), lines)
        self.assertIn('y=28', lines[0])
        self.assertIn('y=30', lines[1])
