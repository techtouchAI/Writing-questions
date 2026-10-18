"""REAL-ARTIFACT underline parity tests -- kept separate from the synthetic.

The synthetic suite (test_diag_c6_underline_parity.py) proves the detector's
logic on constructed pages whose rules are *drawn* at known offsets. These
tests run the same check against the fixture's real artifacts -- the pages and
`vector.pdf` the CI jobs actually produce, whose rules come from real text
underlining as the app prints it -- so the two families cannot be mistaken for
each other:

* the check must compare real rules (a zero-rule run proves nothing and is
  not read as a pass here);
* and when real underline ink is removed from the real page raster, the check
  reports the rule as unmeasurable -- skipped, never silently agreed.

Skipped locally without `C6_ARTIFACTS`; in CI the suites run in separate
steps precisely so the real evidence is visible on its own.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

TOOL = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                    'check_underline_parity.py')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))


class RealUnderlineParityTests(unittest.TestCase):
    """Underline placement on the fixture's own printed output."""

    def _root(self):
        root = os.environ.get('C6_ARTIFACTS', 'build/visual_parity')
        manifest = os.path.join(root, 'manifest.json')
        pdf = os.path.join(root, 'vector.pdf')
        if not (os.path.exists(manifest) and os.path.exists(pdf)):
            self.skipTest('real artifacts not available')
        return root

    def _run(self, directory):
        return subprocess.run([sys.executable, TOOL, directory],
                              capture_output=True, text=True)

    def test_real_underlines_are_compared_and_agree(self):
        root = self._root()
        proc = self._run(root)
        out = proc.stdout + proc.stderr
        self.assertEqual(proc.returncode, 0, out)
        match = re.search(r'(\d+) rule\(s\) compared', out)
        self.assertIsNotNone(match, out)
        self.assertGreaterEqual(
            int(match.group(1)), 1,
            'لا تسطير حقيقي في مخرجات التركيبة — اختبار فارغ لا يُثبت شيئاً.')
        self.assertNotIn('UNDERLINE offset', out)

    def test_erasing_real_underline_ink_is_skipped_not_agreed(self):
        # إزالة حبر التسطير من لقطة حقيقية: يجب أن يُبلغ الفحص عن عدم قابلية
        # القياس (skip) لا أن يمر كاتفاق — الحبر المفقود ليس مطابقة.
        try:
            import numpy as np
            import pymupdf
            import check_underline_parity as cu
        except ImportError:
            self.skipTest('pymupdf/numpy not installed')
        root = self._root()
        doc = pymupdf.open(os.path.join(root, 'vector.pdf'))
        tampered_page = None
        measured = None
        for index in range(doc.page_count):
            preview = os.path.join(root, f'preview_page_{index + 1}.png')
            if not os.path.exists(preview):
                continue
            luma = cu.load_luma(preview)
            scale = luma.shape[1] / doc[index].rect.width
            for rule in cu.rules_in_pdf(doc[index]):
                found = cu.preview_offset(luma, rule['bbox'], scale)
                if found is None:
                    continue
                tampered_page = (index, preview, luma, found)
                break
            if tampered_page:
                break
        if tampered_page is None:
            self.skipTest('no measurable underline ink in the real artifacts')
        index, preview, luma, measured = tampered_page

        with tempfile.TemporaryDirectory() as tmp:
            for name in os.listdir(root):
                src = os.path.join(root, name)
                if os.path.isfile(src):
                    shutil.copy2(src, os.path.join(tmp, name))
            cleaned = np.array(luma, copy=True)
            rows = measured['rule_rows']
            for y in range(rows[0], rows[1] + 1):
                cleaned[y, :] = 0.0   # luma 0 = white: حبر القاعدة زائل
            samples = ((1.0 - cleaned) * 255).astype('uint8').tobytes()
            pix = pymupdf.Pixmap(pymupdf.csGRAY, cleaned.shape[1],
                                 cleaned.shape[0], samples, False)
            pix.save(os.path.join(tmp, f'preview_page_{index + 1}.png'))
            proc = self._run(tmp)
            out = proc.stdout + proc.stderr
            self.assertTrue(
                'not measurable' in out or 'no rule checked' in out,
                'حبر تسطير مفقود من صفحة حقيقية يجب ألا يقرأ كاتفاق: ' + out)


if __name__ == '__main__':
    unittest.main(verbosity=2)
